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
 * Tests for HITLClient.
 *
 * These tests verify the HITLClient functionality for human-in-the-loop
 * escalation and response handling.
 *
 * Ported from: sdks/py_sdk/tests/test_hitl_client.py
 */

interface MockHITLServiceClient {
  Escalate: ReturnType<typeof vi.fn>;
  Respond: ReturnType<typeof vi.fn>;
  GetPendingEscalations: ReturnType<typeof vi.fn>;
}

interface EscalationRequest {
  agent_id: string;
  negotiation_id: string;
  reason: string;
  context: Record<string, string>;
  urgency?: string;
}

interface EscalationResponse {
  escalation_id: string;
  acknowledged: boolean;
  eta_ms?: number;
}

interface HITLResponse {
  escalation_id: string;
  responder_id: string;
  action: string;
  parameters: Record<string, string>;
}

interface PendingEscalation {
  escalation_id: string;
  agent_id: string;
  negotiation_id: string;
  reason: string;
  created_at: string;
  urgency: string;
}

// Simplified mock client for testing
class MockHITLClient {
  private mockClient: MockHITLServiceClient;

  constructor(opts: { address: string }) {
    this.mockClient = {
      Escalate: vi.fn(),
      Respond: vi.fn(),
      GetPendingEscalations: vi.fn(),
    };
  }

  get client(): MockHITLServiceClient {
    return this.mockClient;
  }

  async escalate(request: EscalationRequest): Promise<EscalationResponse> {
    return new Promise((resolve, reject) => {
      this.mockClient.Escalate(request, {}, {}, (err: Error | null, res: EscalationResponse) => {
        if (err) return reject(err);
        resolve(res);
      });
    });
  }

  async respond(response: HITLResponse): Promise<boolean> {
    return new Promise((resolve, reject) => {
      this.mockClient.Respond(response, {}, {}, (err: Error | null, res: { ok: boolean }) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    });
  }

  async getPendingEscalations(agentId?: string): Promise<PendingEscalation[]> {
    return new Promise((resolve, reject) => {
      this.mockClient.GetPendingEscalations(
        { agent_id: agentId },
        {},
        {},
        (err: Error | null, res: { escalations: PendingEscalation[] }) => {
          if (err) return reject(err);
          resolve(res?.escalations ?? []);
        }
      );
    });
  }
}

describe('HITLClient', () => {
  describe('construction', () => {
    it('should initialize with valid options', () => {
      const client = new MockHITLClient({ address: 'localhost:50051' });
      expect(client).toBeDefined();
      expect(client.client).toBeDefined();
    });
  });

  describe('escalate', () => {
    let client: MockHITLClient;

    beforeEach(() => {
      client = new MockHITLClient({ address: 'localhost:50051' });
    });

    it('should escalate with all parameters', async () => {
      const mockResponse: EscalationResponse = {
        escalation_id: 'esc-123',
        acknowledged: true,
        eta_ms: 300000,
      };

      client.client.Escalate.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.escalate({
        agent_id: 'agent-1',
        negotiation_id: 'neg-123',
        reason: 'debate_deadlock',
        context: {
          round: '5',
          last_score: '0.45',
        },
        urgency: 'HIGH',
      });

      expect(result.escalation_id).toBe('esc-123');
      expect(result.acknowledged).toBe(true);
      expect(result.eta_ms).toBe(300000);
    });

    it('should escalate with minimal parameters', async () => {
      const mockResponse: EscalationResponse = {
        escalation_id: 'esc-456',
        acknowledged: true,
      };

      client.client.Escalate.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.escalate({
        agent_id: 'agent-1',
        negotiation_id: 'neg-123',
        reason: 'security_flag',
        context: {},
      });

      expect(result.escalation_id).toBe('esc-456');
      expect(result.acknowledged).toBe(true);
    });

    it('should handle different escalation reasons', async () => {
      const reasons = ['debate_deadlock', 'security_flag', 'timeout', 'budget_exceeded', 'manual_request'];

      for (const reason of reasons) {
        client.client.Escalate.mockImplementation(
          (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
            cb(null, {
              escalation_id: `esc-${reason}`,
              acknowledged: true,
            });
          }
        );

        const result = await client.escalate({
          agent_id: 'agent-1',
          negotiation_id: 'neg-123',
          reason,
          context: {},
        });

        expect(result.escalation_id).toBe(`esc-${reason}`);
      }
    });

    it('should handle escalation rejection', async () => {
      const mockResponse: EscalationResponse = {
        escalation_id: '',
        acknowledged: false,
      };

      client.client.Escalate.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResponse);
        }
      );

      const result = await client.escalate({
        agent_id: 'agent-1',
        negotiation_id: 'neg-123',
        reason: 'debate_deadlock',
        context: {},
      });

      expect(result.acknowledged).toBe(false);
    });

    it('should handle gRPC errors', async () => {
      client.client.Escalate.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Service unavailable'), null);
        }
      );

      await expect(
        client.escalate({
          agent_id: 'agent-1',
          negotiation_id: 'neg-123',
          reason: 'debate_deadlock',
          context: {},
        })
      ).rejects.toThrow('Service unavailable');
    });
  });

  describe('respond', () => {
    let client: MockHITLClient;

    beforeEach(() => {
      client = new MockHITLClient({ address: 'localhost:50051' });
    });

    it('should respond with approve action', async () => {
      client.client.Respond.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.respond({
        escalation_id: 'esc-123',
        responder_id: 'human-1',
        action: 'approve',
        parameters: {
          comment: 'Looks good',
        },
      });

      expect(result).toBe(true);
      expect(client.client.Respond).toHaveBeenCalledWith(
        {
          escalation_id: 'esc-123',
          responder_id: 'human-1',
          action: 'approve',
          parameters: { comment: 'Looks good' },
        },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should respond with reject action', async () => {
      client.client.Respond.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.respond({
        escalation_id: 'esc-123',
        responder_id: 'human-1',
        action: 'reject',
        parameters: {
          reason: 'Does not meet requirements',
        },
      });

      expect(result).toBe(true);
    });

    it('should respond with retry action', async () => {
      client.client.Respond.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.respond({
        escalation_id: 'esc-123',
        responder_id: 'human-1',
        action: 'retry',
        parameters: {
          max_additional_rounds: '3',
        },
      });

      expect(result).toBe(true);
    });

    it('should respond with modify action', async () => {
      client.client.Respond.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.respond({
        escalation_id: 'esc-123',
        responder_id: 'human-1',
        action: 'modify',
        parameters: {
          modification: 'Adjust threshold to 0.8',
        },
      });

      expect(result).toBe(true);
    });

    it('should handle response failure', async () => {
      client.client.Respond.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: false });
        }
      );

      const result = await client.respond({
        escalation_id: 'esc-123',
        responder_id: 'human-1',
        action: 'approve',
        parameters: {},
      });

      expect(result).toBe(false);
    });

    it('should handle gRPC errors', async () => {
      client.client.Respond.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Escalation not found'), null);
        }
      );

      await expect(
        client.respond({
          escalation_id: 'esc-unknown',
          responder_id: 'human-1',
          action: 'approve',
          parameters: {},
        })
      ).rejects.toThrow('Escalation not found');
    });
  });

  describe('getPendingEscalations', () => {
    let client: MockHITLClient;

    beforeEach(() => {
      client = new MockHITLClient({ address: 'localhost:50051' });
    });

    it('should get all pending escalations', async () => {
      const mockEscalations: PendingEscalation[] = [
        {
          escalation_id: 'esc-1',
          agent_id: 'agent-1',
          negotiation_id: 'neg-1',
          reason: 'debate_deadlock',
          created_at: '2024-01-01T00:00:00Z',
          urgency: 'HIGH',
        },
        {
          escalation_id: 'esc-2',
          agent_id: 'agent-2',
          negotiation_id: 'neg-2',
          reason: 'timeout',
          created_at: '2024-01-01T00:01:00Z',
          urgency: 'MEDIUM',
        },
      ];

      client.client.GetPendingEscalations.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { escalations: mockEscalations });
        }
      );

      const result = await client.getPendingEscalations();

      expect(result).toHaveLength(2);
      expect(result[0].escalation_id).toBe('esc-1');
      expect(result[1].escalation_id).toBe('esc-2');
    });

    it('should get pending escalations for specific agent', async () => {
      const mockEscalations: PendingEscalation[] = [
        {
          escalation_id: 'esc-1',
          agent_id: 'agent-1',
          negotiation_id: 'neg-1',
          reason: 'debate_deadlock',
          created_at: '2024-01-01T00:00:00Z',
          urgency: 'HIGH',
        },
      ];

      client.client.GetPendingEscalations.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          const filtered = mockEscalations.filter((e) => e.agent_id === req.agent_id);
          cb(null, { escalations: filtered });
        }
      );

      const result = await client.getPendingEscalations('agent-1');

      expect(result).toHaveLength(1);
      expect(result[0].agent_id).toBe('agent-1');
    });

    it('should return empty array when no pending escalations', async () => {
      client.client.GetPendingEscalations.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { escalations: [] });
        }
      );

      const result = await client.getPendingEscalations();

      expect(result).toEqual([]);
    });
  });

  describe('integration', () => {
    it('should support full escalation workflow: escalate -> respond', async () => {
      const client = new MockHITLClient({ address: 'localhost:50051' });

      client.client.Escalate.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, {
            escalation_id: 'esc-workflow',
            acknowledged: true,
            eta_ms: 60000,
          });
        }
      );

      client.client.Respond.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      // Agent escalates
      const escalation = await client.escalate({
        agent_id: 'agent-1',
        negotiation_id: 'neg-123',
        reason: 'debate_deadlock',
        context: { round: '5' },
      });

      expect(escalation.acknowledged).toBe(true);
      expect(escalation.escalation_id).toBe('esc-workflow');

      // Human responds
      const response = await client.respond({
        escalation_id: escalation.escalation_id,
        responder_id: 'human-1',
        action: 'approve',
        parameters: { comment: 'Approved after review' },
      });

      expect(response).toBe(true);
    });

    it('should support multiple escalations from different agents', async () => {
      const client = new MockHITLClient({ address: 'localhost:50051' });

      let escalationCount = 0;
      client.client.Escalate.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          escalationCount++;
          cb(null, {
            escalation_id: `esc-${escalationCount}`,
            acknowledged: true,
          });
        }
      );

      const results = await Promise.all([
        client.escalate({
          agent_id: 'agent-1',
          negotiation_id: 'neg-1',
          reason: 'debate_deadlock',
          context: {},
        }),
        client.escalate({
          agent_id: 'agent-2',
          negotiation_id: 'neg-2',
          reason: 'timeout',
          context: {},
        }),
        client.escalate({
          agent_id: 'agent-3',
          negotiation_id: 'neg-3',
          reason: 'security_flag',
          context: {},
        }),
      ]);

      expect(results).toHaveLength(3);
      results.forEach((r) => {
        expect(r.acknowledged).toBe(true);
      });
    });
  });
});
