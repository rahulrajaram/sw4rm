import { ErrorCode } from '../internal/errorMapping.js';
import type { HandoffRequest, HandoffResponse } from '../clients/handoff.js';

export const REGISTRATION_TYPE_STANDARD_AGENT = 1;
export const REGISTRATION_TYPE_SWARM_GATEWAY = 2;

export const AGENT_STATE_INITIALIZING = 1;
export const AGENT_STATE_RUNNING = 4;
export const AGENT_STATE_FAILED = 10;
export const AGENT_STATE_SHUTTING_DOWN = 11;

export const DEFAULT_PEER_LIVENESS_THRESHOLD_MS = 30_000;

export const NON_SERVING_AGENT_STATES = new Set<number>([
  AGENT_STATE_INITIALIZING,
  AGENT_STATE_FAILED,
  AGENT_STATE_SHUTTING_DOWN,
]);

export interface GatewayPeerDescriptor {
  agentId: string;
  registrationType: number;
  capabilities: string[];
}

export interface PeerRuntimeState {
  state: number;
  lastHeartbeatMs: number;
  cooldownUntilMs: number;
}

export interface PeerSelectorOptions {
  localAgentId: string;
  localCapabilities: string[];
  nowMsFn?: () => number;
  peerHealthFn?: (peer: GatewayPeerDescriptor) => boolean;
  livenessThresholdMs?: number;
}

export interface UpdatePeerRuntimeStateOptions {
  state?: number;
  lastHeartbeatMs?: number;
  cooldownUntilMs?: number;
}

export interface RecordPeerOverloadedOptions {
  retryAfterMs?: number;
  localCooldownMs?: number;
}

export interface GatewayRedirectEmitterOptions {
  agentId: string;
  capabilities?: string[];
  retryAfterMs?: number;
  peerDescriptors?: GatewayPeerDescriptor[];
  peerHealthFn?: (peer: GatewayPeerDescriptor) => boolean;
  nowMsFn?: () => number;
  peerLivenessThresholdMs?: number;
}

export class GatewayValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'GatewayValidationError';
  }
}

function defaultNowMs(): number {
  return Date.now();
}

function sameCapabilities(
  peerCapabilities: string[],
  localCapabilities: Set<string>
): boolean {
  const peerSet = new Set(peerCapabilities);
  if (peerSet.size !== localCapabilities.size) {
    return false;
  }
  for (const localCapability of localCapabilities) {
    if (!peerSet.has(localCapability)) {
      return false;
    }
  }
  return true;
}

export class PeerSelector {
  private readonly localAgentId: string;
  private readonly localCapabilities: Set<string>;
  private readonly nowMs: () => number;
  private readonly peerHealthFn: (peer: GatewayPeerDescriptor) => boolean;
  private readonly livenessThresholdMs: number;

  private peers: GatewayPeerDescriptor[] = [];
  private runtime: Map<string, PeerRuntimeState> = new Map();
  private rrCursor = 0;

  constructor(options: PeerSelectorOptions) {
    const threshold = options.livenessThresholdMs ?? DEFAULT_PEER_LIVENESS_THRESHOLD_MS;
    if (threshold < 0) {
      throw new GatewayValidationError('livenessThresholdMs must be >= 0');
    }

    this.localAgentId = options.localAgentId;
    this.localCapabilities = new Set(options.localCapabilities ?? []);
    this.nowMs = options.nowMsFn ?? defaultNowMs;
    this.peerHealthFn = options.peerHealthFn ?? (() => true);
    this.livenessThresholdMs = threshold;
  }

  setPeers(peers: GatewayPeerDescriptor[]): void {
    this.peers = [...peers];

    const activeIds = new Set(this.peers.map((peer) => peer.agentId));
    for (const agentId of [...this.runtime.keys()]) {
      if (!activeIds.has(agentId)) {
        this.runtime.delete(agentId);
      }
    }

    const nowMs = this.nowMs();
    for (const peer of this.peers) {
      if (!this.runtime.has(peer.agentId)) {
        this.runtime.set(peer.agentId, {
          state: AGENT_STATE_RUNNING,
          lastHeartbeatMs: nowMs,
          cooldownUntilMs: 0,
        });
      }
    }
  }

  updatePeerRuntimeState(
    agentId: string,
    options: UpdatePeerRuntimeStateOptions = {}
  ): void {
    const runtime = this.ensureRuntime(agentId);
    if (options.state !== undefined) {
      runtime.state = options.state;
    }
    if (options.lastHeartbeatMs !== undefined) {
      runtime.lastHeartbeatMs = Math.max(Math.floor(options.lastHeartbeatMs), 0);
    }
    if (options.cooldownUntilMs !== undefined) {
      runtime.cooldownUntilMs = Math.max(Math.floor(options.cooldownUntilMs), 0);
    }
    this.runtime.set(agentId, runtime);
  }

  touchPeerHeartbeat(
    agentId: string,
    options: Pick<UpdatePeerRuntimeStateOptions, 'state'> & { nowMs?: number } = {}
  ): void {
    this.updatePeerRuntimeState(agentId, {
      state: options.state,
      lastHeartbeatMs: options.nowMs ?? this.nowMs(),
    });
  }

  recordPeerOverloaded(
    agentId: string,
    options: RecordPeerOverloadedOptions = {}
  ): void {
    const runtime = this.ensureRuntime(agentId);
    const nowMs = this.nowMs();
    const retryAfterMs = Math.max(Math.floor(options.retryAfterMs ?? 0), 0);
    const localCooldownMs = Math.max(Math.floor(options.localCooldownMs ?? 0), 0);
    const cooldownMs = Math.max(retryAfterMs, localCooldownMs);
    runtime.cooldownUntilMs = Math.max(runtime.cooldownUntilMs, nowMs + cooldownMs);
    this.runtime.set(agentId, runtime);
  }

  isEligible(peer: GatewayPeerDescriptor): boolean {
    if (peer.registrationType !== REGISTRATION_TYPE_SWARM_GATEWAY) {
      return false;
    }
    if (peer.agentId === this.localAgentId) {
      return false;
    }
    return sameCapabilities(peer.capabilities, this.localCapabilities);
  }

  selectPeer(): string {
    const healthy = this.peers.filter((peer) => this.isHealthy(peer));
    if (healthy.length === 0) {
      return '';
    }

    const idx = this.rrCursor % healthy.length;
    this.rrCursor += 1;
    return healthy[idx].agentId;
  }

  private ensureRuntime(agentId: string): PeerRuntimeState {
    const existing = this.runtime.get(agentId);
    if (existing !== undefined) {
      return existing;
    }
    return {
      state: AGENT_STATE_RUNNING,
      lastHeartbeatMs: this.nowMs(),
      cooldownUntilMs: 0,
    };
  }

  private isHealthy(peer: GatewayPeerDescriptor): boolean {
    if (!this.isEligible(peer)) {
      return false;
    }
    if (!this.peerHealthFn(peer)) {
      return false;
    }

    const runtime = this.runtime.get(peer.agentId);
    if (runtime === undefined) {
      return false;
    }

    const nowMs = this.nowMs();
    if (runtime.cooldownUntilMs > nowMs) {
      return false;
    }
    if (nowMs - runtime.lastHeartbeatMs > this.livenessThresholdMs) {
      return false;
    }
    if (NON_SERVING_AGENT_STATES.has(runtime.state)) {
      return false;
    }
    return true;
  }
}

export class GatewayRedirectEmitter {
  private readonly retryAfterMs: number;
  private readonly peerSelector: PeerSelector;

  constructor(options: GatewayRedirectEmitterOptions) {
    if ((options.retryAfterMs ?? 0) < 0) {
      throw new GatewayValidationError('retryAfterMs must be >= 0');
    }

    this.retryAfterMs = options.retryAfterMs ?? 1000;
    this.peerSelector = new PeerSelector({
      localAgentId: options.agentId,
      localCapabilities: options.capabilities ?? [],
      nowMsFn: options.nowMsFn,
      peerHealthFn: options.peerHealthFn,
      livenessThresholdMs: options.peerLivenessThresholdMs,
    });
    this.peerSelector.setPeers(options.peerDescriptors ?? []);
  }

  setPeerDescriptors(peers: GatewayPeerDescriptor[]): void {
    this.peerSelector.setPeers(peers);
  }

  updatePeerRuntimeState(
    agentId: string,
    options: UpdatePeerRuntimeStateOptions = {}
  ): void {
    this.peerSelector.updatePeerRuntimeState(agentId, options);
  }

  touchPeerHeartbeat(
    agentId: string,
    options: Pick<UpdatePeerRuntimeStateOptions, 'state'> & { nowMs?: number } = {}
  ): void {
    this.peerSelector.touchPeerHeartbeat(agentId, options);
  }

  recordPeerOverloaded(
    agentId: string,
    options: RecordPeerOverloadedOptions = {}
  ): void {
    this.peerSelector.recordPeerOverloaded(agentId, options);
  }

  emitOverloadedResponse(request: HandoffRequest): HandoffResponse {
    if (request.delegationPolicy?.allowSpilloverRouting) {
      const redirectToAgentId = this.peerSelector.selectPeer();
      if (redirectToAgentId) {
        return {
          requestId: request.requestId,
          accepted: false,
          rejectionReason: 'Gateway at capacity; redirect to peer gateway',
          rejectionCode: ErrorCode.REDIRECT,
          retryAfterMs: 0,
          redirectToAgentId,
        };
      }
    }

    return {
      requestId: request.requestId,
      accepted: false,
      rejectionReason: 'Gateway at capacity',
      rejectionCode: ErrorCode.OVERLOADED,
      retryAfterMs: this.retryAfterMs,
    };
  }
}
