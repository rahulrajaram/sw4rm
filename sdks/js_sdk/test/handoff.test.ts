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

import { describe, it, expect, beforeEach } from 'vitest';
import {
  HandoffClient,
  HandoffRequest,
  HandoffValidationError,
} from '../src/clients/handoff.js';

describe('HandoffClient', () => {
  let client: HandoffClient;

  beforeEach(() => {
    client = new HandoffClient();
  });

  describe('requestHandoff', () => {
    it('should create a handoff request', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-1',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Need specialized processing',
        contextSnapshot: new TextEncoder().encode('{"state": "in_progress"}'),
        capabilitiesRequired: ['code_review'],
        priority: 5,
      };

      // Start the request (don't wait for response, it will timeout)
      const responsePromise = client.requestHandoff(request);

      // Immediately check that it's pending
      const pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(1);
      expect(pending[0].requestId).toBe('handoff-1');
      expect(pending[0].fromAgent).toBe('agent-a');

      // Accept the handoff so request doesn't timeout
      await client.acceptHandoff('handoff-1');

      const response = await responsePromise;
      expect(response.accepted).toBe(true);
    });

    it('should reject duplicate handoff request', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-dup',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      // First request starts
      const promise1 = client.requestHandoff(request);

      // Second request should fail immediately
      await expect(client.requestHandoff(request)).rejects.toThrow(
        HandoffValidationError
      );

      // Clean up first request
      await client.acceptHandoff('handoff-dup');
      await promise1;
    });

    it('should set createdAt timestamp', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-ts',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const requestPromise = client.requestHandoff(request);

      const pending = await client.getPendingHandoffs('agent-b');
      expect(pending[0].createdAt).toBeDefined();
      expect(typeof pending[0].createdAt).toBe('string');

      // Clean up
      await client.acceptHandoff('handoff-ts');
      await requestPromise;
    });

    it('should preserve custom createdAt if provided', async () => {
      const customTime = '2025-01-01T00:00:00.000Z';
      const request: HandoffRequest = {
        requestId: 'handoff-custom',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
        createdAt: customTime,
      };

      const requestPromise = client.requestHandoff(request);

      const pending = await client.getPendingHandoffs('agent-b');
      expect(pending[0].createdAt).toBe(customTime);

      // Clean up
      await client.acceptHandoff('handoff-custom');
      await requestPromise;
    });
  });

  describe('acceptHandoff', () => {
    it('should accept a pending handoff', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-accept',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);

      await client.acceptHandoff('handoff-accept');

      const response = await responsePromise;
      expect(response.accepted).toBe(true);
      expect(response.requestId).toBe('handoff-accept');
      expect(response.acceptingAgent).toBe('agent-b');
    });

    it('should remove handoff from pending after acceptance', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-remove',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);

      // Initially pending
      let pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(1);

      await client.acceptHandoff('handoff-remove');

      // No longer pending
      pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(0);

      await responsePromise;
    });

    it('should reject accepting non-existent handoff', async () => {
      await expect(client.acceptHandoff('nonexistent')).rejects.toThrow(
        HandoffValidationError
      );
    });

    it('should reject accepting already responded handoff', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-double',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);
      await client.acceptHandoff('handoff-double');

      // Try to accept again
      await expect(client.acceptHandoff('handoff-double')).rejects.toThrow(
        HandoffValidationError
      );

      await responsePromise;
    });
  });

  describe('rejectHandoff', () => {
    it('should reject a pending handoff', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-reject',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);

      await client.rejectHandoff('handoff-reject', 'Agent at capacity');

      const response = await responsePromise;
      expect(response.accepted).toBe(false);
      expect(response.rejectionReason).toBe('Agent at capacity');
    });

    it('should remove handoff from pending after rejection', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-reject-remove',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);

      let pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(1);

      await client.rejectHandoff('handoff-reject-remove', 'Busy');

      pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(0);

      await responsePromise;
    });

    it('should reject rejecting non-existent handoff', async () => {
      await expect(
        client.rejectHandoff('nonexistent', 'reason')
      ).rejects.toThrow(HandoffValidationError);
    });

    it('should reject rejecting already responded handoff', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-double-reject',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);
      await client.rejectHandoff('handoff-double-reject', 'First rejection');

      // Try to reject again
      await expect(
        client.rejectHandoff('handoff-double-reject', 'Second rejection')
      ).rejects.toThrow(HandoffValidationError);

      await responsePromise;
    });
  });

  describe('getPendingHandoffs', () => {
    it('should return empty array when no pending handoffs', async () => {
      const pending = await client.getPendingHandoffs('agent-x');
      expect(pending).toEqual([]);
    });

    it('should return pending handoffs for specific agent', async () => {
      const request1: HandoffRequest = {
        requestId: 'handoff-1',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Handoff 1',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const request2: HandoffRequest = {
        requestId: 'handoff-2',
        fromAgent: 'agent-c',
        toAgent: 'agent-b',
        reason: 'Handoff 2',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 3,
      };

      const request3: HandoffRequest = {
        requestId: 'handoff-3',
        fromAgent: 'agent-a',
        toAgent: 'agent-d',
        reason: 'Different target',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const p1 = client.requestHandoff(request1);
      const p2 = client.requestHandoff(request2);
      const p3 = client.requestHandoff(request3);

      const pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(2);
      expect(pending.map((r) => r.requestId).sort()).toEqual([
        'handoff-1',
        'handoff-2',
      ]);

      // Clean up
      await client.acceptHandoff('handoff-1');
      await client.acceptHandoff('handoff-2');
      await client.acceptHandoff('handoff-3');
      await Promise.all([p1, p2, p3]);
    });

    it('should not return already responded handoffs', async () => {
      const request1: HandoffRequest = {
        requestId: 'handoff-pending-1',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test 1',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const request2: HandoffRequest = {
        requestId: 'handoff-pending-2',
        fromAgent: 'agent-c',
        toAgent: 'agent-b',
        reason: 'Test 2',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const p1 = client.requestHandoff(request1);
      const p2 = client.requestHandoff(request2);

      let pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(2);

      // Accept one
      await client.acceptHandoff('handoff-pending-1');

      pending = await client.getPendingHandoffs('agent-b');
      expect(pending).toHaveLength(1);
      expect(pending[0].requestId).toBe('handoff-pending-2');

      // Clean up
      await client.acceptHandoff('handoff-pending-2');
      await Promise.all([p1, p2]);
    });
  });

  describe('getHandoffResponse', () => {
    it('should return null for pending handoff', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-no-response',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);

      const response = await client.getHandoffResponse('handoff-no-response');
      expect(response).toBeNull();

      // Clean up
      await client.acceptHandoff('handoff-no-response');
      await responsePromise;
    });

    it('should return response for accepted handoff', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-get-response',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);
      await client.acceptHandoff('handoff-get-response');

      const response = await client.getHandoffResponse('handoff-get-response');
      expect(response).not.toBeNull();
      expect(response?.accepted).toBe(true);

      await responsePromise;
    });

    it('should return null for non-existent handoff', async () => {
      const response = await client.getHandoffResponse('nonexistent');
      expect(response).toBeNull();
    });
  });

  describe('getHandoffRequest', () => {
    it('should return request for existing handoff', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-get-request',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Get request test',
        contextSnapshot: new TextEncoder().encode('test context'),
        capabilitiesRequired: ['capability-1'],
        priority: 7,
      };

      const responsePromise = client.requestHandoff(request);

      const retrieved = await client.getHandoffRequest('handoff-get-request');
      expect(retrieved).not.toBeNull();
      expect(retrieved?.fromAgent).toBe('agent-a');
      expect(retrieved?.toAgent).toBe('agent-b');
      expect(retrieved?.reason).toBe('Get request test');
      expect(retrieved?.priority).toBe(7);

      // Clean up
      await client.acceptHandoff('handoff-get-request');
      await responsePromise;
    });

    it('should return null for non-existent handoff', async () => {
      const request = await client.getHandoffRequest('nonexistent');
      expect(request).toBeNull();
    });
  });

  describe('timeout handling', () => {
    it('should timeout if no response received', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-timeout',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Will timeout',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
        timeoutMs: 200, // Short timeout
      };

      const response = await client.requestHandoff(request);

      expect(response.accepted).toBe(false);
      expect(response.rejectionReason).toContain('timed out');
    });

    it('should use default timeout when not specified', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-default-timeout',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Default timeout',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: [],
        priority: 5,
        // timeoutMs not specified, will use default 30000ms
      };

      // Start request but accept it quickly
      const responsePromise = client.requestHandoff(request);

      // Accept within 100ms (well before default 30s timeout)
      setTimeout(() => client.acceptHandoff('handoff-default-timeout'), 50);

      const response = await responsePromise;
      expect(response.accepted).toBe(true);
    });
  });

  describe('context preservation', () => {
    it('should preserve context snapshot', async () => {
      const contextData = { state: 'processing', step: 3, data: [1, 2, 3] };
      const contextSnapshot = new TextEncoder().encode(
        JSON.stringify(contextData)
      );

      const request: HandoffRequest = {
        requestId: 'handoff-context',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Context test',
        contextSnapshot,
        capabilitiesRequired: [],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);

      const pending = await client.getPendingHandoffs('agent-b');
      const retrievedContext = JSON.parse(
        new TextDecoder().decode(pending[0].contextSnapshot)
      );

      expect(retrievedContext).toEqual(contextData);

      // Clean up
      await client.acceptHandoff('handoff-context');
      await responsePromise;
    });
  });

  describe('capability matching', () => {
    it('should preserve capabilities required', async () => {
      const request: HandoffRequest = {
        requestId: 'handoff-caps',
        fromAgent: 'agent-a',
        toAgent: 'agent-b',
        reason: 'Capability test',
        contextSnapshot: new Uint8Array(),
        capabilitiesRequired: ['code_review', 'python', 'security_scan'],
        priority: 5,
      };

      const responsePromise = client.requestHandoff(request);

      const pending = await client.getPendingHandoffs('agent-b');
      expect(pending[0].capabilitiesRequired).toEqual([
        'code_review',
        'python',
        'security_scan',
      ]);

      // Clean up
      await client.acceptHandoff('handoff-caps');
      await responsePromise;
    });
  });
});
