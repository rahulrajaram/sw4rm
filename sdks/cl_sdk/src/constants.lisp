;;;; constants.lisp - Protocol constants and enums

(in-package #:sw4rm-sdk)

;;;; Protocol Enums
;;;
;;; These constants mirror the enum values from protos/common.proto.
;;; All values MUST match the canonical protocol buffer definitions.
;;;
;;; SW4RM Protocol Version: 0.5.0

;;; MessageType (spec §11)
;;; Defines the type of message being sent through the routing infrastructure.

(defconstant +message-type-unspecified+ 0
  "Unspecified message type. Should not be used in production.")

(defconstant +control+ 1
  "Control message for system-level coordination and lifecycle management.")

(defconstant +data+ 2
  "Data message carrying application-level payload.")

(defconstant +heartbeat+ 3
  "Heartbeat message for liveness detection and connection maintenance.")

(defconstant +notification+ 4
  "Notification message for one-way information broadcast.")

(defconstant +acknowledgement+ 5
  "Acknowledgement message confirming receipt or processing of another message.")

(defconstant +hitl-invocation+ 6
  "Human-In-The-Loop invocation message requesting operator intervention.")

(defconstant +worktree-control+ 7
  "Worktree control message for Git worktree management operations.")

(defconstant +negotiation+ 8
  "Negotiation protocol message for multi-agent coordination.")

(defconstant +tool-call+ 9
  "Tool invocation message requesting external capability execution.")

(defconstant +tool-result+ 10
  "Tool result message returning output from tool execution.")

(defconstant +tool-error+ 11
  "Tool error message indicating tool execution failure.")

;;; AckStage (spec §11)
;;; Defines the acknowledgement stage in message processing lifecycle.

(defconstant +ack-stage-unspecified+ 0
  "Unspecified acknowledgement stage.")

(defconstant +received+ 1
  "Message has been received by the transport layer.")

(defconstant +read+ 2
  "Message has been read and parsed by the recipient.")

(defconstant +fulfilled+ 3
  "Message has been successfully processed and completed.")

(defconstant +rejected+ 4
  "Message has been explicitly rejected by the recipient.")

(defconstant +failed+ 5
  "Message processing has failed due to an error.")

(defconstant +timed-out+ 6
  "Message processing has exceeded timeout threshold.")

;;; ErrorCode (spec §11)
;;; Protocol error codes for structured error reporting.

(defconstant +error-code-unspecified+ 0
  "Unspecified error code.")

(defconstant +buffer-full+ 1
  "Activity buffer is at capacity and cannot accept new entries.")

(defconstant +no-route+ 2
  "No route exists to the destination agent or service.")

(defconstant +ack-timeout+ 3
  "Acknowledgement was not received within timeout period.")

(defconstant +agent-unavailable+ 4
  "Target agent is not available or not registered.")

(defconstant +agent-shutdown+ 5
  "Agent is shutting down and cannot process new requests.")

(defconstant +validation-error+ 6
  "Input validation failed - invalid parameters or constraints violated.")

(defconstant +permission-denied+ 7
  "Operation denied due to insufficient permissions or policy violation.")

(defconstant +unsupported-message-type+ 8
  "Message type is not supported by the recipient.")

(defconstant +oversize-payload+ 9
  "Payload size exceeds maximum allowed limit.")

(defconstant +tool-timeout+ 10
  "Tool execution exceeded timeout threshold.")

(defconstant +partial-delivery+ 11
  "Partial delivery of chunked message (reserved for future use).")

(defconstant +forced-preemption+ 12
  "Task was forcefully preempted by scheduler.")

(defconstant +ttl-expired+ 13
  "Message time-to-live has expired.")

(defconstant +duplicate-detected+ 14
  "Duplicate request detected via idempotency token.")

(defconstant +already-in-progress+ 15
  "Operation is already in progress (idempotency token maps to non-terminal state).")

(defconstant +internal-error+ 99
  "Internal system error - catch-all for unexpected failures.")

;;; AgentState (spec §8)
;;; Defines agent lifecycle states from initialization to termination.

(defconstant +agent-state-unspecified+ 0
  "Unspecified agent state.")

(defconstant +initializing+ 1
  "Agent is performing initial configuration and setup.")

(defconstant +runnable+ 2
  "Agent is ready to receive task assignments.")

(defconstant +scheduled+ 3
  "Agent has received task assignment but has not begun execution.")

(defconstant +running+ 4
  "Agent is actively executing assigned task.")

(defconstant +waiting+ 5
  "Agent is waiting for external event (user input, service response).")

(defconstant +waiting-resources+ 6
  "Agent is waiting for required resources to become available.")

(defconstant +suspended+ 7
  "Agent execution suspended by scheduler (typically for preemption).")

(defconstant +resumed+ 8
  "Agent transitioning from suspended back to active execution.")

(defconstant +completed+ 9
  "Agent has successfully completed assigned task.")

(defconstant +failed+ 10
  "Agent has encountered unrecoverable error.")

(defconstant +shutting-down+ 11
  "Agent is performing graceful shutdown procedures.")

(defconstant +recovering+ 12
  "Agent is attempting to recover from previous failure.")

;;; CommunicationClass (spec §7.3)
;;; Defines message priority lanes for Quality of Service.

(defconstant +communication-class-unspecified+ 0
  "Unspecified communication class.")

(defconstant +privileged+ 1
  "High-priority, low-latency communication lane.")

(defconstant +standard+ 2
  "Normal priority communication lane for routine traffic.")

(defconstant +bulk+ 3
  "Low-priority, high-volume communication lane.")

;;; DebateIntensity (spec §17)
;;; Defines intensity levels for negotiation and debate protocols.

(defconstant +debate-intensity-unspecified+ 0
  "Unspecified debate intensity.")

(defconstant +lowest+ 1
  "Minimal debate - quick consensus with minimal deliberation.")

(defconstant +low+ 2
  "Light debate - brief consideration of alternatives.")

(defconstant +medium+ 3
  "Moderate debate - balanced deliberation and consensus building.")

(defconstant +high+ 4
  "Intense debate - thorough examination of alternatives.")

(defconstant +highest+ 5
  "Maximum debate intensity - exhaustive deliberation and analysis.")

;;; HitlReasonType (spec §15)
;;; Defines reasons for Human-In-The-Loop escalation.

(defconstant +hitl-reason-unspecified+ 0
  "Unspecified HITL reason.")

(defconstant +conflict+ 1
  "Conflict detected between agents or operations requiring human resolution.")

(defconstant +security-approval+ 2
  "Security-sensitive operation requiring human approval.")

(defconstant +task-escalation+ 3
  "Task complexity or risk level requires human oversight.")

(defconstant +manual-override+ 4
  "Manual operator override requested.")

(defconstant +worktree-override+ 5
  "Worktree operation conflict requiring human resolution.")

(defconstant +debate-deadlock+ 6
  "Negotiation deadlock - agents unable to reach consensus.")

(defconstant +tool-privilege-escalation+ 7
  "Tool requires elevated privileges needing human approval.")

(defconstant +connector-approval+ 8
  "External connector integration requiring human approval.")

;;; EnvelopeState (spec §11)
;;; Defines message envelope lifecycle states.
;;; Lifecycle: SENT -> RECEIVED -> READ -> FULFILLED
;;; Error states: REJECTED, FAILED, TIMED_OUT

(defconstant +envelope-state-unspecified+ 0
  "Unspecified envelope state.")

(defconstant +sent+ 1
  "Envelope has been sent but not yet acknowledged.")

(defconstant +received-envelope+ 2
  "Envelope has been received by transport layer.")

(defconstant +read-envelope+ 3
  "Envelope has been read and parsed by recipient.")

(defconstant +fulfilled-envelope+ 4
  "Envelope processing completed successfully.")

(defconstant +rejected-envelope+ 5
  "Envelope explicitly rejected by recipient.")

(defconstant +failed-envelope+ 6
  "Envelope processing failed due to error.")

(defconstant +timed-out-envelope+ 7
  "Envelope processing exceeded timeout threshold.")

;;; WorktreeState (spec §16)
;;; Defines Git worktree binding states for agents.

(defconstant +worktree-state-unspecified+ 0
  "Unspecified worktree state.")

(defconstant +unbound+ 1
  "Agent has no worktree binding.")

(defconstant +bound-home+ 2
  "Agent bound to its home worktree.")

(defconstant +switch-pending+ 3
  "Worktree switch operation in progress.")

(defconstant +bound-non-home+ 4
  "Agent bound to non-home worktree (temporary binding).")

(defconstant +bind-failed+ 5
  "Worktree binding operation failed.")

;;;; Default Service Endpoints
;;;
;;; Default ports for SW4RM services (spec §5).
;;; Implementations SHOULD use environment variable overrides for deployment flexibility.

(defconstant +default-router-port+ 50051
  "Default port for Router service.")

(defconstant +default-registry-port+ 50052
  "Default port for Registry service.")

(defconstant +default-scheduler-port+ 50053
  "Default port for Scheduler service.")

(defconstant +default-hitl-port+ 50054
  "Default port for HITL service.")

(defconstant +default-worktree-port+ 50055
  "Default port for Worktree service.")

(defconstant +default-tool-port+ 50056
  "Default port for Tool service.")

(defconstant +default-connector-port+ 50057
  "Default port for Connector service.")

(defconstant +default-negotiation-port+ 50058
  "Default port for Negotiation service.")

(defconstant +default-reasoning-port+ 50059
  "Default port for Reasoning service.")

(defconstant +default-logging-port+ 50060
  "Default port for Logging service.")

(defparameter *default-host* "localhost"
  "Default host for all services in development environments.")

;;;; Default Timeouts and Limits

(defparameter *default-timeout-ms* 30000
  "Default timeout for operations in milliseconds (30 seconds).")

(defparameter *default-retry-max-attempts* 3
  "Default maximum number of retry attempts for failed operations.")

(defparameter *default-heartbeat-interval-ms* 30000
  "Default heartbeat interval in milliseconds (30 seconds).")

(defparameter *default-ack-timeout-ms* 10000
  "Default acknowledgement timeout in milliseconds (10 seconds, per spec §11).")

(defparameter *default-activity-buffer-size* 10000
  "Default maximum entries in activity buffer (per spec §10.1).")

(defparameter *default-activity-buffer-per-agent* 100
  "Default maximum entries per agent in activity buffer (per spec §10.1).")

(defparameter *default-deduplication-window-seconds* 3600
  "Default idempotency token cache duration in seconds (1 hour, per spec §11.2).")
