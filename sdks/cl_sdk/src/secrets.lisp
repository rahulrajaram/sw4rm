;;;; secrets.lisp
;;;; Secret management and resolution for SW4RM SDK

(in-package :sw4rm-sdk)

;;; Condition Types

(define-condition secret-not-found (error)
  ((secret-key :initarg :secret-key :reader secret-key))
  (:report (lambda (condition stream)
             (format stream "Secret not found: ~A" (secret-key condition))))
  (:documentation "Signaled when a requested secret is not found in any backend."))

(define-condition secret-backend-error (error)
  ((backend :initarg :backend :reader backend)
   (operation :initarg :operation :reader operation)
   (reason :initarg :reason :reader reason))
  (:report (lambda (condition stream)
             (format stream "Secret backend error in ~A during ~A: ~A"
                     (backend condition)
                     (operation condition)
                     (reason condition))))
  (:documentation "Signaled when a secret backend operation fails."))

;;; Secret Backend Protocol

(defgeneric get-secret (backend key)
  (:documentation "Retrieve a secret value by key.

   Args:
     backend: Secret backend instance
     key: Secret key (string)

   Returns:
     Secret value (string) or NIL if not found"))

(defgeneric set-secret (backend key value)
  (:documentation "Store a secret value.

   Args:
     backend: Secret backend instance
     key: Secret key (string)
     value: Secret value (string)

   Returns:
     T on success"))

(defgeneric delete-secret (backend key)
  (:documentation "Delete a secret.

   Args:
     backend: Secret backend instance
     key: Secret key (string)

   Returns:
     T if deleted, NIL if not found"))

(defgeneric list-secrets (backend)
  (:documentation "List all secret keys in the backend.

   Args:
     backend: Secret backend instance

   Returns:
     List of secret keys (strings)"))

;;; File-Based Secret Backend

(defclass file-backend ()
  ((file-path
    :initarg :file-path
    :accessor backend-file-path
    :type string
    :initform (merge-pathnames ".secrets.json" (user-homedir-pathname))
    :documentation "Path to JSON file storing secrets.")

   (cache
    :accessor backend-cache
    :type hash-table
    :initform (make-hash-table :test 'equal)
    :documentation "In-memory cache of secrets.")

   (lock
    :accessor backend-lock
    :initform (bt:make-recursive-lock "file-backend-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "File-based secret backend storing secrets in a JSON file.
                   Secrets are cached in memory and persisted to disk."))

(defmethod initialize-instance :after ((backend file-backend) &key)
  "Load secrets from file on initialization."
  (load-secrets-from-file backend))

(defun load-secrets-from-file (backend)
  "Load secrets from JSON file into cache.

   Args:
     backend: file-backend instance"
  (bt:with-recursive-lock-held ((backend-lock backend))
    (let ((file-path (backend-file-path backend)))
      (when (probe-file file-path)
        (handler-case
            (with-open-file (stream file-path :direction :input)
              (let ((json-data (json:decode-json stream)))
                (clrhash (backend-cache backend))
                (dolist (entry json-data)
                  (let ((key (cdr (assoc :key entry)))
                        (value (cdr (assoc :value entry))))
                    (setf (gethash key (backend-cache backend)) value)))))
          (error (e)
            (warn "Failed to load secrets from ~A: ~A" file-path e)))))))

(defun save-secrets-to-file (backend)
  "Save secrets from cache to JSON file.

   Args:
     backend: file-backend instance"
  (bt:with-recursive-lock-held ((backend-lock backend))
    (let ((file-path (backend-file-path backend))
          (entries nil))

      ;; Build list of entries
      (maphash (lambda (key value)
                 (push (list (cons :key key)
                           (cons :value value))
                       entries))
               (backend-cache backend))

      ;; Write to file
      (handler-case
          (progn
            (ensure-directories-exist file-path)
            (with-open-file (stream file-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
              (json:encode-json entries stream)))
        (error (e)
          (error 'secret-backend-error
                 :backend backend
                 :operation :save
                 :reason (format nil "~A" e)))))))

(defmethod get-secret ((backend file-backend) key)
  "Get a secret from the file backend.

   Args:
     backend: file-backend instance
     key: Secret key

   Returns:
     Secret value or NIL if not found"
  (gethash key (backend-cache backend)))

(defmethod set-secret ((backend file-backend) key value)
  "Set a secret in the file backend.

   Args:
     backend: file-backend instance
     key: Secret key
     value: Secret value

   Returns:
     T"
  (bt:with-recursive-lock-held ((backend-lock backend))
    (setf (gethash key (backend-cache backend)) value)
    (save-secrets-to-file backend)
    t))

(defmethod delete-secret ((backend file-backend) key)
  "Delete a secret from the file backend.

   Args:
     backend: file-backend instance
     key: Secret key

   Returns:
     T if deleted, NIL if not found"
  (bt:with-recursive-lock-held ((backend-lock backend))
    (let ((existed (remhash key (backend-cache backend))))
      (when existed
        (save-secrets-to-file backend))
      existed)))

(defmethod list-secrets ((backend file-backend))
  "List all secret keys in the file backend.

   Args:
     backend: file-backend instance

   Returns:
     List of secret keys"
  (let ((keys nil))
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             (backend-cache backend))
    keys))

;;; Environment Variable Backend

(defclass env-backend ()
  ((prefix
    :initarg :prefix
    :accessor env-prefix
    :type string
    :initform "SW4RM_SECRET_"
    :documentation "Prefix for environment variable names."))
  (:documentation "Secret backend that reads from environment variables.
                   Read-only backend."))

(defmethod get-secret ((backend env-backend) key)
  "Get a secret from environment variables.

   Args:
     backend: env-backend instance
     key: Secret key (will be prefixed and uppercased)

   Returns:
     Secret value or NIL if not found"
  (let ((env-var (format nil "~A~A"
                        (env-prefix backend)
                        (string-upcase key))))
    (uiop:getenv env-var)))

(defmethod set-secret ((backend env-backend) key value)
  "Environment backend is read-only."
  (declare (ignore key value))
  (error 'secret-backend-error
         :backend backend
         :operation :set
         :reason "Environment backend is read-only"))

(defmethod delete-secret ((backend env-backend) key)
  "Environment backend is read-only."
  (declare (ignore key))
  (error 'secret-backend-error
         :backend backend
         :operation :delete
         :reason "Environment backend is read-only"))

(defmethod list-secrets ((backend env-backend))
  "List secrets from environment variables (limited support).

   Returns:
     Empty list (cannot enumerate environment variables portably)"
  nil)

;;; Secret Resolver

(defclass secret-resolver ()
  ((backends
    :initarg :backends
    :accessor resolver-backends
    :type list
    :initform nil
    :documentation "List of secret backends to query in order.")

   (fallback-value
    :initarg :fallback-value
    :accessor fallback-value
    :type t
    :initform nil
    :documentation "Value to return if secret not found in any backend."))
  (:documentation "Secret resolver that queries multiple backends in order.
                   First backend to return a value wins."))

(defmethod add-backend ((resolver secret-resolver) backend)
  "Add a backend to the resolver.

   Backends are queried in the order they were added.

   Args:
     resolver: secret-resolver instance
     backend: Secret backend to add"
  (pushnew backend (resolver-backends resolver) :test #'eq))

(defmethod remove-backend ((resolver secret-resolver) backend)
  "Remove a backend from the resolver.

   Args:
     resolver: secret-resolver instance
     backend: Secret backend to remove"
  (setf (resolver-backends resolver)
        (remove backend (resolver-backends resolver) :test #'eq)))

(defmethod resolve-secret ((resolver secret-resolver) key &key (signal-if-not-found nil))
  "Resolve a secret by querying backends in order.

   Args:
     resolver: secret-resolver instance
     key: Secret key
     signal-if-not-found: If T, signal SECRET-NOT-FOUND if not found

   Returns:
     Secret value, or fallback-value if not found

   Signals:
     SECRET-NOT-FOUND: If signal-if-not-found is T and secret not found"
  (dolist (backend (resolver-backends resolver))
    (let ((value (get-secret backend key)))
      (when value
        (return-from resolve-secret value))))

  ;; Not found in any backend
  (if signal-if-not-found
      (error 'secret-not-found :secret-key key)
      (fallback-value resolver)))

(defmethod store-secret ((resolver secret-resolver) key value &key (backend-index 0))
  "Store a secret in a specific backend.

   Args:
     resolver: secret-resolver instance
     key: Secret key
     value: Secret value
     backend-index: Index of backend to use (default 0, first backend)

   Returns:
     T on success

   Signals:
     ERROR: If backend-index is out of range"
  (let ((backends (resolver-backends resolver)))
    (when (>= backend-index (length backends))
      (error "Backend index ~A out of range (have ~A backends)"
             backend-index (length backends)))

    (let ((backend (nth backend-index backends)))
      (set-secret backend key value))))

;;; Utility Functions

(defun make-file-backend (&optional (file-path nil))
  "Create a file-based secret backend.

   Args:
     file-path: Optional path to secrets file (defaults to ~/.secrets.json)

   Returns:
     file-backend instance"
  (if file-path
      (make-instance 'file-backend :file-path file-path)
      (make-instance 'file-backend)))

(defun make-env-backend (&optional (prefix "SW4RM_SECRET_"))
  "Create an environment variable secret backend.

   Args:
     prefix: Prefix for environment variable names (default SW4RM_SECRET_)

   Returns:
     env-backend instance"
  (make-instance 'env-backend :prefix prefix))

(defun make-default-resolver ()
  "Create a default secret resolver.

   The default resolver queries:
   1. Environment variables (SW4RM_SECRET_* prefix)
   2. File backend (~/.secrets.json)

   Returns:
     secret-resolver instance"
  (let ((resolver (make-instance 'secret-resolver)))
    (add-backend resolver (make-env-backend))
    (add-backend resolver (make-file-backend))
    resolver))
