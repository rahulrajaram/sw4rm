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

/**
 * Handoff client for SW4RM.
 *
 * This module provides the HandoffClient for managing agent-to-agent task
 * handoffs. The handoff pattern enables:
 * - Graceful transfer of work between agents
 * - Context preservation during handoff
 * - Capability-based routing to appropriate agents
 *
 * Based on handoff.proto definitions.
 */
import { ErrorCode } from '../internal/errorMapping.js';

/**
 * Status of a handoff request.
 */
export enum HandoffStatus {
  HANDOFF_STATUS_UNSPECIFIED = 0,
  PENDING = 1,
  ACCEPTED = 2,
  REJECTED = 3,
  COMPLETED = 4,
  EXPIRED = 5,
}

export const DEFAULT_MAX_RETRIES_ON_OVERLOADED = 2;
export const DEFAULT_INITIAL_BACKOFF_MS = 250;
export const DEFAULT_BACKOFF_MULTIPLIER = 2.0;
export const DEFAULT_MAX_BACKOFF_MS = 2000;
export const DEFAULT_MAX_REDIRECTS = 0;

/**
 * SW4-004 budget envelope for cross-swarm delegation.
 */
export interface BudgetEnvelope {
  tokenBudgetRemaining?: number;
  wallTimeRemainingMs?: number;
  /** Required for cross-swarm delegation. */
  deadlineEpochMs: number;
  currentDepth?: number;
  maxDelegationDepth?: number;
}

/**
 * SW4-004/SW4-005 delegation policy envelope.
 */
export interface SwarmDelegationPolicy {
  maxRetriesOnOverloaded?: number;
  initialBackoffMs?: number;
  backoffMultiplier?: number;
  maxBackoffMs?: number;
  allowSpilloverRouting?: boolean;
  maxRedirects?: number;
}

/**
 * A request to hand off work from one agent to another.
 *
 * Contains the context needed for the receiving agent to continue
 * the work, including capability requirements and priority information.
 */
export interface HandoffRequest {
  /** Unique identifier for this handoff request */
  requestId: string;
  /** Agent ID of the agent initiating the handoff */
  fromAgent: string;
  /** Agent ID of the target agent (or empty for capability-based routing) */
  toAgent: string;
  /** Human-readable reason for the handoff */
  reason: string;
  /** Serialized context snapshot for the receiving agent */
  contextSnapshot: Uint8Array;
  /** List of capabilities required by the receiving agent */
  capabilitiesRequired: string[];
  /** Priority level of the handoff (lower is higher priority) */
  priority: number;
  /** Timeout in milliseconds for the handoff to be accepted */
  timeoutMs?: number;
  /** SW4-004 budget envelope for cross-swarm handoff */
  budget?: BudgetEnvelope;
  /** SW4-004/SW4-005 delegation policy envelope */
  delegationPolicy?: SwarmDelegationPolicy;
  /** Timestamp when the request was created (ISO-8601 string) */
  createdAt?: string;
}

/**
 * Response to a handoff request.
 *
 * Indicates whether the handoff was accepted and by whom, or provides
 * a rejection reason.
 */
export interface HandoffResponse {
  /** Identifier of the handoff request being responded to */
  requestId: string;
  /** Whether the handoff was accepted */
  accepted: boolean;
  /** Agent ID of the agent that accepted the handoff (if accepted) */
  acceptingAgent?: string;
  /** Reason for rejection (if not accepted) */
  rejectionReason?: string;
  /** SW4-004/SW4-005 rejection code */
  rejectionCode?: ErrorCode;
  /** SW4-004 retry hint in milliseconds (for OVERLOADED) */
  retryAfterMs?: number;
  /** SW4-005 redirect target agent ID */
  redirectToAgentId?: string;
}

export interface RejectHandoffOptions {
  rejectionCode?: ErrorCode;
  retryAfterMs?: number;
  redirectToAgentId?: string;
}

function defaultDelegationPolicy(): SwarmDelegationPolicy {
  return {
    maxRetriesOnOverloaded: DEFAULT_MAX_RETRIES_ON_OVERLOADED,
    initialBackoffMs: DEFAULT_INITIAL_BACKOFF_MS,
    backoffMultiplier: DEFAULT_BACKOFF_MULTIPLIER,
    maxBackoffMs: DEFAULT_MAX_BACKOFF_MS,
    allowSpilloverRouting: false,
    maxRedirects: DEFAULT_MAX_REDIRECTS,
  };
}

function normalizeDelegationPolicy(
  policy?: SwarmDelegationPolicy
): SwarmDelegationPolicy {
  const defaults = defaultDelegationPolicy();
  const maxRetriesOnOverloaded = policy?.maxRetriesOnOverloaded;
  const initialBackoffMs = policy?.initialBackoffMs;
  const backoffMultiplier = policy?.backoffMultiplier;
  const maxBackoffMs = policy?.maxBackoffMs;
  const allowSpilloverRouting = policy?.allowSpilloverRouting;
  const maxRedirects = policy?.maxRedirects;

  return {
    maxRetriesOnOverloaded:
      maxRetriesOnOverloaded === undefined
        ? defaults.maxRetriesOnOverloaded
        : maxRetriesOnOverloaded,
    initialBackoffMs:
      initialBackoffMs !== undefined && initialBackoffMs > 0
        ? initialBackoffMs
        : defaults.initialBackoffMs,
    backoffMultiplier:
      backoffMultiplier !== undefined && backoffMultiplier > 0
        ? backoffMultiplier
        : defaults.backoffMultiplier,
    maxBackoffMs:
      maxBackoffMs !== undefined && maxBackoffMs > 0
        ? maxBackoffMs
        : defaults.maxBackoffMs,
    allowSpilloverRouting: allowSpilloverRouting ?? defaults.allowSpilloverRouting,
    maxRedirects: maxRedirects === undefined ? defaults.maxRedirects : maxRedirects,
  };
}

/**
 * Error thrown when a handoff operation fails validation.
 */
export class HandoffValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'HandoffValidationError';
  }
}

/**
 * Error thrown when a handoff operation times out.
 */
export class HandoffTimeoutError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'HandoffTimeoutError';
  }
}

/**
 * Client for managing agent-to-agent handoffs.
 *
 * Enables agents to transfer work to other agents while preserving
 * context and ensuring proper capability matching. This is an in-memory
 * implementation for Phase 2; future phases will integrate with gRPC services.
 */
export class HandoffClient {
  private requests: Map<string, HandoffRequest> = new Map();
  private responses: Map<string, HandoffResponse> = new Map();
  private pendingByAgent: Map<string, Set<string>> = new Map();

  /**
   * Request a handoff to another agent.
   *
   * Initiates a handoff request that the target agent can accept or reject.
   * The request is stored and made available to the target agent via
   * getPendingHandoffs().
   *
   * @param request - The handoff request containing context and requirements
   * @returns The response once the handoff is accepted, rejected, or times out
   * @throws HandoffValidationError if a request with the same ID already exists
   *
   * @example
   * ```typescript
   * const client = new HandoffClient();
   * const request: HandoffRequest = {
   *   requestId: "handoff-123",
   *   fromAgent: "agent-a",
   *   toAgent: "agent-b",
   *   reason: "Capability mismatch",
   *   contextSnapshot: new TextEncoder().encode('{"state": "in_progress"}'),
   *   capabilitiesRequired: ["code_review"],
   *   priority: 5
   * };
   * const response = await client.requestHandoff(request);
   * ```
   */
  async requestHandoff(request: HandoffRequest): Promise<HandoffResponse> {
    if (this.requests.has(request.requestId)) {
      throw new HandoffValidationError(
        `Handoff request with ID '${request.requestId}' already exists`
      );
    }
    if (
      request.budget !== undefined &&
      (!request.budget.deadlineEpochMs || request.budget.deadlineEpochMs <= 0)
    ) {
      throw new HandoffValidationError(
        'budget.deadlineEpochMs is required for cross-swarm delegation'
      );
    }

    // Set createdAt if not provided
    const requestWithTimestamp: HandoffRequest = {
      ...request,
      createdAt: request.createdAt || new Date().toISOString(),
      delegationPolicy:
        request.budget !== undefined || request.delegationPolicy !== undefined
          ? normalizeDelegationPolicy(request.delegationPolicy)
          : undefined,
    };

    this.requests.set(request.requestId, requestWithTimestamp);

    // Add to pending list for target agent
    if (request.toAgent) {
      if (!this.pendingByAgent.has(request.toAgent)) {
        this.pendingByAgent.set(request.toAgent, new Set());
      }
      this.pendingByAgent.get(request.toAgent)!.add(request.requestId);
    }

    // Wait for response with timeout
    const timeoutMs = request.timeoutMs || 30000;
    const startTime = Date.now();
    const pollIntervalMs = 100;

    while (Date.now() - startTime < timeoutMs) {
      const response = this.responses.get(request.requestId);
      if (response) {
        return response;
      }
      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }

    // Timeout - create rejection response
    const timeoutResponse: HandoffResponse = {
      requestId: request.requestId,
      accepted: false,
      rejectionReason: `Handoff request timed out after ${timeoutMs}ms`,
      rejectionCode: ErrorCode.ACK_TIMEOUT,
    };
    this.responses.set(request.requestId, timeoutResponse);

    // Clean up pending list
    if (request.toAgent && this.pendingByAgent.has(request.toAgent)) {
      this.pendingByAgent.get(request.toAgent)!.delete(request.requestId);
    }

    return timeoutResponse;
  }

  /**
   * Accept a pending handoff request.
   *
   * Called by the target agent to accept a handoff. After acceptance,
   * the agent should process the context snapshot and continue the work.
   *
   * @param handoffId - The ID of the handoff request to accept
   * @throws HandoffValidationError if no request exists with the given ID
   * @throws HandoffValidationError if the request has already been responded to
   *
   * @example
   * ```typescript
   * // Get pending handoffs for this agent
   * const pending = await client.getPendingHandoffs("agent-b");
   * if (pending.length > 0) {
   *   await client.acceptHandoff(pending[0].requestId);
   * }
   * ```
   */
  async acceptHandoff(handoffId: string): Promise<void> {
    const request = this.requests.get(handoffId);
    if (!request) {
      throw new HandoffValidationError(
        `No handoff request found with ID '${handoffId}'`
      );
    }

    if (this.responses.has(handoffId)) {
      throw new HandoffValidationError(
        `Handoff request '${handoffId}' has already been responded to`
      );
    }

    const response: HandoffResponse = {
      requestId: handoffId,
      accepted: true,
      acceptingAgent: request.toAgent,
    };

    this.responses.set(handoffId, response);

    // Remove from pending list
    if (request.toAgent && this.pendingByAgent.has(request.toAgent)) {
      this.pendingByAgent.get(request.toAgent)!.delete(handoffId);
    }
  }

  /**
   * Reject a pending handoff request.
   *
   * Called by the target agent to reject a handoff. A reason should be
   * provided to help the originating agent determine next steps.
   *
   * @param handoffId - The ID of the handoff request to reject
   * @param reason - Human-readable reason for the rejection
   * @throws HandoffValidationError if no request exists with the given ID
   * @throws HandoffValidationError if the request has already been responded to
   *
   * @example
   * ```typescript
   * await client.rejectHandoff("handoff-123", "Agent at capacity");
   * ```
   */
  async rejectHandoff(
    handoffId: string,
    reason: string,
    options?: RejectHandoffOptions
  ): Promise<void> {
    const request = this.requests.get(handoffId);
    if (!request) {
      throw new HandoffValidationError(
        `No handoff request found with ID '${handoffId}'`
      );
    }

    if (this.responses.has(handoffId)) {
      throw new HandoffValidationError(
        `Handoff request '${handoffId}' has already been responded to`
      );
    }

    const response: HandoffResponse = {
      requestId: handoffId,
      accepted: false,
      rejectionReason: reason,
      rejectionCode: options?.rejectionCode ?? ErrorCode.ERROR_CODE_UNSPECIFIED,
      retryAfterMs: options?.retryAfterMs,
      redirectToAgentId: options?.redirectToAgentId,
    };

    this.responses.set(handoffId, response);

    // Remove from pending list
    if (request.toAgent && this.pendingByAgent.has(request.toAgent)) {
      this.pendingByAgent.get(request.toAgent)!.delete(handoffId);
    }
  }

  /**
   * Get all pending handoff requests for an agent.
   *
   * Returns handoff requests that have been addressed to the specified
   * agent and have not yet been accepted or rejected.
   *
   * @param agentId - The ID of the agent to get pending handoffs for
   * @returns List of pending handoff requests for the agent
   *
   * @example
   * ```typescript
   * const pending = await client.getPendingHandoffs("agent-b");
   * console.log(`${pending.length} pending handoffs`);
   * for (const request of pending) {
   *   console.log(`From ${request.fromAgent}: ${request.reason}`);
   * }
   * ```
   */
  async getPendingHandoffs(agentId: string): Promise<HandoffRequest[]> {
    const pendingIds = this.pendingByAgent.get(agentId);
    if (!pendingIds) {
      return [];
    }

    const pending: HandoffRequest[] = [];
    for (const requestId of pendingIds) {
      const request = this.requests.get(requestId);
      if (request && !this.responses.has(requestId)) {
        pending.push(request);
      }
    }

    return pending;
  }

  /**
   * Get the response for a handoff request.
   *
   * Returns the response if the handoff has been accepted, rejected, or
   * timed out. Returns null if the handoff is still pending.
   *
   * @param handoffId - The ID of the handoff request
   * @returns The handoff response if available, null otherwise
   */
  async getHandoffResponse(handoffId: string): Promise<HandoffResponse | null> {
    return this.responses.get(handoffId) || null;
  }

  /**
   * Get the original handoff request.
   *
   * @param handoffId - The ID of the handoff request
   * @returns The handoff request if it exists, null otherwise
   */
  async getHandoffRequest(handoffId: string): Promise<HandoffRequest | null> {
    return this.requests.get(handoffId) || null;
  }
}
