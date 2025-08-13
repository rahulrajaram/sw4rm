import { ErrorCode } from './errorMapping.js';

export type GrpcErrorInfo = { status?: number; message?: string; details?: string };

export type ErrorMapRule = (err: GrpcErrorInfo) => ErrorCode | undefined;

export class ErrorCodeMapper {
  private rules: ErrorMapRule[] = [];
  constructor(rules?: ErrorMapRule[]) {
    if (rules) this.rules = [...rules];
  }
  addRule(rule: ErrorMapRule) { this.rules.push(rule); }
  map(err: GrpcErrorInfo, fallback: (status?: number) => ErrorCode): ErrorCode {
    for (const r of this.rules) {
      const code = r(err);
      if (code !== undefined) return code;
    }
    return fallback(err.status);
  }
}

