import { describe, it, expect } from 'vitest';
import { mapGrpcStatusToErrorCode, ErrorCode } from '../src/internal/errorMapping.js';

describe('error mapping', () => {
  it('maps RESOURCE_EXHAUSTED to BUFFER_FULL', () => {
    expect(mapGrpcStatusToErrorCode(8)).toBe(ErrorCode.BUFFER_FULL);
  });
  it('maps DEADLINE_EXCEEDED to ACK_TIMEOUT', () => {
    expect(mapGrpcStatusToErrorCode(4)).toBe(ErrorCode.ACK_TIMEOUT);
  });
  it('maps PERMISSION_DENIED to PERMISSION_DENIED', () => {
    expect(mapGrpcStatusToErrorCode(7)).toBe(ErrorCode.PERMISSION_DENIED);
  });
});

