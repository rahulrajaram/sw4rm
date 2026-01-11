;;;; registry-service.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Registry Service
;;;;
;;;; Purpose: Agent registration, heartbeat tracking, and discovery service.
;;;; This is the equivalent of the Python registry_service.py.
;;;;
;;;; Protocol: JSON-over-TCP with 4-byte big-endian length prefix
;;;; Default Port: 50052
;;;;
;;;; Features:
;;;;   - Agent registration with metadata
;;;;   - Heartbeat tracking with configurable TTL
;;;;   - Automatic cleanup of stale agents
;;;;   - Protected agents (never auto-removed)
;;;;   - Thread-safe in-memory state
;;;;
;;;; Usage:
;;;;   sbcl --load registry-service.lisp --eval '(registry-service:start-server)'
;;;;
;;;; Environment:
;;;;   REGISTRY_PORT - Server port (default: 50052)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :registry-service
  (:use :cl)
  (:export #:start-server
           #:stop-server
           #:*server*
           #:*agents*
           #:register-agent
           #:deregister-agent
           #:heartbeat
           #:list-agents
           #:get-agent
           #:clear-all))

(in-package :registry-service)

;;; ==========================================================================
;;; Dependencies
;;; ==========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:usocket :bordeaux-threads :cl-json :alexandria :local-time)
                :silent t))

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *default-port* 50052
  "Default registry service port.")

(defparameter *heartbeat-timeout* 300
  "Seconds before an agent is considered stale (5 minutes).")

(defparameter *cleanup-interval* 60
  "Seconds between cleanup sweeps.")

(defparameter *protected-agents* '("scheduler")
  "Agent IDs that are never auto-removed.")

;;; ==========================================================================
;;; Agent Record
;;; ==========================================================================

(defclass agent-record ()
  ((agent-id :initarg :agent-id :accessor agent-id :type string)
   (metadata :initarg :metadata :accessor agent-metadata :initform nil)
   (status :initarg :status :accessor agent-status :initform :active)
   (registered-at :initarg :registered-at :accessor agent-registered-at)
   (last-heartbeat :initarg :last-heartbeat :accessor agent-last-heartbeat))
  (:documentation "Record of a registered agent."))

(defun make-agent-record (agent-id &key metadata)
  "Create a new agent record with current timestamp."
  (let ((now (get-universal-time)))
    (make-instance 'agent-record
                   :agent-id agent-id
                   :metadata metadata
                   :registered-at now
                   :last-heartbeat now)))

(defmethod agent-to-plist ((record agent-record))
  "Convert agent record to plist for JSON serialization."
  (list :agent-id (agent-id record)
        :metadata (agent-metadata record)
        :status (string-downcase (symbol-name (agent-status record)))
        :registered-at (agent-registered-at record)
        :last-heartbeat (agent-last-heartbeat record)))

;;; ==========================================================================
;;; State Management
;;; ==========================================================================

(defparameter *agents* (make-hash-table :test 'equal)
  "Hash table of agent-id -> agent-record.")

(defparameter *lock* (bt:make-lock "registry-lock")
  "Lock for thread-safe state access.")

(defparameter *server* nil
  "The running server socket.")

(defparameter *running* nil
  "Flag to control server loop.")

(defparameter *cleanup-thread* nil
  "Background cleanup thread.")

;;; ==========================================================================
;;; Core Operations
;;; ==========================================================================

(defun register-agent (agent-id &key metadata)
  "Register an agent or update existing registration.
Returns the agent record."
  (bt:with-lock-held (*lock*)
    (let ((existing (gethash agent-id *agents*)))
      (if existing
          (progn
            (setf (agent-metadata existing) metadata)
            (setf (agent-last-heartbeat existing) (get-universal-time))
            (setf (agent-status existing) :active)
            existing)
          (let ((record (make-agent-record agent-id :metadata metadata)))
            (setf (gethash agent-id *agents*) record)
            (format t "[Registry] Registered agent: ~A~%" agent-id)
            record)))))

(defun deregister-agent (agent-id)
  "Remove an agent from the registry.
Returns T if agent existed, NIL otherwise."
  (bt:with-lock-held (*lock*)
    (when (gethash agent-id *agents*)
      (remhash agent-id *agents*)
      (format t "[Registry] Deregistered agent: ~A~%" agent-id)
      t)))

(defun heartbeat (agent-id &key status metadata)
  "Update an agent's heartbeat timestamp and optionally status/metadata.
Returns the updated agent record or NIL if not found."
  (bt:with-lock-held (*lock*)
    (let ((record (gethash agent-id *agents*)))
      (when record
        (setf (agent-last-heartbeat record) (get-universal-time))
        (when status
          (setf (agent-status record) status))
        (when metadata
          (setf (agent-metadata record) metadata))
        record))))

(defun list-agents (&key status)
  "List all registered agents, optionally filtered by status."
  (bt:with-lock-held (*lock*)
    (let ((results nil))
      (maphash (lambda (id record)
                 (declare (ignore id))
                 (when (or (null status)
                           (eq (agent-status record) status))
                   (push (agent-to-plist record) results)))
               *agents*)
      (nreverse results))))

(defun get-agent (agent-id)
  "Get a specific agent by ID."
  (bt:with-lock-held (*lock*)
    (let ((record (gethash agent-id *agents*)))
      (when record
        (agent-to-plist record)))))

(defun clear-all ()
  "Clear all agents (for testing)."
  (bt:with-lock-held (*lock*)
    (clrhash *agents*)))

;;; ==========================================================================
;;; Stale Agent Cleanup
;;; ==========================================================================

(defun cleanup-stale-agents ()
  "Remove agents that haven't sent a heartbeat within the timeout period.
Protected agents are never removed."
  (let ((now (get-universal-time))
        (removed 0))
    (bt:with-lock-held (*lock*)
      (maphash (lambda (agent-id record)
                 (let ((age (- now (agent-last-heartbeat record))))
                   (when (and (> age *heartbeat-timeout*)
                              (not (member agent-id *protected-agents* :test #'equal)))
                     (remhash agent-id *agents*)
                     (incf removed)
                     (format t "[Registry] Removed stale agent: ~A (age: ~Ds)~%"
                             agent-id age))))
               *agents*))
    (when (> removed 0)
      (format t "[Registry] Cleanup removed ~D stale agent(s)~%" removed))))

(defun start-cleanup-thread ()
  "Start the background cleanup thread."
  (setf *cleanup-thread*
        (bt:make-thread
         (lambda ()
           (loop while *running*
                 do (sleep *cleanup-interval*)
                    (when *running*
                      (handler-case
                          (cleanup-stale-agents)
                        (error (e)
                          (format t "[Registry] Cleanup error: ~A~%" e))))))
         :name "registry-cleanup")))

;;; ==========================================================================
;;; JSON-over-TCP Protocol
;;; ==========================================================================

(defun read-message (stream)
  "Read a length-prefixed JSON message from stream.
Returns parsed JSON as plist or NIL on error/EOF."
  (handler-case
      (let ((length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
        (when (= 4 (read-sequence length-bytes stream))
          (let ((length (+ (ash (aref length-bytes 0) 24)
                           (ash (aref length-bytes 1) 16)
                           (ash (aref length-bytes 2) 8)
                           (aref length-bytes 3))))
            (when (and (> length 0) (< length (* 16 1024 1024))) ; 16MB max
              (let ((payload (make-array length :element-type '(unsigned-byte 8))))
                (when (= length (read-sequence payload stream))
                  (let ((json-string (babel:octets-to-string payload :encoding :utf-8)))
                    (cl-json:decode-json-from-string json-string))))))))
    (end-of-file () nil)
    (error () nil)))

(defun write-message (stream response)
  "Write a length-prefixed JSON message to stream."
  (let* ((json-string (cl-json:encode-json-to-string response))
         (payload (babel:string-to-octets json-string :encoding :utf-8))
         (length (length payload))
         (length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
    (setf (aref length-bytes 0) (ldb (byte 8 24) length))
    (setf (aref length-bytes 1) (ldb (byte 8 16) length))
    (setf (aref length-bytes 2) (ldb (byte 8 8) length))
    (setf (aref length-bytes 3) (ldb (byte 8 0) length))
    (write-sequence length-bytes stream)
    (write-sequence payload stream)
    (force-output stream)))

;;; ==========================================================================
;;; Request Handling
;;; ==========================================================================

(defun handle-request (request)
  "Process a request and return a response.
Request format: {:method ... :params {...}}
Response format: {:success T/NIL :result ... :error ...}"
  (let ((method (cdr (assoc :method request)))
        (params (cdr (assoc :params request))))
    (handler-case
        (cond
          ;; RegisterAgent
          ((string-equal method "register")
           (let* ((agent-id (cdr (assoc :agent-id params)))
                  (metadata (cdr (assoc :metadata params)))
                  (record (register-agent agent-id :metadata metadata)))
             (list (cons :success t)
                   (cons :result (agent-to-plist record)))))

          ;; DeregisterAgent
          ((string-equal method "deregister")
           (let* ((agent-id (cdr (assoc :agent-id params)))
                  (removed (deregister-agent agent-id)))
             (list (cons :success removed)
                   (cons :result (if removed "deregistered" "not found")))))

          ;; Heartbeat
          ((string-equal method "heartbeat")
           (let* ((agent-id (cdr (assoc :agent-id params)))
                  (status (cdr (assoc :status params)))
                  (metadata (cdr (assoc :metadata params)))
                  (record (heartbeat agent-id
                                     :status (when status (intern (string-upcase status) :keyword))
                                     :metadata metadata)))
             (if record
                 (list (cons :success t)
                       (cons :result (agent-to-plist record)))
                 (list (cons :success nil)
                       (cons :error "agent not found")))))

          ;; ListAgents
          ((string-equal method "list")
           (let* ((status-str (cdr (assoc :status params)))
                  (status (when status-str (intern (string-upcase status-str) :keyword)))
                  (agents (list-agents :status status)))
             (list (cons :success t)
                   (cons :result agents))))

          ;; GetAgent
          ((string-equal method "get")
           (let* ((agent-id (cdr (assoc :agent-id params)))
                  (agent (get-agent agent-id)))
             (if agent
                 (list (cons :success t)
                       (cons :result agent))
                 (list (cons :success nil)
                       (cons :error "agent not found")))))

          ;; Health check
          ((string-equal method "health")
           (list (cons :success t)
                 (cons :result "healthy")
                 (cons :agent-count (hash-table-count *agents*))))

          ;; Unknown method
          (t
           (list (cons :success nil)
                 (cons :error (format nil "unknown method: ~A" method)))))

      (error (e)
        (list (cons :success nil)
              (cons :error (format nil "~A" e)))))))

;;; ==========================================================================
;;; Client Connection Handler
;;; ==========================================================================

(defun handle-client (client-socket)
  "Handle a single client connection."
  (let ((stream (usocket:socket-stream client-socket)))
    (unwind-protect
         (loop for request = (read-message stream)
               while request
               do (let ((response (handle-request request)))
                    (write-message stream response)))
      (usocket:socket-close client-socket))))

;;; ==========================================================================
;;; Server Lifecycle
;;; ==========================================================================

(defun get-port ()
  "Get port from environment or use default."
  (let ((env-port (uiop:getenv "REGISTRY_PORT")))
    (if env-port
        (parse-integer env-port :junk-allowed t)
        *default-port*)))

(defun start-server (&key (port nil))
  "Start the registry service.
Returns the server socket."
  (let ((actual-port (or port (get-port))))
    (format t "[Registry] Starting on port ~D~%" actual-port)

    ;; Create server socket
    (setf *server* (usocket:socket-listen "0.0.0.0" actual-port
                                           :reuse-address t
                                           :element-type '(unsigned-byte 8)))
    (setf *running* t)

    ;; Start cleanup thread
    (start-cleanup-thread)

    ;; Accept connections in a loop
    (format t "[Registry] Ready to accept connections~%")
    (unwind-protect
         (loop while *running*
               do (handler-case
                      (let ((client (usocket:socket-accept *server*
                                                           :element-type '(unsigned-byte 8))))
                        (bt:make-thread
                         (lambda () (handle-client client))
                         :name "registry-client"))
                    (usocket:connection-aborted-error ()
                      ;; Server shutting down
                      nil)
                    (error (e)
                      (when *running*
                        (format t "[Registry] Accept error: ~A~%" e)))))
      (stop-server))

    *server*))

(defun stop-server ()
  "Stop the registry service."
  (setf *running* nil)
  (when *server*
    (handler-case
        (usocket:socket-close *server*)
      (error () nil))
    (setf *server* nil))
  (when (and *cleanup-thread* (bt:thread-alive-p *cleanup-thread*))
    (bt:destroy-thread *cleanup-thread*)
    (setf *cleanup-thread* nil))
  (format t "[Registry] Server stopped~%"))

;;; ==========================================================================
;;; Signal Handling
;;; ==========================================================================

#+sbcl
(defun install-signal-handlers ()
  "Install signal handlers for graceful shutdown."
  (sb-sys:enable-interrupt
   sb-unix:sigint
   (lambda (sig code scp)
     (declare (ignore sig code scp))
     (format t "~%[Registry] Received SIGINT, shutting down...~%")
     (stop-server)))
  (sb-sys:enable-interrupt
   sb-unix:sigterm
   (lambda (sig code scp)
     (declare (ignore sig code scp))
     (format t "[Registry] Received SIGTERM, shutting down...~%")
     (stop-server))))

;;; ==========================================================================
;;; Entry Point
;;; ==========================================================================

(defun main ()
  "Entry point for standalone execution."
  #+sbcl (install-signal-handlers)
  (start-server))

;;; Auto-start when loaded as script
#+sbcl
(when (member "--eval" sb-ext:*posix-argv* :test #'string-equal)
  ;; Running from command line
  nil)

;;;; End of registry-service.lisp
