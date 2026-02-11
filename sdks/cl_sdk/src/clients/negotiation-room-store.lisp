;;;; negotiation-room-store.lisp - Storage backends for negotiation room data
;;;;
;;;; Provides in-memory and file-based storage for negotiation room proposals,
;;;; votes, and decisions.

(in-package :sw4rm)

;;;; Storage Protocol

(defclass negotiation-room-store ()
  ()
  (:documentation "Abstract base class for negotiation room storage backends.

Storage backends provide persistence for:
- Artifact proposals
- Critic votes
- Final decisions

Concrete implementations can use in-memory storage (for single-process
or testing), file-based storage (JSON), or distributed storage (database,
distributed cache)."))

;;;; Generic Operations

(defgeneric save-proposal (store proposal)
  (:documentation "Save an artifact proposal to storage.

Args:
  store: The storage backend instance.
  proposal: Proposal plist to save.

Signals:
  ERROR: If a proposal with the same artifact-id already exists."))

(defmethod save-proposal ((store negotiation-room-store) proposal)
  (error 'rpc-error
         :message "save-proposal not implemented for base class"
         :code "UNIMPLEMENTED"))

(defgeneric has-proposal (store artifact-id)
  (:documentation "Check if a proposal exists in storage.

Args:
  store: The storage backend instance.
  artifact-id: The artifact identifier.

Returns:
  T if proposal exists, NIL otherwise."))

(defmethod has-proposal ((store negotiation-room-store) artifact-id)
  (error 'rpc-error
         :message "has-proposal not implemented for base class"
         :code "UNIMPLEMENTED"))

(defgeneric get-proposal (store artifact-id)
  (:documentation "Retrieve a proposal from storage.

Args:
  store: The storage backend instance.
  artifact-id: The artifact identifier.

Returns:
  Proposal plist if found, NIL otherwise."))

(defmethod get-proposal ((store negotiation-room-store) artifact-id)
  (error 'rpc-error
         :message "get-proposal not implemented for base class"
         :code "UNIMPLEMENTED"))

(defgeneric add-vote (store vote)
  (:documentation "Add a vote to storage.

Args:
  store: The storage backend instance.
  vote: Vote plist to add.

Signals:
  ERROR: If the critic has already voted for this artifact."))

(defmethod add-vote ((store negotiation-room-store) vote)
  (error 'rpc-error
         :message "add-vote not implemented for base class"
         :code "UNIMPLEMENTED"))

(defgeneric get-votes (store artifact-id)
  (:documentation "Retrieve all votes for an artifact.

Args:
  store: The storage backend instance.
  artifact-id: The artifact identifier.

Returns:
  List of vote plists (empty list if no votes)."))

(defmethod get-votes ((store negotiation-room-store) artifact-id)
  (error 'rpc-error
         :message "get-votes not implemented for base class"
         :code "UNIMPLEMENTED"))

(defgeneric save-decision (store decision)
  (:documentation "Save a decision to storage.

Args:
  store: The storage backend instance.
  decision: Decision plist to save.

Signals:
  ERROR: If a decision already exists for this artifact."))

(defmethod save-decision ((store negotiation-room-store) decision)
  (error 'rpc-error
         :message "save-decision not implemented for base class"
         :code "UNIMPLEMENTED"))

(defgeneric get-decision (store artifact-id)
  (:documentation "Retrieve a decision from storage.

Args:
  store: The storage backend instance.
  artifact-id: The artifact identifier.

Returns:
  Decision plist if found, NIL otherwise."))

(defmethod get-decision ((store negotiation-room-store) artifact-id)
  (error 'rpc-error
         :message "get-decision not implemented for base class"
         :code "UNIMPLEMENTED"))

(defgeneric list-proposals (store &optional negotiation-room-id)
  (:documentation "List all proposals, optionally filtered by room.

Args:
  store: The storage backend instance.
  negotiation-room-id: Optional room ID filter.

Returns:
  List of proposal plists matching the filter criteria."))

(defmethod list-proposals ((store negotiation-room-store) &optional negotiation-room-id)
  (error 'rpc-error
         :message "list-proposals not implemented for base class"
         :code "UNIMPLEMENTED"))

;;;; In-Memory Store Implementation

(defclass in-memory-negotiation-room-store (negotiation-room-store)
  ((proposals
    :initform (make-hash-table :test 'equal)
    :accessor store-proposals
    :documentation "Hash table: artifact-id -> proposal plist")
   (votes
    :initform (make-hash-table :test 'equal)
    :accessor store-votes
    :documentation "Hash table: artifact-id -> list of vote plists")
   (decisions
    :initform (make-hash-table :test 'equal)
    :accessor store-decisions
    :documentation "Hash table: artifact-id -> decision plist")
   (lock
    :initform (bordeaux-threads:make-lock "negotiation-room-store-lock")
    :accessor store-lock
    :documentation "Lock for thread-safe access"))
  (:documentation "In-memory storage backend for negotiation room data.

Suitable for single-process deployments and testing. All data is held
in memory and will be lost on process restart. For persistence, use
JSON-file-negotiation-room-store or a database-backed store.

Thread-safe using locks for concurrent access."))

(defmethod save-proposal ((store in-memory-negotiation-room-store) proposal)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (let ((artifact-id (getf proposal :artifact-id)))
      (when (gethash artifact-id (store-proposals store))
        (error "Proposal with artifact-id ~S already exists" artifact-id))
      (setf (gethash artifact-id (store-proposals store)) proposal)
      ;; Initialize empty vote list
      (setf (gethash artifact-id (store-votes store)) '()))))

(defmethod has-proposal ((store in-memory-negotiation-room-store) artifact-id)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (not (null (gethash artifact-id (store-proposals store))))))

(defmethod get-proposal ((store in-memory-negotiation-room-store) artifact-id)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (gethash artifact-id (store-proposals store))))

(defmethod add-vote ((store in-memory-negotiation-room-store) vote)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (let ((artifact-id (getf vote :artifact-id))
          (critic-id (getf vote :critic-id)))
      (unless (gethash artifact-id (store-proposals store))
        (error "No proposal found for artifact-id ~S" artifact-id))
      (let ((existing-votes (gethash artifact-id (store-votes store))))
        (when (find critic-id existing-votes :key (lambda (v) (getf v :critic-id)) :test #'string=)
          (error "Critic ~S has already voted for artifact ~S" critic-id artifact-id))
        (setf (gethash artifact-id (store-votes store))
              (append existing-votes (list vote)))))))

(defmethod get-votes ((store in-memory-negotiation-room-store) artifact-id)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (gethash artifact-id (store-votes store) '())))

(defmethod save-decision ((store in-memory-negotiation-room-store) decision)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (let ((artifact-id (getf decision :artifact-id)))
      (unless (gethash artifact-id (store-proposals store))
        (error "No proposal found for artifact-id ~S" artifact-id))
      (when (gethash artifact-id (store-decisions store))
        (error "Decision already exists for artifact-id ~S" artifact-id))
      (setf (gethash artifact-id (store-decisions store)) decision))))

(defmethod get-decision ((store in-memory-negotiation-room-store) artifact-id)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (gethash artifact-id (store-decisions store))))

(defmethod list-proposals ((store in-memory-negotiation-room-store) &optional negotiation-room-id)
  (bordeaux-threads:with-lock-held ((store-lock store))
    (let ((all-proposals '()))
      (maphash (lambda (k v)
                 (declare (ignore k))
                 (push v all-proposals))
               (store-proposals store))
      (if negotiation-room-id
          (remove-if-not (lambda (p) (string= (getf p :negotiation-room-id) negotiation-room-id))
                         all-proposals)
          all-proposals))))

;;;; JSON File Store Implementation (Placeholder)

(defclass json-file-negotiation-room-store (negotiation-room-store)
  ((directory
    :initarg :directory
    :accessor store-directory
    :type string
    :documentation "Directory path for JSON file storage"))
  (:documentation "File-based JSON storage backend for negotiation room data.

Stores proposals, votes, and decisions as JSON files in the specified
directory. Suitable for persistent single-node deployments.

Implementation Note:
This is a placeholder. Actual implementation requires JSON library
(e.g., cl-json, jzon) and file I/O operations."))

(defmethod save-proposal ((store json-file-negotiation-room-store) proposal)
  ;; Stub: Would serialize proposal to JSON and write to file
  (error 'rpc-error
         :message "JSON file store not implemented - requires JSON library integration"
         :code "UNIMPLEMENTED"))

(defmethod has-proposal ((store json-file-negotiation-room-store) artifact-id)
  ;; Stub: Would check if file exists
  (error 'rpc-error
         :message "JSON file store not implemented - requires JSON library integration"
         :code "UNIMPLEMENTED"))

(defmethod get-proposal ((store json-file-negotiation-room-store) artifact-id)
  ;; Stub: Would read and deserialize JSON file
  (error 'rpc-error
         :message "JSON file store not implemented - requires JSON library integration"
         :code "UNIMPLEMENTED"))

;;;; Default Store Singleton

(defvar *default-negotiation-room-store* nil
  "Shared default in-memory store for negotiation room clients.

All clients in the same process can share this store by default,
enabling state sharing without explicit store passing.")

(defun get-default-store ()
  "Get or create the default shared negotiation room store.

Returns:
  The shared in-memory-negotiation-room-store instance."
  (unless *default-negotiation-room-store*
    (setf *default-negotiation-room-store*
          (make-instance 'in-memory-negotiation-room-store)))
  *default-negotiation-room-store*)
