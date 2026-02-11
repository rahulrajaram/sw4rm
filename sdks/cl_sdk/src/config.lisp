;;;; config.lisp - Configuration structures and loaders

(in-package #:sw4rm-sdk)

;;;; Service Endpoints
;;;
;;; Configuration for all SW4RM service addresses.

(defstruct endpoints
  "Service endpoint addresses for SW4RM infrastructure.

All endpoints are strings in 'host:port' format (e.g., 'localhost:50051').
Implementations SHOULD honor environment variable overrides for deployment flexibility."
  (router
   (format nil "~A:~D" *default-host* +default-router-port+)
   :type string)
  (registry
   (format nil "~A:~D" *default-host* +default-registry-port+)
   :type string)
  (scheduler
   (format nil "~A:~D" *default-host* +default-scheduler-port+)
   :type string)
  (hitl
   (format nil "~A:~D" *default-host* +default-hitl-port+)
   :type string)
  (worktree
   (format nil "~A:~D" *default-host* +default-worktree-port+)
   :type string)
  (tool
   (format nil "~A:~D" *default-host* +default-tool-port+)
   :type string)
  (connector
   (format nil "~A:~D" *default-host* +default-connector-port+)
   :type string)
  (negotiation
   (format nil "~A:~D" *default-host* +default-negotiation-port+)
   :type string)
  (reasoning
   (format nil "~A:~D" *default-host* +default-reasoning-port+)
   :type string)
  (logging
   (format nil "~A:~D" *default-host* +default-logging-port+)
   :type string))

;;;; Agent Configuration
;;;
;;; Comprehensive configuration for agent runtime behavior.

(defstruct agent-config
  "Agent runtime configuration.

Specifies agent identity, capabilities, service endpoints, and operational parameters
such as timeouts and retry policies."
  (agent-id
   "agent-1"
   :type string
   :read-only t)
  (name
   "Agent"
   :type string)
  (description
   nil
   :type (or null string))
  (version
   "0.5.0"
   :type string)
  (capabilities
   nil
   :type list
   :documentation "List of capability strings this agent provides.")
  (endpoints
   (make-default-endpoints)
   :type endpoints)
  (timeout-ms
   *default-timeout-ms*
   :type integer
   :documentation "Default timeout for operations in milliseconds.")
  (retry-max-attempts
   *default-retry-max-attempts*
   :type integer
   :documentation "Maximum number of retry attempts for failed operations.")
  (heartbeat-interval-ms
   *default-heartbeat-interval-ms*
   :type integer
   :documentation "Interval between heartbeat messages in milliseconds."))

;;;; Configuration Constructors
;;;
;;; Functions for creating configuration with environment variable overrides.

(defun make-default-endpoints ()
  "Create endpoints configuration with environment variable overrides.

Environment variables (SW4RM_* prefix):
  SW4RM_ROUTER_ADDR     - Router service address
  SW4RM_REGISTRY_ADDR   - Registry service address
  SW4RM_SCHEDULER_ADDR  - Scheduler service address
  SW4RM_HITL_ADDR       - HITL service address
  SW4RM_WORKTREE_ADDR   - Worktree service address
  SW4RM_TOOL_ADDR       - Tool service address
  SW4RM_CONNECTOR_ADDR  - Connector service address
  SW4RM_NEGOTIATION_ADDR - Negotiation service address
  SW4RM_REASONING_ADDR  - Reasoning service address
  SW4RM_LOGGING_ADDR    - Logging service address

Returns:
  ENDPOINTS structure with defaults overridden by environment variables."
  (make-endpoints
   :router (or (uiop:getenv "SW4RM_ROUTER_ADDR")
               (format nil "~A:~D" *default-host* +default-router-port+))
   :registry (or (uiop:getenv "SW4RM_REGISTRY_ADDR")
                 (format nil "~A:~D" *default-host* +default-registry-port+))
   :scheduler (or (uiop:getenv "SW4RM_SCHEDULER_ADDR")
                  (format nil "~A:~D" *default-host* +default-scheduler-port+))
   :hitl (or (uiop:getenv "SW4RM_HITL_ADDR")
             (format nil "~A:~D" *default-host* +default-hitl-port+))
   :worktree (or (uiop:getenv "SW4RM_WORKTREE_ADDR")
                 (format nil "~A:~D" *default-host* +default-worktree-port+))
   :tool (or (uiop:getenv "SW4RM_TOOL_ADDR")
             (format nil "~A:~D" *default-host* +default-tool-port+))
   :connector (or (uiop:getenv "SW4RM_CONNECTOR_ADDR")
                  (format nil "~A:~D" *default-host* +default-connector-port+))
   :negotiation (or (uiop:getenv "SW4RM_NEGOTIATION_ADDR")
                    (format nil "~A:~D" *default-host* +default-negotiation-port+))
   :reasoning (or (uiop:getenv "SW4RM_REASONING_ADDR")
                  (format nil "~A:~D" *default-host* +default-reasoning-port+))
   :logging (or (uiop:getenv "SW4RM_LOGGING_ADDR")
                (format nil "~A:~D" *default-host* +default-logging-port+))))

(defun load-config-from-env ()
  "Load agent configuration from environment variables.

Environment variables:
  AGENT_ID               - Agent identifier (default: 'agent-1')
  AGENT_NAME             - Agent display name (default: 'Agent')
  AGENT_DESCRIPTION      - Agent description
  AGENT_VERSION          - Agent version (default: '0.5.0')
  SW4RM_TIMEOUT_MS       - Default timeout in milliseconds
  SW4RM_RETRY_MAX_ATTEMPTS - Maximum retry attempts
  SW4RM_HEARTBEAT_INTERVAL_MS - Heartbeat interval in milliseconds

Plus all SW4RM_*_ADDR variables for service endpoints (see MAKE-DEFAULT-ENDPOINTS).

Returns:
  AGENT-CONFIG structure with values from environment or defaults."
  (make-agent-config
   :agent-id (or (uiop:getenv "AGENT_ID") "agent-1")
   :name (or (uiop:getenv "AGENT_NAME") "Agent")
   :description (uiop:getenv "AGENT_DESCRIPTION")
   :version (or (uiop:getenv "AGENT_VERSION") "0.5.0")
   :endpoints (make-default-endpoints)
   :timeout-ms (if-let ((val (uiop:getenv "SW4RM_TIMEOUT_MS")))
                 (parse-integer val :junk-allowed t)
                 *default-timeout-ms*)
   :retry-max-attempts (if-let ((val (uiop:getenv "SW4RM_RETRY_MAX_ATTEMPTS")))
                         (parse-integer val :junk-allowed t)
                         *default-retry-max-attempts*)
   :heartbeat-interval-ms (if-let ((val (uiop:getenv "SW4RM_HEARTBEAT_INTERVAL_MS")))
                            (parse-integer val :junk-allowed t)
                            *default-heartbeat-interval-ms*)))
