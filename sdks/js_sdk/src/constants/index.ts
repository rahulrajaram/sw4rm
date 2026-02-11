// Protocol constants mirroring common.proto enums.
//
// These are numeric values to keep the SDK usable without generated stubs
// at import time. Values must match common.proto definitions.

// Re-export ErrorCode and MessageType from their existing locations
export { ErrorCode } from '../internal/errorMapping.js';
export { MessageType } from '../internal/envelope.js';

/**
 * CommunicationClass constants (spec section 7.3).
 */
export enum CommunicationClass {
  COMM_CLASS_UNSPECIFIED = 0,
  PRIVILEGED = 1,
  STANDARD = 2,
  BULK = 3,
}

/**
 * DebateIntensity constants (spec section 17).
 */
export enum DebateIntensity {
  DEBATE_INTENSITY_UNSPECIFIED = 0,
  LOWEST = 1,
  LOW = 2,
  MEDIUM = 3,
  HIGH = 4,
  HIGHEST = 5,
}

/**
 * HitlReasonType constants (spec section 15).
 */
export enum HitlReasonType {
  HITL_REASON_UNSPECIFIED = 0,
  CONFLICT = 1,
  SECURITY_APPROVAL = 2,
  TASK_ESCALATION = 3,
  MANUAL_OVERRIDE = 4,
  WORKTREE_OVERRIDE = 5,
  DEBATE_DEADLOCK = 6,
  TOOL_PRIVILEGE_ESCALATION = 7,
  CONNECTOR_APPROVAL = 8,
}

/**
 * AgentState constants (spec section 8).
 * Re-exported from agentState.ts for convenience.
 */
export { AgentState } from '../runtime/agentState.js';

/**
 * AckStage constants.
 */
export enum AckStage {
  ACK_STAGE_UNSPECIFIED = 0,
  RECEIVED = 1,
  READ = 2,
  FULFILLED = 3,
  REJECTED = 4,
  FAILED = 5,
  TIMED_OUT = 6,
}

/**
 * EnvelopeState lifecycle constants.
 *
 * Tracks the lifecycle of an envelope through the system:
 * SENT -> RECEIVED -> READ -> FULFILLED/REJECTED/FAILED/TIMED_OUT
 */
export enum EnvelopeState {
  ENVELOPE_STATE_UNSPECIFIED = 0,
  SENT = 1,
  RECEIVED = 2,
  READ = 3,
  FULFILLED = 4,
  REJECTED = 5,
  FAILED = 6,
  TIMED_OUT = 7,
}

/**
 * WorktreeState constants (spec section 16).
 */
export enum WorktreeStateEnum {
  WORKTREE_STATE_UNSPECIFIED = 0,
  UNBOUND = 1,
  BOUND_HOME = 2,
  SWITCH_PENDING = 3,
  BOUND_NON_HOME = 4,
  BIND_FAILED = 5,
}

/**
 * Default timeout for acknowledgement in milliseconds.
 */
export const DEFAULT_ACK_TIMEOUT_MS = 10000;

/**
 * Deduplication window in seconds.
 */
export const DEDUP_WINDOW_S = 3600;

/**
 * Check if an envelope state is terminal (no further transitions expected).
 *
 * Terminal states: FULFILLED, REJECTED, FAILED, TIMED_OUT
 */
export function isTerminalEnvelopeState(state: EnvelopeState): boolean {
  return (
    state === EnvelopeState.FULFILLED ||
    state === EnvelopeState.REJECTED ||
    state === EnvelopeState.FAILED ||
    state === EnvelopeState.TIMED_OUT
  );
}

/**
 * Update the state of an envelope object.
 */
export function updateEnvelopeState<T extends { state?: number }>(
  envelope: T,
  newState: EnvelopeState
): T {
  (envelope as any).state = newState;
  return envelope;
}
