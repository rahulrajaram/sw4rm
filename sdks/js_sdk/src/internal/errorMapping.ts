// Spec-compliant error mapping and typed error
// Maps gRPC status codes to sw4rm.common.ErrorCode semantics

export enum ErrorCode {
  ERROR_CODE_UNSPECIFIED = 0,
  BUFFER_FULL = 1,
  NO_ROUTE = 2,
  ACK_TIMEOUT = 3,
  AGENT_UNAVAILABLE = 4,
  AGENT_SHUTDOWN = 5,
  VALIDATION_ERROR = 6,
  PERMISSION_DENIED = 7,
  UNSUPPORTED_MESSAGE_TYPE = 8,
  OVERSIZE_PAYLOAD = 9,
  TOOL_TIMEOUT = 10,
  PARTIAL_DELIVERY = 11,
  FORCED_PREEMPTION = 12,
  TTL_EXPIRED = 13,
  DUPLICATE_DETECTED = 14,
  ALREADY_IN_PROGRESS = 15,
  // SW4-004 Inter-Swarm Composition
  OVERLOADED = 16,
  // SW4-005 Spillover Routing
  REDIRECT = 20,
  INTERNAL_ERROR = 99,
}

export class Sw4rmError extends Error {
  readonly code: ErrorCode;
  readonly grpcStatus?: number;
  readonly details?: string;
  constructor(message: string, code: ErrorCode, opts?: { grpcStatus?: number; details?: string }) {
    super(message);
    this.name = 'Sw4rmError';
    this.code = code;
    this.grpcStatus = opts?.grpcStatus;
    this.details = opts?.details;
  }
}

/**
 * Thrown when input validation fails.
 * Default error code: VALIDATION_ERROR
 */
export class ValidationError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.VALIDATION_ERROR, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'ValidationError';
  }
}

/**
 * Thrown when an operation times out.
 * Default error code: ACK_TIMEOUT
 */
export class TimeoutError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.ACK_TIMEOUT, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'TimeoutError';
  }
}

/**
 * Thrown when an invalid state transition is attempted.
 * Default error code: INTERNAL_ERROR
 */
export class StateTransitionError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.INTERNAL_ERROR, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'StateTransitionError';
  }
}

/**
 * Thrown when negotiation fails.
 * Default error code: INTERNAL_ERROR
 */
export class NegotiationError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.INTERNAL_ERROR, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'NegotiationError';
  }
}

/**
 * Thrown when the activity buffer is full.
 * Default error code: BUFFER_FULL
 */
export class BufferFullError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.BUFFER_FULL, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'BufferFullError';
  }
}

/**
 * Thrown when no route to destination exists.
 * Default error code: NO_ROUTE
 */
export class RouteError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.NO_ROUTE, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'RouteError';
  }
}

/**
 * Thrown when permission is denied.
 * Default error code: PERMISSION_DENIED
 */
export class PermissionError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.PERMISSION_DENIED, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'PermissionError';
  }
}

/**
 * Thrown when a duplicate request is detected.
 * Default error code: DUPLICATE_DETECTED
 */
export class DuplicateDetectedError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.DUPLICATE_DETECTED, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'DuplicateDetectedError';
  }
}

// Lightweight constants to avoid importing @grpc/grpc-js types here
const GrpcStatus = {
  OK: 0,
  CANCELLED: 1,
  UNKNOWN: 2,
  INVALID_ARGUMENT: 3,
  DEADLINE_EXCEEDED: 4,
  NOT_FOUND: 5,
  ALREADY_EXISTS: 6,
  PERMISSION_DENIED: 7,
  RESOURCE_EXHAUSTED: 8,
  FAILED_PRECONDITION: 9,
  ABORTED: 10,
  OUT_OF_RANGE: 11,
  UNIMPLEMENTED: 12,
  INTERNAL: 13,
  UNAVAILABLE: 14,
  DATA_LOSS: 15,
  UNAUTHENTICATED: 16,
} as const;

/**
 * Thrown when an agent is forcibly preempted by the scheduler.
 * Default error code: FORCED_PREEMPTION
 */
export class PreemptionError extends Sw4rmError {
  readonly agentId: string;
  readonly reason: string;
  constructor(agentId: string, reason: string, code: ErrorCode = ErrorCode.FORCED_PREEMPTION, opts?: { grpcStatus?: number; details?: string }) {
    super(`Agent ${agentId} preempted: ${reason}`, code, opts);
    this.name = 'PreemptionError';
    this.agentId = agentId;
    this.reason = reason;
  }
}

/**
 * Thrown when a worktree operation fails (bind, switch, etc.).
 * Default error code: INTERNAL_ERROR
 */
export class WorktreeError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.INTERNAL_ERROR, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'WorktreeError';
  }
}

/**
 * Thrown when an action violates a configured policy.
 * Default error code: PERMISSION_DENIED
 */
export class PolicyViolationError extends Sw4rmError {
  constructor(message: string, code: ErrorCode = ErrorCode.PERMISSION_DENIED, opts?: { grpcStatus?: number; details?: string }) {
    super(message, code, opts);
    this.name = 'PolicyViolationError';
  }
}

export function mapGrpcStatusToErrorCode(status: number): ErrorCode {
  switch (status) {
    case GrpcStatus.OK:
      return ErrorCode.ERROR_CODE_UNSPECIFIED;
    case GrpcStatus.RESOURCE_EXHAUSTED:
      return ErrorCode.BUFFER_FULL; // back-pressure
    case GrpcStatus.NOT_FOUND:
      return ErrorCode.NO_ROUTE; // no route to agent/service
    case GrpcStatus.DEADLINE_EXCEEDED:
      return ErrorCode.ACK_TIMEOUT; // generic timeout; specific TTL may come from server
    case GrpcStatus.UNAVAILABLE:
      return ErrorCode.AGENT_UNAVAILABLE;
    case GrpcStatus.PERMISSION_DENIED:
    case GrpcStatus.UNAUTHENTICATED:
      return ErrorCode.PERMISSION_DENIED;
    case GrpcStatus.INVALID_ARGUMENT:
    case GrpcStatus.OUT_OF_RANGE:
    case GrpcStatus.FAILED_PRECONDITION:
      return ErrorCode.VALIDATION_ERROR;
    case GrpcStatus.UNIMPLEMENTED:
      return ErrorCode.UNSUPPORTED_MESSAGE_TYPE;
    case GrpcStatus.ABORTED:
    case GrpcStatus.INTERNAL:
    case GrpcStatus.DATA_LOSS:
    case GrpcStatus.CANCELLED:
    case GrpcStatus.ALREADY_EXISTS:
    case GrpcStatus.UNKNOWN:
    default:
      return ErrorCode.INTERNAL_ERROR;
  }
}
