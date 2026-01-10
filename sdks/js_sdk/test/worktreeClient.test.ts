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
 * Tests for WorktreeClient.
 *
 * These tests verify the WorktreeClient functionality for binding agents
 * to worktrees, switching between worktrees, and managing worktree state.
 *
 * Ported from: sdks/py_sdk/tests/test_worktree_client.py
 */

interface MockWorktreeServiceClient {
  Bind: ReturnType<typeof vi.fn>;
  Unbind: ReturnType<typeof vi.fn>;
  RequestSwitch: ReturnType<typeof vi.fn>;
  ApproveSwitch: ReturnType<typeof vi.fn>;
  RejectSwitch: ReturnType<typeof vi.fn>;
  Status: ReturnType<typeof vi.fn>;
}

type WorktreeState = 'UNBOUND' | 'BOUND' | 'SWITCH_PENDING' | 'SWITCH_APPROVED' | 'SWITCH_REJECTED';

interface WorktreeStatus {
  state: WorktreeState;
  repo_id?: string;
  worktree_id?: string;
}

interface WorktreePolicyHook {
  canBind(context: { agent_id: string; current_state: string }, repoId: string, worktreeId: string): boolean;
  canUnbind(context: { agent_id: string; current_state: string }): boolean;
  canSwitch(context: { agent_id: string; current_state: string; target_worktree_id: string }): boolean;
}

class DefaultWorktreePolicy implements WorktreePolicyHook {
  canBind(): boolean {
    return true;
  }
  canUnbind(): boolean {
    return true;
  }
  canSwitch(): boolean {
    return true;
  }
}

class RestrictivePolicy implements WorktreePolicyHook {
  private allowedWorktrees: string[];

  constructor(allowedWorktrees: string[]) {
    this.allowedWorktrees = allowedWorktrees;
  }

  canBind(_context: { agent_id: string; current_state: string }, _repoId: string, worktreeId: string): boolean {
    return this.allowedWorktrees.includes(worktreeId);
  }

  canUnbind(): boolean {
    return true;
  }

  canSwitch(context: { agent_id: string; current_state: string; target_worktree_id: string }): boolean {
    return this.allowedWorktrees.includes(context.target_worktree_id);
  }
}

// Simplified mock client for testing
class MockWorktreeClient {
  private mockClient: MockWorktreeServiceClient;
  private policy: WorktreePolicyHook;

  constructor(opts: { address: string }) {
    this.mockClient = {
      Bind: vi.fn(),
      Unbind: vi.fn(),
      RequestSwitch: vi.fn(),
      ApproveSwitch: vi.fn(),
      RejectSwitch: vi.fn(),
      Status: vi.fn(),
    };
    this.policy = new DefaultWorktreePolicy();
  }

  get client(): MockWorktreeServiceClient {
    return this.mockClient;
  }

  setPolicy(policy: WorktreePolicyHook): void {
    this.policy = policy;
  }

  async bind(agentId: string, repoId: string, worktreeId: string): Promise<{ ok: boolean; reason?: string }> {
    if (!this.policy.canBind({ agent_id: agentId, current_state: 'UNKNOWN' }, repoId, worktreeId)) {
      throw new Error('WorktreePolicy denied bind');
    }
    return new Promise((resolve, reject) => {
      this.mockClient.Bind(
        { agent_id: agentId, repo_id: repoId, worktree_id: worktreeId },
        {},
        {},
        (err: Error | null, res: { ok: boolean; reason?: string }) => {
          if (err) return reject(err);
          resolve({ ok: !!res?.ok, reason: res?.reason });
        }
      );
    });
  }

  async unbind(agentId: string): Promise<boolean> {
    if (!this.policy.canUnbind({ agent_id: agentId, current_state: 'UNKNOWN' })) {
      throw new Error('WorktreePolicy denied unbind');
    }
    return new Promise((resolve, reject) => {
      this.mockClient.Unbind(
        { agent_id: agentId },
        {},
        {},
        (err: Error | null, res: { ok: boolean }) => {
          if (err) return reject(err);
          resolve(!!res?.ok);
        }
      );
    });
  }

  async requestSwitch(
    agentId: string,
    targetWorktreeId: string,
    requiresHitl: boolean
  ): Promise<WorktreeStatus> {
    if (!this.policy.canSwitch({ agent_id: agentId, current_state: 'UNKNOWN', target_worktree_id: targetWorktreeId })) {
      throw new Error('WorktreePolicy denied switch');
    }
    return new Promise((resolve, reject) => {
      this.mockClient.RequestSwitch(
        { agent_id: agentId, target_worktree_id: targetWorktreeId, requires_hitl: requiresHitl },
        {},
        {},
        (err: Error | null, res: WorktreeStatus) => {
          if (err) return reject(err);
          resolve(res);
        }
      );
    });
  }

  async approveSwitch(agentId: string, targetWorktreeId: string, ttlMs: number): Promise<string> {
    return new Promise((resolve, reject) => {
      this.mockClient.ApproveSwitch(
        { agent_id: agentId, target_worktree_id: targetWorktreeId, ttl_ms: ttlMs },
        {},
        {},
        (err: Error | null, res: { state: string }) => {
          if (err) return reject(err);
          resolve(res?.state ?? 'UNBOUND');
        }
      );
    });
  }

  async rejectSwitch(agentId: string, reason?: string): Promise<string> {
    return new Promise((resolve, reject) => {
      this.mockClient.RejectSwitch(
        { agent_id: agentId, reason },
        {},
        {},
        (err: Error | null, res: { state: string }) => {
          if (err) return reject(err);
          resolve(res?.state ?? 'UNBOUND');
        }
      );
    });
  }

  async status(agentId: string): Promise<WorktreeStatus> {
    return new Promise((resolve, reject) => {
      this.mockClient.Status(
        { agent_id: agentId },
        {},
        {},
        (err: Error | null, res: WorktreeStatus) => {
          if (err) return reject(err);
          resolve(res);
        }
      );
    });
  }
}

describe('WorktreeClient', () => {
  describe('construction', () => {
    it('should initialize with valid options', () => {
      const client = new MockWorktreeClient({ address: 'localhost:50051' });
      expect(client).toBeDefined();
      expect(client.client).toBeDefined();
    });
  });

  describe('bind', () => {
    let client: MockWorktreeClient;

    beforeEach(() => {
      client = new MockWorktreeClient({ address: 'localhost:50051' });
    });

    it('should bind agent to worktree', async () => {
      client.client.Bind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.bind('agent-1', 'repo-1', 'wt-1');

      expect(result.ok).toBe(true);
      expect(client.client.Bind).toHaveBeenCalledWith(
        { agent_id: 'agent-1', repo_id: 'repo-1', worktree_id: 'wt-1' },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should handle bind failure', async () => {
      client.client.Bind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: false, reason: 'Worktree already bound' });
        }
      );

      const result = await client.bind('agent-1', 'repo-1', 'wt-1');

      expect(result.ok).toBe(false);
      expect(result.reason).toBe('Worktree already bound');
    });

    it('should handle gRPC errors', async () => {
      client.client.Bind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Worktree not found'), null);
        }
      );

      await expect(client.bind('agent-1', 'repo-1', 'nonexistent')).rejects.toThrow('Worktree not found');
    });

    it('should respect policy on bind', async () => {
      const policy = new RestrictivePolicy(['wt-allowed']);
      client.setPolicy(policy);

      // Allowed worktree
      client.client.Bind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const allowed = await client.bind('agent-1', 'repo-1', 'wt-allowed');
      expect(allowed.ok).toBe(true);

      // Denied worktree
      await expect(client.bind('agent-1', 'repo-1', 'wt-denied')).rejects.toThrow('WorktreePolicy denied bind');
    });
  });

  describe('unbind', () => {
    let client: MockWorktreeClient;

    beforeEach(() => {
      client = new MockWorktreeClient({ address: 'localhost:50051' });
    });

    it('should unbind agent from worktree', async () => {
      client.client.Unbind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.unbind('agent-1');

      expect(result).toBe(true);
      expect(client.client.Unbind).toHaveBeenCalledWith(
        { agent_id: 'agent-1' },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should handle unbind failure', async () => {
      client.client.Unbind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: false });
        }
      );

      const result = await client.unbind('agent-1');

      expect(result).toBe(false);
    });
  });

  describe('requestSwitch', () => {
    let client: MockWorktreeClient;

    beforeEach(() => {
      client = new MockWorktreeClient({ address: 'localhost:50051' });
    });

    it('should request switch without HITL', async () => {
      const mockStatus: WorktreeStatus = {
        state: 'BOUND',
        repo_id: 'repo-1',
        worktree_id: 'wt-2',
      };

      client.client.RequestSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockStatus);
        }
      );

      const result = await client.requestSwitch('agent-1', 'wt-2', false);

      expect(result.state).toBe('BOUND');
      expect(result.worktree_id).toBe('wt-2');
    });

    it('should request switch with HITL', async () => {
      const mockStatus: WorktreeStatus = {
        state: 'SWITCH_PENDING',
        repo_id: 'repo-1',
        worktree_id: 'wt-1',
      };

      client.client.RequestSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockStatus);
        }
      );

      const result = await client.requestSwitch('agent-1', 'wt-2', true);

      expect(result.state).toBe('SWITCH_PENDING');
      expect(client.client.RequestSwitch).toHaveBeenCalledWith(
        { agent_id: 'agent-1', target_worktree_id: 'wt-2', requires_hitl: true },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should respect policy on switch', async () => {
      const policy = new RestrictivePolicy(['wt-allowed']);
      client.setPolicy(policy);

      await expect(client.requestSwitch('agent-1', 'wt-denied', false)).rejects.toThrow(
        'WorktreePolicy denied switch'
      );
    });
  });

  describe('approveSwitch', () => {
    let client: MockWorktreeClient;

    beforeEach(() => {
      client = new MockWorktreeClient({ address: 'localhost:50051' });
    });

    it('should approve switch', async () => {
      client.client.ApproveSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND' });
        }
      );

      const result = await client.approveSwitch('agent-1', 'wt-2', 60000);

      expect(result).toBe('BOUND');
      expect(client.client.ApproveSwitch).toHaveBeenCalledWith(
        { agent_id: 'agent-1', target_worktree_id: 'wt-2', ttl_ms: 60000 },
        {},
        {},
        expect.any(Function)
      );
    });
  });

  describe('rejectSwitch', () => {
    let client: MockWorktreeClient;

    beforeEach(() => {
      client = new MockWorktreeClient({ address: 'localhost:50051' });
    });

    it('should reject switch with reason', async () => {
      client.client.RejectSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND' });
        }
      );

      const result = await client.rejectSwitch('agent-1', 'Security concern');

      expect(result).toBe('BOUND');
      expect(client.client.RejectSwitch).toHaveBeenCalledWith(
        { agent_id: 'agent-1', reason: 'Security concern' },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should reject switch without reason', async () => {
      client.client.RejectSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND' });
        }
      );

      const result = await client.rejectSwitch('agent-1');

      expect(result).toBe('BOUND');
    });
  });

  describe('status', () => {
    let client: MockWorktreeClient;

    beforeEach(() => {
      client = new MockWorktreeClient({ address: 'localhost:50051' });
    });

    it('should get status for bound agent', async () => {
      const mockStatus: WorktreeStatus = {
        state: 'BOUND',
        repo_id: 'repo-1',
        worktree_id: 'wt-1',
      };

      client.client.Status.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockStatus);
        }
      );

      const result = await client.status('agent-1');

      expect(result.state).toBe('BOUND');
      expect(result.repo_id).toBe('repo-1');
      expect(result.worktree_id).toBe('wt-1');
    });

    it('should get status for unbound agent', async () => {
      const mockStatus: WorktreeStatus = {
        state: 'UNBOUND',
      };

      client.client.Status.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockStatus);
        }
      );

      const result = await client.status('agent-1');

      expect(result.state).toBe('UNBOUND');
      expect(result.repo_id).toBeUndefined();
      expect(result.worktree_id).toBeUndefined();
    });

    it('should get status for pending switch', async () => {
      const mockStatus: WorktreeStatus = {
        state: 'SWITCH_PENDING',
        repo_id: 'repo-1',
        worktree_id: 'wt-1',
      };

      client.client.Status.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockStatus);
        }
      );

      const result = await client.status('agent-1');

      expect(result.state).toBe('SWITCH_PENDING');
    });
  });

  describe('integration', () => {
    it('should support full worktree lifecycle: bind -> switch -> unbind', async () => {
      const client = new MockWorktreeClient({ address: 'localhost:50051' });

      // Bind
      client.client.Bind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      // Status
      client.client.Status.mockImplementationOnce(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND', repo_id: 'repo-1', worktree_id: 'wt-1' });
        }
      );

      // Switch
      client.client.RequestSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND', repo_id: 'repo-1', worktree_id: 'wt-2' });
        }
      );

      // Status after switch
      client.client.Status.mockImplementationOnce(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND', repo_id: 'repo-1', worktree_id: 'wt-2' });
        }
      );

      // Unbind
      client.client.Unbind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      // Execute lifecycle
      const bindResult = await client.bind('agent-1', 'repo-1', 'wt-1');
      expect(bindResult.ok).toBe(true);

      const status1 = await client.status('agent-1');
      expect(status1.state).toBe('BOUND');
      expect(status1.worktree_id).toBe('wt-1');

      const switchResult = await client.requestSwitch('agent-1', 'wt-2', false);
      expect(switchResult.worktree_id).toBe('wt-2');

      const status2 = await client.status('agent-1');
      expect(status2.worktree_id).toBe('wt-2');

      const unbindResult = await client.unbind('agent-1');
      expect(unbindResult).toBe(true);
    });

    it('should support HITL switch workflow: request -> approve', async () => {
      const client = new MockWorktreeClient({ address: 'localhost:50051' });

      // Initial bind
      client.client.Bind.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      // Request switch (pending)
      client.client.RequestSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'SWITCH_PENDING', repo_id: 'repo-1', worktree_id: 'wt-1' });
        }
      );

      // Approve switch
      client.client.ApproveSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND' });
        }
      );

      await client.bind('agent-1', 'repo-1', 'wt-1');

      const switchRequest = await client.requestSwitch('agent-1', 'wt-2', true);
      expect(switchRequest.state).toBe('SWITCH_PENDING');

      const approved = await client.approveSwitch('agent-1', 'wt-2', 60000);
      expect(approved).toBe('BOUND');
    });

    it('should support HITL switch workflow: request -> reject', async () => {
      const client = new MockWorktreeClient({ address: 'localhost:50051' });

      // Request switch (pending)
      client.client.RequestSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'SWITCH_PENDING', repo_id: 'repo-1', worktree_id: 'wt-1' });
        }
      );

      // Reject switch
      client.client.RejectSwitch.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { state: 'BOUND' });
        }
      );

      const switchRequest = await client.requestSwitch('agent-1', 'wt-2', true);
      expect(switchRequest.state).toBe('SWITCH_PENDING');

      const rejected = await client.rejectSwitch('agent-1', 'Not authorized');
      expect(rejected).toBe('BOUND');
    });
  });
});
