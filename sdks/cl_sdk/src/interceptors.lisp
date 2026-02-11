;;;; interceptors.lisp
;;;; Interceptor chain for request/response processing

(in-package :sw4rm-sdk)

;;; Condition Types

(define-condition interceptor-error (error)
  ((interceptor-name :initarg :interceptor :reader interceptor-error-name)
   (interceptor-phase :initarg :phase :reader interceptor-error-phase)
   (interceptor-reason :initarg :reason :reader interceptor-error-reason))
  (:report (lambda (condition stream)
             (format stream "Interceptor error in ~A during ~A: ~A"
                     (interceptor-error-name condition)
                     (interceptor-error-phase condition)
                     (interceptor-error-reason condition))))
  (:documentation "Signaled when an interceptor encounters an error."))

;;; Interceptor Protocol

(defgeneric on-request (interceptor request context)
  (:documentation "Called before a request is processed.

   Args:
     interceptor: Interceptor instance
     request: Request data (hash table or plist)
     context: Context hash table for sharing state

   Returns:
     Modified request (or original if no modification)"))

(defgeneric on-response (interceptor response context)
  (:documentation "Called after a response is received.

   Args:
     interceptor: Interceptor instance
     response: Response data (hash table or plist)
     context: Context hash table for sharing state

   Returns:
     Modified response (or original if no modification)"))

(defgeneric interceptor-name (interceptor)
  (:documentation "Get the name of the interceptor.

   Args:
     interceptor: Interceptor instance

   Returns:
     String name"))

;;; Interceptor Chain

(defclass interceptor-chain ()
  ((interceptors
    :initarg :interceptors
    :accessor chain-interceptors
    :type list
    :initform nil
    :documentation "List of interceptors to apply in order.")

   (enabled
    :initarg :enabled
    :accessor chain-enabled
    :type boolean
    :initform t
    :documentation "Whether the chain is enabled.")

   (lock
    :accessor chain-lock
    :initform (bt:make-lock "interceptor-chain-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "Chain of interceptors for request/response processing.
                   Interceptors are applied in order for requests,
                   and in reverse order for responses."))

(defmethod add-interceptor ((chain interceptor-chain) interceptor)
  "Add an interceptor to the end of the chain.

   Args:
     chain: interceptor-chain instance
     interceptor: Interceptor to add"
  (bt:with-lock-held ((chain-lock chain))
    (setf (chain-interceptors chain)
          (append (chain-interceptors chain) (list interceptor)))))

(defmethod add-interceptor-first ((chain interceptor-chain) interceptor)
  "Add an interceptor to the beginning of the chain.

   Args:
     chain: interceptor-chain instance
     interceptor: Interceptor to add"
  (bt:with-lock-held ((chain-lock chain))
    (push interceptor (chain-interceptors chain))))

(defmethod remove-interceptor ((chain interceptor-chain) interceptor)
  "Remove an interceptor from the chain.

   Args:
     chain: interceptor-chain instance
     interceptor: Interceptor to remove"
  (bt:with-lock-held ((chain-lock chain))
    (setf (chain-interceptors chain)
          (remove interceptor (chain-interceptors chain) :test #'eq))))

(defmethod clear-interceptors ((chain interceptor-chain))
  "Remove all interceptors from the chain.

   Args:
     chain: interceptor-chain instance"
  (bt:with-lock-held ((chain-lock chain))
    (setf (chain-interceptors chain) nil)))

(defmethod process-request ((chain interceptor-chain) request)
  "Process a request through the interceptor chain.

   Args:
     chain: interceptor-chain instance
     request: Request data

   Returns:
     Modified request"
  (if (not (chain-enabled chain))
      request
      (let ((context (make-hash-table :test 'equal))
            (current-request request))

        ;; Apply interceptors in order
        (dolist (interceptor (chain-interceptors chain))
          (handler-case
              (setf current-request (on-request interceptor current-request context))
            (error (e)
              (error 'interceptor-error
                     :interceptor interceptor
                     :phase :request
                     :reason (format nil "~A" e)))))

        current-request)))

(defmethod process-response ((chain interceptor-chain) response)
  "Process a response through the interceptor chain.

   Args:
     chain: interceptor-chain instance
     response: Response data

   Returns:
     Modified response"
  (if (not (chain-enabled chain))
      response
      (let ((context (make-hash-table :test 'equal))
            (current-response response))

        ;; Apply interceptors in reverse order
        (dolist (interceptor (reverse (chain-interceptors chain)))
          (handler-case
              (setf current-response (on-response interceptor current-response context))
            (error (e)
              (error 'interceptor-error
                     :interceptor interceptor
                     :phase :response
                     :reason (format nil "~A" e)))))

        current-response)))

;;; Timing Interceptor

(defclass timing-interceptor ()
  ((timings
    :accessor interceptor-timings
    :type list
    :initform nil
    :documentation "List of timing records (plists).")

   (max-history
    :initarg :max-history
    :accessor max-history
    :type (integer 0 *)
    :initform 100
    :documentation "Maximum number of timing records to keep."))
  (:documentation "Interceptor that measures request/response timing."))

(defmethod interceptor-name ((interceptor timing-interceptor))
  "timing")

(defmethod on-request ((interceptor timing-interceptor) request context)
  "Record request start time.

   Args:
     interceptor: timing-interceptor instance
     request: Request data
     context: Context hash table

   Returns:
     Unmodified request"
  (setf (gethash :start-time context) (get-internal-real-time))
  request)

(defmethod on-response ((interceptor timing-interceptor) response context)
  "Record response time and calculate duration.

   Args:
     interceptor: timing-interceptor instance
     response: Response data
     context: Context hash table

   Returns:
     Unmodified response"
  (let* ((start-time (gethash :start-time context))
         (end-time (get-internal-real-time))
         (duration-ms (if start-time
                         (/ (* (- end-time start-time) 1000.0)
                            internal-time-units-per-second)
                         0.0)))

    ;; Record timing
    (push (list :timestamp (get-universal-time)
                :duration-ms duration-ms)
          (interceptor-timings interceptor))

    ;; Trim history
    (when (> (length (interceptor-timings interceptor)) (max-history interceptor))
      (setf (interceptor-timings interceptor)
            (subseq (interceptor-timings interceptor) 0 (max-history interceptor))))

    response))

(defmethod get-timings ((interceptor timing-interceptor) &key (limit nil))
  "Get timing records.

   Args:
     interceptor: timing-interceptor instance
     limit: Optional maximum number of records to return

   Returns:
     List of timing records (plists)"
  (if limit
      (subseq (interceptor-timings interceptor)
              0
              (min limit (length (interceptor-timings interceptor))))
      (interceptor-timings interceptor)))

(defmethod get-average-duration ((interceptor timing-interceptor))
  "Get average request duration.

   Args:
     interceptor: timing-interceptor instance

   Returns:
     Average duration in milliseconds, or NIL if no data"
  (let ((timings (interceptor-timings interceptor)))
    (when timings
      (/ (reduce #'+ (mapcar (lambda (entry) (getf entry :duration-ms)) timings))
         (length timings)))))

;;; Logging Interceptor

(defclass logging-interceptor ()
  ((log-requests
    :initarg :log-requests
    :accessor log-requests
    :type boolean
    :initform t
    :documentation "Whether to log requests.")

   (log-responses
    :initarg :log-responses
    :accessor log-responses
    :type boolean
    :initform t
    :documentation "Whether to log responses.")

   (log-level
    :initarg :log-level
    :accessor log-level
    :type keyword
    :initform :info
    :documentation "Log level (:debug, :info, :warn, :error).")

   (logger
    :initarg :logger
    :accessor interceptor-logger
    :type (or null function)
    :initform nil
    :documentation "Custom logger function (timestamp level message)"))
  (:documentation "Interceptor that logs requests and responses."))

(defmethod interceptor-name ((interceptor logging-interceptor))
  "logging")

(defun default-log-function (timestamp level message)
  "Default logging function that prints to *standard-output*.

   Args:
     timestamp: Universal time
     level: Log level keyword
     message: Log message string"
  (format t "~A [~A] ~A~%" timestamp level message))

(defmethod log-message ((interceptor logging-interceptor) level message)
  "Log a message using the interceptor's logger.

   Args:
     interceptor: logging-interceptor instance
     level: Log level keyword
     message: Message string"
  (let ((logger (or (interceptor-logger interceptor) #'default-log-function)))
    (funcall logger (get-universal-time) level message)))

(defmethod on-request ((interceptor logging-interceptor) request context)
  "Log the request.

   Args:
     interceptor: logging-interceptor instance
     request: Request data
     context: Context hash table

   Returns:
     Unmodified request"
  (when (log-requests interceptor)
    (log-message interceptor
                (log-level interceptor)
                (format nil "Request: ~A" request)))
  request)

(defmethod on-response ((interceptor logging-interceptor) response context)
  "Log the response.

   Args:
     interceptor: logging-interceptor instance
     response: Response data
     context: Context hash table

   Returns:
     Unmodified response"
  (when (log-responses interceptor)
    (log-message interceptor
                (log-level interceptor)
                (format nil "Response: ~A" response)))
  response)

;;; Header Interceptor

(defclass header-interceptor ()
  ((headers
    :initarg :headers
    :accessor interceptor-headers
    :type list
    :initform nil
    :documentation "List of headers to add (plists with :key and :value).")

   (on-request-only
    :initarg :on-request-only
    :accessor on-request-only
    :type boolean
    :initform t
    :documentation "Whether to only add headers to requests (not responses)."))
  (:documentation "Interceptor that adds custom headers to requests/responses."))

(defmethod interceptor-name ((interceptor header-interceptor))
  "header")

(defmethod add-header ((interceptor header-interceptor) key value)
  "Add a header to the interceptor.

   Args:
     interceptor: header-interceptor instance
     key: Header key (string)
     value: Header value (string)"
  (push (list :key key :value value) (interceptor-headers interceptor)))

(defmethod on-request ((interceptor header-interceptor) request context)
  "Add headers to the request.

   Args:
     interceptor: header-interceptor instance
     request: Request data (hash table or plist)
     context: Context hash table

   Returns:
     Modified request with added headers"
  (declare (ignore context))
  (let ((modified-request (if (hash-table-p request)
                             (copy-hash-table request)
                             (copy-list request))))

    ;; Add headers
    (dolist (header (interceptor-headers interceptor))
      (let ((key (getf header :key))
            (value (getf header :value)))
        (if (hash-table-p modified-request)
            (setf (gethash key modified-request) value)
            (setf (getf modified-request (intern (string-upcase key) :keyword)) value))))

    modified-request))

(defmethod on-response ((interceptor header-interceptor) response context)
  "Add headers to the response (if enabled).

   Args:
     interceptor: header-interceptor instance
     response: Response data
     context: Context hash table

   Returns:
     Modified response with added headers (or unmodified if on-request-only)"
  (declare (ignore context))
  (if (on-request-only interceptor)
      response
      (let ((modified-response (if (hash-table-p response)
                                  (copy-hash-table response)
                                  (copy-list response))))

        ;; Add headers
        (dolist (header (interceptor-headers interceptor))
          (let ((key (getf header :key))
                (value (getf header :value)))
            (if (hash-table-p modified-response)
                (setf (gethash key modified-response) value)
                (setf (getf modified-response (intern (string-upcase key) :keyword)) value))))

        modified-response)))

;;; Utility Functions

;;; copy-hash-table is provided by alexandria (inherited via :use)

(defun make-interceptor-chain ()
  "Create an empty interceptor chain.

   Returns:
     interceptor-chain instance"
  (make-instance 'interceptor-chain))

(defun make-timing-interceptor ()
  "Create a timing interceptor.

   Returns:
     timing-interceptor instance"
  (make-instance 'timing-interceptor))

(defun make-logging-interceptor (&key (log-requests t)
                                     (log-responses t)
                                     (log-level :info)
                                     (logger nil))
  "Create a logging interceptor.

   Args:
     log-requests: Whether to log requests (default T)
     log-responses: Whether to log responses (default T)
     log-level: Log level (default :info)
     logger: Custom logger function (optional)

   Returns:
     logging-interceptor instance"
  (make-instance 'logging-interceptor
                 :log-requests log-requests
                 :log-responses log-responses
                 :log-level log-level
                 :logger logger))

(defun make-header-interceptor (&key headers (on-request-only t))
  "Create a header interceptor.

   Args:
     headers: List of header plists (:key and :value)
     on-request-only: Only add to requests (default T)

   Returns:
     header-interceptor instance"
  (make-instance 'header-interceptor
                 :headers headers
                 :on-request-only on-request-only))
