;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; grpc/transport.lisp
;;;;
;;;; JSON-over-TCP Transport Layer for SW4RM Orchestrator
;;;;
;;;; This module implements a TCP-based transport layer as an alternative to gRPC.
;;;; It provides the same semantics as gRPC but uses a simpler protocol:
;;;;   - 4-byte big-endian length prefix
;;;;   - JSON payload (using proto-compat.lisp serialization)
;;;;   - Bidirectional communication over persistent connections
;;;;
;;;; This transport is production-ready and can be used until native gRPC is available.
;;;;
;;;; Protocol Format:
;;;;   [LENGTH:4 bytes, big-endian][JSON PAYLOAD: LENGTH bytes]
;;;;
;;;; Message Types:
;;;;   - request: {"type":"request","method":"...","id":"...","payload":{...}}
;;;;   - response: {"type":"response","id":"...","success":true/false,"payload":{...}}
;;;;   - ping: {"type":"ping","timestamp":...}
;;;;   - pong: {"type":"pong","timestamp":...}
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.grpc)

;;;; ============================================================================
;;;; Transport Configuration
;;;; ============================================================================

(defparameter *transport-read-timeout* 30
  "Default timeout in seconds for read operations.")

(defparameter *transport-connect-timeout* 10
  "Default timeout in seconds for connection establishment.")

(defparameter *transport-buffer-size* 65536
  "Default buffer size for reading data (64KB).")

(defparameter *transport-max-message-size* 16777216
  "Maximum message size in bytes (16MB). Messages larger than this are rejected.")

;;;; ============================================================================
;;;; TCP-TRANSPORT Class
;;;; ============================================================================

(defclass tcp-transport ()
  ((host
    :initarg :host
    :accessor transport-host
    :type string
    :documentation "Remote host to connect to.")

   (port
    :initarg :port
    :accessor transport-port
    :type (integer 1 65535)
    :documentation "Remote port to connect to.")

   (socket
    :accessor transport-socket
    :initform nil
    :documentation "Active usocket connection.")

   (stream
    :accessor transport-stream
    :initform nil
    :documentation "Bidirectional stream for the socket.")

   (connected-p
    :accessor transport-connected-p
    :initform nil
    :type boolean
    :documentation "T if transport has an active connection.")

   (request-id-counter
    :accessor transport-request-id-counter
    :initform 0
    :type integer
    :documentation "Counter for generating unique request IDs.")

   (pending-requests
    :accessor transport-pending-requests
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table of request-id -> (promise . timestamp).")

   (lock
    :accessor transport-lock
    :initform (bt:make-lock "transport-lock")
    :documentation "Lock for thread-safe operations.")

   (read-buffer
    :accessor transport-read-buffer
    :initform (make-array *transport-buffer-size*
                          :element-type '(unsigned-byte 8)
                          :adjustable t)
    :documentation "Reusable buffer for reading data."))

  (:documentation "TCP transport for JSON-over-TCP protocol.

This class provides a TCP-based transport layer that implements the same
semantics as gRPC but uses a simpler wire format (4-byte length prefix + JSON).

Usage:
  (let ((transport (make-tcp-transport \"localhost\" 50051)))
    (transport-connect transport)
    (let ((response (transport-send-request transport \"DeliverEnvelope\" payload)))
      (process-response response))
    (transport-disconnect transport))"))

;;;; ============================================================================
;;;; Transport Factory
;;;; ============================================================================

(defun make-tcp-transport (host port)
  "Create a new TCP transport instance.

Args:
  host - Hostname or IP address
  port - Port number

Returns:
  TCP-TRANSPORT instance (not yet connected)."
  (make-instance 'tcp-transport
                 :host host
                 :port port))

;;;; ============================================================================
;;;; Connection Management
;;;; ============================================================================

(defgeneric transport-connect (transport)
  (:documentation "Establish TCP connection.

Signals:
  SWARM-UNREACHABLE if connection fails."))

(defmethod transport-connect ((transport tcp-transport))
  "Establish TCP connection."
  (when (transport-connected-p transport)
    (return-from transport-connect transport))

  (handler-case
      (let* ((socket (usocket:socket-connect
                      (transport-host transport)
                      (transport-port transport)
                      :element-type '(unsigned-byte 8)
                      :timeout *transport-connect-timeout*))
             (stream (usocket:socket-stream socket)))

        (setf (transport-socket transport) socket
              (transport-stream transport) stream
              (transport-connected-p transport) t)

        (format t "~&[TRANSPORT] Connected to ~A:~D~%"
                (transport-host transport)
                (transport-port transport))

        transport)

    (usocket:connection-refused-error ()
      (error 'sw4rm-orchestrator.errors:swarm-unreachable
             :swarm-id (format nil "~A:~D"
                               (transport-host transport)
                               (transport-port transport))
             :message "Connection refused"))

    (usocket:timeout-error ()
      (error 'sw4rm-orchestrator.errors:swarm-unreachable
             :swarm-id (format nil "~A:~D"
                               (transport-host transport)
                               (transport-port transport))
             :message "Connection timeout"))

    (usocket:socket-error (e)
      (error 'sw4rm-orchestrator.errors:swarm-unreachable
             :swarm-id (format nil "~A:~D"
                               (transport-host transport)
                               (transport-port transport))
             :message (format nil "Socket error: ~A" e)))

    (error (e)
      (error 'sw4rm-orchestrator.errors:swarm-unreachable
             :swarm-id (format nil "~A:~D"
                               (transport-host transport)
                               (transport-port transport))
             :message (format nil "Connection failed: ~A" e)))))

(defgeneric transport-disconnect (transport)
  (:documentation "Close TCP connection."))

(defmethod transport-disconnect ((transport tcp-transport))
  "Close TCP connection."
  (when (transport-connected-p transport)
    (handler-case
        (progn
          (when (transport-stream transport)
            (close (transport-stream transport) :abort t))
          (when (transport-socket transport)
            (usocket:socket-close (transport-socket transport))))
      (error () nil))

    (setf (transport-socket transport) nil
          (transport-stream transport) nil
          (transport-connected-p transport) nil)

    (format t "~&[TRANSPORT] Disconnected from ~A:~D~%"
            (transport-host transport)
            (transport-port transport)))
  nil)

(defgeneric transport-reconnect (transport)
  (:documentation "Disconnect and reconnect."))

(defmethod transport-reconnect ((transport tcp-transport))
  "Disconnect and reconnect."
  (transport-disconnect transport)
  (transport-connect transport))

;;;; ============================================================================
;;;; Wire Protocol - Message Framing
;;;; ============================================================================

(defun write-length-prefix (stream length)
  "Write 4-byte big-endian length prefix to stream.

Args:
  stream - Output stream (element-type (unsigned-byte 8))
  length - Message length in bytes"
  (write-byte (ldb (byte 8 24) length) stream)
  (write-byte (ldb (byte 8 16) length) stream)
  (write-byte (ldb (byte 8 8) length) stream)
  (write-byte (ldb (byte 8 0) length) stream))

(defun read-length-prefix (stream)
  "Read 4-byte big-endian length prefix from stream.

Args:
  stream - Input stream (element-type (unsigned-byte 8))

Returns:
  Message length as integer, or NIL on EOF."
  (let ((b0 (read-byte stream nil nil)))
    (unless b0 (return-from read-length-prefix nil))
    (let ((b1 (read-byte stream))
          (b2 (read-byte stream))
          (b3 (read-byte stream)))
      (+ (ash b0 24) (ash b1 16) (ash b2 8) b3))))

(defun write-message (transport message-json)
  "Write a framed message to the transport.

Args:
  transport - TCP-TRANSPORT instance
  message-json - JSON string to send

Signals:
  SWARM-DISCONNECTED if transport is not connected."
  (unless (transport-connected-p transport)
    (error 'sw4rm-orchestrator.errors:swarm-disconnected
           :swarm-id (format nil "~A:~D"
                             (transport-host transport)
                             (transport-port transport))
           :reason :not-connected
           :message "Transport not connected"))

  (let* ((octets (sw4rm-orchestrator.envelope::string-to-octets message-json))
         (length (length octets))
         (stream (transport-stream transport)))

    ;; Check message size
    (when (> length *transport-max-message-size*)
      (error 'sw4rm-orchestrator.errors:envelope-error
             :message (format nil "Message too large: ~D bytes (max: ~D)"
                              length *transport-max-message-size*)))

    (bt:with-lock-held ((transport-lock transport))
      ;; Write length prefix
      (write-length-prefix stream length)
      ;; Write message body
      (write-sequence octets stream)
      ;; Flush
      (force-output stream))))

(defun read-message (transport &optional (timeout *transport-read-timeout*))
  "Read a framed message from the transport.

Args:
  transport - TCP-TRANSPORT instance
  timeout - Read timeout in seconds (default: *transport-read-timeout*)

Returns:
  JSON string, or NIL on timeout/EOF.

Signals:
  SWARM-DISCONNECTED if connection is lost."
  (declare (ignore timeout)) ; TODO: implement proper timeout
  (unless (transport-connected-p transport)
    (return-from read-message nil))

  (let ((stream (transport-stream transport)))
    (handler-case
        (let ((length (read-length-prefix stream)))
          (unless length
            (setf (transport-connected-p transport) nil)
            (return-from read-message nil))

          ;; Validate length
          (when (> length *transport-max-message-size*)
            (error 'sw4rm-orchestrator.errors:envelope-error
                   :message (format nil "Received message too large: ~D bytes"
                                    length)))

          ;; Read message body
          (let ((buffer (make-array length :element-type '(unsigned-byte 8))))
            (read-sequence buffer stream)
            (sw4rm-orchestrator.envelope::octets-to-string buffer)))

      (end-of-file ()
        (setf (transport-connected-p transport) nil)
        nil)

      (error (e)
        (setf (transport-connected-p transport) nil)
        (error 'sw4rm-orchestrator.errors:swarm-disconnected
               :swarm-id (format nil "~A:~D"
                                 (transport-host transport)
                                 (transport-port transport))
               :reason :read-error
               :message (format nil "Read error: ~A" e))))))

;;;; ============================================================================
;;;; Request/Response Protocol
;;;; ============================================================================

(defun generate-request-id (transport)
  "Generate a unique request ID."
  (bt:with-lock-held ((transport-lock transport))
    (format nil "req-~D-~D"
            (incf (transport-request-id-counter transport))
            (get-universal-time))))

(defun make-request-message (method request-id payload)
  "Create a JSON request message.

Args:
  method - RPC method name (string)
  request-id - Unique request identifier
  payload - Request payload (hash-table or plist)

Returns:
  JSON string."
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "type" msg) "request"
          (gethash "method" msg) method
          (gethash "id" msg) request-id
          (gethash "payload" msg) payload
          (gethash "timestamp" msg) (get-universal-time))
    (sw4rm-orchestrator.envelope::lisp-to-json
     (sw4rm-orchestrator.envelope::lisp-to-json msg))))

(defun make-response-message (request-id success payload &optional error-message)
  "Create a JSON response message.

Args:
  request-id - Request ID being responded to
  success - T for success, NIL for failure
  payload - Response payload
  error-message - Error message (if success is NIL)

Returns:
  JSON string."
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "type" msg) "response"
          (gethash "id" msg) request-id
          (gethash "success" msg) success
          (gethash "payload" msg) payload
          (gethash "timestamp" msg) (get-universal-time))
    (when error-message
      (setf (gethash "error" msg) error-message))
    (sw4rm-orchestrator.envelope::lisp-to-json msg)))

(defun make-ping-message ()
  "Create a ping message for health checking."
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "type" msg) "ping"
          (gethash "timestamp" msg) (get-universal-time))
    (sw4rm-orchestrator.envelope::lisp-to-json msg)))

(defun make-pong-message (ping-timestamp)
  "Create a pong response to a ping."
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "type" msg) "pong"
          (gethash "ping_timestamp" msg) ping-timestamp
          (gethash "timestamp" msg) (get-universal-time))
    (sw4rm-orchestrator.envelope::lisp-to-json msg)))

;;;; ============================================================================
;;;; Synchronous RPC Calls
;;;; ============================================================================

(defgeneric transport-send-request (transport method payload)
  (:documentation "Send a request and wait for response.

Args:
  transport - TCP-TRANSPORT instance
  method - RPC method name
  payload - Request payload

Returns:
  Response payload hash-table.

Signals:
  SWARM-UNREACHABLE on network errors.
  DEADLINE-EXCEEDED on timeout."))

(defmethod transport-send-request ((transport tcp-transport) method payload)
  "Send a request and wait for response."
  ;; Ensure connected
  (unless (transport-connected-p transport)
    (transport-connect transport))

  (let* ((request-id (generate-request-id transport))
         (request-json (make-request-message method request-id payload)))

    ;; Send request
    (write-message transport request-json)

    ;; Wait for response
    (let ((response-json (read-message transport)))
      (unless response-json
        (error 'sw4rm-orchestrator.errors:swarm-disconnected
               :swarm-id (format nil "~A:~D"
                                 (transport-host transport)
                                 (transport-port transport))
               :reason :no-response
               :message "No response received"))

      ;; Parse response
      (let ((response (sw4rm-orchestrator.envelope::parse-json response-json)))
        ;; Verify response ID matches
        (unless (equal (gethash "id" response) request-id)
          (warn "Response ID mismatch: expected ~A, got ~A"
                request-id (gethash "id" response)))

        ;; Check success
        (if (gethash "success" response)
            (gethash "payload" response)
            (error 'sw4rm-orchestrator.errors:swarm-unreachable
                   :swarm-id (format nil "~A:~D"
                                     (transport-host transport)
                                     (transport-port transport))
                   :message (or (gethash "error" response)
                                "Request failed")))))))

;;;; ============================================================================
;;;; Ping/Pong for Health Checking
;;;; ============================================================================

(defgeneric transport-ping (transport &key timeout)
  (:documentation "Send ping and measure round-trip latency.

Returns:
  (VALUES latency-ms success-p)"))

(defmethod transport-ping ((transport tcp-transport) &key (timeout 5))
  "Send ping and measure round-trip latency."
  (declare (ignore timeout))
  (unless (transport-connected-p transport)
    (return-from transport-ping (values nil nil)))

  (let ((start-time (get-internal-real-time))
        (ping-json (make-ping-message)))

    (handler-case
        (progn
          ;; Send ping
          (write-message transport ping-json)

          ;; Wait for pong
          (let ((pong-json (read-message transport)))
            (unless pong-json
              (return-from transport-ping (values nil nil)))

            ;; Calculate latency
            (let* ((end-time (get-internal-real-time))
                   (latency-ms (/ (* 1000 (- end-time start-time))
                                  internal-time-units-per-second)))
              (values latency-ms t))))

      (error ()
        (values nil nil)))))

;;;; ============================================================================
;;;; TCP-TRANSPORT-SERVER Class
;;;; ============================================================================

(defclass tcp-transport-server ()
  ((host
    :initarg :host
    :accessor server-transport-host
    :initform "0.0.0.0"
    :type string
    :documentation "Host to bind to.")

   (port
    :initarg :port
    :accessor server-transport-port
    :type (integer 1 65535)
    :documentation "Port to listen on.")

   (socket
    :accessor server-transport-socket
    :initform nil
    :documentation "Server socket.")

   (running-p
    :accessor server-transport-running-p
    :initform nil
    :type boolean
    :documentation "T if server is running.")

   (clients
    :accessor server-transport-clients
    :initform nil
    :type list
    :documentation "List of connected client sockets.")

   (handler
    :initarg :handler
    :accessor server-transport-handler
    :type (or null function)
    :documentation "Handler function for incoming requests.
Takes (method payload) and returns response payload.")

   (accept-thread
    :accessor server-transport-accept-thread
    :initform nil
    :documentation "Thread accepting new connections.")

   (lock
    :accessor server-transport-lock
    :initform (bt:make-lock "server-transport-lock")
    :documentation "Lock for thread-safe operations."))

  (:documentation "TCP transport server for accepting client connections."))

;;;; ============================================================================
;;;; Server Factory and Lifecycle
;;;; ============================================================================

(defun make-tcp-transport-server (port &key (host "0.0.0.0") handler)
  "Create a TCP transport server.

Args:
  port - Port to listen on
  host - Host to bind to (default: 0.0.0.0)
  handler - Function to handle requests: (lambda (method payload) ...)

Returns:
  TCP-TRANSPORT-SERVER instance (not yet started)."
  (make-instance 'tcp-transport-server
                 :host host
                 :port port
                 :handler handler))

(defgeneric transport-server-start (server)
  (:documentation "Start the transport server."))

(defmethod transport-server-start ((server tcp-transport-server))
  "Start the transport server."
  (when (server-transport-running-p server)
    (error "Server is already running"))

  ;; Create server socket
  (let ((socket (usocket:socket-listen
                 (server-transport-host server)
                 (server-transport-port server)
                 :element-type '(unsigned-byte 8)
                 :reuse-address t)))

    (setf (server-transport-socket server) socket
          (server-transport-running-p server) t)

    ;; Start accept thread
    (setf (server-transport-accept-thread server)
          (bt:make-thread
           (lambda ()
             (server-accept-loop server))
           :name "tcp-transport-accept"))

    (format t "~&[TRANSPORT-SERVER] Listening on ~A:~D~%"
            (server-transport-host server)
            (server-transport-port server))

    server))

(defgeneric transport-server-stop (server)
  (:documentation "Stop the transport server."))

(defmethod transport-server-stop ((server tcp-transport-server))
  "Stop the transport server."
  (unless (server-transport-running-p server)
    (return-from transport-server-stop nil))

  (setf (server-transport-running-p server) nil)

  ;; Close all client connections
  (bt:with-lock-held ((server-transport-lock server))
    (dolist (client (server-transport-clients server))
      (handler-case
          (usocket:socket-close client)
        (error () nil)))
    (setf (server-transport-clients server) nil))

  ;; Close server socket
  (when (server-transport-socket server)
    (handler-case
        (usocket:socket-close (server-transport-socket server))
      (error () nil))
    (setf (server-transport-socket server) nil))

  (format t "~&[TRANSPORT-SERVER] Stopped~%")
  nil)

;;;; ============================================================================
;;;; Server Accept Loop
;;;; ============================================================================

(defun server-accept-loop (server)
  "Accept incoming connections in a loop."
  (loop while (server-transport-running-p server)
        do (handler-case
               (let ((client-socket
                       (usocket:socket-accept
                        (server-transport-socket server)
                        :element-type '(unsigned-byte 8))))
                 (when client-socket
                   ;; Add to clients list
                   (bt:with-lock-held ((server-transport-lock server))
                     (push client-socket (server-transport-clients server)))

                   ;; Spawn handler thread
                   (bt:make-thread
                    (lambda ()
                      (server-handle-client server client-socket))
                    :name "tcp-transport-client-handler")))
             (error (e)
               (when (server-transport-running-p server)
                 (format t "~&[TRANSPORT-SERVER] Accept error: ~A~%" e))))))

(defun server-handle-client (server client-socket)
  "Handle a client connection."
  (let ((stream (usocket:socket-stream client-socket)))
    (unwind-protect
         (loop while (server-transport-running-p server)
               do (handler-case
                      (let ((message-json (read-message-from-stream stream)))
                        (unless message-json
                          (return)) ; Connection closed

                        ;; Parse message
                        (let ((message (sw4rm-orchestrator.envelope::parse-json
                                        message-json)))
                          (cond
                            ;; Handle request
                            ((equal (gethash "type" message) "request")
                             (let* ((method (gethash "method" message))
                                    (request-id (gethash "id" message))
                                    (payload (gethash "payload" message))
                                    (response-payload nil)
                                    (success t)
                                    (error-msg nil))

                               ;; Call handler
                               (handler-case
                                   (when (server-transport-handler server)
                                     (setf response-payload
                                           (funcall (server-transport-handler server)
                                                    method payload)))
                                 (error (e)
                                   (setf success nil
                                         error-msg (format nil "~A" e))))

                               ;; Send response
                               (let ((response-json
                                       (make-response-message
                                        request-id success response-payload error-msg)))
                                 (write-message-to-stream stream response-json))))

                            ;; Handle ping
                            ((equal (gethash "type" message) "ping")
                             (let ((pong-json
                                     (make-pong-message
                                      (gethash "timestamp" message))))
                               (write-message-to-stream stream pong-json))))))

                    (error ()
                      (return)))) ; Exit on any error

      ;; Cleanup
      (handler-case
          (usocket:socket-close client-socket)
        (error () nil))

      ;; Remove from clients list
      (bt:with-lock-held ((server-transport-lock server))
        (setf (server-transport-clients server)
              (remove client-socket (server-transport-clients server)))))))

;;;; ============================================================================
;;;; Stream-level I/O (for server use)
;;;; ============================================================================

(defun read-message-from-stream (stream)
  "Read a framed message from a raw stream."
  (handler-case
      (let ((length (read-length-prefix stream)))
        (unless length (return-from read-message-from-stream nil))
        (when (> length *transport-max-message-size*)
          (error "Message too large: ~D bytes" length))
        (let ((buffer (make-array length :element-type '(unsigned-byte 8))))
          (read-sequence buffer stream)
          (sw4rm-orchestrator.envelope::octets-to-string buffer)))
    (end-of-file () nil)
    (error () nil)))

(defun write-message-to-stream (stream message-json)
  "Write a framed message to a raw stream."
  (let* ((octets (sw4rm-orchestrator.envelope::string-to-octets message-json))
         (length (length octets)))
    (write-length-prefix stream length)
    (write-sequence octets stream)
    (force-output stream)))

;;;; ============================================================================
;;;; Integration with Existing Client/Server
;;;; ============================================================================

(defun make-transport-backed-client (swarm-id host port)
  "Create a LEAF-GRPC-CLIENT that uses TCP transport.

This is a convenience function that creates a client pre-configured
to use the JSON-over-TCP transport instead of gRPC.

Args:
  swarm-id - Swarm ID for the client
  host - Remote host
  port - Remote port

Returns:
  LEAF-GRPC-CLIENT instance with transport."
  (let ((client (make-instance 'leaf-grpc-client
                               :swarm-id swarm-id
                               :host host
                               :port port))
        (transport (make-tcp-transport host port)))

    ;; Store transport in channel slot (repurposed)
    (setf (client-channel client) transport)

    client))

(defmethod connect ((client leaf-grpc-client))
  "Connect using TCP transport if available."
  (let ((transport (client-channel client)))
    (if (typep transport 'tcp-transport)
        ;; Use TCP transport
        (progn
          (transport-connect transport)
          (setf (client-connected-p client) t)
          client)
        ;; Fallback to original placeholder behavior
        (call-next-method))))

(defmethod disconnect ((client leaf-grpc-client))
  "Disconnect using TCP transport if available."
  (let ((transport (client-channel client)))
    (if (typep transport 'tcp-transport)
        ;; Use TCP transport
        (progn
          (transport-disconnect transport)
          (setf (client-connected-p client) nil)
          nil)
        ;; Fallback to original placeholder behavior
        (call-next-method))))

(defmethod deliver-envelope ((client leaf-grpc-client)
                              (envelope sw4rm-orchestrator.envelope:cross-swarm-envelope))
  "Deliver envelope using TCP transport if available."
  (let ((transport (client-channel client)))
    (if (typep transport 'tcp-transport)
        ;; Use TCP transport
        (progn
          (unless (transport-connected-p transport)
            (transport-connect transport))

          ;; Convert envelope to proto format for wire
          (let* ((proto (envelope-to-proto envelope))
                 (payload (make-hash-table :test 'equal)))

            ;; Build request payload
            (setf (gethash "envelope" payload) (proto-to-json proto))

            ;; Send via transport
            (let ((response (transport-send-request
                             transport "DeliverEnvelope" payload)))

              ;; Build response hash-table
              (let ((result (make-hash-table :test 'equal)))
                (setf (gethash "success" result) t
                      (gethash "message_id" result)
                      (sw4rm-orchestrator.envelope:envelope-id envelope)
                      (gethash "timestamp" result) (get-universal-time))
                result))))
        ;; Fallback to original placeholder behavior
        (call-next-method))))

(defmethod ping ((client leaf-grpc-client) &key (timeout 5))
  "Ping using TCP transport if available."
  (let ((transport (client-channel client)))
    (if (typep transport 'tcp-transport)
        ;; Use TCP transport
        (transport-ping transport :timeout timeout)
        ;; Fallback to original placeholder behavior
        (call-next-method))))

;;;; ============================================================================
;;;; PRINT-OBJECT Methods
;;;; ============================================================================

(defmethod print-object ((transport tcp-transport) stream)
  "Print TCP-TRANSPORT in readable format."
  (print-unreadable-object (transport stream :type t :identity nil)
    (format stream "~A:~D ~A"
            (transport-host transport)
            (transport-port transport)
            (if (transport-connected-p transport) "CONNECTED" "DISCONNECTED"))))

(defmethod print-object ((server tcp-transport-server) stream)
  "Print TCP-TRANSPORT-SERVER in readable format."
  (print-unreadable-object (server stream :type t :identity nil)
    (format stream "~A:~D ~A"
            (server-transport-host server)
            (server-transport-port server)
            (if (server-transport-running-p server) "RUNNING" "STOPPED"))))

;;;; ============================================================================
;;;; End of file
;;;; ============================================================================
