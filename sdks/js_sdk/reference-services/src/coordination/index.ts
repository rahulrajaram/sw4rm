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
 * SW4RM Coordination Services.
 *
 * This module provides gRPC server implementations for the three in-memory
 * coordination services:
 *
 * - HandoffServiceImpl: Agent-to-agent task handoff coordination
 * - WorkflowServiceImpl: DAG-based workflow orchestration
 * - NegotiationRoomServiceImpl: Multi-agent artifact approval workflows
 *
 * These services maintain centralized state that can be shared across
 * distributed agent deployments. All three SDKs (Python, Rust, TypeScript)
 * can connect to these services as gRPC clients.
 */

export { HandoffServiceImpl, HandoffStatus } from './handoff-service.js';
export { WorkflowServiceImpl, NodeStatus, TriggerType } from './workflow-service.js';
export { NegotiationRoomServiceImpl, ArtifactType, DecisionOutcome } from './negotiation-room-service.js';

// Re-export types
export type {
  HandoffRequest,
  HandoffResponse,
  GetPendingHandoffsRequest,
  GetPendingHandoffsResponse,
  CompleteHandoffRequest,
  CompleteHandoffResponse,
} from './handoff-service.js';

export type {
  WorkflowNode,
  WorkflowDefinition,
  NodeState,
  WorkflowState,
  CreateWorkflowRequest,
  CreateWorkflowResponse,
  StartWorkflowRequest,
  StartWorkflowResponse,
  GetWorkflowStateRequest,
  GetWorkflowStateResponse,
  ResumeWorkflowRequest,
  ResumeWorkflowResponse,
} from './workflow-service.js';

export type {
  NegotiationProposal,
  NegotiationVote,
  AggregatedScore,
  NegotiationDecision,
  SubmitProposalRequest,
  SubmitProposalResponse,
  SubmitVoteRequest,
  SubmitVoteResponse,
  GetVotesRequest,
  GetVotesResponse,
  GetDecisionRequest,
  GetDecisionResponse,
  WaitForDecisionRequest,
  WaitForDecisionResponse,
} from './negotiation-room-service.js';
