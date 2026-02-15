import { describe, expect, it } from 'vitest';
import {
  AGENT_STATE_INITIALIZING,
  AGENT_STATE_RUNNING,
  AGENT_STATE_SHUTTING_DOWN,
  ErrorCode,
  GatewayRedirectEmitter,
  REGISTRATION_TYPE_STANDARD_AGENT,
  REGISTRATION_TYPE_SWARM_GATEWAY,
  type GatewayPeerDescriptor,
  type HandoffRequest,
} from '../src/index.js';

function peerDescriptor(
  agentId: string,
  registrationType = REGISTRATION_TYPE_SWARM_GATEWAY,
  capabilities: string[] = ['plan', 'execute']
): GatewayPeerDescriptor {
  return {
    agentId,
    registrationType,
    capabilities,
  };
}

function makeRequest(
  requestId: string,
  allowSpillover = false
): HandoffRequest {
  return {
    requestId,
    fromAgent: 'parent',
    toAgent: 'gateway-1',
    reason: 'delegate',
    contextSnapshot: new Uint8Array(),
    capabilitiesRequired: [],
    priority: 0,
    delegationPolicy: {
      allowSpilloverRouting: allowSpillover,
    },
  };
}

describe('GatewayRedirectEmitter', () => {
  it('emits REDIRECT when spillover is enabled and healthy peer exists', () => {
    const gateway = new GatewayRedirectEmitter({
      agentId: 'gateway-1',
      capabilities: ['plan', 'execute'],
      peerDescriptors: [
        peerDescriptor('worker-1', REGISTRATION_TYPE_STANDARD_AGENT),
        peerDescriptor('gateway-2'),
      ],
    });

    const response = gateway.emitOverloadedResponse(makeRequest('req-redirect', true));

    expect(response.accepted).toBe(false);
    expect(response.rejectionCode).toBe(ErrorCode.REDIRECT);
    expect(response.redirectToAgentId).toBe('gateway-2');
    expect(response.retryAfterMs).toBe(0);
  });

  it('falls back to OVERLOADED when spillover is disabled', () => {
    const gateway = new GatewayRedirectEmitter({
      agentId: 'gateway-1',
      capabilities: ['plan', 'execute'],
      retryAfterMs: 222,
      peerDescriptors: [peerDescriptor('gateway-2')],
    });

    const response = gateway.emitOverloadedResponse(makeRequest('req-no-spillover', false));

    expect(response.accepted).toBe(false);
    expect(response.rejectionCode).toBe(ErrorCode.OVERLOADED);
    expect(response.redirectToAgentId).toBeUndefined();
    expect(response.retryAfterMs).toBe(222);
  });

  it('falls back to OVERLOADED when no healthy eligible peers remain', () => {
    const gateway = new GatewayRedirectEmitter({
      agentId: 'gateway-1',
      capabilities: ['plan', 'execute'],
      retryAfterMs: 333,
      peerDescriptors: [peerDescriptor('gateway-2')],
      peerHealthFn: () => false,
    });

    const response = gateway.emitOverloadedResponse(makeRequest('req-unhealthy', true));

    expect(response.accepted).toBe(false);
    expect(response.rejectionCode).toBe(ErrorCode.OVERLOADED);
    expect(response.retryAfterMs).toBe(333);
  });

  it('filters stale, non-serving, and cooldown peers from redirect selection', () => {
    const clock = { nowMs: 200_000 };
    const gateway = new GatewayRedirectEmitter({
      agentId: 'gateway-1',
      capabilities: ['plan', 'execute'],
      nowMsFn: () => clock.nowMs,
      peerDescriptors: [
        peerDescriptor('peer-stale'),
        peerDescriptor('peer-initializing'),
        peerDescriptor('peer-cooldown'),
        peerDescriptor('peer-shutting-down'),
        peerDescriptor('peer-healthy'),
      ],
    });

    gateway.updatePeerRuntimeState('peer-stale', {
      state: AGENT_STATE_RUNNING,
      lastHeartbeatMs: clock.nowMs - 120_000,
    });
    gateway.touchPeerHeartbeat('peer-initializing', { state: AGENT_STATE_INITIALIZING });
    gateway.touchPeerHeartbeat('peer-cooldown', { state: AGENT_STATE_RUNNING });
    gateway.recordPeerOverloaded('peer-cooldown', { retryAfterMs: 15_000 });
    gateway.touchPeerHeartbeat('peer-shutting-down', { state: AGENT_STATE_SHUTTING_DOWN });
    gateway.touchPeerHeartbeat('peer-healthy', { state: AGENT_STATE_RUNNING });

    const response = gateway.emitOverloadedResponse(makeRequest('req-health-filter', true));

    expect(response.accepted).toBe(false);
    expect(response.rejectionCode).toBe(ErrorCode.REDIRECT);
    expect(response.redirectToAgentId).toBe('peer-healthy');
  });

  it('uses round-robin selection across healthy peers', () => {
    const clock = { nowMs: 10_000 };
    const gateway = new GatewayRedirectEmitter({
      agentId: 'gateway-1',
      capabilities: ['plan', 'execute'],
      nowMsFn: () => clock.nowMs,
      peerDescriptors: [
        peerDescriptor('peer-1'),
        peerDescriptor('peer-2'),
        peerDescriptor('peer-3'),
      ],
    });

    gateway.touchPeerHeartbeat('peer-1', { state: AGENT_STATE_RUNNING });
    gateway.touchPeerHeartbeat('peer-2', { state: AGENT_STATE_RUNNING });
    gateway.touchPeerHeartbeat('peer-3', { state: AGENT_STATE_RUNNING });

    const seen: string[] = [];
    for (let idx = 0; idx < 6; idx += 1) {
      const response = gateway.emitOverloadedResponse(
        makeRequest(`req-rr-${idx}`, true)
      );
      seen.push(response.redirectToAgentId ?? '');
    }

    expect(seen).toEqual([
      'peer-1',
      'peer-2',
      'peer-3',
      'peer-1',
      'peer-2',
      'peer-3',
    ]);
  });
});
