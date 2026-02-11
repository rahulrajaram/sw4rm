;;;; registry.lisp - Registry Service client for SW4RM
;;;;
;;;; Manages agent registration, heartbeats, deregistration, and discovery.
;;;; The registry maintains the catalog of active agents and their capabilities
;;;; for routing and scheduling decisions.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass registry-client (base-client)
  ()
  (:documentation "Client for the SW4RM Registry Service.

The registry service provides:
- Agent registration with capabilities and metadata
- Periodic heartbeats to maintain registration
- Agent deregistration on shutdown
- Discovery of agents by capability or ID

All agents must register with the registry before they can receive tasks
or participate in multi-agent workflows."))

;;;; RPC Methods

(defgeneric register-agent (client agent-descriptor)
  (:documentation "Register an agent with the registry.

Adds the agent to the active registry with its capabilities, communication
preferences, and metadata. The agent must send periodic heartbeats to
maintain its registration.

Args:
  client: The registry-client instance.
  agent-descriptor: Plist with agent details:
    :agent-id (string) - Unique agent identifier
    :name (string) - Human-readable agent name
    :capabilities (list of strings) - Agent capabilities/skills
    :communication-class (string) - Communication preference (e.g., \"async\")
    :metadata (alist) - Additional key-value metadata

Returns:
  Registration response plist with :success boolean.

Signals:
  RPC-ERROR: If registration fails.

Example:
  (register-agent client
                  (list :agent-id \"agent-1\"
                        :name \"Code Generator\"
                        :capabilities '(\"code-generation\" \"python\")
                        :communication-class \"async\"
                        :metadata '((:version . \"1.0\"))))"))

(defmethod register-agent ((client registry-client) agent-descriptor)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RegistryService.RegisterAgent
      (error 'rpc-error
             :message "RegisterAgent not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric deregister-agent (client agent-id &optional reason)
  (:documentation "Deregister an agent from the registry.

Removes the agent from the active registry, making it unavailable for
new task assignments. Optionally provides a reason for deregistration.

Args:
  client: The registry-client instance.
  agent-id: Unique identifier of the agent to deregister.
  reason: Optional reason for deregistration (default: \"\").

Returns:
  Deregistration response plist with :success boolean.

Signals:
  RPC-ERROR: If deregistration fails.

Example:
  (deregister-agent client \"agent-1\" \"Graceful shutdown\")"))

(defmethod deregister-agent ((client registry-client) agent-id &optional (reason ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RegistryService.DeregisterAgent
      (error 'rpc-error
             :message "DeregisterAgent not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric heartbeat (client agent-id state &optional health-metrics)
  (:documentation "Send a heartbeat to maintain agent registration.

Agents must send periodic heartbeats (typically every 10-30 seconds) to
indicate they are still active. Missing heartbeats will cause the agent
to be marked as unresponsive and removed from the active registry.

Args:
  client: The registry-client instance.
  agent-id: Unique identifier of the agent.
  state: Current agent state (e.g., :idle, :busy, :offline).
  health-metrics: Optional alist of health metrics (e.g., ((:cpu . 45) (:memory . 2048))).

Returns:
  Heartbeat response plist with :acknowledged boolean.

Signals:
  RPC-ERROR: If heartbeat fails.

Example:
  (heartbeat client \"agent-1\" :idle
             '((:cpu . 45) (:memory . 2048) (:tasks-active . 0)))"))

(defmethod heartbeat ((client registry-client) agent-id state &optional health-metrics)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RegistryService.Heartbeat
      (error 'rpc-error
             :message "Heartbeat not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric discover-agents (client &key capability communication-class)
  (:documentation "Discover agents in the registry by criteria.

Queries the registry for active agents matching the specified filters.
Can filter by capability (skill/role) or communication class.

Args:
  client: The registry-client instance.
  capability: Optional capability to filter by (string).
  communication-class: Optional communication class to filter by (string).

Returns:
  List of agent descriptor plists matching the criteria.

Signals:
  RPC-ERROR: If discovery fails.

Example:
  ;; Find all agents with Python capability
  (discover-agents client :capability \"python\")

  ;; Find all async communication agents
  (discover-agents client :communication-class \"async\")"))

(defmethod discover-agents ((client registry-client) &key capability communication-class)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RegistryService.DiscoverAgents
      (error 'rpc-error
             :message "DiscoverAgents not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric get-agent (client agent-id)
  (:documentation "Retrieve agent descriptor by ID.

Fetches the full agent descriptor including capabilities, metadata, and
current state for the specified agent.

Args:
  client: The registry-client instance.
  agent-id: Unique identifier of the agent.

Returns:
  Agent descriptor plist if found, NIL otherwise.

Signals:
  RPC-ERROR: If lookup fails.

Example:
  (get-agent client \"agent-1\")
  => (:agent-id \"agent-1\"
      :name \"Code Generator\"
      :capabilities (\"code-generation\" \"python\")
      :state :idle)"))

(defmethod get-agent ((client registry-client) agent-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RegistryService.GetAgent
      (error 'rpc-error
             :message "GetAgent not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))
