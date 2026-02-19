;;;; connector.lisp - Connector Service client for SW4RM
;;;;
;;;; Manages tool provider registration and discovery.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass connector-client (base-client)
  ()
  (:documentation "Client for the SW4RM Connector Service.

The connector service provides:
- Tool provider registration
- Provider discovery and listing
- Tool capability queries

Providers register their available tools with the connector, which
maintains the catalog for tool resolution and routing."))

;;;; RPC Methods

(defgeneric register-provider (client provider-id tools)
  (:documentation "Register a tool provider with its available tools.

Registers a provider and its tool catalog with the connector service.
The tools list describes each tool's capabilities, schemas, and metadata.

Args:
  client: The connector-client instance.
  provider-id: Unique identifier for the provider.
  tools: List of tool descriptor plists, each with:
    :tool-name (string) - Name of the tool
    :input-schema (string) - JSON Schema or URL for input
    :output-schema (string) - JSON Schema or URL for output
    :idempotent (boolean) - Whether the tool is idempotent
    :needs-worktree (boolean) - Whether the tool needs a worktree
    :default-timeout-s (integer) - Default timeout in seconds
    :max-concurrency (integer) - Maximum concurrent executions
    :side-effects (string) - Side effects (e.g., \"filesystem\", \"network\")

Returns:
  Registration response plist with :ok boolean and :reason string.

Signals:
  RPC-ERROR: If registration fails.

Example:
  (register-provider client \"filesystem\"
                     (list (list :tool-name \"read-file\"
                                 :input-schema \"file://schemas/read-file-input.json\"
                                 :output-schema \"file://schemas/read-file-output.json\"
                                 :idempotent t
                                 :needs-worktree t
                                 :default-timeout-s 30
                                 :max-concurrency 10
                                 :side-effects \"filesystem\")))"))

(defmethod register-provider ((client connector-client) provider-id tools)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-provider-register-request provider-id tools))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.connector.ConnectorService/RegisterProvider"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-provider-register-response response-bytes)))))

(defgeneric list-providers (client)
  (:documentation "List all registered tool providers.

Retrieves the catalog of all active tool providers.

Args:
  client: The connector-client instance.

Returns:
  List of provider plists, each with:
    :provider-id (string) - Provider identifier
    :registered-at (timestamp) - Registration time
    :tool-count (integer) - Number of tools provided

Signals:
  RPC-ERROR: If listing fails.

Example:
  (list-providers client)
  => ((:provider-id \"filesystem\" :tool-count 5)
      (:provider-id \"network\" :tool-count 3))"))

(defmethod list-providers ((client connector-client))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC ConnectorService.ListProviders
      (error 'rpc-error
             :message "ListProviders not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric get-provider (client provider-id)
  (:documentation "Get details for a specific tool provider.

Retrieves the full provider registration including all tools and metadata.

Args:
  client: The connector-client instance.
  provider-id: Unique identifier for the provider.

Returns:
  Provider details plist with:
    :provider-id (string) - Provider identifier
    :tools (list) - List of tool descriptors
    :registered-at (timestamp) - Registration time

Signals:
  RPC-ERROR: If provider not found or retrieval fails.

Example:
  (get-provider client \"filesystem\")
  => (:provider-id \"filesystem\"
      :tools ((:tool-name \"read-file\" ...) (:tool-name \"write-file\" ...))
      :registered-at \"2026-02-11T10:00:00Z\")"))

(defmethod get-provider ((client connector-client) provider-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-describe-tools-request provider-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.connector.ConnectorService/DescribeTools"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-describe-tools-response response-bytes)))))
