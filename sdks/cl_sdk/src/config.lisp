;;;; config.lisp
;;;;
;;;; Configuration management for SW4RM orchestrator
;;;;
;;;; This module provides configuration loading, validation, and access
;;;; for the orchestrator system. Configuration can be loaded from:
;;;;   - Command-line arguments
;;;;   - Environment variables
;;;;   - Configuration files (JSON, EDN, or Lisp s-expressions)
;;;;   - Programmatic settings
;;;;
;;;; Configuration precedence (highest to lowest):
;;;;   1. Programmatic settings (set-config)
;;;;   2. Command-line arguments
;;;;   3. Environment variables
;;;;   4. Configuration file
;;;;   5. Default values
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator)

;;;; ============================================================================
;;;; Global configuration state
;;;; ============================================================================

(defvar *config* (make-hash-table :test 'equal)
  "Global configuration hash table.

   Configuration keys are strings organized hierarchically:
     \"orchestrator.id\"
     \"orchestrator.grpc.host\"
     \"orchestrator.grpc.port\"
     \"orchestrator.checkpoint.enabled\"
     \"orchestrator.checkpoint.interval\"
     \"orchestrator.checkpoint.path\"
     \"logging.level\"
     \"logging.file\"
     \"routing.strategy\"
     \"routing.max-hops\"")

(defvar *config-file-path* nil
  "Path to loaded configuration file (nil if not loaded from file).")

(defvar *config-defaults* nil
  "Default configuration values (initialized at load time).")

;;;; ============================================================================
;;;; Default configuration values
;;;; ============================================================================

(defun initialize-default-config ()
  "Initialize default configuration values.

   Returns:
     Hash table with default configuration."
  (let ((defaults (make-hash-table :test 'equal)))
    ;; Orchestrator identity
    (setf (gethash "orchestrator.id" defaults) "orchestrator-root")
    (setf (gethash "orchestrator.name" defaults) "SW4RM Orchestrator")
    (setf (gethash "orchestrator.version" defaults) "0.6.0")

    ;; gRPC server configuration
    (setf (gethash "grpc.host" defaults) "0.0.0.0")
    (setf (gethash "grpc.port" defaults) 50050)
    (setf (gethash "grpc.max-connections" defaults) 100)
    (setf (gethash "grpc.keepalive-interval" defaults) 30)
    (setf (gethash "grpc.connection-timeout" defaults) 10)

    ;; Routing configuration
    (setf (gethash "routing.strategy" defaults) "hierarchical")
    (setf (gethash "routing.max-hops" defaults) 10)
    (setf (gethash "routing.broadcast-timeout" defaults) 5)
    (setf (gethash "routing.allow-loops" defaults) nil)

    ;; Checkpoint configuration
    (setf (gethash "checkpoint.enabled" defaults) t)
    (setf (gethash "checkpoint.interval" defaults) 300) ; 5 minutes
    (setf (gethash "checkpoint.path" defaults) "/var/sw4rm/checkpoints")
    (setf (gethash "checkpoint.compression" defaults) t)
    (setf (gethash "checkpoint.max-history" defaults) 10)

    ;; Write-ahead log configuration
    (setf (gethash "wal.enabled" defaults) t)
    (setf (gethash "wal.path" defaults) "/var/sw4rm/wal")
    (setf (gethash "wal.max-size" defaults) (* 100 1024 1024)) ; 100MB
    (setf (gethash "wal.sync-interval" defaults) 1)

    ;; Logging configuration
    (setf (gethash "logging.level" defaults) "INFO")
    (setf (gethash "logging.file" defaults) "/var/log/sw4rm/orchestrator.log")
    (setf (gethash "logging.console" defaults) t)
    (setf (gethash "logging.structured" defaults) nil)

    ;; Metrics configuration
    (setf (gethash "metrics.enabled" defaults) t)
    (setf (gethash "metrics.export-format" defaults) "prometheus")
    (setf (gethash "metrics.export-port" defaults) 9090)
    (setf (gethash "metrics.collection-interval" defaults) 10)

    ;; Coordination configuration
    (setf (gethash "coordination.barrier-timeout" defaults) 60)
    (setf (gethash "coordination.lease-default-ttl" defaults) 30)
    (setf (gethash "coordination.artifact-registry-size" defaults) 1000)
    (setf (gethash "coordination.semaphore-default-limit" defaults) 10)
    (setf (gethash "coordination.negotiation-timeout" defaults) 30)

    ;; Health check configuration
    (setf (gethash "health.heartbeat-interval" defaults) 10)
    (setf (gethash "health.heartbeat-timeout" defaults) 30)
    (setf (gethash "health.unhealthy-threshold" defaults) 3)

    ;; Routing strategy configuration
    (setf (gethash "routing.strategy.default" defaults) "direct")
    (setf (gethash "routing.strategy.fallback" defaults) "round-robin")
    (setf (gethash "routing.strategy.health-check-interval" defaults) 5)

    defaults))

;;;; ============================================================================
;;;; Configuration access
;;;; ============================================================================

(defun get-config (key &optional default)
  "Get configuration value by key.

   Args:
     key: Configuration key (string)
     default: Default value if key not found (optional)

   Returns:
     Configuration value or default if not found.

   Examples:
     (get-config \"grpc.port\")
     (get-config \"unknown.key\" 42)
     (get-config \"orchestrator.id\")"
  (multiple-value-bind (value present) (gethash key *config*)
    (if present
        value
        (or (gethash key *config-defaults*)
            default))))

(defun set-config (key value)
  "Set configuration value by key.

   Args:
     key: Configuration key (string)
     value: Value to set (any type)

   Returns:
     value

   Example:
     (set-config \"grpc.port\" 50051)"
  (setf (gethash key *config*) value))

(defun has-config-p (key)
  "Check if configuration key exists.

   Args:
     key: Configuration key (string)

   Returns:
     T if key exists, NIL otherwise."
  (or (nth-value 1 (gethash key *config*))
      (nth-value 1 (gethash key *config-defaults*))))

(defun remove-config (key)
  "Remove configuration key.

   Args:
     key: Configuration key (string)

   Returns:
     T if key was removed, NIL if it didn't exist."
  (remhash key *config*))

(defun clear-config ()
  "Clear all configuration (except defaults).

   Returns:
     NIL"
  (clrhash *config*)
  nil)

;;;; ============================================================================
;;;; Configuration file loading
;;;; ============================================================================

(defun load-config-file (path &key (format :auto))
  "Load configuration from file.

   Args:
     path: Path to configuration file
     format: File format (:auto, :json, :lisp) - :auto detects from extension

   Returns:
     Number of configuration keys loaded.

   Raises:
     ERROR if file cannot be read or parsed.

   Examples:
     (load-config-file \"/etc/sw4rm/config.json\")
     (load-config-file \"/etc/sw4rm/config.lisp\" :format :lisp)"
  (unless (probe-file path)
    (error "Configuration file not found: ~A" path))

  (let ((detected-format (detect-config-format path format)))
    (ecase detected-format
      (:json (load-json-config path))
      (:lisp (load-lisp-config path))
      (t (error "Unsupported configuration format: ~A" detected-format)))))

(defun detect-config-format (path format)
  "Detect configuration file format from extension.

   Args:
     path: File path
     format: Requested format (:auto to detect)

   Returns:
     Detected format (:json, :lisp)"
  (if (eq format :auto)
      (let ((extension (pathname-type path)))
        (cond
          ((member extension '("json" "JSON") :test #'string=) :json)
          ((member extension '("lisp" "lsp" "cl" "LISP" "LSP" "CL") :test #'string=) :lisp)
          (t (error "Cannot detect configuration format from extension: ~A" extension))))
      format))

(defun load-json-config (path)
  "Load configuration from JSON file.

   Args:
     path: Path to JSON file

   Returns:
     Number of keys loaded."
  ;; TODO: Implement JSON parsing with cl-json
  ;; For now, signal that this needs implementation
  (warn "JSON configuration loading not yet implemented for ~A" path)
  0)

(defun load-lisp-config (path)
  "Load configuration from Lisp file.

   The file should contain a list of (key value) pairs:
     ((\"orchestrator.id\" \"my-orchestrator\")
      (\"grpc.port\" 50051)
      (\"logging.level\" \"DEBUG\"))

   Args:
     path: Path to Lisp file

   Returns:
     Number of keys loaded."
  (with-open-file (stream path :direction :input)
    (let ((config-list (read stream))
          (count 0))
      (dolist (entry config-list)
        (destructuring-bind (key value) entry
          (set-config key value)
          (incf count)))
      (setf *config-file-path* path)
      count)))

;;;; ============================================================================
;;;; Configuration saving
;;;; ============================================================================

(defun save-config-file (path &key (format :lisp) (include-defaults nil))
  "Save configuration to file.

   Args:
     path: Path to save configuration
     format: File format (:json, :lisp)
     include-defaults: Whether to include default values

   Returns:
     Number of keys saved.

   Example:
     (save-config-file \"/etc/sw4rm/config.lisp\")"
  (ecase format
    (:json (save-json-config path include-defaults))
    (:lisp (save-lisp-config path include-defaults))))

(defun save-lisp-config (path include-defaults)
  "Save configuration to Lisp file.

   Args:
     path: Path to save file
     include-defaults: Include default values

   Returns:
     Number of keys saved."
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (let ((count 0)
          (config-list '()))
      ;; Collect configuration entries
      (maphash (lambda (key value)
                 (push (list key value) config-list)
                 (incf count))
               *config*)
      ;; Optionally include defaults
      (when include-defaults
        (maphash (lambda (key value)
                   (unless (gethash key *config*)
                     (push (list key value) config-list)
                     (incf count)))
                 *config-defaults*))
      ;; Sort for readability
      (setf config-list (sort config-list #'string< :key #'car))
      ;; Write to file
      (format stream ";;;; SW4RM Orchestrator Configuration~%")
      (format stream ";;;; Generated: ~A~%~%" (get-universal-time))
      (prin1 config-list stream)
      (terpri stream)
      count)))

(defun save-json-config (path include-defaults)
  "Save configuration to JSON file.

   Args:
     path: Path to save file
     include-defaults: Include default values

   Returns:
     Number of keys saved."
  ;; TODO: Implement JSON encoding with cl-json
  (warn "JSON configuration saving not yet implemented for ~A" path)
  0)

;;;; ============================================================================
;;;; Environment variable integration
;;;; ============================================================================

(defun load-config-from-env (&key (prefix "SW4RM_"))
  "Load configuration from environment variables.

   Environment variables are mapped to configuration keys by:
     SW4RM_GRPC_PORT -> \"grpc.port\"
     SW4RM_ORCHESTRATOR_ID -> \"orchestrator.id\"

   Args:
     prefix: Prefix for environment variables (default \"SW4RM_\")

   Returns:
     Number of keys loaded from environment.

   Example:
     $ export SW4RM_GRPC_PORT=50051
     $ export SW4RM_LOGGING_LEVEL=DEBUG
     (load-config-from-env)"
  (let ((count 0))
    ;; Iterate through environment variables
    ;; Note: This is implementation-specific, may need #+sbcl, #+ccl, etc.
    #+sbcl
    (dolist (env-pair (sb-ext:posix-environ))
      (let* ((env-string (if (consp env-pair) (car env-pair) env-pair))
             (equals-pos (position #\= env-string)))
        (when (and equals-pos
                   (>= (length env-string) (length prefix))
                   (string= env-string prefix :end1 (length prefix)))
          (let* ((env-key (subseq env-string (length prefix) equals-pos))
                 (env-value (subseq env-string (1+ equals-pos)))
                 (config-key (env-key-to-config-key env-key)))
            (set-config config-key (parse-env-value env-value))
            (incf count)))))
    #-sbcl
    (warn "load-config-from-env not implemented for this Lisp implementation")
    count))

(defun env-key-to-config-key (env-key)
  "Convert environment variable key to configuration key.

   SW4RM_GRPC_PORT -> \"grpc.port\"

   Args:
     env-key: Environment variable key (without prefix)

   Returns:
     Configuration key string."
  (string-downcase (substitute #\. #\_ env-key)))

(defun parse-env-value (value-string)
  "Parse environment variable value to appropriate type.

   Attempts to parse as:
     - Integer (\"123\" -> 123)
     - Boolean (\"true\" -> T, \"false\" -> NIL)
     - String (default)

   Args:
     value-string: String value from environment

   Returns:
     Parsed value."
  (cond
    ;; Boolean
    ((string-equal value-string "true") t)
    ((string-equal value-string "false") nil)
    ;; Integer
    ((every #'digit-char-p value-string)
     (parse-integer value-string :junk-allowed t))
    ;; Default: string
    (t value-string)))

;;;; ============================================================================
;;;; Configuration validation
;;;; ============================================================================

(define-condition config-validation-error (error)
  ((key :initarg :key
        :reader config-validation-error-key
        :documentation "Configuration key that failed validation")
   (value :initarg :value
          :reader config-validation-error-value
          :documentation "Invalid configuration value")
   (reason :initarg :reason
           :reader config-validation-error-reason
           :documentation "Reason for validation failure"))
  (:documentation "Signaled when configuration validation fails.

   Slots:
     KEY - The configuration key that failed
     VALUE - The invalid value
     REASON - Human-readable explanation

   See Also:
     VALIDATE-CONFIG, VALIDATE-CHECKPOINT-CONFIG")
  (:report (lambda (condition stream)
             (format stream "Configuration validation failed for ~S: ~A (value: ~S)"
                     (config-validation-error-key condition)
                     (config-validation-error-reason condition)
                     (config-validation-error-value condition)))))

(defun validate-config ()
  "Validate current configuration.

   Checks:
     - Required keys are present
     - Values have correct types
     - Values are in valid ranges
     - Checkpoint configuration is valid (if enabled)

   Returns:
     T if valid, signals CONFIG-VALIDATION-ERROR otherwise.

   See Also:
     CONFIG-VALIDATION-ERROR, VALIDATE-CHECKPOINT-CONFIG"
  (flet ((require-key (key)
           (unless (has-config-p key)
             (error 'config-validation-error
                    :key key
                    :value nil
                    :reason "Required configuration key missing")))
         (require-type (key expected-type)
           (let ((value (get-config key)))
             (unless (typep value expected-type)
               (error 'config-validation-error
                      :key key
                      :value value
                      :reason (format nil "Expected type ~A, got ~A"
                                      expected-type (type-of value)))))))
    ;; Validate required keys
    (require-key "orchestrator.id")
    (require-key "grpc.port")
    (require-key "grpc.host")

    ;; Validate types
    (require-type "grpc.port" 'integer)
    (require-type "grpc.host" 'string)
    (require-type "routing.max-hops" 'integer)

    ;; Validate ranges
    (let ((port (get-config "grpc.port")))
      (unless (<= 1 port 65535)
        (error 'config-validation-error
               :key "grpc.port"
               :value port
               :reason "Port must be between 1 and 65535")))

    (let ((max-hops (get-config "routing.max-hops")))
      (unless (> max-hops 0)
        (error 'config-validation-error
               :key "routing.max-hops"
               :value max-hops
               :reason "Max hops must be positive")))

    ;; Validate checkpoint configuration if enabled
    (when (get-config "checkpoint.enabled")
      (validate-checkpoint-config))

    t))

(defun validate-checkpoint-config ()
  "Validate checkpoint-specific configuration.

   Checks:
     - checkpoint.interval is a positive integer
     - checkpoint.path directory exists and is writable

   Returns:
     T if valid, signals CONFIG-VALIDATION-ERROR otherwise.

   Side Effects:
     - Creates checkpoint.path directory if it doesn't exist

   Called by:
     VALIDATE-CONFIG when checkpoint.enabled is T

   See Also:
     CONFIG-VALIDATION-ERROR, VALIDATE-CONFIG"
  (let ((interval (get-config "checkpoint.interval"))
        (path (get-config "checkpoint.path")))

    ;; Validate checkpoint.interval type
    (unless (typep interval 'integer)
      (error 'config-validation-error
             :key "checkpoint.interval"
             :value interval
             :reason (format nil "Expected integer, got ~A" (type-of interval))))

    ;; Validate checkpoint.interval is positive
    (unless (> interval 0)
      (error 'config-validation-error
             :key "checkpoint.interval"
             :value interval
             :reason "Checkpoint interval must be positive"))

    ;; Validate checkpoint.path type
    (unless (typep path 'string)
      (error 'config-validation-error
             :key "checkpoint.path"
             :value path
             :reason (format nil "Expected string, got ~A" (type-of path))))

    ;; Ensure checkpoint directory exists and is writable
    (let ((checkpoint-dir (pathname path)))
      (handler-case
          (progn
            ;; Create directory if it doesn't exist
            (ensure-directories-exist
             (make-pathname :directory (pathname-directory checkpoint-dir)
                            :name nil :type nil
                            :defaults checkpoint-dir))

            ;; Test write permission by attempting to create a temporary file
            (let ((test-file (merge-pathnames ".sw4rm-write-test" checkpoint-dir)))
              (handler-case
                  (progn
                    ;; Try to create and write to test file
                    (with-open-file (stream test-file
                                            :direction :output
                                            :if-exists :supersede
                                            :if-does-not-exist :create)
                      (format stream "write test~%"))
                    ;; Delete test file on success
                    (when (probe-file test-file)
                      (delete-file test-file)))
                (error (e)
                  (error 'config-validation-error
                         :key "checkpoint.path"
                         :value path
                         :reason (format nil "Directory is not writable: ~A" e))))))
        (config-validation-error (e)
          ;; Re-signal config validation errors
          (error e))
        (error (e)
          ;; Wrap other errors
          (error 'config-validation-error
                 :key "checkpoint.path"
                 :value path
                 :reason (format nil "Invalid checkpoint path: ~A" e)))))

    t))

;;;; ============================================================================
;;;; Pretty printing
;;;; ============================================================================

(defun print-config (&key (stream t) (include-defaults nil))
  "Print current configuration in human-readable format.

   Args:
     stream: Output stream (default T for *standard-output*)
     include-defaults: Include default values

   Returns:
     NIL"
  (format stream "~&=== SW4RM Orchestrator Configuration ===~%~%")

  ;; Print active configuration
  (format stream "Active Configuration:~%")
  (let ((keys (sort (loop for key being the hash-keys of *config* collect key)
                    #'string<)))
    (dolist (key keys)
      (format stream "  ~A = ~S~%" key (gethash key *config*))))

  ;; Optionally print defaults
  (when include-defaults
    (format stream "~%Default Configuration:~%")
    (let ((keys (sort (loop for key being the hash-keys of *config-defaults* collect key)
                      #'string<)))
      (dolist (key keys)
        (unless (gethash key *config*)
          (format stream "  ~A = ~S~%" key (gethash key *config-defaults*))))))

  (when *config-file-path*
    (format stream "~%Loaded from: ~A~%" *config-file-path*))

  nil)

;;;; ============================================================================
;;;; Initialization
;;;; ============================================================================

(eval-when (:load-toplevel :execute)
  "Initialize default configuration when this file is loaded."
  (setf *config-defaults* (initialize-default-config)))

;;;; End of file
