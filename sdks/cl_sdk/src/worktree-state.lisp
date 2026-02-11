;;;; worktree-state.lisp
;;;; Worktree state machine implementation per SW4RM spec §16

(in-package :sw4rm-sdk)

;;; Condition Types

(define-condition worktree-state-error (error)
  ((from-state :initarg :from-state :reader from-state)
   (to-state :initarg :to-state :reader to-state)
   (reason :initarg :reason :reader reason :initform nil))
  (:report (lambda (condition stream)
             (format stream "Invalid worktree state transition from ~A to ~A~@[: ~A~]"
                     (from-state condition)
                     (to-state condition)
                     (reason condition))))
  (:documentation "Signaled when an invalid worktree state transition is attempted."))

;;; State Definitions

(deftype worktree-state ()
  "Valid worktree binding states per SW4RM spec §16."
  '(member :unbound :bound-home :switch-pending :bound-non-home :bind-failed))

;;; Transition Matrix

(defparameter *worktree-transition-matrix*
  '((:unbound . (:bound-home :bind-failed))
    (:bound-home . (:switch-pending :unbound))
    (:switch-pending . (:bound-non-home :bound-home))
    (:bound-non-home . (:bound-home :unbound))
    (:bind-failed . (:unbound :bound-home)))
  "Transition matrix for worktree binding states per spec §16.")

;;; Transition Validation Functions

(defun valid-worktree-transitions (from-state)
  "Return a list of valid target states from FROM-STATE.

   Args:
     from-state: Current worktree state (keyword)

   Returns:
     List of valid target states, or NIL if no transitions allowed."
  (check-type from-state worktree-state)
  (cdr (assoc from-state *worktree-transition-matrix*)))

(defun valid-worktree-transition-p (from-state to-state)
  "Return T if transitioning from FROM-STATE to TO-STATE is valid.

   Args:
     from-state: Current worktree state (keyword)
     to-state: Target worktree state (keyword)

   Returns:
     T if transition is valid, NIL otherwise."
  (check-type from-state worktree-state)
  (check-type to-state worktree-state)
  (member to-state (valid-worktree-transitions from-state)))

;;; Binding Information Structure

(defstruct binding-info
  "Information about a worktree binding."
  (worktree-id nil :type (or null string))
  (repo-id nil :type (or null string))
  (branch nil :type (or null string))
  (bound-at nil :type (or null integer))
  (expires-at nil :type (or null integer)))

;;; Worktree State Machine Class

(defclass worktree-state-machine ()
  ((state
    :initarg :state
    :accessor worktree-state
    :type worktree-state
    :initform :unbound
    :documentation "Current worktree binding state.")

   (home-binding
    :initarg :home-binding
    :accessor home-binding
    :type (or null binding-info)
    :initform nil
    :documentation "Information about the home worktree binding.")

   (current-binding
    :initarg :current-binding
    :accessor current-binding
    :type (or null binding-info)
    :initform nil
    :documentation "Information about the current worktree binding.")

   (pending-switch
    :initarg :pending-switch
    :accessor pending-switch
    :type (or null binding-info)
    :initform nil
    :documentation "Information about a pending switch request.")

   (switch-ttl
    :initarg :switch-ttl
    :accessor switch-ttl
    :type (integer 0 *)
    :initform 3600
    :documentation "Time-to-live for non-home bindings in seconds (default 1 hour).")

   (state-history
    :initarg :state-history
    :accessor state-history
    :type list
    :initform nil
    :documentation "History of state transitions, newest first.")

   (lock
    :accessor state-lock
    :initform (bt:make-lock "worktree-state-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "Worktree state machine managing worktree binding lifecycle.
                   Implements the complete state transition matrix from spec §16."))

;;; State Transition History

(defstruct worktree-transition-entry
  "Records a worktree state transition event."
  (from-state nil :type (or null worktree-state))
  (to-state nil :type worktree-state)
  (timestamp (get-universal-time) :type integer)
  (metadata nil :type list))

;;; Internal Transition Method

(defmethod %transition-worktree-state ((wsm worktree-state-machine) to-state &key metadata)
  "Internal method to perform state transition (assumes lock held).

   Args:
     wsm: Worktree state machine instance
     to-state: Target state
     metadata: Optional metadata plist

   Returns:
     The new state

   Signals:
     WORKTREE-STATE-ERROR: If transition is invalid"
  (let ((from-state (worktree-state wsm)))
    (unless (valid-worktree-transition-p from-state to-state)
      (error 'worktree-state-error
             :from-state from-state
             :to-state to-state
             :reason (format nil "No valid transition from ~A to ~A"
                            from-state to-state)))

    ;; Perform transition
    (setf (worktree-state wsm) to-state)

    ;; Record history
    (push (make-worktree-transition-entry
           :from-state from-state
           :to-state to-state
           :timestamp (get-universal-time)
           :metadata metadata)
          (state-history wsm))

    to-state))

;;; Public Methods

(defmethod bind-worktree ((wsm worktree-state-machine)
                         worktree-id repo-id branch
                         &key (is-home t))
  "Bind the agent to a worktree.

   Transitions from UNBOUND or BIND-FAILED to BOUND-HOME.

   Args:
     wsm: Worktree state machine instance
     worktree-id: Worktree identifier
     repo-id: Repository identifier
     branch: Git branch name
     is-home: If T, this is the home binding (default T)

   Returns:
     The new state

   Signals:
     WORKTREE-STATE-ERROR: If transition is invalid"
  (bt:with-lock-held ((state-lock wsm))
    (let ((binding (make-binding-info
                    :worktree-id worktree-id
                    :repo-id repo-id
                    :branch branch
                    :bound-at (get-universal-time)
                    :expires-at nil)))

      (if is-home
          (progn
            (setf (home-binding wsm) binding)
            (setf (current-binding wsm) binding)
            (%transition-worktree-state wsm :bound-home
                                       :metadata (list :worktree-id worktree-id
                                                      :repo-id repo-id
                                                      :branch branch)))
          (error "Non-home binding must go through switch approval process")))))

(defmethod unbind-worktree ((wsm worktree-state-machine))
  "Unbind the agent from the current worktree.

   Transitions to UNBOUND state.

   Args:
     wsm: Worktree state machine instance

   Returns:
     The new state

   Signals:
     WORKTREE-STATE-ERROR: If transition is invalid"
  (bt:with-lock-held ((state-lock wsm))
    (let ((old-binding (current-binding wsm)))
      (setf (current-binding wsm) nil)
      (setf (pending-switch wsm) nil)
      (%transition-worktree-state wsm :unbound
                                 :metadata (list :old-worktree-id
                                               (when old-binding
                                                 (binding-info-worktree-id old-binding)))))))

(defmethod request-switch ((wsm worktree-state-machine)
                          worktree-id repo-id branch)
  "Request a switch to a non-home worktree.

   Transitions from BOUND-HOME to SWITCH-PENDING.

   Args:
     wsm: Worktree state machine instance
     worktree-id: Target worktree identifier
     repo-id: Target repository identifier
     branch: Target git branch name

   Returns:
     The new state

   Signals:
     WORKTREE-STATE-ERROR: If transition is invalid"
  (bt:with-lock-held ((state-lock wsm))
    (let ((binding (make-binding-info
                    :worktree-id worktree-id
                    :repo-id repo-id
                    :branch branch
                    :bound-at nil
                    :expires-at nil)))
      (setf (pending-switch wsm) binding)
      (%transition-worktree-state wsm :switch-pending
                                 :metadata (list :worktree-id worktree-id
                                               :repo-id repo-id
                                               :branch branch)))))

(defmethod approve-switch-local ((wsm worktree-state-machine))
  "Approve a pending worktree switch.

   Transitions from SWITCH-PENDING to BOUND-NON-HOME.

   Args:
     wsm: Worktree state machine instance

   Returns:
     The new state

   Signals:
     WORKTREE-STATE-ERROR: If transition is invalid or no pending switch"
  (bt:with-lock-held ((state-lock wsm))
    (unless (pending-switch wsm)
      (error 'worktree-state-error
             :from-state (worktree-state wsm)
             :to-state :bound-non-home
             :reason "No pending switch to approve"))

    (let* ((binding (pending-switch wsm))
           (now (get-universal-time)))
      (setf (binding-info-bound-at binding) now)
      (setf (binding-info-expires-at binding)
            (+ now (switch-ttl wsm)))
      (setf (current-binding wsm) binding)
      (setf (pending-switch wsm) nil)
      (%transition-worktree-state wsm :bound-non-home
                                 :metadata (list :worktree-id
                                               (binding-info-worktree-id binding)
                                               :expires-at
                                               (binding-info-expires-at binding))))))

(defmethod reject-switch-local ((wsm worktree-state-machine))
  "Reject a pending worktree switch.

   Transitions from SWITCH-PENDING back to BOUND-HOME.

   Args:
     wsm: Worktree state machine instance

   Returns:
     The new state

   Signals:
     WORKTREE-STATE-ERROR: If transition is invalid"
  (bt:with-lock-held ((state-lock wsm))
    (setf (pending-switch wsm) nil)
    (setf (current-binding wsm) (home-binding wsm))
    (%transition-worktree-state wsm :bound-home
                               :metadata (list :reason "switch-rejected"))))

(defmethod revert-to-home ((wsm worktree-state-machine))
  "Revert from non-home binding to home binding.

   Transitions from BOUND-NON-HOME to BOUND-HOME (TTL expiry or manual revoke).

   Args:
     wsm: Worktree state machine instance

   Returns:
     The new state

   Signals:
     WORKTREE-STATE-ERROR: If transition is invalid"
  (bt:with-lock-held ((state-lock wsm))
    (setf (current-binding wsm) (home-binding wsm))
    (%transition-worktree-state wsm :bound-home
                               :metadata (list :reason "reverted-to-home"))))

(defmethod check-ttl-expiry ((wsm worktree-state-machine))
  "Check if the current non-home binding has expired.

   If expired, automatically revert to home.

   Args:
     wsm: Worktree state machine instance

   Returns:
     T if binding was expired and reverted, NIL otherwise"
  (bt:with-lock-held ((state-lock wsm))
    (when (and (eq (worktree-state wsm) :bound-non-home)
               (current-binding wsm))
      (let ((expires-at (binding-info-expires-at (current-binding wsm))))
        (when (and expires-at (>= (get-universal-time) expires-at))
          (revert-to-home wsm)
          t)))))

(defmethod get-current-worktree ((wsm worktree-state-machine))
  "Get the current worktree binding information.

   Args:
     wsm: Worktree state machine instance

   Returns:
     binding-info struct or NIL if unbound"
  (current-binding wsm))

(defmethod get-home-worktree ((wsm worktree-state-machine))
  "Get the home worktree binding information.

   Args:
     wsm: Worktree state machine instance

   Returns:
     binding-info struct or NIL if not set"
  (home-binding wsm))

(defmethod get-pending-switch ((wsm worktree-state-machine))
  "Get the pending switch request information.

   Args:
     wsm: Worktree state machine instance

   Returns:
     binding-info struct or NIL if no pending switch"
  (pending-switch wsm))

(defmethod print-object ((wsm worktree-state-machine) stream)
  "Print worktree state machine in readable format."
  (print-unreadable-object (wsm stream :type t)
    (format stream "state=~A" (worktree-state wsm))
    (when (current-binding wsm)
      (format stream " worktree=~A"
              (binding-info-worktree-id (current-binding wsm))))))
