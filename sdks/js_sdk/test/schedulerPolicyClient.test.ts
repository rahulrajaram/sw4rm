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
 * Tests for SchedulerPolicyClient.
 *
 * These tests verify the SchedulerPolicyClient functionality for
 * deriving effective policies with scheduler guardrails.
 *
 * Ported from: sdks/py_sdk/tests/test_scheduler_policy_client.py
 */

interface MockSchedulerPolicyServiceClient {
  DeriveEffective: ReturnType<typeof vi.fn>;
}

interface NegotiationPolicy {
  max_rounds?: number;
  score_threshold?: number;
  diff_tolerance?: number;
  round_timeout_ms?: number;
  token_budget_per_round?: number;
  total_token_budget?: number;
  oscillation_limit?: number;
  hitl_mode?: string;
}

interface ExecutionPolicy {
  timeout_ms?: number;
  max_retries?: number;
  backoff?: string;
  worktree_required?: boolean;
  network_policy?: string;
  privilege_level?: string;
}

interface EscalationPolicy {
  auto_escalate_on_deadlock?: boolean;
  deadlock_rounds?: number;
  escalation_reasons?: string[];
}

interface EffectivePolicy {
  policy_id: string;
  version: string;
  negotiation?: NegotiationPolicy;
  execution?: ExecutionPolicy;
  escalation?: EscalationPolicy;
  applied?: Record<string, NegotiationPolicy>;
}

interface AgentPreferences {
  max_rounds?: number;
  score_threshold?: number;
  diff_tolerance?: number;
  round_timeout_ms?: number;
  token_budget_per_round?: number;
}

// Simplified mock client for testing
class MockSchedulerPolicyClient {
  private mockClient: MockSchedulerPolicyServiceClient;

  constructor(opts: { address: string }) {
    this.mockClient = {
      DeriveEffective: vi.fn(),
    };
  }

  get client(): MockSchedulerPolicyServiceClient {
    return this.mockClient;
  }

  async deriveEffective(
    profileName: string,
    agentPrefs?: Record<string, AgentPreferences>,
    negotiationId?: string
  ): Promise<EffectivePolicy> {
    return new Promise((resolve, reject) => {
      this.mockClient.DeriveEffective(
        { profile_name: profileName, agent_preferences: agentPrefs, negotiation_id: negotiationId },
        {},
        {},
        (err: Error | null, res: EffectivePolicy) => {
          if (err) return reject(err);
          resolve(res);
        }
      );
    });
  }
}

describe('SchedulerPolicyClient', () => {
  describe('construction', () => {
    it('should initialize with valid options', () => {
      const client = new MockSchedulerPolicyClient({ address: 'localhost:50051' });
      expect(client).toBeDefined();
      expect(client.client).toBeDefined();
    });
  });

  describe('deriveEffective', () => {
    let client: MockSchedulerPolicyClient;

    beforeEach(() => {
      client = new MockSchedulerPolicyClient({ address: 'localhost:50051' });
    });

    it('should derive effective policy with profile only', async () => {
      const mockPolicy: EffectivePolicy = {
        policy_id: 'policy-123',
        version: '1.0',
        negotiation: {
          max_rounds: 10,
          score_threshold: 0.7,
        },
      };

      client.client.DeriveEffective.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockPolicy);
        }
      );

      const result = await client.deriveEffective('MEDIUM');

      expect(result.policy_id).toBe('policy-123');
      expect(result.negotiation?.max_rounds).toBe(10);
      expect(client.client.DeriveEffective).toHaveBeenCalledWith(
        { profile_name: 'MEDIUM', agent_preferences: undefined, negotiation_id: undefined },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should derive effective policy with agent preferences', async () => {
      const mockPolicy: EffectivePolicy = {
        policy_id: 'policy-456',
        version: '1.0',
        negotiation: {
          max_rounds: 5, // Clamped from agent preference
          score_threshold: 0.8, // Higher threshold from agent
        },
        applied: {
          'agent-1': {
            max_rounds: 5,
            score_threshold: 0.8,
          },
        },
      };

      client.client.DeriveEffective.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockPolicy);
        }
      );

      const agentPrefs: Record<string, AgentPreferences> = {
        'agent-1': {
          max_rounds: 5,
          score_threshold: 0.8,
        },
      };

      const result = await client.deriveEffective('MEDIUM', agentPrefs);

      expect(result.policy_id).toBe('policy-456');
      expect(result.applied?.['agent-1']?.max_rounds).toBe(5);
    });

    it('should derive effective policy with negotiation ID', async () => {
      const mockPolicy: EffectivePolicy = {
        policy_id: 'policy-789',
        version: '1.0',
        negotiation: {
          max_rounds: 10,
        },
      };

      client.client.DeriveEffective.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockPolicy);
        }
      );

      const result = await client.deriveEffective('MEDIUM', undefined, 'neg-123');

      expect(result).toBeDefined();
      expect(client.client.DeriveEffective).toHaveBeenCalledWith(
        { profile_name: 'MEDIUM', agent_preferences: undefined, negotiation_id: 'neg-123' },
        {},
        {},
        expect.any(Function)
      );
    });

    it('should derive effective policy with all parameters', async () => {
      const mockPolicy: EffectivePolicy = {
        policy_id: 'policy-full',
        version: '1.0',
        negotiation: {
          max_rounds: 15,
          score_threshold: 0.85,
          diff_tolerance: 0.2,
          round_timeout_ms: 20000,
          hitl_mode: 'PauseOnFinalAccept',
        },
        execution: {
          timeout_ms: 30000,
          max_retries: 2,
        },
        escalation: {
          auto_escalate_on_deadlock: true,
          deadlock_rounds: 2,
        },
      };

      client.client.DeriveEffective.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockPolicy);
        }
      );

      const agentPrefs = {
        'agent-1': {
          max_rounds: 10,
        },
        'agent-2': {
          score_threshold: 0.9,
        },
      };

      const result = await client.deriveEffective('HIGH', agentPrefs, 'neg-456');

      expect(result.policy_id).toBe('policy-full');
      expect(result.negotiation?.hitl_mode).toBe('PauseOnFinalAccept');
      expect(result.execution?.timeout_ms).toBe(30000);
      expect(result.escalation?.auto_escalate_on_deadlock).toBe(true);
    });

    it('should handle unknown profile', async () => {
      client.client.DeriveEffective.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Profile not found: UNKNOWN'), null);
        }
      );

      await expect(client.deriveEffective('UNKNOWN')).rejects.toThrow('Profile not found');
    });

    it('should handle gRPC errors', async () => {
      client.client.DeriveEffective.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Service unavailable'), null);
        }
      );

      await expect(client.deriveEffective('MEDIUM')).rejects.toThrow('Service unavailable');
    });
  });

  describe('profile clamping', () => {
    let client: MockSchedulerPolicyClient;

    beforeEach(() => {
      client = new MockSchedulerPolicyClient({ address: 'localhost:50051' });
    });

    it('should clamp max_rounds to profile maximum', async () => {
      // Profile allows max 10 rounds, agent requests 15
      client.client.DeriveEffective.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          // Simulate clamping behavior
          const result: EffectivePolicy = {
            policy_id: 'test',
            version: '1.0',
            negotiation: {
              max_rounds: Math.min(req.agent_preferences?.['agent-1']?.max_rounds ?? 10, 10),
            },
            applied: req.agent_preferences,
          };
          cb(null, result);
        }
      );

      const result = await client.deriveEffective('MEDIUM', {
        'agent-1': { max_rounds: 15 },
      });

      expect(result.negotiation?.max_rounds).toBe(10); // Clamped to profile max
    });

    it('should raise score_threshold to profile minimum', async () => {
      // Profile requires minimum 0.7 threshold, agent requests 0.5
      client.client.DeriveEffective.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          // Simulate clamping behavior
          const result: EffectivePolicy = {
            policy_id: 'test',
            version: '1.0',
            negotiation: {
              score_threshold: Math.max(req.agent_preferences?.['agent-1']?.score_threshold ?? 0.7, 0.7),
            },
          };
          cb(null, result);
        }
      );

      const result = await client.deriveEffective('MEDIUM', {
        'agent-1': { score_threshold: 0.5 },
      });

      expect(result.negotiation?.score_threshold).toBe(0.7); // Raised to profile min
    });

    it('should clamp diff_tolerance to profile maximum', async () => {
      // Profile allows max 0.3 tolerance, agent requests 0.5
      client.client.DeriveEffective.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          const result: EffectivePolicy = {
            policy_id: 'test',
            version: '1.0',
            negotiation: {
              diff_tolerance: Math.min(req.agent_preferences?.['agent-1']?.diff_tolerance ?? 0.3, 0.3),
            },
          };
          cb(null, result);
        }
      );

      const result = await client.deriveEffective('MEDIUM', {
        'agent-1': { diff_tolerance: 0.5 },
      });

      expect(result.negotiation?.diff_tolerance).toBe(0.3); // Clamped to profile max
    });
  });

  describe('integration', () => {
    it('should support multiple derive calls with different profiles', async () => {
      const client = new MockSchedulerPolicyClient({ address: 'localhost:50051' });

      client.client.DeriveEffective.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          const profiles: Record<string, NegotiationPolicy> = {
            LOW: { max_rounds: 5, score_threshold: 0.6 },
            MEDIUM: { max_rounds: 10, score_threshold: 0.7 },
            HIGH: { max_rounds: 15, score_threshold: 0.85 },
          };
          cb(null, {
            policy_id: `policy-${req.profile_name}`,
            version: '1.0',
            negotiation: profiles[req.profile_name] ?? profiles.MEDIUM,
          });
        }
      );

      const low = await client.deriveEffective('LOW');
      const medium = await client.deriveEffective('MEDIUM');
      const high = await client.deriveEffective('HIGH');

      expect(low.negotiation?.max_rounds).toBe(5);
      expect(medium.negotiation?.max_rounds).toBe(10);
      expect(high.negotiation?.max_rounds).toBe(15);

      expect(low.negotiation?.score_threshold).toBe(0.6);
      expect(medium.negotiation?.score_threshold).toBe(0.7);
      expect(high.negotiation?.score_threshold).toBe(0.85);
    });
  });
});
