;;;; Canonical wire client. Local workflow/handoff helpers retain their APIs.
(in-package :sw4rm-sdk)

(defclass protocol-client (base-client) ()
  (:documentation "Wire access to every canonical SW4RM RPC, using message plists."))

(defun protocol-rpc (path)
  (or (assoc path *protocol-rpc-schemas* :test #'string=)
      (error "Unknown canonical SW4RM RPC: ~A" path)))

(defun protocol-rpc-paths ()
  "Return a fresh list of every canonical RPC path supported by this SDK."
  (mapcar #'first *protocol-rpc-schemas*))

(defun call-protocol-rpc (client path request &key metadata)
  "Call one canonical unary RPC. No implicit retry of possibly effectful calls."
  (destructuring-bind (rpc-path request-type response-type streaming) (protocol-rpc path)
    (when streaming (error "~A requires stream-protocol-rpc" path))
    (let ((bytes (encode-protocol-message request-type request)))
      (ensure-connected client)
      (decode-protocol-message
       response-type
       (grpc-unary-call (client-channel client) rpc-path bytes
                        :deadline-ms (client-timeout-ms client) :metadata metadata)))))

(defun stream-protocol-rpc (client path request handler &key (deadline-ms 0) metadata)
  "Start a canonical server stream; return the cancellable transport handle.
HANDLER receives each decoded message and NIL at end-of-stream.
Use WAIT-FOR-STREAM to wait for completion and report remote errors.

Streams are long-lived subscriptions, so DEADLINE-MS defaults to 0 (no
deadline) like ROUTER-CLIENT:OPEN-STREAM, independent of the client-wide
unary timeout. Pass an explicit DEADLINE-MS for bounded subscriptions."
  (destructuring-bind (rpc-path request-type response-type streaming) (protocol-rpc path)
    (unless streaming (error "~A requires call-protocol-rpc" path))
    (let ((bytes (encode-protocol-message request-type request)))
      (ensure-connected client)
      (grpc-server-stream
       (client-channel client) rpc-path bytes
       (lambda (response) (funcall handler (when response (decode-protocol-message response-type response))))
       :deadline-ms deadline-ms :metadata metadata))))
