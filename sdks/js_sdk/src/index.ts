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

// SW4RM JavaScript SDK
export const version = '0.5.0';

// Clients
export * from './clients/router.js';
export * from './clients/scheduler.js';
export * from './clients/schedulerPolicy.js';
export * from './clients/worktree.js';
export * from './clients/tool.js';
export {
  LoggingClient,
  type LogEvent,
  // Skip Timestamp as it conflicts with internal/envelope.js
} from './clients/logging.js';
export * from './clients/activity.js';
export * from './clients/hitl.js';
export * from './clients/negotiation.js';
export * from './clients/reasoning.js';
export * from './clients/connector.js';
export * from './clients/registry.js';

// Phase 2 Clients (Negotiation Room, Handoff, Workflow)
export * from './clients/negotiationRoom.js';
export * from './clients/negotiationRoomStore.js';
export * from './clients/handoff.js';
export * from './clients/workflow.js';

// Internal helpers (exported for advanced usage)
export { 
  buildEnvelope,
  type EnvelopeBuilt,
  type EnvelopeInput,
  nowTimestamp,
  type Timestamp,
  // Skip MessageType as it's already exported from constants
} from './internal/envelope.js';
export * from './internal/errorMapping.js';
export {
  ClientOptions,
  BaseClient,
  // Skip RetryPolicy — canonical version exported from agentConfig.js
} from './internal/baseClient.js';
export * from './internal/time.js';
export * from './internal/interceptors.js';
export * from './internal/worktreeState.js';
export * from './internal/worktreePolicy.js';
export * from './internal/runtime/activityBuffer.js';
export {
  AckState,
  ACKLifecycleManager,
  // Skip AckStage — canonical version exported from constants/index.js
} from './internal/runtime/ackLifecycle.js';
export {
  EnvelopeLike,
  MessageProcessor,
  // Skip MessageType — canonical version exported from constants/index.js
} from './internal/runtime/messageProcessor.js';
export * from './runtime/ackHelpers.js';
export * from './runtime/activitySync.js';
export * from './runtime/streams.js';
export * from './runtime/negotiationEvents.js';
export * from './persistence/persistence.js';

// Phase 2 Runtime (Voting, Policy Store, Agent State)
export * from './runtime/voting.js';
export * from './runtime/policyStore.js';
export {
  AgentState,
  isValidTransition,
  getValidTransitions,
  type AgentLifecycleHooks,
  AgentStateMachine,
  // Skip StateTransitionError — canonical version exported from internal/errorMapping.js
} from './runtime/agentState.js';
export * from './internal/ids.js';
export * from './internal/idempotency.js';
export * from './runtime/persistenceAdapter.js';
export * from './internal/errorMapper.js';
export * from './internal/ack.js';
export * from './internal/control.js';

// Constants (all protocol enums)
export {
  CommunicationClass,
  DebateIntensity,
  HitlReasonType,
  AckStage,
  EnvelopeState,
  WorktreeStateEnum,
  DEFAULT_ACK_TIMEOUT_MS,
  DEDUP_WINDOW_S,
  isTerminalEnvelopeState,
  updateEnvelopeState,
  // Skip ErrorCode, MessageType, AgentState — already exported from their source modules
} from './constants/index.js';

// Audit module
export * from './audit.js';

// Centralized agent configuration
export * from './agentConfig.js';

// Persistent Activity Buffer (Three-ID model)
export {
  type EnvelopeRecord,
  PersistentActivityBuffer,
  // Skip PersistenceBackend, JSONFilePersistence — canonical versions exported from persistence/persistence.js
} from './persistentActivityBuffer.js';

// Secrets (experimental)
export * from './secrets/types.js'
export * from './secrets/errors.js'
export * from './secrets/backend.js'
export * from './secrets/resolver.js'
export * from './secrets/backends/file.js'
export * from './secrets/backends/keyring.js'
export * from './secrets/factory.js'
