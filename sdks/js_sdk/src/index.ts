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
export const version = '0.3.0';

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
export * from './internal/baseClient.js';
export * from './internal/time.js';
export * from './internal/interceptors.js';
export * from './internal/worktreeState.js';
export * from './internal/worktreePolicy.js';
export * from './internal/runtime/activityBuffer.js';
export * from './internal/runtime/ackLifecycle.js';
export * from './internal/runtime/messageProcessor.js';
export * from './runtime/ackHelpers.js';
export * from './runtime/activitySync.js';
export * from './runtime/streams.js';
export * from './runtime/negotiationEvents.js';
export * from './persistence/persistence.js';
export * from './internal/ids.js';
export * from './internal/idempotency.js';
export * from './runtime/persistenceAdapter.js';
export * from './internal/errorMapper.js';
export * from './internal/ack.js';
export * from './internal/control.js';

// Secrets (experimental)
export * from './secrets/types.js'
export * from './secrets/errors.js'
export * from './secrets/backend.js'
export * from './secrets/resolver.js'
export * from './secrets/backends/file.js'
export * from './secrets/backends/keyring.js'
export * from './secrets/factory.js'
