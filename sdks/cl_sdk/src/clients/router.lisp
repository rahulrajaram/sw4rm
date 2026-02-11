;;;; router.lisp - Router Service client for SW4RM
;;;;
;;;; Provides message routing capabilities between agents. The router handles
;;;; delivery of envelopes to their intended recipients and supports streaming
;;;; for continuous message reception.

(in-package :sw4rm)

;;;; Client Class

(defclass router-client (base-client)
  ()
  (:documentation "Client for the SW4RM Router Service.

The router service provides:
- Unary message sending (fire-and-forget or acknowledged)
- Bidirectional streaming for continuous message delivery
- Routing metadata and diagnostics

Agents use the router to communicate asynchronously without direct
point-to-point connections."))

;;;; RPC Methods

(defgeneric send-envelope (client envelope)
  (:documentation "Send a message envelope to its destination.

Delivers a message to the specified recipient(s) through the router.
The envelope contains producer ID, message type, payload, and routing
metadata.

Args:
  client: The router-client instance.
  envelope: Plist with envelope fields:
    :producer-id (string) - Agent ID of message sender
    :consumer-id (string) - Agent ID of intended recipient
    :message-type (string) - Message type/topic
    :payload (bytes) - Message payload
    :correlation-id (string, optional) - Correlation/trace ID
    :metadata (alist, optional) - Additional routing metadata

Returns:
  Send response plist with :delivered boolean and :message-id.

Signals:
  RPC-ERROR: If send fails.

Example:
  (send-envelope client
                 (list :producer-id \"agent-1\"
                       :consumer-id \"agent-2\"
                       :message-type \"task.request\"
                       :payload #(72 101 108 108 111)
                       :correlation-id \"wf-123\"))"))

(defmethod send-envelope ((client router-client) envelope)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RouterService.SendMessage
      (error 'rpc-error
             :message "SendEnvelope not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric open-stream (client agent-id handler-fn)
  (:documentation "Open bidirectional streaming connection for message delivery.

Establishes a persistent bidirectional stream between the agent and the
router. The agent can send messages through the stream and receive
incoming messages via the handler function.

Args:
  client: The router-client instance.
  agent-id: Unique identifier of the agent opening the stream.
  handler-fn: Function called for each incoming message. Takes one argument:
              the envelope plist.

Returns:
  Stream handle (implementation-specific) that can be used to send messages
  or close the stream.

Signals:
  RPC-ERROR: If stream establishment fails.

Example:
  (defun handle-incoming (envelope)
    (format t \"Received: ~A~%\" (getf envelope :message-type)))

  (let ((stream (open-stream client \"agent-1\" #'handle-incoming)))
    ;; Stream is now active, handler-fn will be called for incoming messages
    ;; Use stream to send outgoing messages
    ;; ...
    ;; Close stream when done
    (close-stream stream))

Implementation Note:
Bidirectional streaming in gRPC requires thread/async handling for the
incoming message loop. The actual implementation will depend on the
chosen gRPC library's streaming API."))

(defmethod open-stream ((client router-client) agent-id handler-fn)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC RouterService.OpenStream
  ;; and set up bidirectional streaming with the handler-fn callback
  (error 'rpc-error
         :message "OpenStream not implemented - requires gRPC integration"
         :code "UNIMPLEMENTED"))

(defgeneric route-info (client agent-id)
  (:documentation "Get routing information and diagnostics for an agent.

Retrieves routing metadata, queue depths, message counts, and other
diagnostics for the specified agent.

Args:
  client: The router-client instance.
  agent-id: Unique identifier of the agent.

Returns:
  Route info plist with:
    :agent-id (string) - Agent identifier
    :pending-messages (integer) - Number of queued messages
    :streams-active (integer) - Number of active streams
    :last-activity (timestamp) - Last message activity

Signals:
  RPC-ERROR: If info retrieval fails.

Example:
  (route-info client \"agent-1\")
  => (:agent-id \"agent-1\"
      :pending-messages 5
      :streams-active 1
      :last-activity \"2026-02-11T10:30:00Z\")"))

(defmethod route-info ((client router-client) agent-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RouterService.RouteInfo
      (error 'rpc-error
             :message "RouteInfo not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

;;;; Streaming Utilities

(defgeneric close-stream (stream)
  (:documentation "Close an active bidirectional stream.

Cleanly shuts down the stream, flushing any pending messages and
releasing resources.

Args:
  stream: The stream handle returned by OPEN-STREAM.

Returns:
  T on success.

Signals:
  RPC-ERROR: If close fails."))

(defmethod close-stream (stream)
  "Default stub implementation."
  (error 'rpc-error
         :message "CloseStream not implemented - requires gRPC integration"
         :code "UNIMPLEMENTED"))
