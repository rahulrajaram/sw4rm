/**
 * Cross-SDK compatibility tests.
 *
 * These tests verify that envelope structures and message formats are
 * compatible between JavaScript and Rust SDK implementations.
 */

import { describe, it, expect } from 'vitest';
import { buildEnvelope, MessageType } from '../src/index.js';

describe('Cross-SDK Compatibility', () => {
  describe('Envelope Structure', () => {
    it('should generate envelope with all required Three-ID Model fields', () => {
      const envelope = buildEnvelope({
        message_type: MessageType.DATA,
        producer_id: 'agent-js-1',
        content_type: 'application/json',
        payload: Buffer.from(JSON.stringify({ action: 'test' })),
        correlation_id: 'corr-123',
      });

      // Verify Three-ID Model fields (SPEC_REQUESTS Phase 1)
      expect(envelope.message_id).toBeDefined();
      expect(envelope.message_id).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      );
      expect(envelope.correlation_id).toBe('corr-123');
      expect(envelope.sequence_number).toBeDefined();
      expect(envelope.retry_count).toBe(0);

      // Verify message structure
      expect(envelope.producer_id).toBe('agent-js-1');
      expect(envelope.message_type).toBe(MessageType.DATA);
      expect(envelope.content_type).toBe('application/json');
      expect(envelope.content_length).toBeGreaterThan(0);
    });

    it('should support idempotency token for retry safety', () => {
      const envelope = buildEnvelope({
        message_type: MessageType.DATA,
        producer_id: 'agent-js-1',
        content_type: 'application/json',
        payload: Buffer.from('{}'),
        idempotency_token: 'idem-token-xyz',
      });

      expect(envelope.idempotency_token).toBe('idem-token-xyz');
    });

    it('should serialize envelope to JSON in cross-SDK compatible format', () => {
      const envelope = buildEnvelope({
        message_type: MessageType.CONTROL,
        producer_id: 'agent-js-1',
        content_type: 'application/vnd.sw4rm.scheduler-command-v1+json',
        payload: Buffer.from(JSON.stringify({
          stage: 'prompt',
          input_payload: { prompt: 'test' },
        })),
      });

      // JSON serialization should be parseable by Rust SDK
      const json = JSON.stringify(envelope);
      const parsed = JSON.parse(json);

      // Verify all required fields are present in JSON
      expect(parsed).toHaveProperty('message_id');
      expect(parsed).toHaveProperty('producer_id');
      expect(parsed).toHaveProperty('message_type');
      expect(parsed).toHaveProperty('content_type');
      expect(parsed).toHaveProperty('sequence_number');
      expect(parsed).toHaveProperty('retry_count');
    });
  });

  describe('MessageType Constants', () => {
    it('should have consistent message type values with proto spec', () => {
      // These numeric values must match proto definitions (0-11)
      // JS SDK uses numeric enum values matching proto; Rust SDK uses string constants
      expect(MessageType.MESSAGE_TYPE_UNSPECIFIED).toBe(0);
      expect(MessageType.CONTROL).toBe(1);
      expect(MessageType.DATA).toBe(2);
      expect(MessageType.HEARTBEAT).toBe(3);
      expect(MessageType.NOTIFICATION).toBe(4);
      expect(MessageType.ACKNOWLEDGEMENT).toBe(5);
      expect(MessageType.HITL_INVOCATION).toBe(6);
      expect(MessageType.WORKTREE_CONTROL).toBe(7);
      expect(MessageType.NEGOTIATION).toBe(8);
      expect(MessageType.TOOL_CALL).toBe(9);
      expect(MessageType.TOOL_RESULT).toBe(10);
      expect(MessageType.TOOL_ERROR).toBe(11);
    });

    it('should have correct enum key names matching Rust SDK', () => {
      // Verify the enum key names exist
      expect('CONTROL' in MessageType).toBe(true);
      expect('DATA' in MessageType).toBe(true);
      expect('HEARTBEAT' in MessageType).toBe(true);
      expect('NOTIFICATION' in MessageType).toBe(true);
      expect('ACKNOWLEDGEMENT' in MessageType).toBe(true);
      expect('HITL_INVOCATION' in MessageType).toBe(true);
      expect('WORKTREE_CONTROL' in MessageType).toBe(true);
      expect('NEGOTIATION' in MessageType).toBe(true);
      expect('TOOL_CALL' in MessageType).toBe(true);
      expect('TOOL_RESULT' in MessageType).toBe(true);
      expect('TOOL_ERROR' in MessageType).toBe(true);
    });
  });

  describe('Policy Structure Compatibility', () => {
    it('should have EffectivePolicy with all three policy types', async () => {
      const { InMemoryPolicyStore } = await import('../src/runtime/policyStore.js');

      const store = new InMemoryPolicyStore();
      const policy = await store.createEffectivePolicy('MEDIUM');

      // Verify unified EffectivePolicy model (SPEC_REQUESTS Phase 3)
      expect(policy).toHaveProperty('policyId');
      expect(policy).toHaveProperty('version');
      expect(policy).toHaveProperty('negotiation');
      expect(policy).toHaveProperty('execution');
      expect(policy).toHaveProperty('escalation');

      // Verify NegotiationPolicy fields
      expect(policy.negotiation).toHaveProperty('maxRounds');
      expect(policy.negotiation).toHaveProperty('scoreThreshold');
      expect(policy.negotiation).toHaveProperty('oscillationLimit');

      // Verify ExecutionPolicy fields (TaskExecutionPolicy)
      expect(policy.execution).toHaveProperty('timeoutMs');
      expect(policy.execution).toHaveProperty('maxRetries');
      expect(policy.execution).toHaveProperty('networkPolicy');
      expect(policy.execution).toHaveProperty('privilegeLevel');

      // Verify EscalationPolicy fields
      expect(policy.escalation).toHaveProperty('autoEscalateOnDeadlock');
      expect(policy.escalation).toHaveProperty('deadlockRounds');
      expect(policy.escalation).toHaveProperty('escalationReasons');
    });
  });
});
