;;;; router-service.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Router Service
;;;;
;;;; Purpose: Message routing service with queue-based delivery and streaming.
;;;; This is the equivalent of the Python router_service.py.
;;;;
;;;; Protocol: JSON-over-TCP with 4-byte big-endian length prefix
;;;; Default Port: 50051
;;;;
;;;; Features:
;;;;   - Message routing between agents
;;;;   - Per-agent message queues (max 100 messages)
;;;;   - Streaming message delivery
;;;;   - Message type filtering (CONTROL, DATA, NOTIFICATION)
;;;;   - Correlation ID tracking
;;;;   - Thread-safe queue operations
;;;;
;;;; Usage:
;;;;   sbcl --load router-service.lisp --eval '(router-service:start-server)'
;;;;
;;;; Environment:
;;;;   ROUTER_PORT - Server port (default: 50051)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :router-service
  (:use :cl)
  (:export #:start-server
           #:stop-server
           #:*server*
           #:send-message
           #:receive-message
           #:get-queue-depth
           #:list-queues
           #:clear-all))

(in-package :router-service)

;;; ==========================================================================
;;; Dependencies
;;; ==========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:usocket :bordeaux-threads :cl-json :alexandria :local-time)
                :silent t))

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *default-port* 50051
  "Default router service port.")

(defparameter *max-queue-size* 100
  "Maximum messages per agent queue.")

(defparameter *receive-timeout* 30
  "Default timeout for receive operations (seconds).")

;;; ==========================================================================
;;; Message Types
;;; ==========================================================================

(deftype message-type ()
  '(member :control :data :notification))

;;; ==========================================================================
;;; Message Record
;;; ==========================================================================

(defclass message-record ()
  ((message-id :initarg :message-id :accessor message-id :type string)
   (producer-id :initarg :producer-id :accessor producer-id :type string)
   (consumer-id :initarg :consumer-id :accessor consumer-id :type string)
   (message-type :initarg :message-type :accessor message-type)
   (content-type :initarg :content-type :accessor content-type :initform nil)
   (payload :initarg :payload :accessor message-payload)
   (correlation-id :initarg :correlation-id :accessor correlation-id :initform nil)
   (timestamp :initarg :timestamp :accessor message-timestamp))
  (:documentation "A message to be routed between agents."))

(defun make-message (producer-id consumer-id &key
                                               message-type
                                               content-type
                                               payload
                                               correlation-id)
  "Create a new message record."
  (make-instance 'message-record
                 :message-id (format nil "msg-~A-~A"
                                     (get-universal-time)
                                     (random 1000000))
                 :producer-id producer-id
                 :consumer-id consumer-id
                 :message-type (or message-type :data)
                 :content-type content-type
                 :payload payload
                 :correlation-id correlation-id
                 :timestamp (get-universal-time)))

(defmethod message-to-plist ((msg message-record))
  "Convert message to plist for JSON serialization."
  (list :message-id (message-id msg)
        :producer-id (producer-id msg)
        :consumer-id (consumer-id msg)
        :message-type (string-downcase (symbol-name (message-type msg)))
        :content-type (content-type msg)
        :payload (message-payload msg)
        :correlation-id (correlation-id msg)
        :timestamp (message-timestamp msg)))

;;; ==========================================================================
;;; Queue Management
;;; ==========================================================================

(defclass agent-queue ()
  ((agent-id :initarg :agent-id :accessor queue-agent-id)
   (messages :initform (make-array 0 :adjustable t :fill-pointer 0)
             :accessor queue-messages)
   (lock :initform (bt:make-lock "queue-lock") :accessor queue-lock)
   (condition :initform (bt:make-condition-variable) :accessor queue-condition)
   (active-streams :initform 0 :accessor queue-active-streams))
  (:documentation "Per-agent message queue."))

(defun make-agent-queue (agent-id)
  "Create a new agent queue."
  (make-instance 'agent-queue :agent-id agent-id))

;;; ==========================================================================
;;; State Management
;;; ==========================================================================

(defparameter *queues* (make-hash-table :test 'equal)
  "Hash table of agent-id -> agent-queue.")

(defparameter *global-lock* (bt:make-lock "router-lock")
  "Lock for queue creation/deletion.")

(defparameter *server* nil
  "The running server socket.")

(defparameter *running* nil
  "Flag to control server loop.")

;;; ==========================================================================
;;; Queue Operations
;;; ==========================================================================

(defun get-or-create-queue (agent-id)
  "Get an agent's queue, creating it if necessary."
  (bt:with-lock-held (*global-lock*)
    (or (gethash agent-id *queues*)
        (setf (gethash agent-id *queues*)
              (make-agent-queue agent-id)))))

(defun enqueue-message (queue message)
  "Add a message to an agent's queue.
Returns T if queued, NIL if queue is full."
  (bt:with-lock-held ((queue-lock queue))
    (cond
      ((>= (length (queue-messages queue)) *max-queue-size*)
       (format t "[Router] Queue full for ~A, dropping message~%"
               (queue-agent-id queue))
       nil)
      (t
       (vector-push-extend message (queue-messages queue))
       (bt:condition-notify (queue-condition queue))
       t))))

(defun dequeue-message (queue &key timeout message-type)
  "Remove and return the next message from queue.
Optionally filter by message-type.
Returns NIL if timeout expires with no message."
  (let ((deadline (when timeout (+ (get-internal-real-time)
                                   (* timeout internal-time-units-per-second)))))
    (bt:with-lock-held ((queue-lock queue))
      (loop
        ;; Check for matching message
        (let ((messages (queue-messages queue)))
          (dotimes (i (length messages))
            (let ((msg (aref messages i)))
              (when (or (null message-type)
                        (eq (message-type msg) message-type))
                ;; Remove and return this message
                (let ((result msg))
                  ;; Shift remaining messages
                  (loop for j from i below (1- (length messages))
                        do (setf (aref messages j) (aref messages (1+ j))))
                  (decf (fill-pointer messages))
                  (return-from dequeue-message result))))))
        ;; No message found, wait or timeout
        (if (and deadline (>= (get-internal-real-time) deadline))
            (return-from dequeue-message nil)
            (let ((remaining (when deadline
                               (/ (- deadline (get-internal-real-time))
                                  internal-time-units-per-second))))
              (bt:condition-wait (queue-condition queue)
                                 (queue-lock queue)
                                 :timeout (or remaining 1.0))))))))

;;; ==========================================================================
;;; Core Operations
;;; ==========================================================================

(defun send-message (producer-id consumer-id &key
                                               message-type
                                               content-type
                                               payload
                                               correlation-id)
  "Send a message from producer to consumer.
Returns the message record on success."
  (let ((message (make-message producer-id consumer-id
                               :message-type message-type
                               :content-type content-type
                               :payload payload
                               :correlation-id correlation-id))
        (queue (get-or-create-queue consumer-id)))
    (when (enqueue-message queue message)
      (format t "[Router] ~A -> ~A: ~A (type: ~A)~%"
              producer-id consumer-id
              (message-id message)
              (message-type message))
      message)))

(defun receive-message (agent-id &key timeout message-type)
  "Receive a message for an agent.
Returns the message or NIL on timeout."
  (let ((queue (get-or-create-queue agent-id)))
    (dequeue-message queue :timeout timeout :message-type message-type)))

(defun get-queue-depth (agent-id)
  "Get the number of pending messages for an agent."
  (let ((queue (gethash agent-id *queues*)))
    (if queue
        (bt:with-lock-held ((queue-lock queue))
          (length (queue-messages queue)))
        0)))

(defun list-queues ()
  "List all agent queues with their depths."
  (bt:with-lock-held (*global-lock*)
    (let ((results nil))
      (maphash (lambda (agent-id queue)
                 (push (list :agent-id agent-id
                             :depth (bt:with-lock-held ((queue-lock queue))
                                      (length (queue-messages queue)))
                             :active-streams (queue-active-streams queue))
                       results))
               *queues*)
      (nreverse results))))

(defun clear-all ()
  "Clear all queues (for testing)."
  (bt:with-lock-held (*global-lock*)
    (clrhash *queues*)))

;;; ==========================================================================
;;; JSON-over-TCP Protocol
;;; ==========================================================================

(defun read-message-frame (stream)
  "Read a length-prefixed JSON message from stream."
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

(defun write-message-frame (stream response)
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

(defun handle-request (request stream)
  "Process a request and return a response.
For streaming requests, sends multiple responses."
  (let ((method (cdr (assoc :method request)))
        (params (cdr (assoc :params request))))
    (handler-case
        (cond
          ;; SendMessage
          ((string-equal method "send")
           (let* ((producer-id (cdr (assoc :producer-id params)))
                  (consumer-id (cdr (assoc :consumer-id params)))
                  (msg-type-str (cdr (assoc :message-type params)))
                  (msg-type (when msg-type-str
                              (intern (string-upcase msg-type-str) :keyword)))
                  (content-type (cdr (assoc :content-type params)))
                  (payload (cdr (assoc :payload params)))
                  (correlation-id (cdr (assoc :correlation-id params)))
                  (message (send-message producer-id consumer-id
                                         :message-type (or msg-type :data)
                                         :content-type content-type
                                         :payload payload
                                         :correlation-id correlation-id)))
             (if message
                 (list (cons :success t)
                       (cons :result (message-to-plist message)))
                 (list (cons :success nil)
                       (cons :error "queue full")))))

          ;; ReceiveMessage (single)
          ((string-equal method "receive")
           (let* ((agent-id (cdr (assoc :agent-id params)))
                  (timeout (or (cdr (assoc :timeout params)) *receive-timeout*))
                  (msg-type-str (cdr (assoc :message-type params)))
                  (msg-type (when msg-type-str
                              (intern (string-upcase msg-type-str) :keyword)))
                  (message (receive-message agent-id
                                            :timeout timeout
                                            :message-type msg-type)))
             (if message
                 (list (cons :success t)
                       (cons :result (message-to-plist message)))
                 (list (cons :success nil)
                       (cons :error "timeout")))))

          ;; StreamIncoming (continuous streaming)
          ((string-equal method "stream")
           (let* ((agent-id (cdr (assoc :agent-id params)))
                  (msg-type-str (cdr (assoc :message-type params)))
                  (msg-type (when msg-type-str
                              (intern (string-upcase msg-type-str) :keyword)))
                  (queue (get-or-create-queue agent-id)))
             ;; Track active stream
             (bt:with-lock-held ((queue-lock queue))
               (incf (queue-active-streams queue)))
             ;; Stream messages until disconnect
             (unwind-protect
                  (loop while *running*
                        for message = (receive-message agent-id
                                                       :timeout 1.0
                                                       :message-type msg-type)
                        when message
                          do (write-message-frame stream
                               (list (cons :success t)
                                     (cons :result (message-to-plist message)))))
               (bt:with-lock-held ((queue-lock queue))
                 (decf (queue-active-streams queue))))
             ;; Stream ended
             (list (cons :success t)
                   (cons :result "stream closed"))))

          ;; GetQueueDepth
          ((string-equal method "depth")
           (let* ((agent-id (cdr (assoc :agent-id params)))
                  (depth (get-queue-depth agent-id)))
             (list (cons :success t)
                   (cons :result depth))))

          ;; ListQueues
          ((string-equal method "list")
           (list (cons :success t)
                 (cons :result (list-queues))))

          ;; Health check
          ((string-equal method "health")
           (list (cons :success t)
                 (cons :result "healthy")
                 (cons :queue-count (hash-table-count *queues*))))

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
         (loop for request = (read-message-frame stream)
               while request
               do (let ((response (handle-request request stream)))
                    ;; Only send response for non-streaming requests
                    (unless (string-equal (cdr (assoc :method request)) "stream")
                      (write-message-frame stream response))))
      (usocket:socket-close client-socket))))

;;; ==========================================================================
;;; Server Lifecycle
;;; ==========================================================================

(defun get-port ()
  "Get port from environment or use default."
  (let ((env-port (uiop:getenv "ROUTER_PORT")))
    (if env-port
        (parse-integer env-port :junk-allowed t)
        *default-port*)))

(defun start-server (&key (port nil))
  "Start the router service."
  (let ((actual-port (or port (get-port))))
    (format t "[Router] Starting on port ~D~%" actual-port)

    (setf *server* (usocket:socket-listen "0.0.0.0" actual-port
                                           :reuse-address t
                                           :element-type '(unsigned-byte 8)))
    (setf *running* t)

    (format t "[Router] Ready to accept connections~%")
    (unwind-protect
         (loop while *running*
               do (handler-case
                      (let ((client (usocket:socket-accept *server*
                                                           :element-type '(unsigned-byte 8))))
                        (bt:make-thread
                         (lambda () (handle-client client))
                         :name "router-client"))
                    (usocket:connection-aborted-error () nil)
                    (error (e)
                      (when *running*
                        (format t "[Router] Accept error: ~A~%" e)))))
      (stop-server))

    *server*))

(defun stop-server ()
  "Stop the router service."
  (setf *running* nil)
  (when *server*
    (handler-case
        (usocket:socket-close *server*)
      (error () nil))
    (setf *server* nil))
  (format t "[Router] Server stopped~%"))

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
     (format t "~%[Router] Received SIGINT, shutting down...~%")
     (stop-server)))
  (sb-sys:enable-interrupt
   sb-unix:sigterm
   (lambda (sig code scp)
     (declare (ignore sig code scp))
     (format t "[Router] Received SIGTERM, shutting down...~%")
     (stop-server))))

;;; ==========================================================================
;;; Entry Point
;;; ==========================================================================

(defun main ()
  "Entry point for standalone execution."
  #+sbcl (install-signal-handlers)
  (start-server))

;;;; End of router-service.lisp
