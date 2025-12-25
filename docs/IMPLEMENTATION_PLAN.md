# SW4RM Protocol Alignment Plan

**Version:** 0.4.0-alpha
**Created:** 2025-12-23
**Status:** ACTIVE
**Scope:** Full Protocol Alignment (Spec, SDKs, Examples)

---

## Executive Summary

This plan ensures complete alignment between the SW4RM specification (`spec.md`), the `SPEC_REQUESTS` proposals, all SDK implementations (Python, JavaScript, Rust), and reference examples. It supersedes the previous implementation plan (v1.0.0) which focused solely on Python SDK parity and is now marked COMPLETED.

---

## Table of Contents

1. [Phase 0: Spec-Request Alignment](#phase-0-spec-request-alignment)
2. [Phase 1: Protocol Coherence Fixes](#phase-1-protocol-coherence-fixes)
3. [Phase 2: JavaScript SDK Parity](#phase-2-javascript-sdk-parity)
4. [Phase 3: Rust SDK Parity](#phase-3-rust-sdk-parity)
5. [Phase 4: Reference Examples](#phase-4-reference-examples)
6. [Phase 5: Documentation & Validation](#phase-5-documentation--validation)
7. [Gap Analysis Summary](#gap-analysis-summary)
8. [Risk Register](#risk-register)
9. [Dependency Graph](#dependency-graph)

---

## Current State Assessment

### SDK Completeness Matrix

| Feature | Python SDK | JavaScript SDK | Rust SDK |
|---------|------------|----------------|----------|
| RegistryClient | ✅ | ✅ | ✅ |
| RouterClient | ✅ | ✅ | ✅ |
| SchedulerClient | ✅ | ✅ | ✅ |
| WorktreeClient | ✅ | ✅ | ✅ |
| ToolClient | ✅ | ✅ | ✅ |
| HitlClient | ✅ | ✅ | ✅ |
| NegotiationClient | ✅ | ✅ | ✅ |
| ConnectorClient | ✅ | ✅ | ✅ |
| ReasoningClient | ✅ | ✅ | ✅ |
| LoggingClient | ✅ | ✅ | ✅ |
| ActivityClient | ✅ | ✅ | ✅ |
| SchedulerPolicyClient | ✅ | ✅ | ✅ |
| **NegotiationRoomClient** | ✅ | ✅ | ✅ |
| **HandoffClient** | ✅ | ✅ | ✅ |
| **WorkflowClient** | ✅ | ✅ | ✅ |
| Agent Runtime State Machine | ✅ | ✅ | ✅ |
| ActivityBuffer | ✅ | ✅ | ✅ |
| Worktree State Machine | ✅ | ✅ | ✅ |
| ACK Lifecycle | ✅ | ✅ | ✅ |
| Voting/Aggregation | ✅ | ✅ | ✅ |
| Policy Store | ✅ | ✅ | ✅ |

### Spec vs SPEC_REQUESTS Gap Summary

| SPEC_REQUEST Item | Spec Status | Proto Status |
|-------------------|-------------|--------------|
| 6.1 Negotiation Room Pattern | NOT in spec | ✅ `negotiation_room.proto` |
| 6.2 Three-ID Envelope Model | Partial (terminology mismatch) | ✅ `common.proto` |
| 6.3 Policy Profile | ✅ In spec | ✅ `policy.proto` |
| Handoff Protocol | NOT in spec | ✅ `handoff.proto` |
| Workflow Orchestration | NOT in spec | ✅ `workflow.proto` |

---

## Phase 0: Spec-Request Alignment

**Objective:** Update `spec.md` to incorporate all implemented proto services and resolve SPEC_REQUESTS gaps.

**File:** `/home/rahul/Documents/sigagent/documentation/protocol/spec.md`

### 0.1 Add Missing Spec Sections

#### 0.1.1 Section 17.5: Negotiation Room Pattern

- [ ] **0.1.1.1** Add normative section documenting producer-critic-coordinator model
- [ ] **0.1.1.2** Reference `negotiation_room.proto` message definitions:
  - `NegotiationProposal`
  - `NegotiationVote`
  - `NegotiationDecision`
- [ ] **0.1.1.3** Define `ArtifactType` enum semantics (REQUIREMENTS, PLAN, CODE, DEPLOYMENT)
- [ ] **0.1.1.4** Define `DecisionOutcome` enum semantics (APPROVED, REVISION_REQUESTED, ESCALATED_TO_HITL)
- [ ] **0.1.1.5** Document coordinator aggregation algorithm
- [ ] **0.1.1.6** Document policy application rules for auto-approve thresholds
- [ ] **0.1.1.7** Add sequence diagram for negotiation room flow

#### 0.1.2 Section 17.6: Agent Handoff Protocol

- [ ] **0.1.2.1** Add normative section for agent-to-agent task handoff
- [ ] **0.1.2.2** Reference `handoff.proto` definitions:
  - `HandoffRequest`
  - `HandoffResponse`
  - `HandoffService`
- [ ] **0.1.2.3** Document context preservation during handoff
- [ ] **0.1.2.4** Document capability matching requirements
- [ ] **0.1.2.5** Define handoff states: REQUESTED, ACCEPTED, REJECTED, IN_PROGRESS, COMPLETED
- [ ] **0.1.2.6** Add sequence diagram for handoff flow

#### 0.1.3 Section 17.7: Workflow Orchestration

- [ ] **0.1.3.1** Add normative section for DAG-based workflow execution
- [ ] **0.1.3.2** Reference `workflow.proto` definitions:
  - `WorkflowNode`
  - `WorkflowDefinition`
  - `WorkflowInstance`
  - `WorkflowService`
- [ ] **0.1.3.3** Document trigger types (EventTrigger, ScheduleTrigger, ManualTrigger)
- [ ] **0.1.3.4** Document node states: PENDING, RUNNING, COMPLETED, FAILED, SKIPPED
- [ ] **0.1.3.5** Define DAG validation requirements (cycle detection)
- [ ] **0.1.3.6** Document context passing between nodes
- [ ] **0.1.3.7** Add sequence diagram for workflow execution

### 0.2 Update Appendix with New Protos

- [ ] **0.2.1** Add `negotiation_room.proto` to spec appendix
- [ ] **0.2.2** Add `handoff.proto` to spec appendix
- [ ] **0.2.3** Add `workflow.proto` to spec appendix

### 0.3 Resolve Terminology Gaps

- [ ] **0.3.1** Clarify relationship between `EnvelopeState` (SPEC_REQUESTS §6.2) and `AckStage` (spec §11)
- [ ] **0.3.2** Add cross-reference table mapping SPEC_REQUESTS terminology to spec terminology
- [ ] **0.3.3** Document three-ID semantics explicitly:
  - `message_id`: Unique per attempt
  - `correlation_id`: Groups workflow/session
  - `idempotency_token`: Stable across retries

---

## Phase 1: Protocol Coherence Fixes

**Objective:** Fix internal inconsistencies in the spec and protos.

### 1.1 Proto Namespace Unification

**Issue:** Package namespace divergence across proto files.

**Status:** COMPLETED (2025-12-23)

| Proto File | Current Namespace | Expected Namespace |
|------------|-------------------|-------------------|
| `negotiation_room.proto` | ~~`sw4rm.v1`~~ | `sw4rm.negotiation_room` ✅ |
| `workflow.proto` | ~~`sw4rm.v1`~~ | `sw4rm.workflow` ✅ |
| `handoff.proto` | `sw4rm.handoff` | `sw4rm.handoff` ✅ |

- [x] **1.1.1** Update `negotiation_room.proto` package to `sw4rm.negotiation_room`
- [x] **1.1.2** Update `workflow.proto` package to `sw4rm.workflow`
- [ ] **1.1.3** Regenerate Python proto stubs: `make protos` (requires manual run)
- [ ] **1.1.4** Regenerate JavaScript proto stubs (requires manual run)
- [ ] **1.1.5** Regenerate Rust proto stubs (via `build.rs`) (requires manual run)
- [x] **1.1.6** Update all SDK imports to use new package names (N/A - SDK uses native types not generated stubs for these services)
- [x] **1.1.7** Document namespace convention in proto file headers (see negotiation_room.proto, workflow.proto, handoff.proto)

### 1.2 Message State Machine Consistency

**Issue:** Appendix C diagram shows ACKNOWLEDGED state not in prose.

**File:** `spec.md` lines 776-787

**Status:** COMPLETED (2025-12-23)

- [x] **1.2.1** Remove ACKNOWLEDGED from state diagram OR clarify it equals RECEIVED
- [x] **1.2.2** Ensure prose matches diagram exactly
- [x] **1.2.3** Add transition rules for late ACK reconciliation

### 1.3 Worktree State Machine Fix

**Issue:** `BIND_FAILED` state in proto but not in spec.

**File:** `spec.md` Section 16

**Status:** COMPLETED (2025-12-23)

- [x] **1.3.1** Add `BIND_FAILED` to Worktree state enum in spec
- [x] **1.3.2** Document as transient error state
- [x] **1.3.3** Add transition: `UNBOUND → BIND_FAILED` (on bind error)
- [x] **1.3.4** Add transition: `BIND_FAILED → UNBOUND` (on retry/reset)

### 1.4 Agent Lifecycle Missing Transitions

**Issue:** Missing timeout/escalation paths in agent state machine.

**Status:** COMPLETED (2025-12-23)

- [x] **1.4.1** Add `WAITING_RESOURCES → FAILED` transition (resource timeout)
- [x] **1.4.2** Add `RECOVERING → SHUTTING_DOWN` transition (recovery abort)
- [x] **1.4.3** Document timeout values for each state

### 1.5 Tool Execution Policy Documentation

**Issue:** `tool.proto` fields not enumerated in spec.

**Status:** COMPLETED (2025-12-23)

- [x] **1.5.1** Document `budget_cpu_ms` semantics in spec §18
- [x] **1.5.2** Document `budget_wall_ms` semantics
- [x] **1.5.3** Document `network_policy` enum values
- [x] **1.5.4** Document `privilege_level` enum values

### 1.6 Edge Case Documentation

**Status:** COMPLETED (2025-12-23)

- [x] **1.6.1** Document: What happens if negotiation timeout fires but HITL unavailable?
- [x] **1.6.2** Document: Expected behavior when Cancel called on streaming tool
- [x] **1.6.3** Document: Activity Buffer size limits (or lack thereof)

---

## Phase 2: JavaScript SDK Parity

**Objective:** Bring JavaScript SDK to feature parity with Python SDK.

**Directory:** `/home/rahul/Documents/sigagent/sdks/js_sdk/`

**Status:** COMPLETED (2025-12-23)

### 2.1 NegotiationRoomClient

**File:** `src/clients/negotiationRoom.ts` (new file)

- [x] **2.1.1** Create `NegotiationRoomClient` class
- [x] **2.1.2** Implement `submitProposal(proposal: NegotiationProposal): Promise<string>`
- [x] **2.1.3** Implement `submitVote(vote: NegotiationVote): Promise<void>`
- [x] **2.1.4** Implement `getVotes(artifactId: string): Promise<NegotiationVote[]>`
- [x] **2.1.5** Implement `getDecision(artifactId: string): Promise<NegotiationDecision | null>`
- [x] **2.1.6** Implement `waitForDecision(artifactId: string, timeoutMs: number): Promise<NegotiationDecision>`
- [x] **2.1.7** Add TypeScript types for all proto messages
- [ ] **2.1.8** Add unit tests in `tests/negotiationRoom.test.ts`

### 2.2 HandoffClient

**File:** `src/clients/handoff.ts` (new file)

- [x] **2.2.1** Create `HandoffClient` class
- [x] **2.2.2** Implement `requestHandoff(request: HandoffRequest): Promise<HandoffResponse>`
- [x] **2.2.3** Implement `acceptHandoff(handoffId: string): Promise<void>`
- [x] **2.2.4** Implement `rejectHandoff(handoffId: string, reason: string): Promise<void>`
- [x] **2.2.5** Implement `getPendingHandoffs(agentId: string): Promise<HandoffRequest[]>`
- [x] **2.2.6** Add TypeScript types for handoff messages
- [ ] **2.2.7** Add unit tests in `tests/handoff.test.ts`

### 2.3 WorkflowClient

**File:** `src/clients/workflow.ts` (new file)

- [x] **2.3.1** Create `WorkflowClient` class
- [x] **2.3.2** Implement `createWorkflow(definition: WorkflowDefinition): Promise<string>`
- [x] **2.3.3** Implement `startWorkflow(workflowId: string): Promise<WorkflowInstance>`
- [x] **2.3.4** Implement `getWorkflowStatus(instanceId: string): Promise<WorkflowInstance>`
- [x] **2.3.5** Implement `cancelWorkflow(instanceId: string): Promise<void>`
- [x] **2.3.6** Add TypeScript types for workflow messages
- [ ] **2.3.7** Add unit tests in `tests/workflow.test.ts`

### 2.4 Voting/Aggregation Helpers

**File:** `src/runtime/voting.ts` (new file)

- [x] **2.4.1** Create `VotingAggregator` interface
- [x] **2.4.2** Implement `SimpleAverageAggregator`
- [x] **2.4.3** Implement `ConfidenceWeightedAggregator`
- [x] **2.4.4** Implement `MajorityVoteAggregator`
- [x] **2.4.5** Implement `BordaCountAggregator`
- [x] **2.4.6** Add `AggregatedScore` type with mean, min, max, stdDev
- [ ] **2.4.7** Add unit tests in `tests/voting.test.ts`

### 2.5 Policy Store

**File:** `src/runtime/policyStore.ts` (new file)

- [x] **2.5.1** Create `PolicyStore` interface
- [x] **2.5.2** Implement `InMemoryPolicyStore`
- [x] **2.5.3** Implement `getPolicy(policyId: string): Promise<EffectivePolicy>`
- [x] **2.5.4** Implement `savePolicy(policy: EffectivePolicy): Promise<string>`
- [x] **2.5.5** Implement `listPolicies(prefix?: string): Promise<string[]>`
- [ ] **2.5.6** Add unit tests in `tests/policyStore.test.ts`

### 2.6 Agent Runtime State Machine

**File:** `src/runtime/agentState.ts` (new file)

- [x] **2.6.1** Create `AgentState` enum with all 12 states from spec section 8
- [x] **2.6.2** Implement state transition validation matrix
- [x] **2.6.3** Add `StateTransitionError` for invalid transitions
- [x] **2.6.4** Add lifecycle hooks (onStateChange, onScheduled, onPreempt, etc.)
- [ ] **2.6.5** Add unit tests for state machine

### 2.7 Export Updates

**File:** `src/index.ts`

- [x] **2.7.1** Export `NegotiationRoomClient`
- [x] **2.7.2** Export `HandoffClient`
- [x] **2.7.3** Export `WorkflowClient`
- [x] **2.7.4** Export voting aggregation helpers
- [x] **2.7.5** Export `PolicyStore` and implementations
- [x] **2.7.6** Export `AgentState` enum

---

## Phase 3: Rust SDK Parity

**Objective:** Bring Rust SDK to feature parity with Python SDK.

**Directory:** `/home/rahul/Documents/sigagent/sdks/rust_sdk/`

**Status:** COMPLETED (2025-12-23)

### 3.1 NegotiationRoomClient

**File:** `src/clients/negotiation_room.rs` (new file)

- [x] **3.1.1** Create `NegotiationRoomClient` struct
- [x] **3.1.2** Implement `submit_proposal(&self, proposal: NegotiationProposal) -> Result<String>`
- [x] **3.1.3** Implement `submit_vote(&self, vote: NegotiationVote) -> Result<()>`
- [x] **3.1.4** Implement `get_votes(&self, artifact_id: &str) -> Result<Vec<NegotiationVote>>`
- [x] **3.1.5** Implement `get_decision(&self, artifact_id: &str) -> Result<Option<NegotiationDecision>>`
- [x] **3.1.6** Implement `wait_for_decision(&self, artifact_id: &str, timeout: Duration) -> Result<NegotiationDecision>`
- [x] **3.1.7** Add type definitions for proto messages
- [x] **3.1.8** Add unit tests

### 3.2 HandoffClient

**File:** `src/clients/handoff.rs` (new file)

- [x] **3.2.1** Create `HandoffClient` struct
- [x] **3.2.2** Implement `request_handoff(&self, request: HandoffRequest) -> Result<HandoffResponse>`
- [x] **3.2.3** Implement `accept_handoff(&self, handoff_id: &str) -> Result<()>`
- [x] **3.2.4** Implement `reject_handoff(&self, handoff_id: &str, reason: &str) -> Result<()>`
- [x] **3.2.5** Implement `get_pending_handoffs(&self, agent_id: &str) -> Result<Vec<HandoffRequest>>`
- [x] **3.2.6** Add type definitions
- [x] **3.2.7** Add unit tests

### 3.3 WorkflowClient

**File:** `src/clients/workflow.rs` (new file)

- [x] **3.3.1** Create `WorkflowClient` struct
- [x] **3.3.2** Implement `create_workflow(&self, definition: WorkflowDefinition) -> Result<String>`
- [x] **3.3.3** Implement `start_workflow(&self, workflow_id: &str) -> Result<WorkflowInstance>`
- [x] **3.3.4** Implement `get_workflow_status(&self, instance_id: &str) -> Result<WorkflowInstance>`
- [x] **3.3.5** Implement `cancel_workflow(&self, instance_id: &str) -> Result<()>`
- [x] **3.3.6** Add type definitions
- [x] **3.3.7** Add unit tests

### 3.4 Voting/Aggregation Module

**File:** `src/voting.rs` (new file)

- [x] **3.4.1** Create `VotingAggregator` trait (implemented as `AggregationStrategy` trait)
- [x] **3.4.2** Implement `SimpleAverageAggregator`
- [x] **3.4.3** Implement `ConfidenceWeightedAggregator`
- [x] **3.4.4** Implement `MajorityVoteAggregator`
- [x] **3.4.5** Implement `BordaCountAggregator`
- [x] **3.4.6** Add `AggregatedScore` struct (in negotiation_room.rs, re-used)
- [x] **3.4.7** Add unit tests

### 3.5 Policy Store

**File:** `src/policy_store.rs` (new file)

- [x] **3.5.1** Create `PolicyStore` trait
- [x] **3.5.2** Implement `InMemoryPolicyStore`
- [x] **3.5.3** Implement `get_policy(&self, policy_id: &str) -> Result<EffectivePolicy>`
- [x] **3.5.4** Implement `save_policy(&self, policy: EffectivePolicy) -> Result<String>`
- [x] **3.5.5** Implement `list_policies(&self, prefix: &str) -> Result<Vec<String>>`
- [x] **3.5.6** Add unit tests
- [x] **3.5.7** Implement `JsonFilePolicyStore` for file-based persistence (bonus)

### 3.6 Fix Persistence Schema Drift

**Issue:** Persistence tests failing due to schema drift (per `logs/rust_sdk_status.md`).

- [x] **3.6.1** Review current persistence schema expectations
- [x] **3.6.2** Align test expectations with envelope-centric schema (already aligned)
- [x] **3.6.3** Update `activity_buffer.rs` if schema changed (no changes needed)
- [x] **3.6.4** Run and pass all persistence tests (101 tests pass)

### 3.7 Module Exports

**File:** `src/lib.rs`

- [x] **3.7.1** Add `pub mod negotiation_room;` (via clients/mod.rs)
- [x] **3.7.2** Add `pub mod handoff;` (via clients/mod.rs)
- [x] **3.7.3** Add `pub mod workflow;` (via clients/mod.rs)
- [x] **3.7.4** Add `pub mod voting;`
- [x] **3.7.5** Add `pub mod policy_store;`

---

## Phase 4: Reference Examples

**Objective:** Create comprehensive examples demonstrating all major features.

### 4.1 JavaScript Examples

**Directory:** `sdks/js_sdk/examples/`

**Status:** COMPLETED (2025-12-23)

- [x] **4.1.1** Create `echoAgent.ts` - Basic agent registration and message echo
- [x] **4.1.2** Create `advancedAgent.ts` - ActivityBuffer, Worktree, ACK lifecycle
- [x] **4.1.3** Create `negotiationRoomExample.ts` - Producer-critic-coordinator flow
- [x] **4.1.4** Create `workflowExample.ts` - DAG-based workflow orchestration
- [x] **4.1.5** Create `handoffExample.ts` - Agent-to-agent context handoff
- [x] **4.1.6** Create `hitlEscalation.ts` - HITL conflict escalation flow
- [x] **4.1.7** Add `README.md` with example descriptions and run instructions

### 4.2 Rust Examples

**Directory:** `sdks/rust_sdk/examples/` (verify and update)

- [x] **4.2.1** Verify `echo_agent.rs` exists and is current
- [x] **4.2.2** Verify `advanced_agent.rs` exists and is current
- [x] **4.2.3** Create `negotiation_room.rs` example
- [x] **4.2.4** Create `workflow.rs` example
- [x] **4.2.5** Create `handoff.rs` example
- [x] **4.2.6** Update `README.md` with example descriptions

### 4.3 Python Examples Enhancement

**Directory:** `/home/rahul/Documents/sigagent/examples/`

- [x] **4.3.1** Create `hitl_escalation_example.py` - HITL conflict handling
- [x] **4.3.2** Create `negotiation_debate_example.py` - Multi-agent negotiation
- [x] **4.3.3** Create `tool_streaming_example.py` - Streaming tool calls with cancellation
- [x] **4.3.4** Create `workflow_orchestration_example.py` - DAG workflow
- [x] **4.3.5** Create `handoff_example.py` - Agent handoff flow

### 4.4 Cross-SDK Feature Matrix Example

- [ ] **4.4.1** Create `examples/README.md` with feature matrix showing what each SDK example demonstrates
- [ ] **4.4.2** Ensure examples are runnable with minimal setup
- [ ] **4.4.3** Add CI validation that examples compile/lint

---

## Phase 5: Documentation & Validation

**Objective:** Ensure all documentation is accurate and complete.

### 5.1 SDK README Updates

- [ ] **5.1.1** Update `sdks/py_sdk/README.md` with new clients (NegotiationRoom, Handoff, Workflow)
- [ ] **5.1.2** Update `sdks/js_sdk/README.md` with full client list
- [ ] **5.1.3** Update `sdks/rust_sdk/README.md` with full client list
- [ ] **5.1.4** Add cross-SDK feature comparison table to each README

### 5.2 Migration Guide

- [ ] **5.2.1** Document breaking changes from proto namespace unification
- [ ] **5.2.2** Provide migration steps for existing code using `sw4rm.v1`
- [ ] **5.2.3** Document API changes in each SDK

### 5.3 Validation Checklist

- [ ] **5.3.1** Run all Python SDK tests: `pytest sdks/py_sdk/tests/`
- [ ] **5.3.2** Run all JavaScript SDK tests: `npm test` in `sdks/js_sdk/`
- [ ] **5.3.3** Run all Rust SDK tests: `cargo test` in `sdks/rust_sdk/`
- [ ] **5.3.4** Verify all examples compile/run
- [ ] **5.3.5** Verify spec sections reference correct proto definitions
- [ ] **5.3.6** Run link checker on all markdown files

---

## Gap Analysis Summary

### By Priority

| Priority | Component | Gap Count | Critical |
|----------|-----------|-----------|----------|
| P0 | Spec vs SPEC_REQUESTS | 5 | 3 (new sections needed) |
| P0 | Protocol Coherence | 6 | 1 (state machine fix) |
| P1 | JavaScript SDK | 8 | 4 (missing clients) |
| P1 | Rust SDK | 9 | 4 (missing clients) + persistence |
| P2 | Examples | 10 | 2 (JS basics missing) |
| P3 | Documentation | 5 | 0 |

### Total Task Count

| Phase | Major Tasks | Subtasks | New Files | Modified Files |
|-------|-------------|----------|-----------|----------------|
| 0 | 3 | ~25 | 0 | 1 (spec.md) |
| 1 | 6 | ~20 | 0 | 5-8 (protos, spec) |
| 2 | 7 | ~45 | 6-8 | 3-5 |
| 3 | 7 | ~45 | 6-8 | 3-5 |
| 4 | 4 | ~20 | 15-20 | 3-5 |
| 5 | 3 | ~15 | 1-2 | 5-8 |
| **Total** | **30** | **~170** | **28-38** | **20-36** |

---

## Risk Register

| ID | Risk | Impact | Probability | Mitigation |
|----|------|--------|-------------|------------|
| R1 | Proto namespace change breaks existing deployments | HIGH | MEDIUM | Version protos, provide migration scripts |
| R2 | JS/Rust SDK implementation diverges from Python | MEDIUM | MEDIUM | Use Python SDK as reference, add cross-SDK tests |
| R3 | New spec sections conflict with existing implementations | HIGH | LOW | Review with stakeholders before merge |
| R4 | Example code becomes stale | LOW | HIGH | Add CI checks for examples |
| R5 | Spec updates not reflected in protos | MEDIUM | MEDIUM | Single PR for spec+proto changes |

---

## Dependency Graph

```
Phase 0 (Spec Alignment)
├── 0.1 Add Missing Sections (no deps)
├── 0.2 Update Appendix (deps: 0.1)
└── 0.3 Resolve Terminology (deps: 0.1)

Phase 1 (Protocol Coherence)
├── 1.1 Proto Namespace Unification (deps: Phase 0)
├── 1.2 Message State Machine Fix (no deps) ✅ COMPLETED
├── 1.3 Worktree State Machine Fix (no deps) ✅ COMPLETED
├── 1.4 Agent Lifecycle Transitions (no deps) ✅ COMPLETED
├── 1.5 Tool Execution Policy Docs (no deps) ✅ COMPLETED
└── 1.6 Edge Case Documentation (no deps) ✅ COMPLETED

Phase 2 (JavaScript SDK)
├── 2.1 NegotiationRoomClient (deps: 1.1)
├── 2.2 HandoffClient (deps: 1.1)
├── 2.3 WorkflowClient (deps: 1.1)
├── 2.4 Voting/Aggregation (deps: 2.1)
├── 2.5 Policy Store (no deps)
├── 2.6 Agent Runtime FSM (no deps)
└── 2.7 Export Updates (deps: 2.1-2.6)

Phase 3 (Rust SDK)
├── 3.1 NegotiationRoomClient (deps: 1.1)
├── 3.2 HandoffClient (deps: 1.1)
├── 3.3 WorkflowClient (deps: 1.1)
├── 3.4 Voting/Aggregation (deps: 3.1)
├── 3.5 Policy Store (no deps)
├── 3.6 Fix Persistence (no deps, HIGH PRIORITY)
└── 3.7 Module Exports (deps: 3.1-3.6)

Phase 4 (Examples) - CAN RUN IN PARALLEL WITH PHASE 2-3
├── 4.1 JS Examples (deps: Phase 2 complete)
├── 4.2 Rust Examples (deps: Phase 3 complete)
├── 4.3 Python Examples (no deps)
└── 4.4 Cross-SDK Matrix (deps: 4.1-4.3)

Phase 5 (Documentation)
├── 5.1 README Updates (deps: Phases 2-4)
├── 5.2 Migration Guide (deps: Phase 1)
└── 5.3 Validation (deps: ALL)
```

---

## Execution Notes

1. **Phase 0 and 1 are blocking** - SDK work cannot proceed until spec and proto alignment complete
2. **Phase 2 and 3 can run in parallel** - JS and Rust SDK work is independent
3. **Phase 4.3 (Python examples) can start immediately** - Python SDK is complete
4. **Proto regeneration required after Phase 1.1** - All SDKs must regenerate stubs
5. **Single commit per logical change** - Do not batch unrelated changes
6. **Run tests after each subtask** - Catch regressions early
7. **Flag blockers immediately** - Do not proceed with assumptions

---

## Previous Plan Status

The previous implementation plan (0.3.x) focused on Python SDK parity and is now **COMPLETED**. All items from that plan have been implemented:

- ✅ Phase 1: SDK Parity (all 13 sections complete)
- ✅ Phase 2: Spec Requests Implementation (all 4 sections complete)
- ✅ Phase 3: Research-Derived Enhancements (all 6 sections complete)

This plan (0.4.0-alpha) builds on that foundation to achieve full protocol alignment across all SDKs.

---

*End of Implementation Plan v0.4.0-alpha*
