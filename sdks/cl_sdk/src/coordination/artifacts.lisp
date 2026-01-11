;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; coordination/artifacts.lisp
;;;;
;;;; Shared Artifact Registry for Cross-Swarm Coordination
;;;;
;;;; This module implements a shared registry for artifacts that can be published
;;;; and discovered across sw4rm instances. Artifacts represent shared state like:
;;;;   - Trained models
;;;;   - Configuration data
;;;;   - Checkpoint states
;;;;   - Intermediate computation results
;;;;
;;;; Key concepts:
;;;;   - SHARED-ARTIFACT-REGISTRY: Central registry for all artifacts
;;;;   - ARTIFACT: A versioned, typed piece of shared data
;;;;   - Locking: Optimistic locking for concurrent access control
;;;;   - Versioning: Track artifact evolution over time
;;;;
;;;; Use cases:
;;;;   - Model sharing: One swarm trains a model, others consume it
;;;;   - Configuration distribution: Update config across all swarms
;;;;   - Checkpoint coordination: Ensure consistent snapshots
;;;;   - Result aggregation: Collect partial results from multiple swarms
;;;;
;;;; Thread Safety:
;;;;   This implementation uses bordeaux-threads for thread-safe operations.
;;;;   Multiple threads can safely access the registry concurrently.
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.coordination)

;;;; ============================================================================
;;;; ARTIFACT Structure
;;;; ============================================================================

(defstruct (artifact (:conc-name artifact-))
  "Shared artifact with metadata and versioning.

  An artifact represents a piece of shared data that can be published by one
  swarm and consumed by others. Each artifact has:
    - Unique ID for lookup
    - Type classification
    - Value (any Lisp object)
    - Metadata for application-specific info
    - Version tracking
    - Lifecycle timestamps

  Slots:
    id - Unique string identifier
    type - Keyword indicating artifact category
    value - Actual data (any Lisp object, must be serializable)
    metadata - Property list with arbitrary key-value pairs
    created-at - Universal time when artifact was first registered
    updated-at - Universal time of last update
    version - Integer version number (incremented on update)

  Example:
    (make-artifact
      :id \"model-v1\"
      :type :model
      :value model-weights
      :metadata (list :accuracy 0.95 :training-swarm \"swarm-a\"))

  See Also:
    REGISTER-ARTIFACT, UPDATE-ARTIFACT, GET-ARTIFACT"
  (id (error "Artifact ID required") :type string :read-only t)
  (type :data :type keyword)
  (value nil :type t)
  (metadata nil :type list)
  (created-at (get-universal-time) :type integer :read-only t)
  (updated-at (get-universal-time) :type integer)
  (version 1 :type (integer 1)))

;;;; ============================================================================
;;;; Lock Information
;;;; ============================================================================

(defstruct (lock-info (:conc-name lock-info-))
  "Lock information for artifact access control.

  Tracks which swarm currently holds a lock on an artifact.

  Slots:
    holder - Swarm ID that owns the lock
    token - Unique token identifying this lock acquisition
    acquired-at - When the lock was acquired
    expires-at - When the lock will expire (NIL for no expiration)"
  (holder nil :type (or null string))
  (token nil :type (or null string))
  (acquired-at (get-universal-time) :type integer)
  (expires-at nil :type (or null integer)))

;;;; ============================================================================
;;;; SHARED-ARTIFACT-REGISTRY Class
;;;; ============================================================================

(defclass shared-artifact-registry ()
  ((artifacts
    :accessor registry-artifacts
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping artifact-id -> ARTIFACT.

    Primary storage for all registered artifacts.")

   (owners
    :accessor registry-owners
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping artifact-id -> owning-swarm-id.

    Tracks which swarm originally registered each artifact.")

   (locks
    :accessor registry-locks
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping artifact-id -> LOCK-INFO.

    Tracks which artifacts are currently locked and by whom.")

   (version-map
    :accessor registry-version-map
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping artifact-id -> version number.

    Redundant with artifact version field, but enables fast version checks.")

   (history
    :accessor registry-history
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping artifact-id -> list of historical versions.

    Each entry is a list of (timestamp . artifact) pairs, newest first.")

   (registry-lock
    :reader registry-lock
    :initform (bt:make-lock "artifact-registry-lock")
    :documentation "Lock for thread-safe registry operations."))

  (:documentation "Shared registry for cross-swarm artifacts.

  The artifact registry is a central coordination point where sw4rms can
  publish, discover, and update shared data. It provides:
    - Registration: Add new artifacts to the registry
    - Discovery: Query artifacts by ID, type, or owner
    - Versioning: Track artifact evolution over time
    - Locking: Prevent concurrent modifications
    - History: Maintain audit trail of changes

  Primary operations:
    - REGISTER-ARTIFACT: Add new artifact to registry
    - GET-ARTIFACT: Retrieve artifact by ID
    - UPDATE-ARTIFACT: Modify existing artifact
    - DELETE-ARTIFACT: Remove artifact from registry
    - LIST-ARTIFACTS: Query artifacts with filters

  Locking operations:
    - ACQUIRE-ARTIFACT-LOCK: Get exclusive access to artifact
    - RELEASE-ARTIFACT-LOCK: Release lock
    - WITH-ARTIFACT-LOCK: Macro for automatic lock management

  Version control:
    - ARTIFACT-VERSION: Get current version number
    - ARTIFACT-HISTORY: Retrieve historical versions

  Thread Safety:
    All operations are thread-safe and can be called concurrently.

  Example:
    (let ((registry (make-artifact-registry)))
      ;; Register artifact
      (register-artifact registry
                        (make-artifact :id \"config-v1\"
                                      :type :config
                                      :value config-data)
                        \"swarm-a\")

      ;; Retrieve artifact
      (let ((artifact (get-artifact registry \"config-v1\")))
        (format t \"Config: ~A~%\" (artifact-value artifact)))

      ;; Update with locking
      (with-artifact-lock (registry \"config-v1\" \"swarm-b\")
        (update-artifact registry \"config-v1\" new-config
                        :by-swarm \"swarm-b\")))

  See Also:
    ARTIFACT, REGISTER-ARTIFACT, GET-ARTIFACT, ACQUIRE-ARTIFACT-LOCK"))

;;;; ============================================================================
;;;; Constructor
;;;; ============================================================================

(defun make-artifact-registry ()
  "Create a new shared artifact registry.

  Returns:
    New SHARED-ARTIFACT-REGISTRY instance.

  Example:
    (defvar *registry* (make-artifact-registry))

  See Also:
    SHARED-ARTIFACT-REGISTRY, REGISTER-ARTIFACT"
  (make-instance 'shared-artifact-registry))

;;;; ============================================================================
;;;; Registry Operations
;;;; ============================================================================

(defun register-artifact (registry artifact owner-swarm)
  "Register a new artifact in the registry.

  Adds an artifact to the registry with the specified owner. The artifact
  ID must be unique (not already registered).

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    artifact - ARTIFACT structure to register
    owner-swarm - String ID of swarm registering the artifact

  Returns:
    T on success.

  Raises:
    ERROR if artifact with same ID already exists

  Side Effects:
    - Adds artifact to registry-artifacts
    - Records owner in registry-owners
    - Initializes version to 1
    - Creates first history entry

  Thread Safety:
    This operation is thread-safe.

  Example:
    (register-artifact registry
                      (make-artifact :id \"model-1\"
                                    :type :model
                                    :value trained-weights)
                      \"training-swarm\")

  See Also:
    GET-ARTIFACT, UPDATE-ARTIFACT, DELETE-ARTIFACT"
  (declare (type shared-artifact-registry registry)
           (type artifact artifact)
           (type string owner-swarm))

  (bt:with-lock-held ((registry-lock registry))
    (let ((artifact-id (artifact-id artifact)))
      ;; Check for duplicate
      (when (gethash artifact-id (registry-artifacts registry))
        (error "Artifact with ID ~S already registered" artifact-id))

      ;; Register artifact
      (setf (gethash artifact-id (registry-artifacts registry)) artifact
            (gethash artifact-id (registry-owners registry)) owner-swarm
            (gethash artifact-id (registry-version-map registry)) 1)

      ;; Initialize history
      (setf (gethash artifact-id (registry-history registry))
            (list (cons (get-universal-time) (copy-artifact artifact)))))
    t))

(defun get-artifact (registry id)
  "Retrieve artifact by ID.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    id - String ID of artifact to retrieve

  Returns:
    ARTIFACT instance if found, NIL otherwise.

  Thread Safety:
    This operation is thread-safe. Returns a copy to prevent external mutation.

  Example:
    (let ((artifact (get-artifact registry \"config-v1\")))
      (when artifact
        (format t \"Value: ~A~%\" (artifact-value artifact))))

  See Also:
    REGISTER-ARTIFACT, LIST-ARTIFACTS"
  (declare (type shared-artifact-registry registry)
           (type string id))

  (bt:with-lock-held ((registry-lock registry))
    (let ((artifact (gethash id (registry-artifacts registry))))
      (when artifact
        (copy-artifact artifact)))))

(defun update-artifact (registry id new-value &key (by-swarm nil))
  "Update an existing artifact's value.

  Updates the artifact's value, increments version, and records in history.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    id - String ID of artifact to update
    new-value - New value for artifact
    by-swarm - Optional swarm ID performing the update (for auditing)

  Returns:
    Updated ARTIFACT instance.

  Raises:
    ERROR if artifact ID not found
    ERROR if artifact is locked by another swarm

  Side Effects:
    - Updates artifact value
    - Increments version number
    - Updates updated-at timestamp
    - Adds entry to history

  Thread Safety:
    This operation is thread-safe.

  Example:
    (update-artifact registry \"config-v1\" new-config-data
                    :by-swarm \"admin-swarm\")

  See Also:
    REGISTER-ARTIFACT, GET-ARTIFACT, ACQUIRE-ARTIFACT-LOCK"
  (declare (type shared-artifact-registry registry)
           (type string id))

  (bt:with-lock-held ((registry-lock registry))
    (let ((artifact (gethash id (registry-artifacts registry))))
      (unless artifact
        (error "Artifact ~S not found" id))

      ;; Check lock
      (let ((lock (gethash id (registry-locks registry))))
        (when (and lock (lock-info-holder lock))
          (unless (and by-swarm (string= by-swarm (lock-info-holder lock)))
            (error "Artifact ~S is locked by ~A"
                   id (lock-info-holder lock)))))

      ;; Update artifact
      (setf (artifact-value artifact) new-value
            (artifact-updated-at artifact) (get-universal-time))
      (incf (artifact-version artifact))

      ;; Update version map
      (setf (gethash id (registry-version-map registry))
            (artifact-version artifact))

      ;; Add to history
      (push (cons (get-universal-time) (copy-artifact artifact))
            (gethash id (registry-history registry)))

      (copy-artifact artifact))))

(defun delete-artifact (registry id)
  "Remove artifact from registry.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    id - String ID of artifact to delete

  Returns:
    T if artifact was deleted, NIL if not found.

  Raises:
    ERROR if artifact is currently locked

  Side Effects:
    - Removes artifact from all registry tables
    - Clears history (optional: could preserve history)

  Thread Safety:
    This operation is thread-safe.

  Example:
    (when (delete-artifact registry \"temp-data\")
      (format t \"Artifact deleted~%\"))

  See Also:
    REGISTER-ARTIFACT, GET-ARTIFACT"
  (declare (type shared-artifact-registry registry)
           (type string id))

  (bt:with-lock-held ((registry-lock registry))
    (let ((lock (gethash id (registry-locks registry))))
      (when (and lock (lock-info-holder lock))
        (error "Cannot delete locked artifact ~S (locked by ~A)"
               id (lock-info-holder lock))))

    (when (remhash id (registry-artifacts registry))
      (remhash id (registry-owners registry))
      (remhash id (registry-version-map registry))
      (remhash id (registry-history registry))
      t)))

(defun list-artifacts (registry &key type owner)
  "List artifacts matching optional filters.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    type - Optional keyword to filter by artifact type
    owner - Optional string to filter by owner swarm

  Returns:
    List of ARTIFACT instances matching filters.

  Thread Safety:
    This operation is thread-safe. Returns copies to prevent mutation.

  Examples:
    ;; All artifacts
    (list-artifacts registry)

    ;; Only models
    (list-artifacts registry :type :model)

    ;; Only artifacts owned by specific swarm
    (list-artifacts registry :owner \"swarm-a\")

    ;; Combination
    (list-artifacts registry :type :config :owner \"admin\")

  See Also:
    GET-ARTIFACT, REGISTER-ARTIFACT"
  (declare (type shared-artifact-registry registry))

  (bt:with-lock-held ((registry-lock registry))
    (loop for artifact-id being the hash-keys
          of (registry-artifacts registry)
          using (hash-value artifact)
          for artifact-owner = (gethash artifact-id (registry-owners registry))
          when (and (or (null type)
                       (eq type (artifact-type artifact)))
                   (or (null owner)
                       (string= owner artifact-owner)))
          collect (copy-artifact artifact))))

;;;; ============================================================================
;;;; Locking Operations
;;;; ============================================================================

(defun acquire-artifact-lock (registry artifact-id swarm-id &key (timeout 30))
  "Acquire exclusive lock on an artifact.

  Attempts to acquire a lock for the specified swarm. If the artifact is
  already locked by another swarm, waits up to TIMEOUT seconds.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    artifact-id - String ID of artifact to lock
    swarm-id - String ID of swarm requesting lock
    timeout - Maximum seconds to wait for lock (default: 30)

  Returns:
    Lock token (string) if successful.

  Raises:
    ERROR if artifact not found
    ERROR if timeout expires without acquiring lock

  Side Effects:
    - Creates lock entry in registry-locks
    - Sets expiration time if timeout > 0

  Thread Safety:
    This operation is thread-safe.

  Example:
    (let ((token (acquire-artifact-lock registry \"model-1\" \"swarm-a\")))
      (unwind-protect
          ;; Do work with locked artifact
          (update-artifact registry \"model-1\" new-value
                          :by-swarm \"swarm-a\")
        ;; Always release lock
        (release-artifact-lock registry \"model-1\" token)))

  See Also:
    RELEASE-ARTIFACT-LOCK, WITH-ARTIFACT-LOCK"
  (declare (type shared-artifact-registry registry)
           (type string artifact-id swarm-id)
           (type (integer 0) timeout))

  (let ((token (format nil "~A-~A-~A" swarm-id artifact-id (get-universal-time)))
        (start-time (get-universal-time)))

    (loop
      (bt:with-lock-held ((registry-lock registry))
        ;; Check artifact exists
        (unless (gethash artifact-id (registry-artifacts registry))
          (error "Artifact ~S not found" artifact-id))

        ;; Check existing lock
        (let ((existing-lock (gethash artifact-id (registry-locks registry))))
          (cond
            ;; No lock, acquire it
            ((null existing-lock)
             (setf (gethash artifact-id (registry-locks registry))
                   (make-lock-info :holder swarm-id
                                  :token token
                                  :acquired-at (get-universal-time)
                                  :expires-at (when (> timeout 0)
                                               (+ (get-universal-time) timeout))))
             (return-from acquire-artifact-lock token))

            ;; Lock held by us (reentrant)
            ((string= (lock-info-holder existing-lock) swarm-id)
             (return-from acquire-artifact-lock (lock-info-token existing-lock)))

            ;; Lock expired, take it
            ((and (lock-info-expires-at existing-lock)
                  (>= (get-universal-time) (lock-info-expires-at existing-lock)))
             (setf (gethash artifact-id (registry-locks registry))
                   (make-lock-info :holder swarm-id
                                  :token token
                                  :acquired-at (get-universal-time)
                                  :expires-at (when (> timeout 0)
                                               (+ (get-universal-time) timeout))))
             (return-from acquire-artifact-lock token))

            ;; Lock held by someone else
            (t
             ;; Check timeout
             (when (>= (- (get-universal-time) start-time) timeout)
               (error "Timeout acquiring lock on artifact ~S (locked by ~A)"
                      artifact-id (lock-info-holder existing-lock)))
             ;; Release registry lock and wait briefly
             nil))))

      ;; Sleep briefly before retry
      (sleep 0.1))))

(defun release-artifact-lock (registry artifact-id lock-token)
  "Release lock on an artifact.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    artifact-id - String ID of locked artifact
    lock-token - Lock token returned by ACQUIRE-ARTIFACT-LOCK

  Returns:
    T if lock was released, NIL if lock not found or token mismatch.

  Thread Safety:
    This operation is thread-safe.

  Example:
    (release-artifact-lock registry \"model-1\" my-token)

  See Also:
    ACQUIRE-ARTIFACT-LOCK, WITH-ARTIFACT-LOCK"
  (declare (type shared-artifact-registry registry)
           (type string artifact-id lock-token))

  (bt:with-lock-held ((registry-lock registry))
    (let ((existing-lock (gethash artifact-id (registry-locks registry))))
      (when (and existing-lock
                 (string= (lock-info-token existing-lock) lock-token))
        (remhash artifact-id (registry-locks registry))
        t))))

(defmacro with-artifact-lock ((registry artifact-id swarm-id &key (timeout 30))
                              &body body)
  "Execute body with artifact lock held, automatic cleanup.

  Acquires lock before executing body, ensures release even if errors occur.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance (evaluated)
    artifact-id - String ID of artifact (evaluated)
    swarm-id - String ID of swarm (evaluated)
    timeout - Lock acquisition timeout (default: 30)
    body - Forms to execute with lock held

  Example:
    (with-artifact-lock (*registry* \"config-v1\" \"swarm-a\" :timeout 60)
      (let ((artifact (get-artifact *registry* \"config-v1\")))
        (update-artifact *registry* \"config-v1\"
                        (process-config (artifact-value artifact))
                        :by-swarm \"swarm-a\")))

  See Also:
    ACQUIRE-ARTIFACT-LOCK, RELEASE-ARTIFACT-LOCK"
  (let ((token-var (gensym "TOKEN"))
        (registry-var (gensym "REGISTRY"))
        (artifact-var (gensym "ARTIFACT")))
    `(let* ((,registry-var ,registry)
            (,artifact-var ,artifact-id)
            (,token-var (acquire-artifact-lock ,registry-var ,artifact-var
                                              ,swarm-id :timeout ,timeout)))
       (unwind-protect
           (progn ,@body)
         (release-artifact-lock ,registry-var ,artifact-var ,token-var)))))

;;;; ============================================================================
;;;; Version Control
;;;; ============================================================================

(defun artifact-version (registry artifact-id)
  "Get current version number of artifact.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    artifact-id - String ID of artifact

  Returns:
    Integer version number, or NIL if artifact not found.

  Thread Safety:
    This operation is thread-safe.

  Example:
    (let ((version (artifact-version registry \"model-1\")))
      (format t \"Model version: ~D~%\" version))

  See Also:
    ARTIFACT-HISTORY, UPDATE-ARTIFACT"
  (declare (type shared-artifact-registry registry)
           (type string artifact-id))

  (bt:with-lock-held ((registry-lock registry))
    (gethash artifact-id (registry-version-map registry))))

(defun artifact-history (registry artifact-id &key (limit 10))
  "Get historical versions of artifact.

  Returns list of past versions, newest first.

  Args:
    registry - SHARED-ARTIFACT-REGISTRY instance
    artifact-id - String ID of artifact
    limit - Maximum number of versions to return (default: 10, 0 = all)

  Returns:
    List of (timestamp . artifact) pairs, or NIL if artifact not found.

  Thread Safety:
    This operation is thread-safe. Returns copies to prevent mutation.

  Example:
    (let ((history (artifact-history registry \"config-v1\" :limit 5)))
      (dolist (entry history)
        (destructuring-bind (timestamp . artifact) entry
          (format t \"Version ~D at ~A~%\"
                  (artifact-version artifact)
                  timestamp))))

  See Also:
    ARTIFACT-VERSION, GET-ARTIFACT"
  (declare (type shared-artifact-registry registry)
           (type string artifact-id)
           (type (integer 0) limit))

  (bt:with-lock-held ((registry-lock registry))
    (let ((history (gethash artifact-id (registry-history registry))))
      (when history
        (let ((limited-history (if (zerop limit)
                                  history
                                  (subseq history 0 (min limit (length history))))))
          ;; Copy artifacts to prevent mutation
          (loop for (timestamp . artifact) in limited-history
                collect (cons timestamp (copy-artifact artifact))))))))

;;;; ============================================================================
;;;; Helper Functions
;;;; ============================================================================

(defun copy-artifact (artifact)
  "Create a deep copy of an artifact.

  Args:
    artifact - ARTIFACT to copy

  Returns:
    New ARTIFACT with copied fields.

  Note:
    This performs a shallow copy of the value field. If the value contains
    mutable structures, they are not deep-copied."
  (make-artifact :id (artifact-id artifact)
                :type (artifact-type artifact)
                :value (artifact-value artifact)
                :metadata (copy-list (artifact-metadata artifact))
                :created-at (artifact-created-at artifact)
                :updated-at (artifact-updated-at artifact)
                :version (artifact-version artifact)))

;;;; ============================================================================
;;;; Print Methods
;;;; ============================================================================

(defmethod print-object ((registry shared-artifact-registry) stream)
  "Print human-readable representation of SHARED-ARTIFACT-REGISTRY.

  Format: #<SHARED-ARTIFACT-REGISTRY artifacts=5 locks=2>"
  (print-unreadable-object (registry stream :type t)
    (bt:with-lock-held ((registry-lock registry))
      (format stream "artifacts=~D locks=~D"
              (hash-table-count (registry-artifacts registry))
              (hash-table-count (registry-locks registry))))))

;;;; End of file
