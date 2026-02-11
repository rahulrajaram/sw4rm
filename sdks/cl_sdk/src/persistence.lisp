;;;; persistence.lisp
;;;; Persistence backends for SW4RM SDK

(in-package :sw4rm-sdk)

;;; Condition Types

(define-condition persistence-error (error)
  ((backend :initarg :backend :reader backend)
   (operation :initarg :operation :reader operation)
   (reason :initarg :reason :reader reason))
  (:report (lambda (condition stream)
             (format stream "Persistence error in ~A during ~A: ~A"
                     (backend condition)
                     (operation condition)
                     (reason condition))))
  (:documentation "Signaled when a persistence operation fails."))

;;; Persistence Backend Protocol

(defgeneric save-records (backend records &key namespace)
  (:documentation "Save records to persistent storage.

   Args:
     backend: Persistence backend instance
     records: List of records to save
     namespace: Optional namespace/collection name

   Returns:
     Number of records saved"))

(defgeneric load-records (backend &key namespace)
  (:documentation "Load records from persistent storage.

   Args:
     backend: Persistence backend instance
     namespace: Optional namespace/collection name

   Returns:
     List of records"))

(defgeneric clear-records (backend &key namespace)
  (:documentation "Clear all records in persistent storage.

   Args:
     backend: Persistence backend instance
     namespace: Optional namespace/collection name

   Returns:
     Number of records deleted"))

;;; JSON File Persistence Backend

(defclass json-file-persistence ()
  ((base-directory
    :initarg :base-directory
    :accessor base-directory
    :type pathname
    :initform (merge-pathnames ".sw4rm/" (user-homedir-pathname))
    :documentation "Base directory for persistence files.")

   (lock
    :accessor persistence-lock
    :initform (bt:make-lock "json-persistence-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "JSON file-based persistence backend.
                   Stores records as JSON files in a directory structure."))

(defmethod initialize-instance :after ((backend json-file-persistence) &key)
  "Ensure base directory exists."
  (ensure-directories-exist (base-directory backend)))

(defun get-namespace-path (backend namespace)
  "Get the file path for a namespace.

   Args:
     backend: json-file-persistence instance
     namespace: Namespace name (string)

   Returns:
     Pathname for the namespace file"
  (let ((filename (format nil "~A.json" (or namespace "default"))))
    (merge-pathnames filename (base-directory backend))))

(defmethod save-records ((backend json-file-persistence) records &key (namespace nil))
  "Save records to a JSON file.

   Args:
     backend: json-file-persistence instance
     records: List of records (plists, hash tables, or structs)
     namespace: Optional namespace (default 'default')

   Returns:
     Number of records saved

   Signals:
     PERSISTENCE-ERROR: If save fails"
  (bt:with-lock-held ((persistence-lock backend))
    (let ((file-path (get-namespace-path backend namespace)))
      (handler-case
          (progn
            (ensure-directories-exist file-path)
            (with-open-file (stream file-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
              (json:encode-json records stream))
            (length records))
        (error (e)
          (error 'persistence-error
                 :backend backend
                 :operation :save
                 :reason (format nil "~A" e)))))))

(defmethod load-records ((backend json-file-persistence) &key (namespace nil))
  "Load records from a JSON file.

   Args:
     backend: json-file-persistence instance
     namespace: Optional namespace (default 'default')

   Returns:
     List of records (plists)

   Signals:
     PERSISTENCE-ERROR: If load fails"
  (bt:with-lock-held ((persistence-lock backend))
    (let ((file-path (get-namespace-path backend namespace)))
      (if (probe-file file-path)
          (handler-case
              (with-open-file (stream file-path :direction :input)
                (json:decode-json stream))
            (error (e)
              (error 'persistence-error
                     :backend backend
                     :operation :load
                     :reason (format nil "~A" e))))
          nil))))

(defmethod clear-records ((backend json-file-persistence) &key (namespace nil))
  "Clear all records in a namespace.

   Args:
     backend: json-file-persistence instance
     namespace: Optional namespace (default 'default')

   Returns:
     Number of records deleted"
  (bt:with-lock-held ((persistence-lock backend))
    (let* ((file-path (get-namespace-path backend namespace))
           (count 0))
      (when (probe-file file-path)
        (handler-case
            (progn
              ;; Load to count records
              (with-open-file (stream file-path :direction :input)
                (let ((records (json:decode-json stream)))
                  (setf count (length records))))
              ;; Delete file
              (delete-file file-path))
          (error (e)
            (error 'persistence-error
                   :backend backend
                   :operation :clear
                   :reason (format nil "~A" e)))))
      count)))

(defmethod list-namespaces ((backend json-file-persistence))
  "List all namespaces (files) in the persistence backend.

   Args:
     backend: json-file-persistence instance

   Returns:
     List of namespace names (strings)"
  (let ((namespaces nil))
    (dolist (path (uiop:directory-files (base-directory backend)))
      (when (string= (pathname-type path) "json")
        (push (pathname-name path) namespaces)))
    namespaces))

;;; In-Memory Persistence Backend (for testing)

(defclass in-memory-persistence ()
  ((storage
    :accessor persistence-storage
    :type hash-table
    :initform (make-hash-table :test 'equal)
    :documentation "Hash table mapping namespaces to record lists.")

   (lock
    :accessor persistence-lock
    :initform (bt:make-lock "memory-persistence-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "In-memory persistence backend for testing.
                   Records are stored in memory only and lost on restart."))

(defmethod save-records ((backend in-memory-persistence) records &key (namespace nil))
  "Save records to memory.

   Args:
     backend: in-memory-persistence instance
     records: List of records
     namespace: Optional namespace (default 'default')

   Returns:
     Number of records saved"
  (bt:with-lock-held ((persistence-lock backend))
    (let ((ns (or namespace "default")))
      (setf (gethash ns (persistence-storage backend)) (copy-list records))
      (length records))))

(defmethod load-records ((backend in-memory-persistence) &key (namespace nil))
  "Load records from memory.

   Args:
     backend: in-memory-persistence instance
     namespace: Optional namespace (default 'default')

   Returns:
     List of records"
  (bt:with-lock-held ((persistence-lock backend))
    (let ((ns (or namespace "default")))
      (gethash ns (persistence-storage backend)))))

(defmethod clear-records ((backend in-memory-persistence) &key (namespace nil))
  "Clear records from memory.

   Args:
     backend: in-memory-persistence instance
     namespace: Optional namespace (default 'default')

   Returns:
     Number of records deleted"
  (bt:with-lock-held ((persistence-lock backend))
    (let* ((ns (or namespace "default"))
           (records (gethash ns (persistence-storage backend)))
           (count (length records)))
      (remhash ns (persistence-storage backend))
      count)))

(defmethod list-namespaces ((backend in-memory-persistence))
  "List all namespaces in the in-memory backend.

   Args:
     backend: in-memory-persistence instance

   Returns:
     List of namespace names (strings)"
  (let ((namespaces nil))
    (maphash (lambda (ns records)
               (declare (ignore records))
               (push ns namespaces))
             (persistence-storage backend))
    namespaces))

;;; Utility Functions

(defun make-json-file-persistence (&optional (base-directory nil))
  "Create a JSON file persistence backend.

   Args:
     base-directory: Optional base directory (defaults to ~/.sw4rm/)

   Returns:
     json-file-persistence instance"
  (if base-directory
      (make-instance 'json-file-persistence :base-directory base-directory)
      (make-instance 'json-file-persistence)))

(defun make-in-memory-persistence ()
  "Create an in-memory persistence backend.

   Returns:
     in-memory-persistence instance"
  (make-instance 'in-memory-persistence))

;;; Record Serialization Utilities

(defun serialize-record (record)
  "Convert a record to a JSON-serializable form.

   Args:
     record: Record (plist, hash table, or struct)

   Returns:
     Plist suitable for JSON encoding"
  (cond
    ((listp record)
     ;; Already a plist
     record)

    ((hash-table-p record)
     ;; Convert hash table to alist for JSON encoding
     (let ((result nil))
       (maphash (lambda (k v)
                  (push (cons k v) result))
                record)
       result))

    (t
     ;; For structs, use format and read back (simple but limited)
     (format nil "~S" record))))

(defun deserialize-record (data)
  "Convert JSON data back to a record.

   Args:
     data: Deserialized JSON data (alist or plist)

   Returns:
     Record in appropriate format"
  ;; JSON decode returns alists, convert to plist
  (if (and (consp data) (consp (car data)))
      ;; Alist format
      (loop for (key . value) in data
            append (list key value))
      ;; Already plist or other format
      data))
