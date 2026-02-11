;;;; policy-store.lisp
;;;; Policy storage and retrieval for SW4RM SDK

(in-package :sw4rm-sdk)

;;; Condition Types

(define-condition policy-not-found (error)
  ((policy-id :initarg :policy-id :reader policy-id))
  (:report (lambda (condition stream)
             (format stream "Policy not found: ~A" (policy-id condition))))
  (:documentation "Signaled when a requested policy is not found."))

(define-condition policy-store-error (error)
  ((store :initarg :store :reader store)
   (operation :initarg :operation :reader operation)
   (reason :initarg :reason :reader reason))
  (:report (lambda (condition stream)
             (format stream "Policy store error in ~A during ~A: ~A"
                     (store condition)
                     (operation condition)
                     (reason condition))))
  (:documentation "Signaled when a policy store operation fails."))

;;; Policy Data Structure

(defstruct policy
  "A policy defining rules or constraints."
  (policy-id nil :type (or null string))
  (name nil :type (or null string))
  (description nil :type (or null string))
  (rules nil :type list)
  (enabled t :type boolean)
  (created-at (get-universal-time) :type integer)
  (updated-at (get-universal-time) :type integer)
  (metadata nil :type list))

;;; Policy Store Protocol

(defgeneric get-policy (store policy-id)
  (:documentation "Retrieve a policy by ID.

   Args:
     store: Policy store instance
     policy-id: Policy identifier (string)

   Returns:
     policy struct or NIL if not found"))

(defgeneric set-policy (store policy)
  (:documentation "Store or update a policy.

   Args:
     store: Policy store instance
     policy: policy struct to store

   Returns:
     The policy-id"))

(defgeneric delete-policy (store policy-id)
  (:documentation "Delete a policy.

   Args:
     store: Policy store instance
     policy-id: Policy identifier (string)

   Returns:
     T if deleted, NIL if not found"))

(defgeneric list-policies (store &key enabled-only)
  (:documentation "List all policies in the store.

   Args:
     store: Policy store instance
     enabled-only: If T, only return enabled policies

   Returns:
     List of policy structs"))

;;; In-Memory Policy Store

(defclass in-memory-policy-store ()
  ((policies
    :accessor store-policies
    :type hash-table
    :initform (make-hash-table :test 'equal)
    :documentation "Hash table mapping policy-id to policy struct.")

   (lock
    :accessor store-lock
    :initform (bt:make-lock "policy-store-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "In-memory policy store.
                   Policies are stored in a hash table and lost on restart."))

(defmethod get-policy ((store in-memory-policy-store) policy-id)
  "Get a policy from the in-memory store.

   Args:
     store: in-memory-policy-store instance
     policy-id: Policy identifier

   Returns:
     policy struct or NIL if not found"
  (gethash policy-id (store-policies store)))

(defmethod set-policy ((store in-memory-policy-store) policy)
  "Set a policy in the in-memory store.

   Args:
     store: in-memory-policy-store instance
     policy: policy struct

   Returns:
     The policy-id"
  (bt:with-lock-held ((store-lock store))
    (unless (policy-policy-id policy)
      (setf (policy-policy-id policy)
            (format nil "policy-~A-~A" (get-universal-time) (random 1000000))))

    (setf (policy-updated-at policy) (get-universal-time))
    (setf (gethash (policy-policy-id policy) (store-policies store)) policy)
    (policy-policy-id policy)))

(defmethod delete-policy ((store in-memory-policy-store) policy-id)
  "Delete a policy from the in-memory store.

   Args:
     store: in-memory-policy-store instance
     policy-id: Policy identifier

   Returns:
     T if deleted, NIL if not found"
  (bt:with-lock-held ((store-lock store))
    (remhash policy-id (store-policies store))))

(defmethod list-policies ((store in-memory-policy-store) &key (enabled-only nil))
  "List all policies in the in-memory store.

   Args:
     store: in-memory-policy-store instance
     enabled-only: If T, only return enabled policies

   Returns:
     List of policy structs"
  (let ((results nil))
    (maphash (lambda (id policy)
               (declare (ignore id))
               (when (or (not enabled-only) (policy-enabled policy))
                 (push policy results)))
             (store-policies store))
    results))

(defmethod clear-all-policies ((store in-memory-policy-store))
  "Clear all policies from the store.

   Args:
     store: in-memory-policy-store instance

   Returns:
     Number of policies removed"
  (bt:with-lock-held ((store-lock store))
    (let ((count (hash-table-count (store-policies store))))
      (clrhash (store-policies store))
      count)))

;;; JSON File Policy Store

(defclass json-file-policy-store ()
  ((file-path
    :initarg :file-path
    :accessor store-file-path
    :type pathname
    :initform (merge-pathnames ".sw4rm/policies.json" (user-homedir-pathname))
    :documentation "Path to JSON file storing policies.")

   (cache
    :accessor store-cache
    :type hash-table
    :initform (make-hash-table :test 'equal)
    :documentation "In-memory cache of policies.")

   (lock
    :accessor store-lock
    :initform (bt:make-lock "json-policy-store-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "JSON file-based policy store.
                   Policies are cached in memory and persisted to disk."))

(defmethod initialize-instance :after ((store json-file-policy-store) &key)
  "Load policies from file on initialization."
  (load-policies-from-file store))

(defun policy-to-alist (policy)
  "Convert a policy struct to an alist for JSON encoding.

   Args:
     policy: policy struct

   Returns:
     Association list"
  (list (cons :policy-id (policy-policy-id policy))
        (cons :name (policy-name policy))
        (cons :description (policy-description policy))
        (cons :rules (policy-rules policy))
        (cons :enabled (policy-enabled policy))
        (cons :created-at (policy-created-at policy))
        (cons :updated-at (policy-updated-at policy))
        (cons :metadata (policy-metadata policy))))

(defun alist-to-policy (alist)
  "Convert an alist to a policy struct.

   Args:
     alist: Association list from JSON

   Returns:
     policy struct"
  (make-policy
   :policy-id (cdr (assoc :policy-id alist))
   :name (cdr (assoc :name alist))
   :description (cdr (assoc :description alist))
   :rules (cdr (assoc :rules alist))
   :enabled (cdr (assoc :enabled alist))
   :created-at (cdr (assoc :created-at alist))
   :updated-at (cdr (assoc :updated-at alist))
   :metadata (cdr (assoc :metadata alist))))

(defun load-policies-from-file (store)
  "Load policies from JSON file into cache.

   Args:
     store: json-file-policy-store instance"
  (bt:with-lock-held ((store-lock store))
    (let ((file-path (store-file-path store)))
      (when (probe-file file-path)
        (handler-case
            (with-open-file (stream file-path :direction :input)
              (let ((json-data (json:decode-json stream)))
                (clrhash (store-cache store))
                (dolist (policy-alist json-data)
                  (let ((policy (alist-to-policy policy-alist)))
                    (setf (gethash (policy-policy-id policy) (store-cache store)) policy)))))
          (error (e)
            (warn "Failed to load policies from ~A: ~A" file-path e)))))))

(defun save-policies-to-file (store)
  "Save policies from cache to JSON file.

   Args:
     store: json-file-policy-store instance"
  (bt:with-lock-held ((store-lock store))
    (let ((file-path (store-file-path store))
          (policies nil))

      ;; Build list of policy alists
      (maphash (lambda (id policy)
                 (declare (ignore id))
                 (push (policy-to-alist policy) policies))
               (store-cache store))

      ;; Write to file
      (handler-case
          (progn
            (ensure-directories-exist file-path)
            (with-open-file (stream file-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
              (json:encode-json policies stream)))
        (error (e)
          (error 'policy-store-error
                 :store store
                 :operation :save
                 :reason (format nil "~A" e)))))))

(defmethod get-policy ((store json-file-policy-store) policy-id)
  "Get a policy from the JSON file store.

   Args:
     store: json-file-policy-store instance
     policy-id: Policy identifier

   Returns:
     policy struct or NIL if not found"
  (gethash policy-id (store-cache store)))

(defmethod set-policy ((store json-file-policy-store) policy)
  "Set a policy in the JSON file store.

   Args:
     store: json-file-policy-store instance
     policy: policy struct

   Returns:
     The policy-id"
  (bt:with-lock-held ((store-lock store))
    (unless (policy-policy-id policy)
      (setf (policy-policy-id policy)
            (format nil "policy-~A-~A" (get-universal-time) (random 1000000))))

    (setf (policy-updated-at policy) (get-universal-time))
    (setf (gethash (policy-policy-id policy) (store-cache store)) policy)
    (save-policies-to-file store)
    (policy-policy-id policy)))

(defmethod delete-policy ((store json-file-policy-store) policy-id)
  "Delete a policy from the JSON file store.

   Args:
     store: json-file-policy-store instance
     policy-id: Policy identifier

   Returns:
     T if deleted, NIL if not found"
  (bt:with-lock-held ((store-lock store))
    (let ((existed (remhash policy-id (store-cache store))))
      (when existed
        (save-policies-to-file store))
      existed)))

(defmethod list-policies ((store json-file-policy-store) &key (enabled-only nil))
  "List all policies in the JSON file store.

   Args:
     store: json-file-policy-store instance
     enabled-only: If T, only return enabled policies

   Returns:
     List of policy structs"
  (let ((results nil))
    (maphash (lambda (id policy)
               (declare (ignore id))
               (when (or (not enabled-only) (policy-enabled policy))
                 (push policy results)))
             (store-cache store))
    results))

;;; Utility Functions

(defun make-in-memory-policy-store ()
  "Create an in-memory policy store.

   Returns:
     in-memory-policy-store instance"
  (make-instance 'in-memory-policy-store))

(defun make-json-file-policy-store (&optional (file-path nil))
  "Create a JSON file policy store.

   Args:
     file-path: Optional path to policy file (defaults to ~/.sw4rm/policies.json)

   Returns:
     json-file-policy-store instance"
  (if file-path
      (make-instance 'json-file-policy-store :file-path file-path)
      (make-instance 'json-file-policy-store)))

(defun create-policy (&key policy-id name description rules enabled metadata)
  "Create a policy struct.

   Args:
     policy-id: Optional policy ID (generated if not provided)
     name: Policy name
     description: Policy description
     rules: List of rules (format depends on policy type)
     enabled: Whether policy is enabled (default T)
     metadata: Optional metadata plist

   Returns:
     policy struct"
  (make-policy
   :policy-id (or policy-id
                 (format nil "policy-~A-~A" (get-universal-time) (random 1000000)))
   :name name
   :description description
   :rules rules
   :enabled (if (null enabled) t enabled)
   :metadata metadata))
