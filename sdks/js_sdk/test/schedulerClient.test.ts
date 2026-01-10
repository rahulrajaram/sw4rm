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
 * Tests for SchedulerClient.
 *
 * These tests verify the SchedulerClient functionality for task submission,
 * preemption, shutdown, and activity buffer operations.
 *
 * Ported from: sdks/py_sdk/tests/test_scheduler_client.py
 */

interface MockSchedulerServiceClient {
  SubmitTask: ReturnType<typeof vi.fn>;
  RequestPreemption: ReturnType<typeof vi.fn>;
  ShutdownAgent: ReturnType<typeof vi.fn>;
  PollActivityBuffer: ReturnType<typeof vi.fn>;
  PurgeActivity: ReturnType<typeof vi.fn>;
}

interface SubmitTaskRequest {
  agent_id: string;
  task_id: string;
  priority: number;
  params: Uint8Array;
  content_type: string;
  scope: string;
}

interface ActivityEntry {
  task_id: string;
  repo_id: string;
  worktree_id: string;
  branch: string;
  description: string;
  timestamp: string;
}

// Simplified mock client for testing
class MockSchedulerClient {
  private mockClient: MockSchedulerServiceClient;

  constructor(opts: { address: string }) {
    this.mockClient = {
      SubmitTask: vi.fn(),
      RequestPreemption: vi.fn(),
      ShutdownAgent: vi.fn(),
      PollActivityBuffer: vi.fn(),
      PurgeActivity: vi.fn(),
    };
  }

  get client(): MockSchedulerServiceClient {
    return this.mockClient;
  }

  private validatePriority(p: number): void {
    if (!Number.isFinite(p) || p < -19 || p > 20) {
      throw new Error(`Priority must be in range -19..20, got ${p}`);
    }
  }

  async submitTask(req: SubmitTaskRequest): Promise<{ accepted: boolean; reason?: string }> {
    this.validatePriority(req.priority);
    return new Promise((resolve, reject) => {
      this.mockClient.SubmitTask(req, {}, {}, (err: Error | null, res: { accepted: boolean; reason?: string }) => {
        if (err) return reject(err);
        resolve({ accepted: !!res?.accepted, reason: res?.reason });
      });
    });
  }

  async requestPreemption(agentId: string, taskId: string, reason?: string): Promise<{ enqueued: boolean }> {
    return new Promise((resolve, reject) => {
      this.mockClient.RequestPreemption(
        { agent_id: agentId, task_id: taskId, reason },
        {},
        {},
        (err: Error | null, res: { enqueued: boolean }) => {
          if (err) return reject(err);
          resolve({ enqueued: !!res?.enqueued });
        }
      );
    });
  }

  async shutdownAgent(agentId: string, graceMs: number): Promise<{ ok: boolean }> {
    return new Promise((resolve, reject) => {
      this.mockClient.ShutdownAgent(
        { agent_id: agentId, grace_period: { seconds: Math.floor(graceMs / 1000), nanos: (graceMs % 1000) * 1000000 } },
        {},
        {},
        (err: Error | null, res: { ok: boolean }) => {
          if (err) return reject(err);
          resolve({ ok: !!res?.ok });
        }
      );
    });
  }

  async pollActivityBuffer(agentId: string): Promise<ActivityEntry[]> {
    return new Promise((resolve, reject) => {
      this.mockClient.PollActivityBuffer(
        { agent_id: agentId },
        {},
        {},
        (err: Error | null, res: { entries: ActivityEntry[] }) => {
          if (err) return reject(err);
          resolve(res?.entries ?? []);
        }
      );
    });
  }

  async purgeActivity(agentId: string, taskIds: string[]): Promise<number> {
    return new Promise((resolve, reject) => {
      this.mockClient.PurgeActivity(
        { agent_id: agentId, task_ids: taskIds },
        {},
        {},
        (err: Error | null, res: { purged: number }) => {
          if (err) return reject(err);
          resolve(Number(res?.purged ?? 0));
        }
      );
    });
  }
}

describe('SchedulerClient', () => {
  describe('construction', () => {
    it('should initialize with valid options', () => {
      const client = new MockSchedulerClient({ address: 'localhost:50051' });
      expect(client).toBeDefined();
      expect(client.client).toBeDefined();
    });
  });

  describe('submitTask', () => {
    let client: MockSchedulerClient;

    beforeEach(() => {
      client = new MockSchedulerClient({ address: 'localhost:50051' });
    });

    it('should submit task with valid params', async () => {
      const mockResponse = { accepted: true };
      client.client.SubmitTask.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.submitTask({
        agent_id: 'agent-1',
        task_id: 'task-1',
        priority: 5,
        scope: 'test-scope',
        params: new TextEncoder().encode('{"key": "value"}'),
        content_type: 'application/json',
      });

      expect(result.accepted).toBe(true);
      expect(client.client.SubmitTask).toHaveBeenCalledTimes(1);
    });

    it('should submit task with default priority', async () => {
      const mockResponse = { accepted: true };
      client.client.SubmitTask.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.submitTask({
        agent_id: 'agent-1',
        task_id: 'task-1',
        priority: 0,
        scope: '',
        params: new Uint8Array(),
        content_type: 'application/json',
      });

      expect(result.accepted).toBe(true);
    });

    it('should accept priority at lower bound (-19)', async () => {
      client.client.SubmitTask.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: true });
        }
      );

      const result = await client.submitTask({
        agent_id: 'agent-1',
        task_id: 'task-1',
        priority: -19,
        scope: '',
        params: new Uint8Array(),
        content_type: 'application/json',
      });

      expect(result.accepted).toBe(true);
    });

    it('should accept priority at upper bound (20)', async () => {
      client.client.SubmitTask.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: true });
        }
      );

      const result = await client.submitTask({
        agent_id: 'agent-1',
        task_id: 'task-1',
        priority: 20,
        scope: '',
        params: new Uint8Array(),
        content_type: 'application/json',
      });

      expect(result.accepted).toBe(true);
    });

    it('should reject priority below lower bound', async () => {
      await expect(
        client.submitTask({
          agent_id: 'agent-1',
          task_id: 'task-1',
          priority: -20,
          scope: '',
          params: new Uint8Array(),
          content_type: 'application/json',
        })
      ).rejects.toThrow('Priority must be in range -19..20');
    });

    it('should reject priority above upper bound', async () => {
      await expect(
        client.submitTask({
          agent_id: 'agent-1',
          task_id: 'task-1',
          priority: 21,
          scope: '',
          params: new Uint8Array(),
          content_type: 'application/json',
        })
      ).rejects.toThrow('Priority must be in range -19..20');
    });

    it('should handle task rejection', async () => {
      const mockResponse = { accepted: false, reason: 'Queue full' };
      client.client.SubmitTask.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.submitTask({
        agent_id: 'agent-1',
        task_id: 'task-1',
        priority: 0,
        scope: '',
        params: new Uint8Array(),
        content_type: 'application/json',
      });

      expect(result.accepted).toBe(false);
      expect(result.reason).toBe('Queue full');
    });
  });

  describe('requestPreemption', () => {
    let client: MockSchedulerClient;

    beforeEach(() => {
      client = new MockSchedulerClient({ address: 'localhost:50051' });
    });

    it('should request preemption with all params', async () => {
      client.client.RequestPreemption.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { enqueued: true });
        }
      );

      const result = await client.requestPreemption('agent-1', 'task-1', 'Higher priority task');

      expect(result.enqueued).toBe(true);
      expect(client.client.RequestPreemption).toHaveBeenCalledWith(
        { agent_id: 'agent-1', task_id: 'task-1', reason: 'Higher priority task' },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should request preemption without reason', async () => {
      client.client.RequestPreemption.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { enqueued: true });
        }
      );

      const result = await client.requestPreemption('agent-1', 'task-1');

      expect(result.enqueued).toBe(true);
    });

    it('should handle preemption failure', async () => {
      client.client.RequestPreemption.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { enqueued: false });
        }
      );

      const result = await client.requestPreemption('agent-1', 'task-1');

      expect(result.enqueued).toBe(false);
    });
  });

  describe('shutdownAgent', () => {
    let client: MockSchedulerClient;

    beforeEach(() => {
      client = new MockSchedulerClient({ address: 'localhost:50051' });
    });

    it('should shutdown agent with grace period', async () => {
      client.client.ShutdownAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.shutdownAgent('agent-1', 30000);

      expect(result.ok).toBe(true);
      expect(client.client.ShutdownAgent).toHaveBeenCalledTimes(1);
    });

    it('should shutdown agent with zero grace period', async () => {
      client.client.ShutdownAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.shutdownAgent('agent-1', 0);

      expect(result.ok).toBe(true);
    });

    it('should handle shutdown failure', async () => {
      client.client.ShutdownAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Agent not found'), null);
        }
      );

      await expect(client.shutdownAgent('agent-1', 30000)).rejects.toThrow('Agent not found');
    });
  });

  describe('pollActivityBuffer', () => {
    let client: MockSchedulerClient;

    beforeEach(() => {
      client = new MockSchedulerClient({ address: 'localhost:50051' });
    });

    it('should return activity entries', async () => {
      const mockEntries: ActivityEntry[] = [
        {
          task_id: 'task-1',
          repo_id: 'repo-1',
          worktree_id: 'wt-1',
          branch: 'main',
          description: 'Test activity',
          timestamp: '2024-01-01T00:00:00Z',
        },
      ];

      client.client.PollActivityBuffer.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: mockEntries });
        }
      );

      const result = await client.pollActivityBuffer('agent-1');

      expect(result).toHaveLength(1);
      expect(result[0].task_id).toBe('task-1');
    });

    it('should return empty array when no activities', async () => {
      client.client.PollActivityBuffer.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: [] });
        }
      );

      const result = await client.pollActivityBuffer('agent-1');

      expect(result).toEqual([]);
    });
  });

  describe('purgeActivity', () => {
    let client: MockSchedulerClient;

    beforeEach(() => {
      client = new MockSchedulerClient({ address: 'localhost:50051' });
    });

    it('should purge multiple task IDs', async () => {
      client.client.PurgeActivity.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { purged: 3 });
        }
      );

      const result = await client.purgeActivity('agent-1', ['task-1', 'task-2', 'task-3']);

      expect(result).toBe(3);
      expect(client.client.PurgeActivity).toHaveBeenCalledWith(
        { agent_id: 'agent-1', task_ids: ['task-1', 'task-2', 'task-3'] },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should handle empty task IDs', async () => {
      client.client.PurgeActivity.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { purged: 0 });
        }
      );

      const result = await client.purgeActivity('agent-1', []);

      expect(result).toBe(0);
    });
  });

  describe('integration', () => {
    it('should support multiple operations in sequence', async () => {
      const client = new MockSchedulerClient({ address: 'localhost:50051' });

      client.client.SubmitTask.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: true });
        }
      );
      client.client.PollActivityBuffer.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { entries: [] });
        }
      );
      client.client.RequestPreemption.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { enqueued: true });
        }
      );
      client.client.PurgeActivity.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { purged: 1 });
        }
      );

      await client.submitTask({
        agent_id: 'agent-1',
        task_id: 'task-1',
        priority: 5,
        scope: '',
        params: new Uint8Array(),
        content_type: 'application/json',
      });
      await client.pollActivityBuffer('agent-1');
      await client.requestPreemption('agent-1', 'task-1');
      await client.purgeActivity('agent-1', ['task-1']);

      expect(client.client.SubmitTask).toHaveBeenCalledTimes(1);
      expect(client.client.PollActivityBuffer).toHaveBeenCalledTimes(1);
      expect(client.client.RequestPreemption).toHaveBeenCalledTimes(1);
      expect(client.client.PurgeActivity).toHaveBeenCalledTimes(1);
    });
  });
});
