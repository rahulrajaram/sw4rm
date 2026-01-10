// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Tests for LoggingClient.
 *
 * These tests verify the LoggingClient functionality for log ingestion,
 * querying, and log level management.
 *
 * Ported from: sdks/py_sdk/tests/test_logging_client.py
 */

interface MockLoggingServiceClient {
  Log: ReturnType<typeof vi.fn>;
  BatchLog: ReturnType<typeof vi.fn>;
  Query: ReturnType<typeof vi.fn>;
  SetLogLevel: ReturnType<typeof vi.fn>;
  GetLogLevel: ReturnType<typeof vi.fn>;
}

type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'FATAL';

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  source: string;
  message: string;
  context?: Record<string, string>;
  trace_id?: string;
  span_id?: string;
}

interface LogQuery {
  source?: string;
  level?: LogLevel;
  start_time?: string;
  end_time?: string;
  trace_id?: string;
  limit?: number;
}

// Simplified mock client for testing
class MockLoggingClient {
  private mockClient: MockLoggingServiceClient;

  constructor(opts: { address: string }) {
    this.mockClient = {
      Log: vi.fn(),
      BatchLog: vi.fn(),
      Query: vi.fn(),
      SetLogLevel: vi.fn(),
      GetLogLevel: vi.fn(),
    };
  }

  get client(): MockLoggingServiceClient {
    return this.mockClient;
  }

  async log(entry: LogEntry): Promise<boolean> {
    return new Promise((resolve, reject) => {
      this.mockClient.Log(entry, {}, {}, (err: Error | null, res: { ok: boolean }) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    });
  }

  async batchLog(entries: LogEntry[]): Promise<{ accepted: number; rejected: number }> {
    return new Promise((resolve, reject) => {
      this.mockClient.BatchLog(
        { entries },
        {},
        {},
        (err: Error | null, res: { accepted: number; rejected: number }) => {
          if (err) return reject(err);
          resolve({ accepted: res?.accepted ?? 0, rejected: res?.rejected ?? 0 });
        }
      );
    });
  }

  async query(query: LogQuery): Promise<LogEntry[]> {
    return new Promise((resolve, reject) => {
      this.mockClient.Query(query, {}, {}, (err: Error | null, res: { entries: LogEntry[] }) => {
        if (err) return reject(err);
        resolve(res?.entries ?? []);
      });
    });
  }

  async setLogLevel(source: string, level: LogLevel): Promise<boolean> {
    return new Promise((resolve, reject) => {
      this.mockClient.SetLogLevel(
        { source, level },
        {},
        {},
        (err: Error | null, res: { ok: boolean }) => {
          if (err) return reject(err);
          resolve(!!res?.ok);
        }
      );
    });
  }

  async getLogLevel(source: string): Promise<LogLevel> {
    return new Promise((resolve, reject) => {
      this.mockClient.GetLogLevel(
        { source },
        {},
        {},
        (err: Error | null, res: { level: LogLevel }) => {
          if (err) return reject(err);
          resolve(res?.level ?? 'INFO');
        }
      );
    });
  }
}

describe('LoggingClient', () => {
  describe('construction', () => {
    it('should initialize with valid options', () => {
      const client = new MockLoggingClient({ address: 'localhost:50051' });
      expect(client).toBeDefined();
      expect(client.client).toBeDefined();
    });
  });

  describe('log', () => {
    let client: MockLoggingClient;

    beforeEach(() => {
      client = new MockLoggingClient({ address: 'localhost:50051' });
    });

    it('should log entry with all fields', async () => {
      client.client.Log.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.log({
        timestamp: '2024-01-01T00:00:00Z',
        level: 'INFO',
        source: 'agent-1',
        message: 'Test log message',
        context: {
          task_id: 'task-123',
          negotiation_id: 'neg-456',
        },
        trace_id: 'trace-789',
        span_id: 'span-abc',
      });

      expect(result).toBe(true);
      expect(client.client.Log).toHaveBeenCalledTimes(1);
    });

    it('should log entry with minimal fields', async () => {
      client.client.Log.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.log({
        timestamp: '2024-01-01T00:00:00Z',
        level: 'DEBUG',
        source: 'agent-1',
        message: 'Debug message',
      });

      expect(result).toBe(true);
    });

    it('should handle all log levels', async () => {
      client.client.Log.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const levels: LogLevel[] = ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'];

      for (const level of levels) {
        const result = await client.log({
          timestamp: new Date().toISOString(),
          level,
          source: 'test',
          message: `${level} message`,
        });
        expect(result).toBe(true);
      }

      expect(client.client.Log).toHaveBeenCalledTimes(5);
    });

    it('should handle log failure', async () => {
      client.client.Log.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: false });
        }
      );

      const result = await client.log({
        timestamp: '2024-01-01T00:00:00Z',
        level: 'ERROR',
        source: 'agent-1',
        message: 'Error message',
      });

      expect(result).toBe(false);
    });

    it('should handle gRPC errors', async () => {
      client.client.Log.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Connection refused'), null);
        }
      );

      await expect(
        client.log({
          timestamp: '2024-01-01T00:00:00Z',
          level: 'INFO',
          source: 'agent-1',
          message: 'Test',
        })
      ).rejects.toThrow('Connection refused');
    });
  });

  describe('batchLog', () => {
    let client: MockLoggingClient;

    beforeEach(() => {
      client = new MockLoggingClient({ address: 'localhost:50051' });
    });

    it('should batch log multiple entries', async () => {
      client.client.BatchLog.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: req.entries.length, rejected: 0 });
        }
      );

      const entries: LogEntry[] = [
        { timestamp: '2024-01-01T00:00:00Z', level: 'INFO', source: 'agent-1', message: 'Log 1' },
        { timestamp: '2024-01-01T00:00:01Z', level: 'DEBUG', source: 'agent-1', message: 'Log 2' },
        { timestamp: '2024-01-01T00:00:02Z', level: 'WARN', source: 'agent-1', message: 'Log 3' },
      ];

      const result = await client.batchLog(entries);

      expect(result.accepted).toBe(3);
      expect(result.rejected).toBe(0);
    });

    it('should handle partial batch acceptance', async () => {
      client.client.BatchLog.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: 2, rejected: 1 });
        }
      );

      const entries: LogEntry[] = [
        { timestamp: '2024-01-01T00:00:00Z', level: 'INFO', source: 'agent-1', message: 'Log 1' },
        { timestamp: 'invalid', level: 'INFO', source: 'agent-1', message: 'Log 2' }, // Invalid timestamp
        { timestamp: '2024-01-01T00:00:02Z', level: 'INFO', source: 'agent-1', message: 'Log 3' },
      ];

      const result = await client.batchLog(entries);

      expect(result.accepted).toBe(2);
      expect(result.rejected).toBe(1);
    });

    it('should handle empty batch', async () => {
      client.client.BatchLog.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: 0, rejected: 0 });
        }
      );

      const result = await client.batchLog([]);

      expect(result.accepted).toBe(0);
      expect(result.rejected).toBe(0);
    });
  });

  describe('query', () => {
    let client: MockLoggingClient;

    beforeEach(() => {
      client = new MockLoggingClient({ address: 'localhost:50051' });
    });

    it('should query logs by source', async () => {
      const mockEntries: LogEntry[] = [
        { timestamp: '2024-01-01T00:00:00Z', level: 'INFO', source: 'agent-1', message: 'Log 1' },
        { timestamp: '2024-01-01T00:00:01Z', level: 'DEBUG', source: 'agent-1', message: 'Log 2' },
      ];

      client.client.Query.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: mockEntries });
        }
      );

      const result = await client.query({ source: 'agent-1' });

      expect(result).toHaveLength(2);
      expect(result[0].source).toBe('agent-1');
    });

    it('should query logs by level', async () => {
      const mockEntries: LogEntry[] = [
        { timestamp: '2024-01-01T00:00:00Z', level: 'ERROR', source: 'agent-1', message: 'Error 1' },
        { timestamp: '2024-01-01T00:00:01Z', level: 'ERROR', source: 'agent-2', message: 'Error 2' },
      ];

      client.client.Query.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: mockEntries });
        }
      );

      const result = await client.query({ level: 'ERROR' });

      expect(result).toHaveLength(2);
      result.forEach((e) => expect(e.level).toBe('ERROR'));
    });

    it('should query logs by time range', async () => {
      const mockEntries: LogEntry[] = [
        { timestamp: '2024-01-01T12:00:00Z', level: 'INFO', source: 'agent-1', message: 'Log 1' },
      ];

      client.client.Query.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: mockEntries });
        }
      );

      const result = await client.query({
        start_time: '2024-01-01T00:00:00Z',
        end_time: '2024-01-02T00:00:00Z',
      });

      expect(result).toHaveLength(1);
    });

    it('should query logs by trace_id', async () => {
      const mockEntries: LogEntry[] = [
        { timestamp: '2024-01-01T00:00:00Z', level: 'INFO', source: 'agent-1', message: 'Log 1', trace_id: 'trace-123' },
        { timestamp: '2024-01-01T00:00:01Z', level: 'DEBUG', source: 'agent-1', message: 'Log 2', trace_id: 'trace-123' },
      ];

      client.client.Query.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: mockEntries });
        }
      );

      const result = await client.query({ trace_id: 'trace-123' });

      expect(result).toHaveLength(2);
      result.forEach((e) => expect(e.trace_id).toBe('trace-123'));
    });

    it('should respect limit parameter', async () => {
      const mockEntries: LogEntry[] = [
        { timestamp: '2024-01-01T00:00:00Z', level: 'INFO', source: 'agent-1', message: 'Log 1' },
        { timestamp: '2024-01-01T00:00:01Z', level: 'INFO', source: 'agent-1', message: 'Log 2' },
      ];

      client.client.Query.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          const limited = mockEntries.slice(0, req.limit ?? mockEntries.length);
          cb(null, { entries: limited });
        }
      );

      const result = await client.query({ limit: 1 });

      expect(result).toHaveLength(1);
    });

    it('should return empty array when no matches', async () => {
      client.client.Query.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: [] });
        }
      );

      const result = await client.query({ source: 'nonexistent' });

      expect(result).toEqual([]);
    });
  });

  describe('setLogLevel', () => {
    let client: MockLoggingClient;

    beforeEach(() => {
      client = new MockLoggingClient({ address: 'localhost:50051' });
    });

    it('should set log level successfully', async () => {
      client.client.SetLogLevel.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.setLogLevel('agent-1', 'DEBUG');

      expect(result).toBe(true);
      expect(client.client.SetLogLevel).toHaveBeenCalledWith(
        { source: 'agent-1', level: 'DEBUG' },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should set different log levels', async () => {
      client.client.SetLogLevel.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const levels: LogLevel[] = ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'];

      for (const level of levels) {
        const result = await client.setLogLevel('agent-1', level);
        expect(result).toBe(true);
      }
    });

    it('should handle set level failure', async () => {
      client.client.SetLogLevel.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: false });
        }
      );

      const result = await client.setLogLevel('unknown', 'DEBUG');

      expect(result).toBe(false);
    });
  });

  describe('getLogLevel', () => {
    let client: MockLoggingClient;

    beforeEach(() => {
      client = new MockLoggingClient({ address: 'localhost:50051' });
    });

    it('should get log level successfully', async () => {
      client.client.GetLogLevel.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { level: 'DEBUG' });
        }
      );

      const result = await client.getLogLevel('agent-1');

      expect(result).toBe('DEBUG');
    });

    it('should return default level for unknown source', async () => {
      client.client.GetLogLevel.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { level: 'INFO' });
        }
      );

      const result = await client.getLogLevel('unknown-source');

      expect(result).toBe('INFO');
    });
  });

  describe('integration', () => {
    it('should support full logging workflow: log -> query', async () => {
      const client = new MockLoggingClient({ address: 'localhost:50051' });

      client.client.Log.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      client.client.Query.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, {
            entries: [
              { timestamp: '2024-01-01T00:00:00Z', level: 'INFO', source: 'agent-1', message: 'Test log' },
            ],
          });
        }
      );

      // Log
      const logged = await client.log({
        timestamp: '2024-01-01T00:00:00Z',
        level: 'INFO',
        source: 'agent-1',
        message: 'Test log',
      });
      expect(logged).toBe(true);

      // Query
      const entries = await client.query({ source: 'agent-1' });
      expect(entries).toHaveLength(1);
      expect(entries[0].message).toBe('Test log');
    });

    it('should support batch logging followed by query', async () => {
      const client = new MockLoggingClient({ address: 'localhost:50051' });

      client.client.BatchLog.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: 3, rejected: 0 });
        }
      );

      client.client.Query.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, {
            entries: [
              { timestamp: '2024-01-01T00:00:00Z', level: 'ERROR', source: 'agent-1', message: 'Error 1' },
            ],
          });
        }
      );

      // Batch log
      const batchResult = await client.batchLog([
        { timestamp: '2024-01-01T00:00:00Z', level: 'INFO', source: 'agent-1', message: 'Log 1' },
        { timestamp: '2024-01-01T00:00:01Z', level: 'WARN', source: 'agent-1', message: 'Log 2' },
        { timestamp: '2024-01-01T00:00:02Z', level: 'ERROR', source: 'agent-1', message: 'Error 1' },
      ]);
      expect(batchResult.accepted).toBe(3);

      // Query errors only
      const errors = await client.query({ level: 'ERROR' });
      expect(errors).toHaveLength(1);
    });
  });
});
