;;;; tool.lisp - Tool Service client for SW4RM
;;;;
;;;; Provides methods for executing tool calls with support for both unary
;;;; and streaming responses.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass tool-client (base-client)
  ()
  (:documentation "Client for the SW4RM Tool Service.

The tool service provides:
- Unary tool execution (single request/response)
- Streaming tool execution (for long-running operations)
- Tool cancellation (best-effort)
- Tool discovery and listing

Tools are executed by registered providers and may operate within
worktree contexts for file system access."))

;;;; RPC Methods

(defgeneric call-tool (client tool-call)
  (:documentation "Execute a unary tool call.

Invokes a tool and waits for the complete result. Suitable for quick
operations that complete in under a few seconds.

Args:
  client: The tool-client instance.
  tool-call: Tool call plist with:
    :call-id (string) - Unique call identifier
    :tool-name (string) - Tool name to invoke
    :provider-id (string) - Tool provider identifier
    :args (bytes or string) - Tool arguments (JSON-encoded)
    :worktree-id (string, optional) - Worktree context
    :timeout-ms (integer, optional) - Call timeout override

Returns:
  Tool frame plist with:
    :call-id (string) - Call identifier
    :status (keyword) - :success or :error
    :result (bytes or string) - Tool result (JSON-encoded)
    :error-message (string, optional) - Error details if failed

Signals:
  RPC-ERROR: If tool call fails.

Example:
  (call-tool client
             (list :call-id \"call-123\"
                   :tool-name \"read-file\"
                   :provider-id \"filesystem\"
                   :args \"{\\\"path\\\": \\\"/etc/hosts\\\"}\"
                   :worktree-id \"wt-main\"))"))

(defmethod call-tool ((client tool-client) tool-call)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC ToolService.Call
      (error 'rpc-error
             :message "CallTool not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric stream-tool-call (client tool-call handler-fn)
  (:documentation "Execute a streaming tool call.

Invokes a tool that returns results incrementally via streaming. The
handler function is called for each frame received from the tool.

Args:
  client: The tool-client instance.
  tool-call: Tool call plist (same format as CALL-TOOL).
  handler-fn: Function called for each result frame. Takes one argument:
              the tool frame plist.

Returns:
  NIL when streaming completes.

Signals:
  RPC-ERROR: If tool call fails.

Example:
  (defun handle-frame (frame)
    (format t \"Progress: ~A~%\" (getf frame :result)))

  (stream-tool-call client
                    (list :call-id \"call-124\"
                          :tool-name \"compile-large-project\"
                          :provider-id \"build\"
                          :args \"{\\\"target\\\": \\\"all\\\"}\")
                    #'handle-frame)

Implementation Note:
Server-side streaming in gRPC requires handling the stream response
iterator. The actual implementation will depend on the chosen gRPC
library's streaming API."))

(defmethod stream-tool-call ((client tool-client) tool-call handler-fn)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC ToolService.CallStream
  ;; and iterate over the response stream, calling handler-fn for each frame
  (error 'rpc-error
         :message "StreamToolCall not implemented - requires gRPC integration"
         :status-code "UNIMPLEMENTED" :details "Stub implementation"))

(defgeneric cancel-tool-call (client call-id)
  (:documentation "Cancel a running tool call (best effort).

Requests cancellation of a tool call. The tool provider may or may not
support cancellation. If supported, the tool will attempt to abort and
return an error frame.

Args:
  client: The tool-client instance.
  call-id: Unique identifier of the call to cancel.

Returns:
  Cancellation response plist with :cancelled boolean.

Signals:
  RPC-ERROR: If cancellation request fails.

Example:
  (cancel-tool-call client \"call-123\")"))

(defmethod cancel-tool-call ((client tool-client) call-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC ToolService.Cancel
      (error 'rpc-error
             :message "CancelToolCall not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric list-tools (client &optional provider-id)
  (:documentation "List available tools, optionally filtered by provider.

Retrieves the catalog of available tools and their metadata. Can be
filtered to a specific provider or list all tools across providers.

Args:
  client: The tool-client instance.
  provider-id: Optional provider ID to filter by.

Returns:
  List of tool descriptor plists, each with:
    :tool-name (string) - Tool name
    :provider-id (string) - Provider identifier
    :description (string) - Tool description
    :input-schema (string) - JSON Schema URL for input
    :output-schema (string) - JSON Schema URL for output
    :idempotent (boolean) - Whether tool is idempotent
    :needs-worktree (boolean) - Whether tool requires worktree
    :default-timeout-ms (integer) - Default timeout

Signals:
  RPC-ERROR: If listing fails.

Example:
  ;; List all tools
  (list-tools client)

  ;; List tools from filesystem provider
  (list-tools client \"filesystem\")"))

(defmethod list-tools ((client tool-client) &optional provider-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC ToolService.ListTools
      (error 'rpc-error
             :message "ListTools not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))
