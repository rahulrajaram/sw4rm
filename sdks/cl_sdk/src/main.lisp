;;;; main.lisp
;;;;
;;;; Main entry point for SW4RM orchestrator
;;;;
;;;; This module provides:
;;;;   - Command-line argument parsing
;;;;   - Orchestrator initialization
;;;;   - Main event loop
;;;;   - Graceful shutdown handling
;;;;   - Standalone executable building
;;;;   - Health status reporting with degraded mode detection
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator)

;;;; ============================================================================
;;;; Global state
;;;; ============================================================================

(defvar *orchestrator* nil
  "Global orchestrator instance (root node).")

(defvar *grpc-server* nil
  "Global gRPC server instance.")

(defvar *shutdown-requested* nil
  "Flag indicating graceful shutdown was requested.")

(defvar *grpc-degraded-mode* nil
  "Flag indicating gRPC server failed to start and we are in degraded mode.

   When T, the orchestrator is running with mock gRPC handlers instead of
   a real gRPC server. Health endpoints will report :DEGRADED instead of :READY.
   This typically occurs when:
     - The gRPC library is not available
     - The port is already in use
     - Network configuration prevents binding

   See Also:
     GRPC-DEGRADED-MODE-P, START-ORCHESTRATOR-SERVER, GET-HEALTH-STATUS")

(defun grpc-degraded-mode-p ()
  "Check if the orchestrator is running in gRPC degraded mode.

   Returns:
     T if gRPC server failed to start and we are using mock handlers,
     NIL if gRPC server is running normally.

   See Also:
     *GRPC-DEGRADED-MODE*, GET-HEALTH-STATUS"
  *grpc-degraded-mode*)

;;;; ============================================================================
;;;; Command-line argument parsing
;;;; ============================================================================

(define-condition cli-error-condition (error)
  ((message :initarg :message :reader cli-error-message))
  (:report (lambda (condition stream)
             (format stream "CLI error: ~A" (cli-error-message condition))))
  (:documentation "Condition signaled for CLI argument errors."))

(defun cli-error (format-string &rest args)
  "Report a CLI error and exit with code 1.

   Args:
     format-string: Format string for error message
     args: Arguments for format string

   Side Effects:
     Prints error message and usage, then exits with code 1.
     If a handler declines to handle CLI-ERROR-CONDITION, exits the process."
  (let ((message (apply #'format nil format-string args)))
    ;; Signal the condition first so tests can catch it
    (restart-case
        (error 'cli-error-condition :message message)
      (continue-with-exit ()
        :report "Print usage and exit with code 1."
        (format *error-output* "~&ERROR: ~A~%~%" message)
        (print-usage)
        #+sbcl (sb-ext:exit :code 1)
        #-sbcl (error "CLI error: ~A" message)))))

(defun pop-arg-value (args-ref flag-name)
  "Safely pop an argument value, checking for missing values.

   Args:
     args-ref: Reference to remaining args list (will be modified)
     flag-name: Name of the flag for error messages

   Returns:
     The argument value string

   Side Effects:
     Modifies args-ref by removing the value
     Exits with error if value is missing"
  (let ((value (pop (symbol-value args-ref))))
    (when (or (null value)
              (and (stringp value) (char= (char value 0) #\-)))
      (cli-error "~A requires a value" flag-name))
    value))

(defun parse-port-value (value-string flag-name)
  "Parse and validate a port number.

   Args:
     value-string: String representation of port number
     flag-name: Name of the flag for error messages

   Returns:
     Integer port number (1-65535)

   Side Effects:
     Exits with error if parsing fails or port is out of range"
  (when (null value-string)
    (cli-error "~A requires a port number" flag-name))
  (handler-case
      (let ((port (parse-integer value-string)))
        (unless (and (integerp port) (<= 1 port 65535))
          (cli-error "~A must be between 1 and 65535, got: ~A" flag-name port))
        port)
    (error (e)
      (declare (ignore e))
      (cli-error "~A requires a valid integer, got: ~A" flag-name value-string))))

(defparameter *valid-log-levels*
  '("DEBUG" "INFO" "WARN" "WARNING" "ERROR" "FATAL")
  "Valid log level strings (case-insensitive).")

(defun validate-log-level (level-string flag-name)
  "Validate a log level string.

   Args:
     level-string: Log level string to validate
     flag-name: Name of the flag for error messages

   Returns:
     Uppercase log level string

   Side Effects:
     Exits with error if log level is invalid"
  (when (null level-string)
    (cli-error "~A requires a log level" flag-name))
  (let ((upper-level (string-upcase level-string)))
    (unless (member upper-level *valid-log-levels* :test #'string=)
      (cli-error "~A must be one of ~{~A~^, ~}, got: ~A"
                 flag-name *valid-log-levels* level-string))
    upper-level))

(defun parse-args (args)
  "Parse command-line arguments with validation.

   Args:
     args: List of command-line argument strings

   Returns:
     Plist of parsed arguments (:config-file, :orchestrator-id, etc.)

   Error Handling:
     - Missing values after flags trigger descriptive errors
     - Invalid port numbers are caught and reported
     - Invalid log levels are validated against allowed values
     - Unknown arguments cause usage to be printed"
  (let ((config-file nil)
        (orchestrator-id nil)
        (grpc-host nil)
        (grpc-port nil)
        (checkpoint-path nil)
        (restore-checkpoint nil)
        (log-level nil)
        (remaining-args args))
    ;; Use symbol for args-ref to allow modification in helper
    (declare (special remaining-args))
    (loop while remaining-args do
      (let ((arg (pop remaining-args)))
        (cond
          ;; Config file
          ((or (string= arg "--config") (string= arg "-c"))
           (let ((value (pop remaining-args)))
             (when (or (null value) (and (stringp value) (plusp (length value))
                                          (char= (char value 0) #\-)))
               (cli-error "--config requires a file path"))
             (setf config-file value)))

          ;; Orchestrator ID
          ((or (string= arg "--id") (string= arg "-i"))
           (let ((value (pop remaining-args)))
             (when (or (null value) (and (stringp value) (plusp (length value))
                                          (char= (char value 0) #\-)))
               (cli-error "--id requires an identifier"))
             (setf orchestrator-id value)))

          ;; gRPC host
          ((string= arg "--host")
           (let ((value (pop remaining-args)))
             (when (or (null value) (and (stringp value) (plusp (length value))
                                          (char= (char value 0) #\-)))
               (cli-error "--host requires a hostname or IP address"))
             (setf grpc-host value)))

          ;; gRPC port - with validation
          ((or (string= arg "--port") (string= arg "-p"))
           (let ((value (pop remaining-args)))
             (setf grpc-port (parse-port-value value "--port"))))

          ;; Checkpoint path
          ((string= arg "--checkpoint-path")
           (let ((value (pop remaining-args)))
             (when (or (null value) (and (stringp value) (plusp (length value))
                                          (char= (char value 0) #\-)))
               (cli-error "--checkpoint-path requires a directory path"))
             (setf checkpoint-path value)))

          ;; Restore from checkpoint
          ((string= arg "--restore")
           (let ((value (pop remaining-args)))
             (when (or (null value) (and (stringp value) (plusp (length value))
                                          (char= (char value 0) #\-)))
               (cli-error "--restore requires a checkpoint file path"))
             (setf restore-checkpoint value)))

          ;; Log level - with validation
          ((string= arg "--log-level")
           (let ((value (pop remaining-args)))
             (setf log-level (validate-log-level value "--log-level"))))

          ;; Help
          ((or (string= arg "--help") (string= arg "-h"))
           (print-usage)
           #+sbcl (sb-ext:exit :code 0)
           #-sbcl (error "Exit not implemented"))

          ;; Unknown argument
          (t
           (cli-error "Unknown argument: ~A" arg)))))

    ;; Return parsed arguments as plist
    (list :config-file config-file
          :orchestrator-id orchestrator-id
          :grpc-host grpc-host
          :grpc-port grpc-port
          :checkpoint-path checkpoint-path
          :restore-checkpoint restore-checkpoint
          :log-level log-level)))

(defun print-usage ()
  "Print command-line usage information."
  (format t "~&SW4RM Orchestrator v0.6.0~%~%")
  (format t "Usage: sw4rm-orchestrator [OPTIONS]~%~%")
  (format t "Options:~%")
  (format t "  -c, --config FILE          Load configuration from FILE~%")
  (format t "  -i, --id ID                Set orchestrator ID (default: from config)~%")
  (format t "  --host HOST                gRPC server host (default: 0.0.0.0)~%")
  (format t "  -p, --port PORT            gRPC server port (default: 50050)~%")
  (format t "  --checkpoint-path PATH     Checkpoint directory (default: /var/sw4rm/checkpoints)~%")
  (format t "  --restore FILE             Restore from checkpoint FILE~%")
  (format t "  --log-level LEVEL          Set log level (DEBUG, INFO, WARN, ERROR)~%")
  (format t "  -h, --help                 Show this help message~%~%")
  (format t "Examples:~%")
  (format t "  sw4rm-orchestrator --config /etc/sw4rm/config.lisp~%")
  (format t "  sw4rm-orchestrator --id root --port 50050~%")
  (format t "  sw4rm-orchestrator --restore /var/sw4rm/checkpoints/latest.bin~%~%"))

;;;; ============================================================================
;;;; Initialization
;;;; ============================================================================

(defun initialize-orchestrator (args-plist)
  "Initialize orchestrator from parsed arguments.

   Args:
     args-plist: Plist of command-line arguments

   Returns:
     Orchestrator instance (swarm-node)."
  ;; Load configuration file if specified
  (when-let ((config-file (getf args-plist :config-file)))
    (format t "Loading configuration from ~A...~%" config-file)
    (load-config-file config-file))

  ;; Load configuration from environment variables
  (load-config-from-env)

  ;; Override with command-line arguments
  (when-let ((orchestrator-id (getf args-plist :orchestrator-id)))
    (set-config "orchestrator.id" orchestrator-id))
  (when-let ((grpc-host (getf args-plist :grpc-host)))
    (set-config "grpc.host" grpc-host))
  (when-let ((grpc-port (getf args-plist :grpc-port)))
    (set-config "grpc.port" grpc-port))
  (when-let ((checkpoint-path (getf args-plist :checkpoint-path)))
    (set-config "checkpoint.path" checkpoint-path))
  (when-let ((log-level (getf args-plist :log-level)))
    (set-config "logging.level" log-level))

  ;; Validate configuration
  (validate-config)

  ;; Initialize logging
  (initialize-logging)

  ;; Reset degraded mode flag on fresh initialization
  (setf *grpc-degraded-mode* nil)

  ;; Restore from checkpoint if requested
  (if-let ((restore-file (getf args-plist :restore-checkpoint)))
    (progn
      (format t "Restoring orchestrator from ~A...~%" restore-file)
      (let ((state (restore-from-checkpoint restore-file)))
        (setf *orchestrator* (orchestrator-state-tree state))
        (restore-orchestrator-state state)))
    ;; Create new orchestrator
    (progn
      (format t "Creating new orchestrator with ID: ~A~%"
              (get-config "orchestrator.id"))
      (setf *orchestrator* (make-instance 'sw4rm-orchestrator.tree:swarm-node
                                          :id (get-config "orchestrator.id")))))

  ;; Enable WAL if configured
  (when (get-config "wal.enabled")
    (format t "Enabling write-ahead log at ~A...~%" (get-config "wal.path"))
    (enable-wal (get-config "wal.path")))

  ;; Start automatic checkpointing if configured
  (when (get-config "checkpoint.enabled")
    (start-automatic-checkpointing))

  *orchestrator*)

(defun initialize-logging ()
  "Initialize logging system based on configuration.

   Sets up log4cl with configured log level and output."
  ;; Configure log4cl if available
  #+log4cl
  (progn
    (let* ((level-str (string-upcase (get-config "logging.level")))
           (level (cond
                    ((string= level-str "DEBUG") :debug)
                    ((string= level-str "WARN") :warn)
                    ((string= level-str "ERROR") :error)
                    (t :info)))
           (log-file (get-config "logging.file"))
           (console (get-config "logging.console")))
      (when (and log-file (not (string= log-file "")))
        (uiop:ensure-all-directories-exist
         (list (uiop:pathname-directory-pathname log-file))))
      ;; Ensure root appenders are cleared; log:config :clear does not touch root.
      (log4cl::clear-logging-configuration)
      (apply #'log:config
             (append (list level :daily log-file :immediate-flush)
                     (when console (list :console))))
      (log:info "Logging initialized: level=~A, file=~A" level-str log-file)))
  #-log4cl
  (format t "Logging initialized: level=~A, file=~A~%"
          (get-config "logging.level")
          (get-config "logging.file")))

(defvar *checkpoint-thread* nil
  "Background thread for automatic checkpointing.")

(defvar *checkpoint-stop-flag* nil
  "Flag to signal checkpoint thread to stop cooperatively.
   When set to T, the checkpoint thread will finish its current operation
   and exit cleanly rather than being forcibly destroyed.")

(defconstant +checkpoint-thread-join-timeout+ 30
  "Maximum seconds to wait for checkpoint thread to exit during shutdown.
   If the thread does not exit within this time, a warning is logged.")

(defun start-automatic-checkpointing ()
  "Start automatic periodic checkpointing.

   Spawns a background thread that saves checkpoints at configured interval.
   The thread checks *checkpoint-stop-flag* to support cooperative shutdown,
   ensuring in-progress checkpoints complete before the thread exits."
  (let ((interval (get-config "checkpoint.interval"))
        (path (get-config "checkpoint.path")))
    (format t "Automatic checkpointing enabled: interval=~A seconds, path=~A~%"
            interval path)
    ;; Reset stop flag before starting thread
    (setf *checkpoint-stop-flag* nil)
    ;; Start background thread using bordeaux-threads
    (setf *checkpoint-thread*
          (bt:make-thread
           (lambda ()
             (loop while (not *checkpoint-stop-flag*)
                   do (progn
                        ;; Sleep in smaller increments to check stop flag more frequently
                        ;; This allows faster response to shutdown requests
                        (let ((sleep-remaining interval))
                          (loop while (and (> sleep-remaining 0)
                                           (not *checkpoint-stop-flag*))
                                do (let ((sleep-time (min sleep-remaining 1)))
                                     (sleep sleep-time)
                                     (decf sleep-remaining sleep-time))))
                        ;; Only proceed with checkpoint if not stopping
                        (when (and *orchestrator* (not *checkpoint-stop-flag*))
                          (handler-case
                              (let ((checkpoint-file (merge-pathnames
                                                      (format nil "auto-~A.bin" (get-universal-time))
                                                      path)))
                                (format t "~&[Auto-Checkpoint] Saving to ~A...~%" checkpoint-file)
                                (save-orchestrator-checkpoint checkpoint-file)
                                (format t "~&[Auto-Checkpoint] Saved successfully~%"))
                            (error (e)
                              (format *error-output* "~&[Auto-Checkpoint] Failed: ~A~%" e)))))))
           :name "sw4rm-checkpoint-thread"))))

(defun stop-checkpoint-thread ()
  "Stop the checkpoint thread cooperatively.

   This function signals the checkpoint thread to stop and waits for it to
   finish any in-progress checkpoint operation before returning. This ensures
   no data corruption from interrupted checkpoint writes.

   The function:
     1. Sets *checkpoint-stop-flag* to T to signal the thread to stop
     2. Waits up to +checkpoint-thread-join-timeout+ seconds for clean exit
     3. Logs a warning if the thread does not exit in time
     4. Clears the thread reference

   Returns:
     T if thread stopped cleanly, NIL if timeout or no thread was running."
  (if (null *checkpoint-thread*)
      (progn
        (log:debug "No checkpoint thread running")
        nil)
      (progn
        ;; Signal the thread to stop
        (setf *checkpoint-stop-flag* t)
        (log:info "Waiting for checkpoint thread to finish (timeout: ~A seconds)..."
                  +checkpoint-thread-join-timeout+)
        ;; Wait for thread to finish with timeout
        (let ((thread-stopped nil))
          (handler-case
              (progn
                ;; bt:join-thread waits for thread completion
                ;; We implement timeout by polling thread-alive-p
                (let ((start-time (get-internal-real-time))
                      (timeout-internal (* +checkpoint-thread-join-timeout+
                                           internal-time-units-per-second)))
                  (loop while (and (bt:thread-alive-p *checkpoint-thread*)
                                   (< (- (get-internal-real-time) start-time)
                                      timeout-internal))
                        do (sleep 0.1))
                  (setf thread-stopped (not (bt:thread-alive-p *checkpoint-thread*)))))
            (error (e)
              (log:error "Error waiting for checkpoint thread: ~A" e)))
          ;; Log result
          (if thread-stopped
              (format t "Checkpoint thread stopped cleanly~%")
              (format *error-output*
                      "WARNING: Checkpoint thread did not stop within ~A seconds~%"
                      +checkpoint-thread-join-timeout+))
          ;; Clear thread reference
          (setf *checkpoint-thread* nil)
          thread-stopped))))

;;;; ============================================================================
;;;; Main entry point
;;;; ============================================================================

(defun main (&optional args)
  "Main entry point for orchestrator executable.

   Args:
     args: Command-line arguments (optional, uses sb-ext:*posix-argv* if nil)

   Returns:
     Exit code (0 for success, non-zero for error)."
  ;; Get command-line arguments
  (let ((argv (or args
                  #+sbcl (rest sb-ext:*posix-argv*)
                  #-sbcl '())))
    ;; Parse arguments
    (let ((args-plist (parse-args argv)))
      ;; Initialize orchestrator
      (handler-case
          (progn
            (initialize-orchestrator args-plist)

            ;; Start gRPC server
            (start-orchestrator-server)

            ;; Print status
            (print-orchestrator-status)

            ;; Install signal handlers for graceful shutdown
            (install-signal-handlers)

            ;; Run main event loop
            (run-event-loop)

            ;; Graceful shutdown
            (shutdown-orchestrator)

            ;; Success
            0)

        ;; Error handling
        (error (e)
          (format *error-output* "~&ERROR: ~A~%" e)
          1)))))

;;;; ============================================================================
;;;; gRPC server management
;;;; ============================================================================

(defun start-orchestrator-server ()
  "Start orchestrator gRPC server.

   Starts server on configured host/port and registers handlers.
   If gRPC startup fails, enters degraded mode with mock handlers and
   sets *GRPC-DEGRADED-MODE* to T. In degraded mode, health endpoints
   will report :DEGRADED status instead of :READY.

   Side Effects:
     - Sets *GRPC-SERVER* to server instance or mock plist
     - Sets *GRPC-DEGRADED-MODE* to T on failure
     - Logs warning/error messages on failure

   See Also:
     *GRPC-DEGRADED-MODE*, GET-HEALTH-STATUS, GRPC-DEGRADED-MODE-P"
  (let ((host (get-config "grpc.host"))
        (port (get-config "grpc.port")))
    (format t "Starting gRPC server on ~A:~A...~%" host port)
    ;; Ensure degraded mode is cleared before attempting startup
    (setf *grpc-degraded-mode* nil)
    (handler-case
        (progn
          ;; Start the gRPC server using the grpc module
          (setf *grpc-server* (sw4rm-orchestrator.grpc:start-grpc-server
                               :host host
                               :port port))

          ;; Register default handlers
          (sw4rm-orchestrator.grpc:register-routing-handler
           (lambda (envelope)
             (route-envelope *orchestrator* envelope)))

          (sw4rm-orchestrator.grpc:register-leaf-status-handler
           (lambda (leaf-id status)
             (format t "~&[Status] Leaf ~A: ~A~%" leaf-id status)))

          (sw4rm-orchestrator.grpc:register-heartbeat-handler
           (lambda (leaf-id heartbeat)
             (format t "~&[Heartbeat] Leaf ~A alive~%" leaf-id)))

          (format t "gRPC server started successfully~%"))
      (error (e)
        ;; IMPORTANT: Explicitly enter degraded mode and log clearly
        (setf *grpc-degraded-mode* t)
        ;; Log at ERROR level to make the degraded state very visible
        (format *error-output*
                "~&========================================~%")
        (format *error-output*
                "~&ERROR: gRPC server startup FAILED~%")
        (format *error-output*
                "~&  Reason: ~A~%" e)
        (format *error-output*
                "~&  Host: ~A, Port: ~A~%" host port)
        (format *error-output*
                "~&========================================~%")
        (format *error-output*
                "~&WARNING: Entering DEGRADED MODE~%")
        (format *error-output*
                "~&  - Health endpoints will report :DEGRADED status~%")
        (format *error-output*
                "~&  - gRPC handlers are NOT available~%")
        (format *error-output*
                "~&  - Cross-swarm routing will NOT function~%")
        (format *error-output*
                "~&========================================~%")
        ;; Also log to standard output for visibility
        #+log4cl (log:error "gRPC startup failed, entering degraded mode: ~A" e)
        #-log4cl (format t "~&[ERROR] gRPC startup failed, entering degraded mode: ~A~%" e)
        ;; Set up mock server for graceful degradation
        (setf *grpc-server* (list :host host :port port :running nil :mock t :degraded t))))))

(defun stop-orchestrator-server ()
  "Stop orchestrator gRPC server gracefully.

   Also clears the degraded mode flag when stopping."
  (format t "Stopping gRPC server...~%")
  (when *grpc-server*
    (handler-case
        (progn
          (when (and (not (getf *grpc-server* :mock))
                     (sw4rm-orchestrator.grpc:grpc-server-running-p))
            (sw4rm-orchestrator.grpc:stop-grpc-server))
          (setf *grpc-server* nil)
          (setf *grpc-degraded-mode* nil)
          (format t "gRPC server stopped~%"))
      (error (e)
        (format *error-output* "Error stopping gRPC server: ~A~%" e)
        (setf *grpc-server* nil)
        (setf *grpc-degraded-mode* nil)))))

;;;; ============================================================================
;;;; Event loop
;;;; ============================================================================

(defun run-event-loop ()
  "Run main event loop until shutdown requested.

   Processes:
     - Incoming gRPC requests (handled by gRPC threads)
     - Periodic tasks (heartbeats, metrics collection)
     - Shutdown signals"
  (format t "Entering main event loop (Ctrl-C to stop)...~%")
  (loop until *shutdown-requested* do
    ;; Sleep and check for shutdown
    ;; In real implementation, this would process events
    (sleep 1)))

;;;; ============================================================================
;;;; Signal handling
;;;; ============================================================================

(defun install-signal-handlers ()
  "Install signal handlers for graceful shutdown.

   Handles:
     - SIGINT (Ctrl-C): Request graceful shutdown
     - SIGTERM: Request graceful shutdown"
  #+sbcl
  (progn
    (sb-sys:enable-interrupt sb-unix:sigint #'handle-shutdown-signal)
    (sb-sys:enable-interrupt sb-unix:sigterm #'handle-shutdown-signal)
    (format t "Signal handlers installed (SIGINT, SIGTERM)~%"))
  #-sbcl
  (warn "Signal handlers not implemented for this Lisp implementation"))

(defun handle-shutdown-signal (signal code scp)
  "Handle shutdown signal.

   Args:
     signal: Signal number
     code: Signal code
     scp: Signal context pointer

   Sets shutdown flag and returns."
  (declare (ignore code scp))
  (format t "~&Received signal ~A, requesting graceful shutdown...~%" signal)
  (setf *shutdown-requested* t))

;;;; ============================================================================
;;;; Shutdown
;;;; ============================================================================

(defun shutdown-orchestrator ()
  "Gracefully shutdown orchestrator.

   Steps:
     1. Stop checkpoint thread cooperatively (wait for in-progress checkpoint)
     2. Save final shutdown checkpoint
     3. Close connections to leaves
     4. Flush WAL
     5. Stop gRPC server
     6. Exit

   The checkpoint thread is stopped first using cooperative shutdown to ensure
   any in-progress checkpoint operation completes before we proceed. This prevents
   data corruption from interrupted writes."
  (format t "~&=== Graceful Shutdown ===~%")

  ;; Stop checkpoint thread cooperatively - wait for in-progress checkpoints
  (when *checkpoint-thread*
    (format t "Stopping checkpoint thread...~%")
    (stop-checkpoint-thread))

  ;; Save checkpoint
  (when (get-config "checkpoint.enabled")
    (format t "Saving final checkpoint...~%")
    (let ((checkpoint-path (merge-pathnames
                            "shutdown.bin"
                            (get-config "checkpoint.path"))))
      (handler-case
          (progn
            (save-orchestrator-checkpoint checkpoint-path)
            (format t "Checkpoint saved to ~A~%" checkpoint-path))
        (error (e)
          (format *error-output* "Failed to save checkpoint: ~A~%" e)))))

  ;; Disconnect from all leaves
  (when *orchestrator*
    (format t "Disconnecting from leaf nodes...~%")
    (dolist (child (sw4rm-orchestrator.tree:list-children *orchestrator*))
      (when (typep child 'sw4rm-orchestrator.tree:swarm-leaf)
        (handler-case
            (let ((client (sw4rm-orchestrator.tree:leaf-grpc-client child)))
              (when client
                (sw4rm-orchestrator.grpc:disconnect client)))
          (error (e)
            (format *error-output* "Failed to disconnect leaf ~A: ~A~%"
                    (sw4rm-orchestrator.tree:swarm-id child) e))))))

  ;; Flush WAL
  (when (wal-enabled-p)
    (format t "Flushing write-ahead log...~%")
    (flush-wal))

  ;; Stop gRPC server
  (stop-orchestrator-server)

  (format t "Shutdown complete~%"))

;;;; ============================================================================
;;;; Health status reporting
;;;; ============================================================================

(defvar *recovery-in-progress* nil
  "Flag indicating WAL replay or checkpoint restore is in progress.

   Set to T during recovery operations and cleared when recovery completes.
   Used by GET-HEALTH-STATUS to return :RECOVERING state.

   See Also:
     GET-HEALTH-STATUS, RESTORE-FROM-CHECKPOINT")

(defun check-leaf-connectivity (leaf)
  "Check if a leaf node can be contacted.

   Attempts to verify gRPC connectivity to the leaf. A leaf is considered
   unreachable if:
     - gRPC channel is nil
     - Last heartbeat is too old (>60 seconds)
     - Connection test fails

   Args:
     leaf: SWARM-LEAF instance

   Returns:
     T if leaf is reachable, NIL if unreachable.

   See Also:
     COMPUTE-CHILD-HEALTH-STATUS"
  (and (sw4rm-orchestrator.tree:grpc-channel leaf)
       (sw4rm-orchestrator.tree:leaf-last-heartbeat leaf)
       (< (- (get-universal-time)
             (sw4rm-orchestrator.tree:leaf-last-heartbeat leaf))
          60)))

(defun compute-child-health-status (orchestrator)
  "Compute aggregated health status based on children.

   Examines all child nodes/leaves and determines overall status:
     - All children :READY -> :READY
     - Some children degraded/unreachable -> :PARTIAL
     - All children degraded/unreachable -> :DEGRADED
     - At least one child unreachable -> :PARTIAL or :UNREACHABLE

   Args:
     orchestrator: SWARM-NODE instance

   Returns:
     One of :READY, :PARTIAL, :DEGRADED, :UNREACHABLE

   See Also:
     GET-HEALTH-STATUS"
  (let ((children (sw4rm-orchestrator.tree:list-children orchestrator)))
    (cond
      ;; No children - ready (nothing to be partial about)
      ((null children)
       :ready)

      ;; Check children status
      (t
       (let ((healthy-count 0)
             (degraded-count 0)
             (unreachable-count 0)
             (total-count (length children)))

         ;; Count children by status
         (dolist (child children)
           (let ((status (sw4rm-orchestrator.tree:node-status child)))
             (cond
               ((eq status :ready)
                (incf healthy-count))
               ((eq status :unreachable)
                (incf unreachable-count))
               ((or (eq status :degraded)
                    (eq status :partial)
                    (eq status :recovering))
                (incf degraded-count)))))

         ;; Additional connectivity check for leaves
         (dolist (child children)
           (when (and (typep child 'sw4rm-orchestrator.tree:swarm-leaf)
                      (eq (sw4rm-orchestrator.tree:node-status child) :ready)
                      (not (check-leaf-connectivity child)))
             (incf unreachable-count)
             (decf healthy-count)))

         ;; Determine overall status
         (cond
           ;; All children healthy
           ((= healthy-count total-count)
            :ready)

           ;; All children unreachable
           ((= unreachable-count total-count)
            :unreachable)

           ;; Some children have problems
           ((or (> unreachable-count 0)
                (> degraded-count 0))
            :partial)

           ;; Default to ready
           (t :ready)))))))

(defun get-health-status ()
  "Get the current health status of the orchestrator.

   Returns one of:
     :READY       - Orchestrator is fully operational with gRPC server running
     :DEGRADED    - Orchestrator is running but experiencing issues
     :NOT-READY   - Orchestrator is not initialized or shutting down
     :UNREACHABLE - Leaf nodes cannot be contacted (P2-5)
     :PARTIAL     - Some children healthy, others degraded (P2-5)
     :RECOVERING  - WAL replay or checkpoint restore in progress (P2-5)

   The health status is determined by:
     1. Recovery state (*recovery-in-progress*)
     2. Orchestrator initialization state
     3. gRPC server state (*grpc-degraded-mode*)
     4. Child node health (for SWARM-NODE instances)
     5. Leaf connectivity (for leaves)

   The health status is used by:
     - Kubernetes liveness/readiness probes
     - Load balancer health checks
     - Monitoring systems
     - Operators checking system state

   Examples:
     (get-health-status)
     => :READY     ; Normal operation

     (get-health-status)
     => :DEGRADED  ; gRPC failed, running with mock handlers

     (get-health-status)
     => :PARTIAL   ; Some children degraded

     (get-health-status)
     => :RECOVERING ; WAL replay in progress

   See Also:
     *GRPC-DEGRADED-MODE*, *RECOVERY-IN-PROGRESS*, GRPC-DEGRADED-MODE-P,
     ORCHESTRATOR-STATUS, COMPUTE-CHILD-HEALTH-STATUS"
  (cond
    ;; No orchestrator instance - not ready
    ((null *orchestrator*)
     :not-ready)

    ;; Shutdown in progress - not ready
    (*shutdown-requested*
     :not-ready)

    ;; Recovery (WAL replay or checkpoint restore) in progress
    (*recovery-in-progress*
     :recovering)

    ;; Check if orchestrator itself is in recovering state
    ((eq (sw4rm-orchestrator.tree:node-status *orchestrator*) :recovering)
     :recovering)

    ;; gRPC failed to start - degraded
    (*grpc-degraded-mode*
     :degraded)

    ;; No gRPC server at all - degraded
    ((null *grpc-server*)
     :degraded)

    ;; For SWARM-NODE, check child health
    ((typep *orchestrator* 'sw4rm-orchestrator.tree:swarm-node)
     (let ((child-status (compute-child-health-status *orchestrator*)))
       (cond
         ;; All children healthy and gRPC running - ready
         ((eq child-status :ready)
          :ready)

         ;; Children have mixed health - partial
         ((eq child-status :partial)
          :partial)

         ;; All children unreachable - unreachable
         ((eq child-status :unreachable)
          :unreachable)

         ;; Children degraded - degraded
         ((eq child-status :degraded)
          :degraded)

         ;; Default
         (t :ready))))

    ;; Everything operational - ready
    (t
     :ready)))

(defun health-status-string ()
  "Get a human-readable health status string.

   Returns a string suitable for HTTP health endpoints or logging.

   Examples:
     (health-status-string)
     => \"ready\"
     => \"degraded\"
     => \"not-ready\""
  (string-downcase (symbol-name (get-health-status))))

;;;; ============================================================================
;;;; Status reporting
;;;; ============================================================================

(defun print-orchestrator-status ()
  "Print orchestrator status to stdout.

   Now includes health status and degraded mode warning."
  (format t "~&=== SW4RM Orchestrator Status ===~%")
  (format t "Orchestrator ID: ~A~%" (get-config "orchestrator.id"))
  (format t "Version: ~A~%" (get-config "orchestrator.version"))
  (format t "gRPC Server: ~A:~A~%"
          (get-config "grpc.host")
          (get-config "grpc.port"))
  ;; Show health status prominently
  (let ((health (get-health-status)))
    (format t "Health Status: ~A~%" health)
    (when (eq health :degraded)
      (format t "~&*** WARNING: Running in DEGRADED MODE ***~%")
      (format t "*** gRPC handlers are NOT available ***~%")))
  (when *orchestrator*
    (format t "Tree Depth: ~A~%" (node-depth *orchestrator*))
    (format t "Children: ~A~%" (length (list-children *orchestrator*))))
  (format t "Checkpoint Enabled: ~A~%" (get-config "checkpoint.enabled"))
  (format t "WAL Enabled: ~A~%" (get-config "wal.enabled"))
  ;; Only print "Ready" if actually ready
  (if (eq (get-health-status) :ready)
      (format t "~%Ready to accept connections.~%~%")
      (format t "~%WARNING: Not fully ready - check health status above.~%~%")))

;;;; ============================================================================
;;;; Standalone executable building
;;;; ============================================================================

(defun build-image ()
  "Build standalone orchestrator executable.

   Creates a standalone binary that can be run without SBCL/Lisp runtime.
   The executable will be saved as 'sw4rm-orchestrator' in the current directory.

   This function is typically called during build/deployment, not at runtime."
  #+sbcl
  (progn
    (format t "Building standalone orchestrator image...~%")
    (sb-ext:save-lisp-and-die "sw4rm-orchestrator"
                              :toplevel #'main
                              :executable t
                              :compression t
                              :save-runtime-options t))
  #-sbcl
  (error "build-image not implemented for this Lisp implementation"))

;;;; ============================================================================
;;;; Development/REPL helpers
;;;; ============================================================================

(defun start-orchestrator (&key
                            (id "orchestrator-root")
                            (host "0.0.0.0")
                            (port 50050))
  "Start orchestrator in REPL for development/testing.

   Args:
     id: Orchestrator ID
     host: gRPC server host
     port: gRPC server port

   Returns:
     Orchestrator instance

   Example:
     (start-orchestrator :id \"dev-orchestrator\" :port 50051)"
  ;; Set configuration
  (set-config "orchestrator.id" id)
  (set-config "grpc.host" host)
  (set-config "grpc.port" port)
  (set-config "checkpoint.enabled" nil)  ; Disable auto-checkpoint in REPL
  (set-config "wal.enabled" nil)         ; Disable WAL in REPL

  ;; Reset degraded mode
  (setf *grpc-degraded-mode* nil)

  ;; Create orchestrator
  (setf *orchestrator* (make-instance 'sw4rm-orchestrator.tree:swarm-node :id id))

  ;; Start server
  (start-orchestrator-server)

  ;; Print status
  (print-orchestrator-status)

  *orchestrator*)

(defun stop-orchestrator ()
  "Stop orchestrator in REPL.

   Performs cooperative shutdown of the checkpoint thread to ensure any
   in-progress checkpoint operation completes before stopping.

   Returns:
     NIL"
  (when *grpc-server*
    (stop-orchestrator-server))
  ;; Use cooperative shutdown for checkpoint thread
  (when *checkpoint-thread*
    (stop-checkpoint-thread))
  (setf *orchestrator* nil)
  (setf *grpc-degraded-mode* nil)
  nil)

(defun restart-orchestrator (&key (graceful t))
  "Restart orchestrator in REPL.

   Args:
     graceful: If T, save checkpoint before restart

   Returns:
     Restarted orchestrator instance"
  (when (and graceful *orchestrator* (get-config "checkpoint.enabled"))
    (format t "Saving checkpoint before restart...~%")
    (save-orchestrator-checkpoint
     (merge-pathnames "restart.bin" (get-config "checkpoint.path"))))

  (stop-orchestrator)
  (start-orchestrator :id (get-config "orchestrator.id")
                      :host (get-config "grpc.host")
                      :port (get-config "grpc.port")))

(defun describe-orchestrator (&optional (orchestrator *orchestrator*))
  "Describe orchestrator state in human-readable format.

   Args:
     orchestrator: Orchestrator instance (defaults to *orchestrator*)

   Returns:
     NIL (prints to stdout)"
  (if (null orchestrator)
      (format t "No orchestrator instance~%")
      (progn
        (format t "~&=== Orchestrator Description ===~%")
        (format t "ID: ~A~%" (sw4rm-orchestrator.tree:swarm-id orchestrator))
        (format t "Type: ~A~%" (type-of orchestrator))
        (format t "Health Status: ~A~%" (get-health-status))
        (when *grpc-degraded-mode*
          (format t "*** DEGRADED MODE: gRPC not available ***~%"))
        (format t "Depth: ~A~%" (sw4rm-orchestrator.tree:node-depth orchestrator))
        (format t "Children: ~A~%" (length (sw4rm-orchestrator.tree:list-children orchestrator)))

        ;; List children
        (let ((children (sw4rm-orchestrator.tree:list-children orchestrator)))
          (when children
            (format t "~%Child nodes:~%")
            (dolist (child children)
              (format t "  - ~A (~A)~%"
                      (sw4rm-orchestrator.tree:swarm-id child)
                      (type-of child)))))

        ;; Routing table stats
        (when (typep orchestrator 'sw4rm-orchestrator.tree:swarm-node)
          (let ((rtable (sw4rm-orchestrator.tree:routing-table orchestrator)))
            (when rtable
              (format t "~%Routing table:~%")
              (format t "  Local routes: ~A~%"
                      (length (sw4rm-orchestrator.routing:routing-table-local-routes rtable)))
              (format t "  External routes: ~A~%"
                      (length (sw4rm-orchestrator.routing:routing-table-external-routes rtable))))))

        (format t "~%")))
  nil)

(defun orchestrator-status (&optional (orchestrator *orchestrator*))
  "Get orchestrator status as a plist.

   Args:
     orchestrator: Orchestrator instance (defaults to *orchestrator*)

   Returns:
     Plist with status information including health and degraded mode."
  (if (null orchestrator)
      (list :status :not-running
            :health :not-ready
            :grpc-degraded-mode nil)
      (list :status :running
            :health (get-health-status)
            :grpc-degraded-mode *grpc-degraded-mode*
            :id (sw4rm-orchestrator.tree:swarm-id orchestrator)
            :type (type-of orchestrator)
            :depth (sw4rm-orchestrator.tree:node-depth orchestrator)
            :children (length (sw4rm-orchestrator.tree:list-children orchestrator))
            :grpc-server-running (and *grpc-server* (not *grpc-degraded-mode*))
            :checkpoint-enabled (get-config "checkpoint.enabled")
            :wal-enabled (get-config "wal.enabled"))))

(defun orchestrator-metrics (&optional (orchestrator *orchestrator*))
  "Get orchestrator metrics as a plist.

   Args:
     orchestrator: Orchestrator instance (defaults to *orchestrator*)

   Returns:
     Plist with metrics"
  (if (null orchestrator)
      (list :error "No orchestrator instance")
      (list :tree-height (sw4rm-orchestrator.tree:tree-height orchestrator)
            :tree-size (sw4rm-orchestrator.tree:tree-size orchestrator)
            :leaf-count (sw4rm-orchestrator.tree:leaf-count orchestrator)
            :node-count (sw4rm-orchestrator.tree:node-count orchestrator)
            :tree-balanced (sw4rm-orchestrator.tree:tree-balanced-p orchestrator))))

(defun make-orchestrator (&key
                          (id "orchestrator-root")
                          (config nil))
  "Create a new orchestrator instance with optional configuration.

   Args:
     id: Orchestrator ID
     config: Configuration plist or hash-table

   Returns:
     New orchestrator instance

   Example:
     (make-orchestrator :id \"root\" :config '(\"grpc.port\" 50051))"
  ;; Apply configuration if provided
  (when config
    (etypecase config
      (hash-table
       (maphash (lambda (k v) (set-config k v)) config))
      (list
       (loop for (key value) on config by #'cddr
             do (set-config key value)))))

  ;; Create and return orchestrator
  (make-instance 'sw4rm-orchestrator.tree:swarm-node :id id))

;;;; End of file
