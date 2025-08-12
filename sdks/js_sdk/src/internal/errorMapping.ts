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

