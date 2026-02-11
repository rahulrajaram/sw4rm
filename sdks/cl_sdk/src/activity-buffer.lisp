;;;; activity-buffer.lisp
;;;; Activity buffer implementation per SW4RM spec §10

(in-package :sw4rm-sdk)

;;; Condition Types

(define-condition buffer-full-error (error)
  ((buffer :initarg :buffer :reader buffer)
   (max-items :initarg :max-items :reader max-items)
   (current-items :initarg :current-items :reader current-items))
  (:report (lambda (condition stream)
             (format stream "Activity buffer is full (~D/~D items). Cannot add new activity without removal."
                     (current-items condition)
                     (max-items condition))))
  (:documentation "Signaled when attempting to add to a full activity buffer.
                   Per spec §10.1, buffer must reject new entries when at capacity."))

;;; Activity Entry Structure

(defstruct activity-entry
  "A single activity entry in the buffer.
   Fields conform to spec §10 requirements."
  (task-id nil :type (or null string))
  (repo-id nil :type (or null string))
  (worktree-id nil :type (or null string))
  (branch nil :type (or null string))
  (timestamp (get-universal-time) :type integer)
  (description nil :type (or null string)))

(defun validate-activity-entry (entry)
  "Validate an activity entry conforms to spec §10 requirements.

   Args:
     entry: Activity entry to validate

   Returns:
     T if valid

   Signals:
     ERROR: If validation fails"
  (check-type entry activity-entry)

  ;; Description must be <= 200 words per spec §10
  (when (activity-entry-description entry)
    (let* ((desc (activity-entry-description entry))
           (word-count (length (remove-if #'(lambda (s) (string= s ""))
                                         (split-sequence:split-sequence #\Space desc)))))
      (when (> word-count 200)
        (error "Activity description exceeds 200 word limit (got ~D words)" word-count))))

  t)

;;; Activity Buffer Class

(defclass activity-buffer ()
  ((entries
    :initarg :entries
    :accessor entries
    :type hash-table
    :initform (make-hash-table :test 'equal)
    :documentation "Hash table mapping activity keys to activity-entry structs.")

   (max-items
    :initarg :max-items
    :accessor max-items
    :type (integer 1 *)
    :initform 1000
    :documentation "Maximum number of activities to store.")

   (lock
    :accessor buffer-lock
    :initform (bt:make-lock "activity-buffer-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "Activity buffer for tracking agent activities.
                   Implements spec §10 requirements including:
                   - Task/repo/worktree/branch tracking
                   - Timestamp recording
                   - Description (max 200 words)
                   - Capacity enforcement (reject when full)
                   - Reconciliation with task states"))

(defmethod initialize-instance :after ((buf activity-buffer) &key)
  "Validate buffer configuration after initialization."
  (with-slots (max-items) buf
    (when (< max-items 1)
      (error "max-items must be at least 1, got ~D" max-items))))

(defun make-activity-key (task-id repo-id worktree-id)
  "Generate a unique key for an activity entry.

   Args:
     task-id: Task identifier
     repo-id: Repository identifier
     worktree-id: Worktree identifier

   Returns:
     String key"
  (format nil "~A/~A/~A"
          (or task-id "")
          (or repo-id "")
          (or worktree-id "")))

(defmethod current-size ((buf activity-buffer))
  "Get the current number of entries in the buffer.

   Args:
     buf: Activity buffer instance

   Returns:
     Number of entries"
  (hash-table-count (entries buf)))

(defmethod is-full-p ((buf activity-buffer))
  "Check if the buffer is at capacity.

   Args:
     buf: Activity buffer instance

   Returns:
     T if buffer is full, NIL otherwise"
  (>= (current-size buf) (max-items buf)))

(defmethod upsert-activity ((buf activity-buffer)
                           &key task-id repo-id worktree-id branch description)
  "Insert or update an activity entry in the buffer.

   Per spec §10.1, signals BUFFER-FULL-ERROR if buffer is at capacity
   and this is a new entry (not an update).

   Args:
     buf: Activity buffer instance
     task-id: Task identifier
     repo-id: Repository identifier
     worktree-id: Worktree identifier
     branch: Git branch name
     description: Activity description (max 200 words)

   Returns:
     The activity entry

   Signals:
     BUFFER-FULL-ERROR: If buffer is full and entry is new
     ERROR: If description exceeds 200 words"
  (bt:with-lock-held ((buffer-lock buf))
    (let* ((key (make-activity-key task-id repo-id worktree-id))
           (existing (gethash key (entries buf)))
           (entry (make-activity-entry
                   :task-id task-id
                   :repo-id repo-id
                   :worktree-id worktree-id
                   :branch branch
                   :timestamp (get-universal-time)
                   :description description)))

      ;; Validate entry
      (validate-activity-entry entry)

      ;; Check capacity if new entry
      (when (and (not existing) (is-full-p buf))
        (error 'buffer-full-error
               :buffer buf
               :max-items (max-items buf)
               :current-items (current-size buf)))

      ;; Store entry
      (setf (gethash key (entries buf)) entry)
      entry)))

(defmethod remove-activity ((buf activity-buffer)
                           &key task-id repo-id worktree-id)
  "Remove an activity entry from the buffer.

   Args:
     buf: Activity buffer instance
     task-id: Task identifier
     repo-id: Repository identifier
     worktree-id: Worktree identifier

   Returns:
     T if entry was found and removed, NIL otherwise"
  (bt:with-lock-held ((buffer-lock buf))
    (let ((key (make-activity-key task-id repo-id worktree-id)))
      (remhash key (entries buf)))))

(defmethod get-activity ((buf activity-buffer)
                        &key task-id repo-id worktree-id)
  "Get an activity entry from the buffer.

   Args:
     buf: Activity buffer instance
     task-id: Task identifier
     repo-id: Repository identifier
     worktree-id: Worktree identifier

   Returns:
     Activity entry or NIL if not found"
  (let ((key (make-activity-key task-id repo-id worktree-id)))
    (gethash key (entries buf))))

(defmethod list-activities ((buf activity-buffer) &key task-id repo-id)
  "List all activities matching the given filters.

   Args:
     buf: Activity buffer instance
     task-id: Optional task ID filter
     repo-id: Optional repository ID filter

   Returns:
     List of activity entries"
  (let ((results nil))
    (maphash (lambda (k v)
               (declare (ignore k))
               (when (and (or (null task-id)
                            (equal task-id (activity-entry-task-id v)))
                         (or (null repo-id)
                            (equal repo-id (activity-entry-repo-id v))))
                 (push v results)))
             (entries buf))
    results))

(defmethod recent-activities ((buf activity-buffer) &key (limit 10))
  "Get the most recent activities.

   Args:
     buf: Activity buffer instance
     limit: Maximum number of entries to return (default 10)

   Returns:
     List of activity entries, sorted newest first"
  (let ((all-entries nil))
    (maphash (lambda (k v)
               (declare (ignore k))
               (push v all-entries))
             (entries buf))
    (subseq (sort all-entries #'> :key #'activity-entry-timestamp)
            0
            (min limit (length all-entries)))))

(defmethod reconcile ((buf activity-buffer) task-states)
  "Purge entries for completed, failed, or unknown tasks.

   Per spec §10, the buffer should be reconciled against actual task states
   to remove stale entries.

   Args:
     buf: Activity buffer instance
     task-states: Hash table mapping task-id to state keyword
                 (:completed, :failed, etc.)

   Returns:
     Number of entries removed"
  (bt:with-lock-held ((buffer-lock buf))
    (let ((removed-count 0))
      (maphash (lambda (key entry)
                 (let* ((task-id (activity-entry-task-id entry))
                        (state (gethash task-id task-states)))
                   ;; Remove if task is completed, failed, or unknown
                   (when (or (null state)
                           (member state '(:completed :failed)))
                     (remhash key (entries buf))
                     (incf removed-count))))
               (entries buf))
      removed-count)))

(defmethod clear-all ((buf activity-buffer))
  "Remove all entries from the buffer.

   Args:
     buf: Activity buffer instance

   Returns:
     Number of entries removed"
  (bt:with-lock-held ((buffer-lock buf))
    (let ((count (hash-table-count (entries buf))))
      (clrhash (entries buf))
      count)))

(defmethod print-object ((buf activity-buffer) stream)
  "Print activity buffer in readable format."
  (print-unreadable-object (buf stream :type t)
    (format stream "~D/~D entries"
            (current-size buf)
            (max-items buf))))
