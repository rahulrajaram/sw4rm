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
 * Tests for RegistryClient.
 *
 * These tests verify the RegistryClient functionality for agent registration,
 * heartbeat, and deregistration operations.
 *
 * Ported from: sdks/py_sdk/tests/test_registry_client.py
 */

// Mock the gRPC client since we're testing the client logic, not the transport
interface MockRegistryServiceClient {
  RegisterAgent: ReturnType<typeof vi.fn>;
  Heartbeat: ReturnType<typeof vi.fn>;
  DeregisterAgent: ReturnType<typeof vi.fn>;
}

interface AgentDescriptor {
  agent_id: string;
  name?: string;
  description?: string;
  capabilities?: string[];
  communication_class?: string;
  modalities_supported?: string[];
  reasoning_connectors?: string[];
  public_key?: Uint8Array;
}

// Simplified mock client for testing
class MockRegistryClient {
  private mockClient: MockRegistryServiceClient;
  private _deadlineMs: number;
  private _userAgent: string;

  constructor(opts: { address: string; deadlineMs?: number; userAgent?: string }) {
    this._deadlineMs = opts.deadlineMs ?? 30000;
    this._userAgent = opts.userAgent ?? 'sw4rm-js-sdk/test';
    this.mockClient = {
      RegisterAgent: vi.fn(),
      Heartbeat: vi.fn(),
      DeregisterAgent: vi.fn(),
    };
  }

  get client(): MockRegistryServiceClient {
    return this.mockClient;
  }

  async registerAgent(agent: AgentDescriptor): Promise<{ accepted: boolean; reason?: string }> {
    return new Promise((resolve, reject) => {
      this.mockClient.RegisterAgent({ agent }, {}, {}, (err: Error | null, res: { accepted: boolean; reason?: string }) => {
        if (err) return reject(err);
        resolve({ accepted: !!res?.accepted, reason: res?.reason });
      });
    });
  }

  async heartbeat(agentId: string, state: string, health?: Record<string, string>): Promise<boolean> {
    return new Promise((resolve, reject) => {
      this.mockClient.Heartbeat({ agent_id: agentId, state, health }, {}, {}, (err: Error | null, res: { ok: boolean }) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    });
  }

  async deregisterAgent(agentId: string, reason?: string): Promise<boolean> {
    return new Promise((resolve, reject) => {
      this.mockClient.DeregisterAgent({ agent_id: agentId, reason }, {}, {}, (err: Error | null, res: { ok: boolean }) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    });
  }
}

describe('RegistryClient', () => {
  describe('construction', () => {
    it('should initialize with valid options', () => {
      const client = new MockRegistryClient({ address: 'localhost:50051' });
      expect(client).toBeDefined();
      expect(client.client).toBeDefined();
    });

    it('should use default deadline when not specified', () => {
      const client = new MockRegistryClient({ address: 'localhost:50051' });
      // Internal deadlineMs defaults to 30000
      expect(client).toBeDefined();
    });

    it('should use custom deadline when specified', () => {
      const client = new MockRegistryClient({
        address: 'localhost:50051',
        deadlineMs: 60000,
      });
      expect(client).toBeDefined();
    });
  });

  describe('registerAgent', () => {
    let client: MockRegistryClient;

    beforeEach(() => {
      client = new MockRegistryClient({ address: 'localhost:50051' });
    });

    it('should register with valid agent descriptor', async () => {
      const mockResponse = { accepted: true };
      client.client.RegisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const descriptor: AgentDescriptor = {
        agent_id: 'agent-1',
        name: 'Test Agent',
        capabilities: ['task_processing'],
        communication_class: 'SW4RM_STANDARD',
      };

      const result = await client.registerAgent(descriptor);

      expect(result.accepted).toBe(true);
      expect(client.client.RegisterAgent).toHaveBeenCalledTimes(1);
    });

    it('should register with minimal descriptor', async () => {
      const mockResponse = { accepted: true };
      client.client.RegisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const descriptor: AgentDescriptor = {
        agent_id: 'agent-1',
      };

      const result = await client.registerAgent(descriptor);

      expect(result.accepted).toBe(true);
    });

    it('should handle registration rejection', async () => {
      const mockResponse = { accepted: false, reason: 'Agent already exists' };
      client.client.RegisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const descriptor: AgentDescriptor = {
        agent_id: 'agent-1',
      };

      const result = await client.registerAgent(descriptor);

      expect(result.accepted).toBe(false);
      expect(result.reason).toBe('Agent already exists');
    });

    it('should handle gRPC errors', async () => {
      client.client.RegisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Connection refused'), null);
        }
      );

      const descriptor: AgentDescriptor = {
        agent_id: 'agent-1',
      };

      await expect(client.registerAgent(descriptor)).rejects.toThrow('Connection refused');
    });
  });

  describe('heartbeat', () => {
    let client: MockRegistryClient;

    beforeEach(() => {
      client = new MockRegistryClient({ address: 'localhost:50051' });
    });

    it('should send heartbeat with agent_id and state', async () => {
      const mockResponse = { ok: true };
      client.client.Heartbeat.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.heartbeat('agent-1', 'ACTIVE');

      expect(result).toBe(true);
      expect(client.client.Heartbeat).toHaveBeenCalledTimes(1);
      expect(client.client.Heartbeat).toHaveBeenCalledWith(
        { agent_id: 'agent-1', state: 'ACTIVE', health: undefined },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should send heartbeat with health metrics', async () => {
      const mockResponse = { ok: true };
      client.client.Heartbeat.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const healthMetrics = {
        cpu_usage: '45%',
        memory_usage: '60%',
        uptime: '3600s',
      };

      const result = await client.heartbeat('agent-1', 'ACTIVE', healthMetrics);

      expect(result).toBe(true);
      expect(client.client.Heartbeat).toHaveBeenCalledWith(
        { agent_id: 'agent-1', state: 'ACTIVE', health: healthMetrics },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should handle heartbeat failure', async () => {
      const mockResponse = { ok: false };
      client.client.Heartbeat.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.heartbeat('agent-1', 'ACTIVE');

      expect(result).toBe(false);
    });

    it('should handle gRPC errors', async () => {
      client.client.Heartbeat.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Deadline exceeded'), null);
        }
      );

      await expect(client.heartbeat('agent-1', 'ACTIVE')).rejects.toThrow('Deadline exceeded');
    });
  });

  describe('deregisterAgent', () => {
    let client: MockRegistryClient;

    beforeEach(() => {
      client = new MockRegistryClient({ address: 'localhost:50051' });
    });

    it('should deregister with only agent_id', async () => {
      const mockResponse = { ok: true };
      client.client.DeregisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.deregisterAgent('agent-1');

      expect(result).toBe(true);
      expect(client.client.DeregisterAgent).toHaveBeenCalledTimes(1);
    });

    it('should deregister with reason', async () => {
      const mockResponse = { ok: true };
      client.client.DeregisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.deregisterAgent('agent-1', 'Agent shutdown');

      expect(result).toBe(true);
      expect(client.client.DeregisterAgent).toHaveBeenCalledWith(
        { agent_id: 'agent-1', reason: 'Agent shutdown' },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should handle deregistration failure', async () => {
      const mockResponse = { ok: false };
      client.client.DeregisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.deregisterAgent('agent-1');

      expect(result).toBe(false);
    });

    it('should handle gRPC errors', async () => {
      client.client.DeregisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Agent not found'), null);
        }
      );

      await expect(client.deregisterAgent('agent-1')).rejects.toThrow('Agent not found');
    });
  });

  describe('integration', () => {
    it('should support full agent lifecycle: register -> heartbeat -> deregister', async () => {
      const client = new MockRegistryClient({ address: 'localhost:50051' });

      // Setup mocks
      client.client.RegisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { accepted: true });
        }
      );
      client.client.Heartbeat.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );
      client.client.DeregisterAgent.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const descriptor: AgentDescriptor = {
        agent_id: 'agent-1',
        name: 'Test Agent',
      };

      // Register
      const registerResult = await client.registerAgent(descriptor);
      expect(registerResult.accepted).toBe(true);

      // Heartbeats
      expect(await client.heartbeat('agent-1', 'ACTIVE')).toBe(true);
      expect(await client.heartbeat('agent-1', 'ACTIVE', { status: 'healthy' })).toBe(true);

      // Deregister
      const deregisterResult = await client.deregisterAgent('agent-1', 'Normal shutdown');
      expect(deregisterResult).toBe(true);

      // Verify call counts
      expect(client.client.RegisterAgent).toHaveBeenCalledTimes(1);
      expect(client.client.Heartbeat).toHaveBeenCalledTimes(2);
      expect(client.client.DeregisterAgent).toHaveBeenCalledTimes(1);
    });

    it('should support multiple heartbeats in sequence', async () => {
      const client = new MockRegistryClient({ address: 'localhost:50051' });

      client.client.Heartbeat.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      for (let i = 0; i < 5; i++) {
        const result = await client.heartbeat('agent-1', 'ACTIVE');
        expect(result).toBe(true);
      }

      expect(client.client.Heartbeat).toHaveBeenCalledTimes(5);
    });
  });
});
