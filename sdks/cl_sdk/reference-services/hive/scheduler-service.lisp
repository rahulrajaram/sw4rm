;;;; scheduler-service.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Scheduler Service
;;;;
;;;; Purpose: LLM-driven task orchestration and multi-agent coordination.
;;;; This is the equivalent of the Python scheduler_service.py.
;;;;
;;;; Protocol: JSON-over-TCP with 4-byte big-endian length prefix
;;;; Default Port: 50053
;;;;
;;;; Features:
;;;;   - LLM-driven plan generation (via Claude CLI)
;;;;   - Session-based task tracking
;;;;   - Multi-agent command dispatch
;;;;   - Progress monitoring and aggregation
;;;;   - DAG-based workflow orchestration
;;;;   - Health status reporting
;;;;
;;;; Usage:
;;;;   sbcl --load scheduler-service.lisp --eval '(scheduler-service:start-server)'
;;;;
;;;; Environment:
;;;;   SCHEDULER_PORT - Server port (default: 50053)
;;;;   REGISTRY_HOST - Registry service host (default: localhost)
;;;;   REGISTRY_PORT - Registry service port (default: 50052)
;;;;   ROUTER_HOST - Router service host (default: localhost)
;;;;   ROUTER_PORT - Router service port (default: 50051)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :scheduler-service
  (:use :cl)
  (:export #:start-server
           #:stop-server
           #:*server*
           #:create-session
           #:get-session
           #:list-sessions
           #:submit-task
           #:cancel-session
           #:clear-all))

(in-package :scheduler-service)

;;; ==========================================================================
;;; Dependencies
;;; ==========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:usocket :bordeaux-threads :cl-json :alexandria
                  :uiop :local-time)
                :silent t))

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *default-port* 50053
  "Default scheduler service port.")

(defparameter *registry-host* "localhost"
  "Registry service host.")

(defparameter *registry-port* 50052
  "Registry service port.")

(defparameter *router-host* "localhost"
  "Router service host.")

(defparameter *router-port* 50051
  "Router service port.")

(defparameter *agent-id* "scheduler"
  "This service's agent ID.")

(defparameter *seed-content-type*
  "application/vnd.sw4rm.scheduler.seed+json;v=1"
  "Content type for seed/plan trigger messages.")

(defparameter *command-content-type*
  "application/vnd.sw4rm.scheduler.command+json;v=1"
  "Content type for command messages.")

(defparameter *report-content-type*
  "application/vnd.sw4rm.agent.report+json;v=1"
  "Content type for agent report messages.")

;;; ==========================================================================
;;; Session State
;;; ==========================================================================

(deftype session-status ()
  '(member :pending :planning :running :completed :failed :cancelled))

(defclass session ()
  ((session-id :initarg :session-id :accessor session-id :type string)
   (status :initarg :status :accessor session-status :initform :pending)
   (prompt :initarg :prompt :accessor session-prompt :initform nil)
   (plan :initarg :plan :accessor session-plan :initform nil)
   (agents :initarg :agents :accessor session-agents :initform nil)
   (agent-status :initform (make-hash-table :test 'equal)
                 :accessor session-agent-status)
   (artifacts :initform nil :accessor session-artifacts)
   (created-at :initarg :created-at :accessor session-created-at)
   (updated-at :initarg :updated-at :accessor session-updated-at)
   (error-message :initform nil :accessor session-error-message))
  (:documentation "A scheduler session tracking a multi-agent task."))

(defun make-session (session-id &key prompt)
  "Create a new session."
  (let ((now (get-universal-time)))
    (make-instance 'session
                   :session-id session-id
                   :prompt prompt
                   :created-at now
                   :updated-at now)))

(defmethod session-to-plist ((s session))
  "Convert session to plist for JSON serialization."
  (list :session-id (session-id s)
        :status (string-downcase (symbol-name (session-status s)))
        :prompt (session-prompt s)
        :plan (session-plan s)
        :agents (session-agents s)
        :agent-status (let ((statuses nil))
                        (maphash (lambda (k v)
                                   (push (cons k v) statuses))
                                 (session-agent-status s))
                        statuses)
        :artifacts (session-artifacts s)
        :created-at (session-created-at s)
        :updated-at (session-updated-at s)
        :error-message (session-error-message s)))

;;; ==========================================================================
;;; State Management
;;; ==========================================================================

(defparameter *sessions* (make-hash-table :test 'equal)
  "Hash table of session-id -> session.")

(defparameter *lock* (bt:make-lock "scheduler-lock")
  "Lock for thread-safe state access.")

(defparameter *server* nil
  "The running server socket.")

(defparameter *running* nil
  "Flag to control server loop.")

(defparameter *stream-thread* nil
  "Background thread for router stream.")

(defparameter *registry-client* nil
  "Connection to registry service.")

(defparameter *router-client* nil
  "Connection to router service.")

;;; ==========================================================================
;;; Service Client Helpers
;;; ==========================================================================

(defun make-client-socket (host port)
  "Create a TCP client connection."
  (handler-case
      (usocket:socket-connect host port
                               :element-type '(unsigned-byte 8))
    (error (e)
      (format t "[Scheduler] Failed to connect to ~A:~D: ~A~%"
              host port e)
      nil)))

(defun client-request (socket request)
  "Send a request and receive response."
  (when socket
    (let ((stream (usocket:socket-stream socket)))
      (handler-case
          (progn
            ;; Write request
            (let* ((json-string (cl-json:encode-json-to-string request))
                   (payload (babel:string-to-octets json-string :encoding :utf-8))
                   (length (length payload))
                   (length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
              (setf (aref length-bytes 0) (ldb (byte 8 24) length))
              (setf (aref length-bytes 1) (ldb (byte 8 16) length))
              (setf (aref length-bytes 2) (ldb (byte 8 8) length))
              (setf (aref length-bytes 3) (ldb (byte 8 0) length))
              (write-sequence length-bytes stream)
              (write-sequence payload stream)
              (force-output stream))
            ;; Read response
            (let ((length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
              (when (= 4 (read-sequence length-bytes stream))
                (let ((length (+ (ash (aref length-bytes 0) 24)
                                 (ash (aref length-bytes 1) 16)
                                 (ash (aref length-bytes 2) 8)
                                 (aref length-bytes 3))))
                  (when (and (> length 0) (< length (* 16 1024 1024)))
                    (let ((payload (make-array length :element-type '(unsigned-byte 8))))
                      (when (= length (read-sequence payload stream))
                        (let ((json-string (babel:octets-to-string payload :encoding :utf-8)))
                          (cl-json:decode-json-from-string json-string)))))))))
        (error (e)
          (format t "[Scheduler] Client request error: ~A~%" e)
          nil)))))

;;; ==========================================================================
;;; Registry Integration
;;; ==========================================================================

(defun register-with-registry ()
  "Register the scheduler with the registry service."
  (setf *registry-client*
        (make-client-socket *registry-host* *registry-port*))
  (when *registry-client*
    (let ((response (client-request *registry-client*
                      (list (cons :method "register")
                            (cons :params
                                  (list (cons :agent-id *agent-id*)
                                        (cons :metadata
                                              (list (cons :type "scheduler")
                                                    (cons :version "1.0")))))))))
      (when (cdr (assoc :success response))
        (format t "[Scheduler] Registered with registry~%")
        t))))

(defun send-heartbeat ()
  "Send heartbeat to registry."
  (when *registry-client*
    (client-request *registry-client*
      (list (cons :method "heartbeat")
            (cons :params
                  (list (cons :agent-id *agent-id*)
                        (cons :status "active")))))))

;;; ==========================================================================
;;; Router Integration
;;; ==========================================================================

(defun send-to-agent (target-agent payload &key correlation-id message-type)
  "Send a message to another agent via router."
  (let ((router (make-client-socket *router-host* *router-port*)))
    (when router
      (unwind-protect
           (let ((response (client-request router
                             (list (cons :method "send")
                                   (cons :params
                                         (list (cons :producer-id *agent-id*)
                                               (cons :consumer-id target-agent)
                                               (cons :message-type
                                                     (string-downcase
                                                      (symbol-name (or message-type :control))))
                                               (cons :content-type *command-content-type*)
                                               (cons :payload payload)
                                               (cons :correlation-id correlation-id)))))))
             (cdr (assoc :success response)))
        (usocket:socket-close router)))))

(defun dispatch-command (session agent-id command)
  "Dispatch a command to an agent."
  (let ((payload (list (cons :stage (cdr (assoc :stage command)))
                       (cons :task (cdr (assoc :task command)))
                       (cons :params (cdr (assoc :params command))))))
    (when (send-to-agent agent-id payload
                         :correlation-id (session-id session)
                         :message-type :control)
      (format t "[Scheduler] Dispatched ~A to ~A~%"
              (cdr (assoc :stage command)) agent-id)
      ;; Update agent status
      (bt:with-lock-held (*lock*)
        (setf (gethash agent-id (session-agent-status session)) :pending)
        (setf (session-updated-at session) (get-universal-time)))
      t)))

;;; ==========================================================================
;;; LLM Integration
;;; ==========================================================================

(defun call-llm (prompt)
  "Call Claude CLI to generate a plan.
Returns parsed JSON plan or NIL on error."
  (handler-case
      (let* ((command (format nil "claude -p ~S --output-format json 2>/dev/null"
                              prompt))
             (output (uiop:run-program command
                                       :output :string
                                       :ignore-error-status t)))
        (when (and output (> (length output) 0))
          ;; Try to extract JSON from output
          (let ((json-start (position #\{ output))
                (json-end (position #\} output :from-end t)))
            (when (and json-start json-end (< json-start json-end))
              (cl-json:decode-json-from-string
               (subseq output json-start (1+ json-end)))))))
    (error (e)
      (format t "[Scheduler] LLM error: ~A~%" e)
      nil)))

(defun generate-plan (prompt)
  "Generate a multi-agent plan from a prompt.
Returns a plan structure: ((agent-id . task-spec) ...)"
  (let* ((plan-prompt (format nil
                        "You are a task orchestrator. Given the following task, create a plan
that assigns work to these available agent types:
- frontend: UI and user interaction
- backend: API and business logic
- analytics: Data processing and analysis
- ml: Machine learning and AI tasks

Task: ~A

Respond with a JSON object where keys are agent IDs and values have:
- task: description of what the agent should do
- expected_artifacts: list of artifacts to produce
- dependencies: list of agent IDs this depends on (empty if none)

Example:
{
  \"backend\": {
    \"task\": \"implement API endpoint\",
    \"expected_artifacts\": [\"api.py\"],
    \"dependencies\": []
  },
  \"frontend\": {
    \"task\": \"create UI component\",
    \"expected_artifacts\": [\"component.tsx\"],
    \"dependencies\": [\"backend\"]
  }
}

Plan:" prompt))
         (result (call-llm plan-prompt)))
    (when result
      ;; Normalize the plan structure
      (let ((normalized nil))
        (loop for (agent-key . task-spec) in result
              for agent-id = (string-downcase (symbol-name agent-key))
              do (push (cons agent-id
                            (list (cons :task (cdr (assoc :task task-spec)))
                                  (cons :expected-artifacts
                                        (cdr (assoc :expected-artifacts task-spec)))
                                  (cons :dependencies
                                        (cdr (assoc :dependencies task-spec)))))
                       normalized))
        (nreverse normalized)))))

;;; ==========================================================================
;;; Session Management
;;; ==========================================================================

(defun create-session (session-id &key prompt)
  "Create a new scheduler session."
  (bt:with-lock-held (*lock*)
    (let ((session (make-session session-id :prompt prompt)))
      (setf (gethash session-id *sessions*) session)
      (format t "[Scheduler] Created session: ~A~%" session-id)
      session)))

(defun get-session (session-id)
  "Get a session by ID."
  (bt:with-lock-held (*lock*)
    (gethash session-id *sessions*)))

(defun list-sessions (&key status)
  "List all sessions, optionally filtered by status."
  (bt:with-lock-held (*lock*)
    (let ((results nil))
      (maphash (lambda (id session)
                 (declare (ignore id))
                 (when (or (null status)
                           (eq (session-status session) status))
                   (push (session-to-plist session) results)))
               *sessions*)
      (nreverse results))))

(defun cancel-session (session-id)
  "Cancel a session."
  (bt:with-lock-held (*lock*)
    (let ((session (gethash session-id *sessions*)))
      (when session
        (setf (session-status session) :cancelled)
        (setf (session-updated-at session) (get-universal-time))
        t))))

(defun clear-all ()
  "Clear all sessions (for testing)."
  (bt:with-lock-held (*lock*)
    (clrhash *sessions*)))

;;; ==========================================================================
;;; Task Orchestration
;;; ==========================================================================

(defun submit-task (session-id prompt)
  "Submit a task for orchestration.
Creates a session, generates a plan, and dispatches to agents."
  (let ((session (or (get-session session-id)
                     (create-session session-id :prompt prompt))))
    ;; Update prompt if provided
    (when prompt
      (bt:with-lock-held (*lock*)
        (setf (session-prompt session) prompt)))

    ;; Generate plan
    (bt:with-lock-held (*lock*)
      (setf (session-status session) :planning))

    (format t "[Scheduler] Generating plan for: ~A~%" prompt)
    (let ((plan (generate-plan prompt)))
      (if plan
          (progn
            (bt:with-lock-held (*lock*)
              (setf (session-plan session) plan)
              (setf (session-agents session)
                    (mapcar #'car plan))
              (setf (session-status session) :running)
              (setf (session-updated-at session) (get-universal-time)))

            ;; Dispatch to agents with no dependencies first
            (loop for (agent-id . task-spec) in plan
                  for deps = (cdr (assoc :dependencies task-spec))
                  when (null deps)
                    do (dispatch-command session agent-id
                         (list (cons :stage "generate")
                               (cons :task (cdr (assoc :task task-spec)))
                               (cons :params task-spec))))

            (format t "[Scheduler] Plan dispatched: ~D agents~%"
                    (length plan))
            session)

          ;; Planning failed
          (progn
            (bt:with-lock-held (*lock*)
              (setf (session-status session) :failed)
              (setf (session-error-message session)
                    "Failed to generate plan from LLM")
              (setf (session-updated-at session) (get-universal-time)))
            session)))))

(defun handle-agent-report (session-id agent-id status &key artifacts)
  "Handle a status report from an agent."
  (let ((session (get-session session-id)))
    (when session
      (bt:with-lock-held (*lock*)
        ;; Update agent status
        (setf (gethash agent-id (session-agent-status session)) status)
        (setf (session-updated-at session) (get-universal-time))

        ;; Collect artifacts
        (when artifacts
          (setf (session-artifacts session)
                (append (session-artifacts session) artifacts)))

        ;; Check if all agents completed
        (let ((all-done t)
              (any-failed nil))
          (maphash (lambda (aid astatus)
                     (declare (ignore aid))
                     (when (eq astatus :failed)
                       (setf any-failed t))
                     (when (not (member astatus '(:completed :failed)))
                       (setf all-done nil)))
                   (session-agent-status session))

          (when all-done
            (setf (session-status session)
                  (if any-failed :failed :completed))
            (format t "[Scheduler] Session ~A ~A~%"
                    session-id (session-status session))))

        ;; Dispatch dependent tasks
        (when (eq status :completed)
          (loop for (aid . task-spec) in (session-plan session)
                for deps = (cdr (assoc :dependencies task-spec))
                for agent-status = (gethash aid (session-agent-status session))
                when (and (member agent-id deps :test #'equal)
                          (null agent-status)
                          ;; Check all deps completed
                          (every (lambda (dep)
                                   (eq (gethash dep (session-agent-status session))
                                       :completed))
                                 deps))
                  do (dispatch-command session aid
                       (list (cons :stage "generate")
                             (cons :task (cdr (assoc :task task-spec)))
                             (cons :params task-spec)))))))))

;;; ==========================================================================
;;; JSON-over-TCP Protocol
;;; ==========================================================================

(defun read-message (stream)
  "Read a length-prefixed JSON message."
  (handler-case
      (let ((length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
        (when (= 4 (read-sequence length-bytes stream))
          (let ((length (+ (ash (aref length-bytes 0) 24)
                           (ash (aref length-bytes 1) 16)
                           (ash (aref length-bytes 2) 8)
                           (aref length-bytes 3))))
            (when (and (> length 0) (< length (* 16 1024 1024)))
              (let ((payload (make-array length :element-type '(unsigned-byte 8))))
                (when (= length (read-sequence payload stream))
                  (let ((json-string (babel:octets-to-string payload :encoding :utf-8)))
                    (cl-json:decode-json-from-string json-string))))))))
    (end-of-file () nil)
    (error () nil)))

(defun write-message (stream response)
  "Write a length-prefixed JSON message."
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
  "Process a request and return a response."
  (let ((method (cdr (assoc :method request)))
        (params (cdr (assoc :params request))))
    (handler-case
        (cond
          ;; SubmitTask
          ((string-equal method "submit")
           (let* ((session-id (or (cdr (assoc :session-id params))
                                  (format nil "session-~A" (get-universal-time))))
                  (prompt (cdr (assoc :prompt params)))
                  (session (submit-task session-id prompt)))
             (list (cons :success t)
                   (cons :result (session-to-plist session)))))

          ;; GetSession
          ((string-equal method "get")
           (let* ((session-id (cdr (assoc :session-id params)))
                  (session (get-session session-id)))
             (if session
                 (list (cons :success t)
                       (cons :result (session-to-plist session)))
                 (list (cons :success nil)
                       (cons :error "session not found")))))

          ;; ListSessions
          ((string-equal method "list")
           (let* ((status-str (cdr (assoc :status params)))
                  (status (when status-str
                            (intern (string-upcase status-str) :keyword)))
                  (sessions (list-sessions :status status)))
             (list (cons :success t)
                   (cons :result sessions))))

          ;; CancelSession
          ((string-equal method "cancel")
           (let* ((session-id (cdr (assoc :session-id params)))
                  (cancelled (cancel-session session-id)))
             (list (cons :success cancelled)
                   (cons :result (if cancelled "cancelled" "not found")))))

          ;; AgentReport (internal)
          ((string-equal method "report")
           (let* ((session-id (cdr (assoc :session-id params)))
                  (agent-id (cdr (assoc :agent-id params)))
                  (status-str (cdr (assoc :status params)))
                  (status (when status-str
                            (intern (string-upcase status-str) :keyword)))
                  (artifacts (cdr (assoc :artifacts params))))
             (handle-agent-report session-id agent-id status :artifacts artifacts)
             (list (cons :success t)
                   (cons :result "report processed"))))

          ;; Health check
          ((string-equal method "health")
           (list (cons :success t)
                 (cons :result "healthy")
                 (cons :session-count (hash-table-count *sessions*))))

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
;;; Router Stream Handler
;;; ==========================================================================

(defun start-router-stream ()
  "Start listening to router for incoming messages."
  (setf *stream-thread*
        (bt:make-thread
         (lambda ()
           (loop while *running*
                 do (handler-case
                        (let ((router (make-client-socket *router-host* *router-port*)))
                          (when router
                            (unwind-protect
                                 (let ((stream (usocket:socket-stream router)))
                                   ;; Start stream request
                                   (let* ((json-string (cl-json:encode-json-to-string
                                                        (list (cons :method "stream")
                                                              (cons :params
                                                                    (list (cons :agent-id *agent-id*))))))
                                          (payload (babel:string-to-octets json-string :encoding :utf-8))
                                          (length (length payload))
                                          (length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
                                     (setf (aref length-bytes 0) (ldb (byte 8 24) length))
                                     (setf (aref length-bytes 1) (ldb (byte 8 16) length))
                                     (setf (aref length-bytes 2) (ldb (byte 8 8) length))
                                     (setf (aref length-bytes 3) (ldb (byte 8 0) length))
                                     (write-sequence length-bytes stream)
                                     (write-sequence payload stream)
                                     (force-output stream))

                                   ;; Read incoming messages
                                   (loop while *running*
                                         for msg = (read-message stream)
                                         while msg
                                         do (handle-incoming-message
                                             (cdr (assoc :result msg)))))
                              (usocket:socket-close router))))
                      (error (e)
                        (format t "[Scheduler] Stream error: ~A~%" e)
                        (sleep 5)))))
         :name "scheduler-stream")))

(defun handle-incoming-message (message)
  "Handle a message received from the router."
  (when message
    (let ((content-type (cdr (assoc :content-type message)))
          (payload (cdr (assoc :payload message)))
          (correlation-id (cdr (assoc :correlation-id message)))
          (producer-id (cdr (assoc :producer-id message))))

      (cond
        ;; Seed message - trigger new task
        ((string-equal content-type *seed-content-type*)
         (let ((prompt (cdr (assoc :prompt payload))))
           (when prompt
             (submit-task (or correlation-id
                              (format nil "session-~A" (get-universal-time)))
                          prompt))))

        ;; Agent report
        ((string-equal content-type *report-content-type*)
         (let ((status-str (cdr (assoc :status payload)))
               (artifacts (cdr (assoc :artifacts payload))))
           (when (and correlation-id producer-id status-str)
             (handle-agent-report correlation-id producer-id
               (intern (string-upcase status-str) :keyword)
               :artifacts artifacts))))))))

;;; ==========================================================================
;;; Server Lifecycle
;;; ==========================================================================

(defun get-env-config ()
  "Get configuration from environment."
  (let ((reg-host (uiop:getenv "REGISTRY_HOST"))
        (reg-port (uiop:getenv "REGISTRY_PORT"))
        (router-host (uiop:getenv "ROUTER_HOST"))
        (router-port (uiop:getenv "ROUTER_PORT")))
    (when reg-host (setf *registry-host* reg-host))
    (when reg-port (setf *registry-port* (parse-integer reg-port :junk-allowed t)))
    (when router-host (setf *router-host* router-host))
    (when router-port (setf *router-port* (parse-integer router-port :junk-allowed t)))))

(defun get-port ()
  "Get port from environment or use default."
  (let ((env-port (uiop:getenv "SCHEDULER_PORT")))
    (if env-port
        (parse-integer env-port :junk-allowed t)
        *default-port*)))

(defun start-server (&key (port nil))
  "Start the scheduler service."
  (get-env-config)
  (let ((actual-port (or port (get-port))))
    (format t "[Scheduler] Starting on port ~D~%" actual-port)

    ;; Register with registry
    (register-with-registry)

    ;; Start router stream listener
    (start-router-stream)

    ;; Create server socket
    (setf *server* (usocket:socket-listen "0.0.0.0" actual-port
                                           :reuse-address t
                                           :element-type '(unsigned-byte 8)))
    (setf *running* t)

    (format t "[Scheduler] Ready to accept connections~%")
    (unwind-protect
         (loop while *running*
               do (handler-case
                      (let ((client (usocket:socket-accept *server*
                                                           :element-type '(unsigned-byte 8))))
                        (bt:make-thread
                         (lambda () (handle-client client))
                         :name "scheduler-client"))
                    (usocket:connection-aborted-error () nil)
                    (error (e)
                      (when *running*
                        (format t "[Scheduler] Accept error: ~A~%" e)))))
      (stop-server))

    *server*))

(defun stop-server ()
  "Stop the scheduler service."
  (setf *running* nil)
  (when *server*
    (handler-case (usocket:socket-close *server*) (error () nil))
    (setf *server* nil))
  (when *registry-client*
    (handler-case (usocket:socket-close *registry-client*) (error () nil))
    (setf *registry-client* nil))
  (when (and *stream-thread* (bt:thread-alive-p *stream-thread*))
    (bt:destroy-thread *stream-thread*)
    (setf *stream-thread* nil))
  (format t "[Scheduler] Server stopped~%"))

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
     (format t "~%[Scheduler] Received SIGINT, shutting down...~%")
     (stop-server)))
  (sb-sys:enable-interrupt
   sb-unix:sigterm
   (lambda (sig code scp)
     (declare (ignore sig code scp))
     (format t "[Scheduler] Received SIGTERM, shutting down...~%")
     (stop-server))))

;;; ==========================================================================
;;; Entry Point
;;; ==========================================================================

(defun main ()
  "Entry point for standalone execution."
  #+sbcl (install-signal-handlers)
  (start-server))

;;;; End of scheduler-service.lisp
