;;;; package.lisp - Package definition for SW4RM SDK

(defpackage #:sw4rm-sdk
  (:use #:cl #:alexandria)
  (:documentation "SW4RM Protocol SDK for Common Lisp.

This package provides a full peer implementation of the SW4RM protocol for
interruptible, message-driven agent coordination.

The SDK implements:
- Message envelope construction with Three-ID model (message_id, correlation_id, idempotency_token)
- Comprehensive error condition hierarchy with restart support
- Agent lifecycle state machine (INITIALIZING -> RUNNABLE -> SCHEDULED -> RUNNING -> COMPLETED/FAILED)
- Activity buffer for tracking in-flight operations
- Idempotency guarantees via token-based deduplication
- Worktree state management for isolated Git operations
- Negotiation protocol support for multi-agent coordination
- Policy-based access control and audit trails
- gRPC client infrastructure for all SW4RM services

See documentation/protocol/spec.md for the canonical protocol specification.")

  ;; Constants - All protocol enums and defaults
  (:export
   ;; MessageType enum
   #:+message-type-unspecified+
   #:+control+
   #:+data+
   #:+heartbeat+
   #:+notification+
   #:+acknowledgement+
   #:+hitl-invocation+
   #:+worktree-control+
   #:+negotiation+
   #:+tool-call+
   #:+tool-result+
   #:+tool-error+

   ;; AckStage enum
   #:+ack-stage-unspecified+
   #:+received+
   #:+read+
   #:+fulfilled+
   #:+rejected+
   #:+failed+
   #:+timed-out+

   ;; ErrorCode enum
   #:+error-code-unspecified+
   #:+buffer-full+
   #:+no-route+
   #:+ack-timeout+
   #:+agent-unavailable+
   #:+agent-shutdown+
   #:+validation-error+
   #:+permission-denied+
   #:+unsupported-message-type+
   #:+oversize-payload+
   #:+tool-timeout+
   #:+partial-delivery+
   #:+forced-preemption+
   #:+ttl-expired+
   #:+duplicate-detected+
   #:+already-in-progress+
   #:+internal-error+

   ;; AgentState enum
   #:+agent-state-unspecified+
   #:+initializing+
   #:+runnable+
   #:+scheduled+
   #:+running+
   #:+waiting+
   #:+waiting-resources+
   #:+suspended+
   #:+resumed+
   #:+completed+
   #:+failed+
   #:+shutting-down+
   #:+recovering+

   ;; CommunicationClass enum
   #:+communication-class-unspecified+
   #:+privileged+
   #:+standard+
   #:+bulk+

   ;; DebateIntensity enum
   #:+debate-intensity-unspecified+
   #:+lowest+
   #:+low+
   #:+medium+
   #:+high+
   #:+highest+

   ;; HitlReasonType enum
   #:+hitl-reason-unspecified+
   #:+conflict+
   #:+security-approval+
   #:+task-escalation+
   #:+manual-override+
   #:+worktree-override+
   #:+debate-deadlock+
   #:+tool-privilege-escalation+
   #:+connector-approval+

   ;; EnvelopeState enum
   #:+envelope-state-unspecified+
   #:+sent+
   #:+received-envelope+
   #:+read-envelope+
   #:+fulfilled-envelope+
   #:+rejected-envelope+
   #:+failed-envelope+
   #:+timed-out-envelope+

   ;; WorktreeState enum
   #:+worktree-state-unspecified+
   #:+unbound+
   #:+bound-home+
   #:+switch-pending+
   #:+bound-non-home+
   #:+bind-failed+

   ;; Default ports and addresses
   #:+default-router-port+
   #:+default-registry-port+
   #:+default-scheduler-port+
   #:+default-hitl-port+
   #:+default-worktree-port+
   #:+default-tool-port+
   #:+default-connector-port+
   #:+default-negotiation-port+
   #:+default-reasoning-port+
   #:+default-logging-port+
   #:*default-host*)

  ;; Errors - Condition hierarchy
  (:export
   #:sw4rm-error
   #:sw4rm-error-message
   #:sw4rm-error-error-code

   #:rpc-error
   #:rpc-error-status-code
   #:rpc-error-details

   #:validation-error
   #:validation-error-field
   #:validation-error-constraint

   #:state-transition-error
   #:state-transition-error-from-state
   #:state-transition-error-to-state
   #:state-transition-error-allowed-transitions

   #:timeout-error
   #:timeout-error-operation
   #:timeout-error-timeout-ms

   #:buffer-full-error
   #:buffer-full-error-current-size
   #:buffer-full-error-max-size

   #:negotiation-error
   #:negotiation-error-negotiation-id
   #:negotiation-error-phase

   #:worktree-error
   #:worktree-error-worktree-id
   #:worktree-error-state

   #:duplicate-detected-error
   #:duplicate-detected-error-idempotency-token

   ;; Error handling macros
   #:with-sw4rm-error-handling
   #:invoke-sw4rm-restart)

  ;; Config - Configuration structures
  (:export
   #:endpoints
   #:make-endpoints
   #:endpoints-router
   #:endpoints-registry
   #:endpoints-scheduler
   #:endpoints-hitl
   #:endpoints-worktree
   #:endpoints-tool
   #:endpoints-connector
   #:endpoints-negotiation
   #:endpoints-reasoning
   #:endpoints-logging

   #:agent-config
   #:make-agent-config
   #:agent-config-agent-id
   #:agent-config-name
   #:agent-config-description
   #:agent-config-version
   #:agent-config-capabilities
   #:agent-config-endpoints
   #:agent-config-timeout-ms
   #:agent-config-retry-max-attempts
   #:agent-config-heartbeat-interval-ms

   #:make-default-endpoints
   #:load-config-from-env)

  ;; Envelope - Message construction
  (:export
   #:make-envelope
   #:update-envelope-state
   #:terminal-state-p
   #:compute-deterministic-hash
   #:make-idempotency-token

   #:sequence-tracker
   #:make-sequence-tracker
   #:next-sequence))
