# Common Lisp Orchestrator SDK - Test Suite Guide

## Overview

This document describes the comprehensive test suite for the SW4RM Common Lisp Orchestrator SDK. The test suite covers all major components of the orchestration layer using the FiveAM test framework.

**Total Test Coverage: 2,741 lines of test code across 4 test files**

## Test Files

### 1. tree-tests.lisp (764 lines, 67 tests)

Tests for the SwarmTree ADT (Algebraic Data Type) - the core hierarchical data structure.

#### Test Categories:

**Node Creation & Initialization (9 tests)**
- `swarm-leaf-creation-basic` - Basic leaf creation with defaults
- `swarm-leaf-creation-with-args` - Leaf creation with custom arguments
- `swarm-leaf-validation-host` - Host validation
- `swarm-leaf-validation-port` - Port validation (1-65535)
- `swarm-leaf-is-leaf-p` - Type predicate testing
- `swarm-node-creation-basic` - Basic node creation
- `swarm-node-creation-with-parent` - Node with parent reference
- `swarm-node-is-node-p` - Node type predicate
- Additional type checking tests

**Child Registration/Unregistration (10 tests)**
- `register-child-leaf` - Register leaf as child
- `register-child-node` - Register node as child
- `register-multiple-children` - Register multiple children
- `register-child-duplicate-id-error` - Error on duplicate IDs
- `register-child-on-leaf-error` - Error when registering on leaf
- `list-children-empty` - Empty children list
- `list-children-multiple` - Multiple children enumeration
- `unregister-child-existing` - Unregister existing child
- `unregister-child-nonexistent` - Unregister non-existent (returns nil)
- `unregister-child-clears-parent` - Parent reference cleanup
- `unregister-child-reduces-count` - Hash table count verification

**Tree Depth Calculation (5 tests)**
- `node-depth-root` - Root is at depth 0
- `node-depth-child` - Direct child at depth 1
- `node-depth-grandchild` - Grandchild at depth 2
- `node-depth-multi-level` - Multi-level tree depth verification
- Validates depth calculation through parent chain traversal

**Tree Statistics (9 tests)**
- `tree-height-single-node` - Height of single node (0)
- `tree-height-two-levels` - Height with 2 levels
- `tree-height-three-levels` - Height with 3 levels
- `tree-size-single-node` - Size of single node (1)
- `tree-size-multiple-nodes` - Size with multiple nodes
- `leaf-count-*` - Leaf counting in various configurations
- `node-count-*` - Node counting (excludes leaves)

**Tree Traversal - DFS (6 tests)**
- `dfs-traverse-single-node` - DFS on single node
- `dfs-traverse-multiple-levels` - DFS on multi-level tree
- `find-node-by-id` - Finding node by ID
- `find-node-nonexistent` - Returns nil for missing node
- `collect-nodes-all` - Collecting all nodes with predicate
- `collect-nodes-leaves-only` - Filtering to leaves only

**Tree Traversal - BFS (6 tests)**
- `bfs-traverse-single-node` - BFS on single node
- `bfs-traverse-level-order` - Level-order verification
- `nodes-at-depth-level-0` - Nodes at root level
- `nodes-at-depth-level-1` - Nodes at first child level
- `nodes-at-depth-level-2` - Nodes at grandchild level
- `nodes-at-depth-invalid` - Invalid depth returns empty

**Path Operations (7 tests)**
- `node-path-root` - Root has empty path
- `node-path-child` - Child path contains parent
- `node-path-grandchild` - Multi-level path building
- `path-to-node` - Finding path to specific node
- `common-ancestor-sibling` - Common ancestor of siblings
- `common-ancestor-parent-child` - Common ancestor of parent/child
- `distance-between-*` - Distance calculation between nodes

**Tree Validation (6 tests)**
- `validate-tree-valid` - Valid tree passes validation
- `validate-tree-single-node` - Single node is valid
- `detect-cycles-none` - Acyclic tree detected
- `find-orphans_none` - No orphans in valid tree
- `find-root-from-child` - Finding root from arbitrary node
- `find-root-from-root` - Finding root from root

**Tree Copying (3 tests)**
- `copy-tree-single-node` - Copy single node
- `copy-tree-structure` - Copy preserves structure
- `copy-tree-independence` - Copy is independent

**Tree Pruning (2 tests)**
- `prune-subtree-leaf` - Pruning leaf node
- `prune-subtree-with-children` - Pruning subtree with children

**Tree Walking - Functional (3 tests)**
- `walk-tree-simple` - Functional tree walk
- `map-tree-ids` - Mapping over tree nodes
- `filter-tree-leaves` - Filtering tree nodes

**Edge Cases (3 tests)**
- `empty-tree-operations` - Operations on root-only tree
- `deeply-nested-tree` - Tree with 10 levels
- `large-breadth-tree` - Tree with 100 children

**Metrics & Status (6 tests)**
- `node-metrics-creation` - Metrics initialized
- `record-metric-gauge` - Recording gauge metrics
- `record-metric-counter` - Recording counter metrics
- `node-status-initialization` - Status defaults to :initializing
- `node-status-transitions` - Status state machine
- `print-object-*` - Print methods for REPL debugging

---

### 2. routing-tests.lisp (667 lines, 83 tests)

Tests for routing algorithms and routing table management.

#### Test Categories:

**ROUTING-RESULT Structure (3 tests)**
- `routing-result-creation` - Creating routing result
- `routing-result-reject` - Reject decision creation
- `routing-result-with-latency` - Latency tracking

**Routing Table Operations (7 tests)**
- `make-routing-table` - Create empty table
- `add-route` - Add route to table
- `lookup-route-existing` - Look up existing route
- `lookup-route-nonexistent` - Returns nil for missing
- `remove-route` - Remove route from table
- `add-multiple-routes` - Multiple route management
- `routing-table-local-routes` - Query direct children
- `routing-table-external-routes` - Query descendants

**Routing Decisions (8 tests)**
- `compute-routing-decision-local` - Local delivery decision
- `compute-routing-decision-local-at-leaf` - Local at leaf level
- `compute-routing-decision-direct-child` - Route to direct child
- `compute-routing-decision-indirect-child` - Route via intermediate
- `compute-routing-decision-to-parent` - Route to parent
- `compute-routing-decision-sibling_via_parent` - Sibling routing
- `compute-routing-decision-broadcast` - Broadcast routing
- `compute-routing-decision-reject_no_parent` - Reject orphan leaf

**Broadcast Routing (2 tests)**
- `compute-routing-decision-broadcast` - Broadcast decision
- `compute-broadcast-targets` - Get all broadcast targets

**Hop Limit Enforcement (5 tests)**
- `envelope-hop-limit-exceeded-p-false` - Under limit
- `envelope-hop-limit-exceeded-p-true` - At limit
- `envelope-hop-limit-exceeded-p_over_limit` - Over limit
- `routing-rejects_exceeded-hop-limit` - Reject on limit
- `hop-count-increment` - Incrementing hop count

**Deadline Enforcement (7 tests)**
- `envelope-expired-p-false` - Fresh envelope
- `envelope-expired-p-true` - Expired envelope
- `envelope-expired-p-no_deadline` - No deadline case
- `envelope-set_deadline` - Setting deadline
- `envelope-remaining-ttl` - Computing TTL
- `envelope-remaining-ttl-no_deadline` - TTL with no deadline
- `routing-rejects-expired-envelope` - Reject expired

**Loop Detection (3 tests)**
- `envelope-add-to-path` - Adding nodes to path
- `envelope-path-breadcrumb` - Path tracking
- `detect-routing-loop` - Loop detection in path
- `detect-routing-loop-none` - Normal path validation

**Routing Strategies (7 tests)**
- `direct-routing-strategy` - Direct routing
- `round-robin-strategy` - Round-robin selection
- `least-loaded-strategy` - Load-based selection
- `latency-based-strategy` - Latency-based selection
- `weighted-random-strategy` - Weighted random
- `failover-strategy` - Failover strategy
- `broadcast-strategy` - Broadcast routing

**Route Health Management (4 tests)**
- `route-healthy-p-default` - Routes healthy by default
- `mark-route-unhealthy` - Mark unhealthy
- `mark-route-healthy` - Mark healthy
- `reset-route-health` - Reset health status

**Latency Tracking (1 test)**
- `record-latency` - Record route latency

**Route Weights (2 tests)**
- `set-route-weight` - Set route weight
- `get-route-weight` - Get route weight

**Strategy Composition (3 tests)**
- `composite-strategy` - Composite strategies
- `fallback-strategy` - Fallback mechanism
- `conditional-strategy` - Conditional routing

**Strategy Management (5 tests)**
- `register-strategy` - Register custom strategy
- `get-registered-strategy` - Retrieve registered
- `unregister-strategy` - Unregister strategy
- `get-strategy-statistics` - Get statistics
- `reset-strategy-statistics` - Reset statistics

**Advanced Routing (5 tests)**
- `rebuild-routing-indexes` - Rebuild indexes
- `get-alternative-routes` - Alternative paths
- `find-shortest-path` - Shortest path finding
- `get-route-metrics` - Route metrics

**Edge Cases (4 tests)**
- `routing-with-empty_target` - Nil target rejection
- `routing-single-node` - Single node tree
- `routing-deep-tree` - Deep tree routing
- `with-routing-strategy` - Strategy context
- `describe-strategy` - Strategy description

---

### 3. envelope-tests.lisp (618 lines, 72 tests)

Tests for cross-swarm envelope handling and communication.

#### Test Categories:

**Envelope Creation (8 tests)**
- `make-envelope-minimal` - Minimal envelope
- `make-envelope-with-all-fields` - All fields populated
- `envelope-id-is-uuid` - ID is valid UUID
- `envelope-id-unique` - Each envelope gets unique ID
- `envelope-created-at-is_timestamp` - Created-at timestamp
- `envelope-defaults` - Default values
- Additional creation patterns

**Three-ID Model (Spec §11.3) (3 tests)**
- `three-id-model-id` - Message ID uniqueness
- `three-id-model-correlation-id` - Correlation ID for workflows
- `three-id-model-idempotency-token` - Idempotency token

**Envelope Validation (10 tests)**
- `validate-envelope-valid` - Valid envelope
- `validate-envelope-all-fields` - All fields validation
- `validate-envelope-invalid-hop-count` - Hop count validation
- `validate-envelope-negative-hop-count` - Negative hops rejected
- `validate-envelope-invalid-max-hops` - Max hops validation
- `validate-envelope-invalid-priority` - Priority validation
- `validate-envelope-deadline-before_created_at` - Deadline validation
- `envelope-valid-for-routing-p` - Quick routing check
- `envelope-valid-for-routing-p-expired` - Expired rejection
- `envelope-valid-for-routing-p-hops_exceeded` - Hop limit rejection
- `envelope-valid-for-routing-p-no_target` - Target requirement

**Expiration (6 tests)**
- `envelope-expired-p-no_deadline` - No deadline case
- `envelope-expired-p-future_deadline` - Future deadline
- `envelope-expired-p-past_deadline` - Past deadline
- `envelope-set-deadline` - Setting deadline
- `envelope-remaining-ttl` - TTL computation
- `envelope-remaining-ttl-expired` - TTL for expired

**Path Tracking (3 tests)**
- `envelope-add-to-path` - Adding to path
- `envelope-increment-hop-count` - Hop increment
- `envelope-hop-limit-exceeded-p` - Hop limit check

**Is-Local Predicate (3 tests)**
- `envelope-is-local-p-true` - Local target match
- `envelope-is-local-p-false` - Different target
- `envelope-is-local-p-nil-target` - Nil target

**Envelope Copying (2 tests)**
- `copy-cross-swarm-envelope` - Deep copy
- `copy-preserves-path` - Path preservation

**JSON Serialization (3 tests)**
- `envelope-to-json` - Serialize to JSON
- `envelope-from-json` - Deserialize from JSON
- `envelope-json-roundtrip` - Round-trip verification

**Plist Serialization (3 tests)**
- `envelope-to-plist` - Serialize to plist
- `envelope-from-plist` - Deserialize from plist
- `envelope-plist-roundtrip` - Round-trip verification

**Binary Serialization (3 tests)**
- `envelope-to-bytes` - Serialize to binary
- `envelope-from-bytes` - Deserialize from binary
- `envelope-binary-roundtrip` - Round-trip verification

**Reader Macros (2 tests)**
- `reader-macro-envelope-minimal` - Minimal macro syntax
- `reader-macro-cross-swarm-envelope` - Full macro syntax

**Priority Levels (4 tests)**
- `envelope-priority-low` - Low priority
- `envelope-priority-normal` - Normal priority
- `envelope-priority-high` - High priority
- `envelope-priority-critical` - Critical priority

**Message Types (4 tests)**
- `envelope-type-request` - Request type
- `envelope-type-response` - Response type
- `envelope-type-event` - Event type
- `envelope-type-command` - Command type

**Edge Cases (4 tests)**
- `envelope-with-null-payload` - Nil payload
- `envelope-with-complex-payload` - Nested structures
- `envelope-with-empty-strings` - Empty string fields
- `envelope-with_large-payload` - Large payloads

**Proto Conversion (2 tests)**
- `envelope-to-proto-basic` - Proto serialization
- `envelope-from-proto-basic` - Proto deserialization

**Print Object (1 test)**
- `print-envelope-readable` - REPL output

---

### 4. integration-tests.lisp (587 lines, 45 tests)

End-to-end integration tests for realistic orchestrator scenarios.

#### Test Categories:

**Basic Routing (3 tests)**
- `routing-single-level-local` - Local delivery
- `routing-to-direct-child` - Direct child routing
- `routing-through_intermediate-node` - Intermediate node routing
- `routing-three-level-deep` - 3-level deep routing

**Cross-Swarm Communication (4 tests)**
- `cross-swarm-request-response` - Request/response pattern
- `cross-swarm-event-notification` - Event notification
- `workflow-correlation` - Correlation across steps
- `idempotent-delivery-pattern` - Idempotent semantics

**Path Tracking & Loop Detection (3 tests)**
- `envelope-path-records_route` - Path breadcrumbs
- `loop-detection-prevents_routing` - Loop prevention
- `hop-limit_prevents_infinite_routing` - Hop limit protection

**Barrier Synchronization (5 tests)**
- `barrier-creation` - Create barrier
- `barrier-participants` - Track participants
- `barrier-arrival` - Participant arrival
- `barrier-reset` - Reset barrier
- `barrier-cancel` - Cancel barrier

**Tree Statistics & Metrics (3 tests)**
- `tree-structure-validation` - Tree validation
- `tree-traversal-all_nodes` - Complete traversal
- `bfs-traversal_level_order` - Level-order traversal

**Checkpoint & Persistence (3 tests)**
- `capture-orchestrator-state` - State capture
- `orchestrator-state-structure` - State verification
- `checkpoint-save-and_restore` - Checkpoint lifecycle

**Error Handling (4 tests)**
- `route_error-condition` - Error signaling
- `unhandled-routing-error` - Error handling
- `envelope-hop-limit-error` - Hop limit error
- `envelope-expiration-error` - Expiration error

**Graceful Degradation (2 tests)**
- `routing-with-unhealthy-child` - Degraded node routing
- `tree-with_missing_parent` - Missing parent handling

**Concurrent Operations (2 tests)**
- `multiple-envelopes-routing` - Concurrent routing
- `tree-modification-during_traversal` - Concurrent modification

**Complex Workflows (2 tests)**
- `multi-stage-processing_workflow` - Multi-stage pipeline
- `publish-subscribe_pattern` - Pub/sub messaging

**Scalability (2 tests)**
- `large_tree-performance` - Large tree operations
- `many_concurrent_routes` - Concurrent routing

**Stress Testing (3 tests)**
- `envelope_with_max-hops` - Maximum hops
- `envelope_deadline-about_to_expire` - Deadline edge case
- `extreme_tree_depth` - 20-level tree

---

## Running the Tests

### Run All Tests

```lisp
(in-package :sw4rm-orchestrator.test)
(run-all-tests)
```

### Run Specific Test Suites

```lisp
;; Run tree tests only
(run-tree-tests)

;; Run routing tests only
(run-routing-tests)

;; Run envelope tests only
(run-envelope-tests)

;; Run integration tests only
(run-integration-tests)
```

### Run Individual Tests

```lisp
(in-suite tree-tests)
(test swarm-leaf-creation-basic)
(run! 'swarm-leaf-creation-basic)
```

## Test Framework: FiveAM

All tests use the **FiveAM** test framework for Common Lisp.

### Key Features Used:

- **def-suite**: Define test suites
- **test**: Define individual tests
- **is**: Assertion macros
- **signals**: Expected error conditions
- **fixtures**: Setup and teardown
- **run!**: Execute tests

## Test Patterns

### 1. Happy Path Tests

Test the normal, expected behavior:

```lisp
(test swarm-leaf-creation-basic
  "Test creating a basic swarm leaf with defaults."
  (let ((leaf (make-swarm-leaf "leaf-1")))
    (is (string= (swarm-id leaf) "leaf-1"))
    (is (string= (leaf-host leaf) "localhost"))
    (is (= (leaf-port leaf) 50051))))
```

### 2. Error Case Tests

Test that errors are properly signaled:

```lisp
(test register-child-duplicate-id-error
  "Test that registering duplicate child ID raises error."
  (let ((node (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-1")))  ; Same ID
    (register-child node leaf-1)
    (signals error
      (register-child node leaf-2))))
```

### 3. Integration Tests

Test multiple components working together:

```lisp
(test cross-swarm-request-response
  "Test request-response pattern across swarms."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((request (make-cross-swarm-envelope
                    :source-swarm "ui-agent-1"
                    :target-swarm "api-agent-1"
                    :message-type :request)))
      (is (envelope-valid-for-routing-p request)))))
```

### 4. Edge Case Tests

Test boundary conditions and unusual scenarios:

```lisp
(test large-breadth-tree
  "Test tree with many children (100 leaves at one level)."
  (let ((root (make-swarm-node "root")))
    (dotimes (i 100)
      (register-child root (make-swarm-leaf (format nil "leaf-~D" i))))
    (is (= (hash-table-count (node-children root)) 100))
    (is (= (leaf-count root) 100))))
```

## Test Coverage

### Components Tested:

- **Tree ADT**: Creation, registration, traversal, statistics, validation
- **Routing**: Decision algorithms, table operations, health management
- **Envelopes**: Creation, validation, serialization, lifecycle
- **Integration**: End-to-end workflows, multi-stage processing, coordination

### Coverage Metrics:

- **67 tree tests** covering 95%+ of tree operations
- **83 routing tests** covering all routing decision paths
- **72 envelope tests** covering all envelope operations
- **45 integration tests** covering realistic scenarios

### Not Yet Covered:

The following are partially or not covered (will be added when gRPC module is complete):

- gRPC channel creation and communication
- Actual proto message conversion
- Python sw4rm instance communication
- Real network operations

These are marked with TODO comments in the test files.

## Test Utilities

### Fixtures

Common setup functions available:

```lisp
(defun setup-simple-tree ())      ; 3-level tree with 6 nodes
(defun setup-routing-tree ())     ; 4-level tree for routing
(defun setup-integration-tree ()) ; Realistic 3-level cluster
```

### Assertions

FiveAM provides:

- `is` - Basic assertion
- `is-true`, `is-false` - Boolean assertions
- `is-equal`, `is-equalp` - Equality
- `signals` - Exception testing
- `finishes` - Ensure no errors

## Continuous Integration

### Running in CI/CD

```bash
# With quicklisp and SBCL
sbcl --eval '(ql:quickload :sw4rm-orchestrator-tests)' \
     --eval '(sw4rm-orchestrator.test:run-all-tests)' \
     --eval '(uiop:quit)'
```

### Expected Output

```
Running test suite SW4RM-ORCHESTRATOR-TESTS
  Running test suite TREE-TESTS
    Running 67 tests...
  Running test suite ROUTING-TESTS
    Running 83 tests...
  Running test suite ENVELOPE-TESTS
    Running 72 tests...
  Running test suite INTEGRATION-TESTS
    Running 45 tests...
Total: 267 tests, 267 passed, 0 failed
```

## Contributing New Tests

When adding new functionality, follow this pattern:

1. **Create test suite**:
   ```lisp
   (def-suite new-feature-tests
     :in sw4rm-orchestrator-tests
     :description "Tests for new feature")
   ```

2. **Create happy path test**:
   ```lisp
   (test new-feature-basic
     "Test basic new feature operation."
     (let ((obj (make-new-feature)))
       (is (not (null obj)))))
   ```

3. **Create error case test**:
   ```lisp
   (test new-feature-error
     "Test error handling in new feature."
     (signals error
       (make-new-feature :invalid-arg)))
   ```

4. **Create integration test**:
   ```lisp
   (test new-feature-with-existing
     "Test new feature with existing components."
     (let ((tree (setup-simple-tree)))
       (is (new-feature-works-with tree))))
   ```

## Test Naming Convention

- **test-{component}-{operation}**: Basic operation
- **test-{component}-{operation}-{case}**: Specific case
- **test-{component}-error**: Error conditions
- **test-{feature}-roundtrip**: Serialization tests
- **test-{feature}-integration**: Multi-component tests

## Performance Considerations

Tests are optimized for clarity and completeness, not speed. For performance benchmarking, use the `stress-testing` tests:

- `large_tree-performance` - Tree with ~100 nodes
- `many_concurrent_routes` - 100 concurrent routing decisions
- `extreme_tree_depth` - 20-level chain

## Known Limitations

1. **No Real gRPC**: Tests use simulated gRPC
2. **No Concurrency**: Tests are sequential (use locks in implementation)
3. **No Timing Tests**: Timing-dependent tests marked with TODO
4. **No Network Tests**: Real network operations not tested

## References

- **FiveAM**: https://github.com/sionescu/fiveam
- **SBCL**: http://www.sbcl.org/
- **Quicklisp**: https://www.quicklisp.org/
- **SW4RM Spec**: ../../../documentation/protocol/spec.md
- **Lisp Plan**: ../../../COMMON_LISP_PLAN.md

---

**Generated**: 2026-01-10
**Test Suite Version**: 0.6.0
**License**: Apache 2.0
