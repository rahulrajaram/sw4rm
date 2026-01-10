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

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  InMemoryPolicyStore,
  JsonFilePolicyStore,
  HitlMode,
  DEFAULT_NEGOTIATION_POLICY,
  DEFAULT_EXECUTION_POLICY,
  DEFAULT_ESCALATION_POLICY,
  type EffectivePolicy,
  type NegotiationPolicy,
} from '../src/runtime/policyStore.js';

/**
 * Tests for PolicyStore implementations.
 *
 * These tests verify the InMemoryPolicyStore and JsonFilePolicyStore
 * implementations for policy storage and retrieval.
 *
 * Ported from: sdks/py_sdk/tests/test_policy_store.py
 */

describe('PolicyStore', () => {
  describe('InMemoryPolicyStore', () => {
    let store: InMemoryPolicyStore;

    beforeEach(() => {
      store = new InMemoryPolicyStore();
    });

    describe('save and get policy', () => {
      it('should save and retrieve a policy', async () => {
        const policy: EffectivePolicy = {
          policyId: 'test-policy-1',
          version: '1.0',
          negotiation: {
            ...DEFAULT_NEGOTIATION_POLICY,
            maxRounds: 5,
          },
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        };

        const savedId = await store.savePolicy(policy);
        expect(savedId).toBe('test-policy-1');

        const retrieved = await store.getPolicy('test-policy-1');
        expect(retrieved).not.toBeNull();
        expect(retrieved?.policyId).toBe('test-policy-1');
        expect(retrieved?.negotiation.maxRounds).toBe(5);
      });

      it('should generate policy ID if not provided', async () => {
        const policy: EffectivePolicy = {
          policyId: '',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        };

        const savedId = await store.savePolicy(policy);
        expect(savedId).toMatch(/^policy-/);

        const retrieved = await store.getPolicy(savedId);
        expect(retrieved).not.toBeNull();
      });

      it('should generate version if not provided', async () => {
        const policy: EffectivePolicy = {
          policyId: 'test-policy',
          version: '',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        };

        await store.savePolicy(policy);
        const retrieved = await store.getPolicy('test-policy');
        expect(retrieved?.version).not.toBe('');
      });

      it('should return null for nonexistent policy', async () => {
        const retrieved = await store.getPolicy('nonexistent');
        expect(retrieved).toBeNull();
      });
    });

    describe('list policies', () => {
      it('should list all policies', async () => {
        for (let i = 0; i < 3; i++) {
          await store.savePolicy({
            policyId: `policy-${i}`,
            version: '1.0',
            negotiation: DEFAULT_NEGOTIATION_POLICY,
            execution: DEFAULT_EXECUTION_POLICY,
            escalation: DEFAULT_ESCALATION_POLICY,
          });
        }

        const policies = await store.listPolicies();
        expect(policies).toContain('policy-0');
        expect(policies).toContain('policy-1');
        expect(policies).toContain('policy-2');
      });

      it('should filter policies by prefix', async () => {
        await store.savePolicy({
          policyId: 'prod-policy-1',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });
        await store.savePolicy({
          policyId: 'prod-policy-2',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });
        await store.savePolicy({
          policyId: 'dev-policy-1',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });

        const prodPolicies = await store.listPolicies('prod-');
        expect(prodPolicies).toHaveLength(2);
        expect(prodPolicies).toContain('prod-policy-1');
        expect(prodPolicies).toContain('prod-policy-2');

        const devPolicies = await store.listPolicies('dev-');
        expect(devPolicies).toHaveLength(1);
        expect(devPolicies).toContain('dev-policy-1');
      });

      it('should return empty array when no policies', async () => {
        const policies = await store.listPolicies();
        expect(policies).toEqual([]);
      });
    });

    describe('delete policy', () => {
      it('should delete existing policy', async () => {
        await store.savePolicy({
          policyId: 'to-delete',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });

        const deleted = await store.deletePolicy('to-delete');
        expect(deleted).toBe(true);

        const retrieved = await store.getPolicy('to-delete');
        expect(retrieved).toBeNull();
      });

      it('should return false for nonexistent policy', async () => {
        const deleted = await store.deletePolicy('nonexistent');
        expect(deleted).toBe(false);
      });
    });

    describe('policy history', () => {
      it('should track policy version history', async () => {
        const versions = [5, 10, 15];
        for (const maxRounds of versions) {
          await store.savePolicy({
            policyId: 'versioned-policy',
            version: '', // Auto-generate
            negotiation: {
              ...DEFAULT_NEGOTIATION_POLICY,
              maxRounds,
            },
            execution: DEFAULT_EXECUTION_POLICY,
            escalation: DEFAULT_ESCALATION_POLICY,
          });
        }

        const history = await store.getHistory('versioned-policy');
        expect(history).toHaveLength(3);
        expect(history[0].negotiation.maxRounds).toBe(5);
        expect(history[1].negotiation.maxRounds).toBe(10);
        expect(history[2].negotiation.maxRounds).toBe(15);
      });

      it('should return empty array for nonexistent policy history', async () => {
        const history = await store.getHistory('nonexistent');
        expect(history).toEqual([]);
      });

      it('should return latest version from getPolicy', async () => {
        for (let i = 1; i <= 3; i++) {
          await store.savePolicy({
            policyId: 'versioned',
            version: '',
            negotiation: {
              ...DEFAULT_NEGOTIATION_POLICY,
              maxRounds: i * 5,
            },
            execution: DEFAULT_EXECUTION_POLICY,
            escalation: DEFAULT_ESCALATION_POLICY,
          });
        }

        const latest = await store.getPolicy('versioned');
        expect(latest?.negotiation.maxRounds).toBe(15);
      });
    });

    describe('profiles', () => {
      it('should have default profiles', async () => {
        const profiles = await store.listProfiles();
        expect(profiles).toContain('LOW');
        expect(profiles).toContain('MEDIUM');
        expect(profiles).toContain('HIGH');
      });

      it('should get LOW profile', async () => {
        const low = await store.getProfile('LOW');
        expect(low).not.toBeNull();
        expect(low?.negotiation.maxRounds).toBe(5);
        expect(low?.negotiation.scoreThreshold).toBe(0.6);
      });

      it('should get MEDIUM profile', async () => {
        const medium = await store.getProfile('MEDIUM');
        expect(medium).not.toBeNull();
        expect(medium?.negotiation.maxRounds).toBe(10);
        expect(medium?.negotiation.scoreThreshold).toBe(0.7);
      });

      it('should get HIGH profile', async () => {
        const high = await store.getProfile('HIGH');
        expect(high).not.toBeNull();
        expect(high?.negotiation.maxRounds).toBe(15);
        expect(high?.negotiation.scoreThreshold).toBe(0.85);
        expect(high?.negotiation.hitl).toBe(HitlMode.PAUSE_ON_FINAL_ACCEPT);
      });

      it('should return null for nonexistent profile', async () => {
        const profile = await store.getProfile('NONEXISTENT');
        expect(profile).toBeNull();
      });

      it('should save custom profile', async () => {
        await store.saveProfile({
          name: 'CUSTOM',
          negotiation: {
            ...DEFAULT_NEGOTIATION_POLICY,
            maxRounds: 20,
          },
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });

        const custom = await store.getProfile('CUSTOM');
        expect(custom?.negotiation.maxRounds).toBe(20);
      });
    });

    describe('createEffectivePolicy', () => {
      it('should create effective policy from profile', async () => {
        const effective = await store.createEffectivePolicy('MEDIUM');

        expect(effective.policyId).toMatch(/^policy-/);
        expect(effective.negotiation.maxRounds).toBe(10);
        expect(effective.negotiation.scoreThreshold).toBe(0.7);
      });

      it('should clamp agent preferences', async () => {
        const effective = await store.createEffectivePolicy('MEDIUM', {
          'agent-1': {
            maxRounds: 15, // Will be clamped to 10
            scoreThreshold: 0.5, // Will be raised to 0.7
          },
        });

        expect(effective.applied?.['agent-1']?.maxRounds).toBe(10);
        expect(effective.applied?.['agent-1']?.scoreThreshold).toBe(0.7);
      });

      it('should throw for nonexistent profile', async () => {
        await expect(store.createEffectivePolicy('NONEXISTENT')).rejects.toThrow(
          "Profile 'NONEXISTENT' does not exist"
        );
      });

      it('should include negotiation ID if provided', async () => {
        const effective = await store.createEffectivePolicy('MEDIUM', undefined, 'neg-123');

        expect(effective.negotiationId).toBe('neg-123');
      });
    });

    describe('complex policy storage', () => {
      it('should store and retrieve complex policies', async () => {
        const complexPolicy: EffectivePolicy = {
          policyId: 'complex-policy',
          version: '1.0',
          negotiation: {
            maxRounds: 10,
            scoreThreshold: 0.85,
            diffTolerance: 0.15,
            roundTimeoutMs: 45000,
            tokenBudgetPerRound: 5000,
            totalTokenBudget: 50000,
            oscillationLimit: 5,
            hitl: HitlMode.PAUSE_BETWEEN_ROUNDS,
            scoring: {
              requireSchemaValid: true,
              requireExamplesPass: true,
              llmWeight: 0.7,
            },
          },
          execution: {
            timeoutMs: 120000,
            maxRetries: 5,
            backoff: 'linear',
            worktreeRequired: true,
            networkPolicy: 'full',
            privilegeLevel: 'elevated',
            budgetCpuMs: 60000,
            budgetWallMs: 120000,
          },
          escalation: {
            autoEscalateOnDeadlock: false,
            deadlockRounds: 5,
            escalationReasons: ['timeout', 'budget_exceeded'],
            defaultAction: 'escalate',
          },
        };

        await store.savePolicy(complexPolicy);
        const retrieved = await store.getPolicy('complex-policy');

        expect(retrieved?.negotiation.maxRounds).toBe(10);
        expect(retrieved?.negotiation.scoreThreshold).toBe(0.85);
        expect(retrieved?.negotiation.hitl).toBe(HitlMode.PAUSE_BETWEEN_ROUNDS);
        expect(retrieved?.execution.worktreeRequired).toBe(true);
        expect(retrieved?.execution.networkPolicy).toBe('full');
        expect(retrieved?.escalation.autoEscalateOnDeadlock).toBe(false);
        expect(retrieved?.escalation.escalationReasons).toEqual(['timeout', 'budget_exceeded']);
      });
    });
  });

  describe('JsonFilePolicyStore', () => {
    let tmpDir: string;
    let store: JsonFilePolicyStore;

    beforeEach(async () => {
      tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sw4rm-policy-test-'));
      store = new JsonFilePolicyStore(tmpDir);
      await store.initialize();
    });

    afterEach(async () => {
      try {
        await fs.rm(tmpDir, { recursive: true, force: true });
      } catch {
        // Ignore cleanup errors
      }
    });

    describe('save and get policy', () => {
      it('should save and retrieve a policy', async () => {
        const policy: EffectivePolicy = {
          policyId: 'test-policy',
          version: '1.0',
          negotiation: {
            ...DEFAULT_NEGOTIATION_POLICY,
            maxRounds: 5,
          },
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        };

        await store.savePolicy(policy);
        const retrieved = await store.getPolicy('test-policy');

        expect(retrieved).not.toBeNull();
        expect(retrieved?.negotiation.maxRounds).toBe(5);
      });

      it('should persist across store instances', async () => {
        const policy: EffectivePolicy = {
          policyId: 'persistent-policy',
          version: '1.0',
          negotiation: {
            ...DEFAULT_NEGOTIATION_POLICY,
            maxRounds: 7,
          },
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        };

        await store.savePolicy(policy);

        // Create new store instance
        const store2 = new JsonFilePolicyStore(tmpDir);
        const retrieved = await store2.getPolicy('persistent-policy');

        expect(retrieved?.negotiation.maxRounds).toBe(7);
      });

      it('should create directory if it does not exist', async () => {
        const nestedDir = path.join(tmpDir, 'nested', 'storage');
        const nestedStore = new JsonFilePolicyStore(nestedDir);
        await nestedStore.initialize();

        const stat = await fs.stat(nestedDir);
        expect(stat.isDirectory()).toBe(true);
      });
    });

    describe('list policies', () => {
      it('should list policies from files', async () => {
        for (let i = 0; i < 3; i++) {
          await store.savePolicy({
            policyId: `policy-${i}`,
            version: '1.0',
            negotiation: DEFAULT_NEGOTIATION_POLICY,
            execution: DEFAULT_EXECUTION_POLICY,
            escalation: DEFAULT_ESCALATION_POLICY,
          });
        }

        const policies = await store.listPolicies();
        expect(policies).toContain('policy-0');
        expect(policies).toContain('policy-1');
        expect(policies).toContain('policy-2');
      });

      it('should filter by prefix', async () => {
        await store.savePolicy({
          policyId: 'prod-policy',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });
        await store.savePolicy({
          policyId: 'dev-policy',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });

        const prodPolicies = await store.listPolicies('prod-');
        expect(prodPolicies).toHaveLength(1);
        expect(prodPolicies[0]).toBe('prod-policy');
      });
    });

    describe('policy history', () => {
      it('should track version history in file', async () => {
        for (let maxRounds = 5; maxRounds <= 15; maxRounds += 5) {
          await store.savePolicy({
            policyId: 'versioned-policy',
            version: '',
            negotiation: {
              ...DEFAULT_NEGOTIATION_POLICY,
              maxRounds,
            },
            execution: DEFAULT_EXECUTION_POLICY,
            escalation: DEFAULT_ESCALATION_POLICY,
          });
        }

        const history = await store.getHistory('versioned-policy');
        expect(history).toHaveLength(3);
        expect(history[0].negotiation.maxRounds).toBe(5);
        expect(history[2].negotiation.maxRounds).toBe(15);
      });
    });

    describe('delete policy', () => {
      it('should delete policy file', async () => {
        await store.savePolicy({
          policyId: 'to-delete',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });

        const deleted = await store.deletePolicy('to-delete');
        expect(deleted).toBe(true);

        const retrieved = await store.getPolicy('to-delete');
        expect(retrieved).toBeNull();
      });
    });

    describe('sanitize policy ID', () => {
      it('should sanitize policy IDs with slashes', async () => {
        await store.savePolicy({
          policyId: 'org/team/policy',
          version: '1.0',
          negotiation: DEFAULT_NEGOTIATION_POLICY,
          execution: DEFAULT_EXECUTION_POLICY,
          escalation: DEFAULT_ESCALATION_POLICY,
        });

        // File should be created with sanitized name
        const files = await fs.readdir(tmpDir);
        expect(files).toContain('org_team_policy.json');
      });
    });
  });

  describe('PolicyStore comparison', () => {
    let memoryStore: InMemoryPolicyStore;
    let tmpDir: string;
    let fileStore: JsonFilePolicyStore;

    beforeEach(async () => {
      memoryStore = new InMemoryPolicyStore();
      tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sw4rm-policy-compare-'));
      fileStore = new JsonFilePolicyStore(tmpDir);
      await fileStore.initialize();
    });

    afterEach(async () => {
      try {
        await fs.rm(tmpDir, { recursive: true, force: true });
      } catch {
        // Ignore cleanup errors
      }
    });

    it('should behave consistently across implementations', async () => {
      const policy: EffectivePolicy = {
        policyId: 'consistent-policy',
        version: '1.0',
        negotiation: {
          ...DEFAULT_NEGOTIATION_POLICY,
          maxRounds: 8,
        },
        execution: DEFAULT_EXECUTION_POLICY,
        escalation: DEFAULT_ESCALATION_POLICY,
      };

      for (const store of [memoryStore, fileStore]) {
        const savedId = await store.savePolicy({ ...policy });
        expect(savedId).toBe('consistent-policy');

        const retrieved = await store.getPolicy('consistent-policy');
        expect(retrieved?.negotiation.maxRounds).toBe(8);
      }
    });

    it('should list policies consistently', async () => {
      for (const store of [memoryStore, fileStore]) {
        for (let i = 0; i < 3; i++) {
          await store.savePolicy({
            policyId: `policy-${i}`,
            version: '1.0',
            negotiation: DEFAULT_NEGOTIATION_POLICY,
            execution: DEFAULT_EXECUTION_POLICY,
            escalation: DEFAULT_ESCALATION_POLICY,
          });
        }

        const policies = await store.listPolicies();
        expect(policies).toHaveLength(3);
      }
    });

    it('should track history consistently', async () => {
      for (const store of [memoryStore, fileStore]) {
        for (let maxRounds = 5; maxRounds <= 15; maxRounds += 5) {
          await store.savePolicy({
            policyId: 'versioned',
            version: '',
            negotiation: {
              ...DEFAULT_NEGOTIATION_POLICY,
              maxRounds,
            },
            execution: DEFAULT_EXECUTION_POLICY,
            escalation: DEFAULT_ESCALATION_POLICY,
          });
        }

        const history = await store.getHistory('versioned');
        expect(history).toHaveLength(3);
        expect(history[0].negotiation.maxRounds).toBe(5);
        expect(history[2].negotiation.maxRounds).toBe(15);
      }
    });
  });
});
