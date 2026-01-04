#!/usr/bin/env tsx

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
 * Handoff Service gRPC Server Implementation.
 *
 * This module provides the gRPC server implementation for the HandoffService,
 * enabling distributed agent-to-agent task handoffs with centralized state.
 */

import * as grpc from '@grpc/grpc-js';

// Handoff status enum values (from proto)
export enum HandoffStatus {
  HANDOFF_STATUS_UNSPECIFIED = 0,
  PENDING = 1,
  ACCEPTED = 2,
  REJECTED = 3,
  COMPLETED = 4,
  EXPIRED = 5,
}

// Type definitions matching proto messages
export interface HandoffRequest {
  request_id: string;
  from_agent: string;
  to_agent: string;
  reason: string;
  context_snapshot: Buffer;
  capabilities_required: string[];
  priority: number;
  timeout?: { seconds: number; nanos: number };
}

export interface HandoffResponse {
  request_id: string;
  accepted: boolean;
  accepting_agent: string;
  rejection_reason: string;
}

export interface GetPendingHandoffsRequest {
  agent_id: string;
}

export interface GetPendingHandoffsResponse {
  pending_requests: HandoffRequest[];
}

export interface CompleteHandoffRequest {
  request_id: string;
  status: number;
}

export interface CompleteHandoffResponse {
  success: boolean;
  message: string;
}

/**
 * gRPC server implementation for HandoffService.
 *
 * Provides centralized handoff coordination for distributed agent deployments.
 * Thread-safe implementation using Maps for state storage.
 */
export class HandoffServiceImpl {
  private requests: Map<string, HandoffRequest> = new Map();
  private responses: Map<string, HandoffResponse> = new Map();
  private pendingByAgent: Map<string, Set<string>> = new Map();
  private status: Map<string, number> = new Map();

  constructor() {
    console.log('HandoffService initialized');
  }

  /**
   * Request a handoff to another agent.
   */
  requestHandoff(
    call: grpc.ServerUnaryCall<HandoffRequest, any>,
    callback: grpc.sendUnaryData<any>
  ): void {
    const request = call.request;
    const requestId = request.request_id;
    const fromAgent = request.from_agent;
    const toAgent = request.to_agent;

    // Validate required fields
    if (!requestId) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'request_id is required',
      });
      return;
    }

    if (!fromAgent) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'from_agent is required',
      });
      return;
    }

    if (!toAgent) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'to_agent is required',
      });
      return;
    }

    // Check for duplicates
    if (this.requests.has(requestId)) {
      callback({
        code: grpc.status.ALREADY_EXISTS,
        message: `Handoff request '${requestId}' already exists`,
      });
      return;
    }

    // Store the request
    this.requests.set(requestId, request);
    this.status.set(requestId, HandoffStatus.PENDING);

    // Add to pending queue for target agent
    if (!this.pendingByAgent.has(toAgent)) {
      this.pendingByAgent.set(toAgent, new Set());
    }
    this.pendingByAgent.get(toAgent)!.add(requestId);

    console.log(`Handoff requested: ${requestId} from ${fromAgent} to ${toAgent}`);

    callback(null, {});
  }

  /**
   * Accept a pending handoff request.
   */
  acceptHandoff(
    call: grpc.ServerUnaryCall<HandoffResponse, any>,
    callback: grpc.sendUnaryData<any>
  ): void {
    const request = call.request;
    const requestId = request.request_id;

    // Check if request exists
    if (!this.requests.has(requestId)) {
      callback({
        code: grpc.status.NOT_FOUND,
        message: `Handoff request '${requestId}' not found`,
      });
      return;
    }

    // Check current status
    if (this.status.get(requestId) !== HandoffStatus.PENDING) {
      callback({
        code: grpc.status.FAILED_PRECONDITION,
        message: `Handoff '${requestId}' is not in PENDING status`,
      });
      return;
    }

    // Update status
    this.status.set(requestId, HandoffStatus.ACCEPTED);

    // Store response
    const response: HandoffResponse = {
      request_id: requestId,
      accepted: true,
      accepting_agent: request.accepting_agent || '',
      rejection_reason: '',
    };
    this.responses.set(requestId, response);

    // Remove from pending queue
    const originalRequest = this.requests.get(requestId)!;
    const toAgent = originalRequest.to_agent;
    if (this.pendingByAgent.has(toAgent)) {
      this.pendingByAgent.get(toAgent)!.delete(requestId);
    }

    console.log(`Handoff accepted: ${requestId} by ${request.accepting_agent}`);

    callback(null, {});
  }

  /**
   * Reject a pending handoff request.
   */
  rejectHandoff(
    call: grpc.ServerUnaryCall<HandoffResponse, any>,
    callback: grpc.sendUnaryData<any>
  ): void {
    const request = call.request;
    const requestId = request.request_id;

    // Check if request exists
    if (!this.requests.has(requestId)) {
      callback({
        code: grpc.status.NOT_FOUND,
        message: `Handoff request '${requestId}' not found`,
      });
      return;
    }

    // Check current status
    if (this.status.get(requestId) !== HandoffStatus.PENDING) {
      callback({
        code: grpc.status.FAILED_PRECONDITION,
        message: `Handoff '${requestId}' is not in PENDING status`,
      });
      return;
    }

    // Update status
    this.status.set(requestId, HandoffStatus.REJECTED);

    // Store response
    const response: HandoffResponse = {
      request_id: requestId,
      accepted: false,
      accepting_agent: '',
      rejection_reason: request.rejection_reason || 'Rejected',
    };
    this.responses.set(requestId, response);

    // Remove from pending queue
    const originalRequest = this.requests.get(requestId)!;
    const toAgent = originalRequest.to_agent;
    if (this.pendingByAgent.has(toAgent)) {
      this.pendingByAgent.get(toAgent)!.delete(requestId);
    }

    console.log(`Handoff rejected: ${requestId}, reason: ${request.rejection_reason}`);

    callback(null, {});
  }

  /**
   * Get all pending handoff requests for an agent.
   */
  getPendingHandoffs(
    call: grpc.ServerUnaryCall<GetPendingHandoffsRequest, GetPendingHandoffsResponse>,
    callback: grpc.sendUnaryData<GetPendingHandoffsResponse>
  ): void {
    const agentId = call.request.agent_id;
    const pendingIds = this.pendingByAgent.get(agentId) || new Set();
    const pendingRequests: HandoffRequest[] = [];

    for (const requestId of pendingIds) {
      const request = this.requests.get(requestId);
      const status = this.status.get(requestId);
      if (request && status === HandoffStatus.PENDING) {
        pendingRequests.push(request);
      }
    }

    console.log(`GetPendingHandoffs for ${agentId}: ${pendingRequests.length} pending`);

    callback(null, { pending_requests: pendingRequests });
  }

  /**
   * Complete or expire a handoff.
   */
  completeHandoff(
    call: grpc.ServerUnaryCall<CompleteHandoffRequest, CompleteHandoffResponse>,
    callback: grpc.sendUnaryData<CompleteHandoffResponse>
  ): void {
    const request = call.request;
    const requestId = request.request_id;
    const newStatus = request.status;

    // Check if request exists
    if (!this.requests.has(requestId)) {
      callback(null, {
        success: false,
        message: `Handoff request '${requestId}' not found`,
      });
      return;
    }

    // Update status
    this.status.set(requestId, newStatus);

    // Clean up pending queue
    const originalRequest = this.requests.get(requestId)!;
    const toAgent = originalRequest.to_agent;
    if (this.pendingByAgent.has(toAgent)) {
      this.pendingByAgent.get(toAgent)!.delete(requestId);
    }

    const statusName = newStatus === HandoffStatus.COMPLETED ? 'COMPLETED' : 'EXPIRED';
    console.log(`Handoff completed: ${requestId} with status ${statusName}`);

    callback(null, {
      success: true,
      message: `Handoff '${requestId}' marked as ${statusName}`,
    });
  }

  // Helper methods

  getStatus(requestId: string): number | undefined {
    return this.status.get(requestId);
  }

  getResponse(requestId: string): HandoffResponse | undefined {
    return this.responses.get(requestId);
  }

  clearAll(): void {
    this.requests.clear();
    this.responses.clear();
    this.pendingByAgent.clear();
    this.status.clear();
    console.log('HandoffService state cleared');
  }

  /**
   * Get the service handlers for gRPC registration.
   */
  getHandlers(): { [key: string]: grpc.handleUnaryCall<any, any> } {
    return {
      RequestHandoff: this.requestHandoff.bind(this),
      AcceptHandoff: this.acceptHandoff.bind(this),
      RejectHandoff: this.rejectHandoff.bind(this),
      GetPendingHandoffs: this.getPendingHandoffs.bind(this),
      CompleteHandoff: this.completeHandoff.bind(this),
    };
  }
}
