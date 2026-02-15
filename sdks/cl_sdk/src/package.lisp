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
   #:+overloaded+
   #:+redirect+
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
   #:+agent-failed+
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
   #:generate-uuid

   #:sequence-tracker
   #:make-sequence-tracker
   #:next-sequence)

  ;; Negotiation events
  (:export
   #:make-event-emitter
   #:on
   #:off
   #:emit
   #:listener-count
   #:get-history
   #:clear-history
   #:clear-listeners
   #:negotiation-event
   #:negotiation-event-event-id
   #:negotiation-event-event-type
   #:negotiation-event-room-id
   #:negotiation-event-agent-id
   #:negotiation-event-timestamp
   #:negotiation-event-payload
   #:make-participant-joined-event
   #:make-participant-left-event
   #:make-proposal-submitted-event
   #:make-critique-added-event
   #:make-vote-cast-event
   #:make-round-complete-event
   #:make-approved-event
   #:make-rejected-event)

  ;; Voting
  (:export
   #:make-vote
   #:vote-agent-id
   #:vote-choice
   #:vote-confidence
   #:vote-timestamp
   #:vote-metadata
   #:vote-to-plist
   #:make-vote-from-plist
   #:aggregate
   #:strategy-name
   #:majority-vote-strategy
   #:confidence-weighted-strategy
   #:simple-average-strategy
   #:borda-count-strategy
   #:voting-aggregator
   #:run-vote
   #:set-strategy
   #:get-round-history
   #:voting-round
   #:voting-round-round-id
   #:voting-round-strategy-name
   #:voting-round-votes)

  ;; Secrets
  (:export
   #:make-file-backend
   #:make-env-backend
   #:make-default-resolver
   #:get-secret
   #:set-secret
   #:delete-secret
   #:list-secrets
   #:add-backend
   #:remove-backend
   #:resolve-secret
   #:store-secret
   #:secret-resolver
   #:secret-not-found
   #:secret-key
   #:secret-backend-error)

  ;; Gateway redirect emitter (SW4-005 local gateway helper)
  (:export
   #:+registration-type-standard-agent+
   #:+registration-type-swarm-gateway+
   #:+default-peer-liveness-threshold-ms+
   #:+non-serving-agent-states+
   #:gateway-peer-descriptor
   #:make-gateway-peer-descriptor
   #:gateway-peer-descriptor-agent-id
   #:gateway-peer-descriptor-registration-type
   #:gateway-peer-descriptor-capabilities
   #:gateway-redirect-emitter
   #:set-peer-descriptors
   #:update-peer-runtime-state
   #:touch-peer-heartbeat
   #:record-peer-overloaded
   #:emit-overloaded-response)

  ;; Handoff client (SW4-004/SW4-005 local surface)
  (:export
   #:handoff-client
   #:+default-max-retries-on-overloaded+
   #:+default-initial-backoff-ms+
   #:+default-backoff-multiplier+
   #:+default-max-backoff-ms+
   #:+default-allow-spillover-routing+
   #:+default-max-redirects+
   #:delegate-to-swarm
   #:+min-cancel-grace-period-ms+
   #:handoff-default-delegation-policy
   #:initiate-handoff
   #:accept-handoff
   #:reject-handoff
   #:reject-handoff-with-options
   #:complete-handoff
   #:get-pending-handoffs
   #:get-handoff-status
   #:register-child-delegation
   #:cancel-delegation
   #:cancelled-delegation-p
   #:cancellation-grace-expired-p
   #:forced-preemption-error-code
   #:collect-forced-preemptions))
