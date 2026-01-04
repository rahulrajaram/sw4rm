# SW4RM Common Lisp Orchestrator SDK

## Proposal: Recursive SW4RM Tree Orchestration in Common Lisp

**Date:** 2026-01-10
**Status:** Proposal
**Author:** Platform Architecture Team

---

## Executive Summary

This proposal introduces a **Common Lisp orchestration layer** for SW4RM that enables recursive composition of sw4rm systems. The orchestrator manages a tree of sw4rm instances where each node is either a leaf (complete sw4rm system) or an inner node (orchestrator coordinating child sw4rms).

**Why Common Lisp?**
- Most powerful macro system for DSL creation
- Conditions/restarts for sophisticated distributed error handling
- CLOS + MOP for extensible agent type system
- Image-based development for stateful orchestration
- Reader macros for custom envelope syntax

---

## Part 1: Vision

### 1.1 The Problem

Current sw4rm architecture is **flat**: one scheduler, one router, one registry, coordinating peer agents. This works for simple workflows but fails for:

- **Complex distributed systems** with multiple independent subsystems
- **Hierarchical coordination** where teams of agents need meta-coordination
- **Cross-domain orchestration** where different sw4rm instances must communicate
- **Scalability** beyond a single scheduler's capacity

### 1.2 The Solution: Recursive SW4RM Trees

```
SwarmTree = Leaf(SwarmInstance) | Node(Orchestrator, children: [SwarmTree])
```

This algebraic data type enables:
- **Arbitrary nesting depth** (though practical systems use 2-4 levels)
- **Independent sw4rm instances** as composable units
- **Hierarchical routing** with path-based message delivery
- **Failure isolation** at sw4rm boundaries

### 1.3 Why a Separate Orchestration Layer?

The orchestrator is a **fundamentally different concern** than individual sw4rm instances:

| Concern | Leaf SW4RM (Python) | Orchestrator (Common Lisp) |
|---------|---------------------|----------------------------|
| Focus | Agent execution | Cross-swarm coordination |
| State | Task queues, agent state | Tree topology, routing tables |
| Operations | Schedule, route, negotiate | Route across boundaries, synchronize |
| Failure handling | Retry, escalate | Reroute, failover, circuit break |
| Abstraction level | Tasks and messages | Sw4rm instances and relationships |

---

## Part 2: Why Common Lisp

### 2.1 Language Capability Comparison

| Capability | Common Lisp | Python | Go | Rust |
|------------|-------------|--------|-----|------|
| Macro system | Reader + compiler macros | Decorators only | None | proc_macro |
| Custom syntax | Yes (reader macros) | No | No | Limited |
| Tree manipulation | Native (cons cells) | Lists/dicts | Slices/maps | Vec/HashMap |
| Error handling | Conditions/restarts | Exceptions | error return | Result<T,E> |
| Meta-object protocol | CLOS + MOP | Limited | None | Traits |
| Runtime modification | Yes (image-based) | Limited | No | No |
| Hot code reload | Yes | Limited | No | No |

### 2.2 Killer Features for Orchestration

#### 2.2.1 Reader Macros for Envelope DSL

Define custom syntax that reads directly into typed structures:

```lisp
;; Standard Lisp
(make-envelope :from "agent-a" :to "agent-b" :payload '(:data 42))

;; With reader macro: #E{...}
#E{:from agent-a :to agent-b :payload {:data 42}}

;; Cross-swarm envelope: #X{...}
#X{:source-swarm frontend :target-swarm backend
   :from ui-agent :to api-agent
   :payload {:contract-version "2.0"}}
```

Implementation:
```lisp
(defun envelope-reader (stream char arg)
  (declare (ignore char arg))
  (let ((form (read-delimited-list #\} stream t)))
    `(make-envelope ,@form)))

(set-dispatch-macro-character #\# #\E #'envelope-reader)
```

#### 2.2.2 Conditions and Restarts for Distributed Error Handling

The **most powerful error handling system** in any programming language:

```lisp
(define-condition swarm-unreachable (sw4rm-error)
  ((swarm-id :initarg :swarm-id :reader unreachable-swarm-id)
   (last-seen :initarg :last-seen :reader last-seen-time))
  (:report (lambda (c s)
             (format s "Swarm ~A unreachable (last seen: ~A)"
                     (unreachable-swarm-id c)
                     (last-seen-time c)))))

(defun route-to-swarm (envelope target-swarm)
  "Route envelope to target swarm with sophisticated error handling."
  (restart-case
      (let ((connection (get-swarm-connection target-swarm)))
        (if (null connection)
            (error 'swarm-unreachable
                   :swarm-id target-swarm
                   :last-seen (get-last-heartbeat target-swarm))
            (send-envelope connection envelope)))

    ;; Restart 1: Retry with exponential backoff
    (retry-with-backoff (&optional (max-attempts 5))
      :report "Retry delivery with exponential backoff"
      :interactive (lambda () (list (prompt-for-integer "Max attempts: ")))
      (loop for attempt from 1 to max-attempts
            for delay = (expt 2 attempt)
            do (sleep delay)
            when (swarm-available-p target-swarm)
              return (route-to-swarm envelope target-swarm)
            finally (error 'swarm-unreachable :swarm-id target-swarm)))

    ;; Restart 2: Route to alternative swarm
    (route-to-alternative (alt-swarm)
      :report "Route to alternative swarm"
      :interactive (lambda () (list (choose-alternative-swarm target-swarm)))
      (route-to-swarm envelope alt-swarm))

    ;; Restart 3: Queue for later delivery
    (queue-for-retry ()
      :report "Queue envelope for later delivery"
      (enqueue-delayed-delivery envelope target-swarm))

    ;; Restart 4: Send to dead letter queue
    (dead-letter ()
      :report "Send to dead letter queue"
      (dead-letter-envelope envelope target-swarm))

    ;; Restart 5: Drop silently (for non-critical messages)
    (drop-message ()
      :report "Drop message silently"
      (log:warn "Dropping message ~A to unreachable swarm ~A"
                (envelope-id envelope) target-swarm)
      nil)))

;; Higher-level code can handle errors without knowing implementation details:
(handler-bind
    ((swarm-unreachable
       (lambda (c)
         (when (critical-swarm-p (unreachable-swarm-id c))
           (alert-ops-team c))
         (invoke-restart 'retry-with-backoff 10))))
  (route-to-swarm envelope target))
```

**Why this matters:** In distributed systems, the *decision* of how to handle failures should be separable from the *detection* of failures. Conditions/restarts provide this separation cleanly.

#### 2.2.3 CLOS + MOP for Extensible Agent Types

```lisp
;;; Base protocol for all swarm tree nodes
(defclass swarm-tree ()
  ((id :initarg :id :accessor swarm-id :type string)
   (parent :initarg :parent :accessor parent-node :initform nil)
   (metrics :accessor node-metrics :initform (make-metrics-collector)))
  (:documentation "Base class for sw4rm tree nodes"))

;;; Leaf node: complete sw4rm instance
(defclass swarm-leaf (swarm-tree)
  ((scheduler :initarg :scheduler :accessor leaf-scheduler)
   (router :initarg :router :accessor leaf-router)
   (registry :initarg :registry :accessor leaf-registry)
   (agents :initarg :agents :accessor leaf-agents :initform '())
   (grpc-channel :initarg :grpc-channel :accessor grpc-channel
                 :documentation "gRPC channel to Python sw4rm instance"))
  (:documentation "Leaf node wrapping a Python sw4rm instance"))

;;; Inner node: orchestrator coordinating children
(defclass swarm-node (swarm-tree)
  ((children :initarg :children :accessor node-children
             :initform (make-hash-table :test 'equal)
             :type hash-table)
   (routing-table :accessor routing-table
                  :initform (make-routing-table))
   (policy :initarg :policy :accessor node-policy
           :initform *default-orchestration-policy*))
  (:documentation "Inner node coordinating child sw4rms"))

;;; MOP: Intercept all message sends for tracing
(defmethod route-envelope :around ((node swarm-tree) envelope)
  "Trace all envelope routing through the tree."
  (let ((start-time (get-internal-real-time)))
    (log:debug "Routing ~A through ~A" (envelope-id envelope) (swarm-id node))
    (unwind-protect
        (call-next-method)
      (let ((duration (- (get-internal-real-time) start-time)))
        (record-metric (node-metrics node) :route-latency duration)))))

;;; MOP: Auto-update routing table on child registration
(defmethod (setf gethash) :after (value (key string) (table routing-table))
  "Update routing indexes when routing table changes."
  (rebuild-routing-indexes table))
```

#### 2.2.4 Image-Based Development

```lisp
;;; Save entire orchestrator state to disk
(defun save-orchestrator-checkpoint (path)
  "Save orchestrator state for crash recovery."
  (let ((state (capture-orchestrator-state *orchestrator*)))
    (with-open-file (out path :direction :output
                              :if-exists :supersede
                              :element-type '(unsigned-byte 8))
      (cl-store:store state out))
    (log:info "Checkpoint saved to ~A" path)))

;;; Build standalone executable
(defun build-orchestrator-image ()
  "Build standalone orchestrator executable."
  (sb-ext:save-lisp-and-die "sw4rm-orchestrator"
    :toplevel #'main
    :executable t
    :compression t
    :save-runtime-options t))

;;; Restore from checkpoint on startup
(defun restore-from-checkpoint (path)
  "Restore orchestrator state from checkpoint."
  (when (probe-file path)
    (with-open-file (in path :direction :input
                             :element-type '(unsigned-byte 8))
      (let ((state (cl-store:restore in)))
        (restore-orchestrator-state *orchestrator* state)
        (log:info "Restored from checkpoint ~A" path)
        t))))
```

---

## Part 3: Architecture

### 3.1 System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Common Lisp Orchestrator                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Tree Manager│  │Cross-Swarm  │  │ Checkpoint/Recovery     │ │
│  │             │  │Router       │  │                         │ │
│  └──────┬──────┘  └──────┬──────┘  └─────────────────────────┘ │
│         │                │                                       │
│  ┌──────┴────────────────┴──────────────────────────────────┐  │
│  │              gRPC Service Layer (cl-grpc)                 │  │
│  └──────────────────────────┬────────────────────────────────┘  │
└─────────────────────────────┼───────────────────────────────────┘
                              │ gRPC
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
   ┌───────────┐        ┌───────────┐        ┌───────────┐
   │  Python   │        │  Python   │        │  Python   │
   │  SW4RM    │        │  SW4RM    │        │  SW4RM    │
   │  Leaf A   │        │  Leaf B   │        │  Leaf C   │
   └───────────┘        └───────────┘        └───────────┘
```

### 3.2 Module Structure

```
sigagent/
├── sdks/
│   ├── py_sdk/                      # Existing Python SDK
│   │   └── sw4rm/
│   │
│   └── cl_sdk/                      # NEW: Common Lisp SDK
│       ├── sw4rm-orchestrator.asd   # ASDF system definition
│       ├── src/
│       │   ├── package.lisp         # Package definitions
│       │   ├── config.lisp          # Configuration management
│       │   │
│       │   ├── tree/                # SwarmTree ADT
│       │   │   ├── types.lisp       # Base types and protocols
│       │   │   ├── leaf.lisp        # Leaf node (Python wrapper)
│       │   │   ├── node.lisp        # Inner node (orchestrator)
│       │   │   └── traversal.lisp   # Tree operations
│       │   │
│       │   ├── envelope/            # Envelope handling
│       │   │   ├── types.lisp       # Envelope data types
│       │   │   ├── reader.lisp      # Reader macros (#E{}, #X{})
│       │   │   └── serialization.lisp
│       │   │
│       │   ├── routing/             # Cross-swarm routing
│       │   │   ├── router.lisp      # Core routing logic
│       │   │   ├── table.lisp       # Routing table management
│       │   │   └── strategies.lisp  # Routing strategies
│       │   │
│       │   ├── coordination/        # Cross-swarm coordination
│       │   │   ├── sync.lisp        # Barrier synchronization
│       │   │   ├── artifacts.lisp   # Shared artifact registry
│       │   │   └── negotiation.lisp # Cross-swarm negotiation
│       │   │
│       │   ├── errors/              # Error handling
│       │   │   ├── conditions.lisp  # Condition definitions
│       │   │   └── restarts.lisp    # Standard restarts
│       │   │
│       │   ├── grpc/                # gRPC bridge to Python
│       │   │   ├── client.lisp      # gRPC client
│       │   │   ├── server.lisp      # gRPC server (for Python callbacks)
│       │   │   └── proto-compat.lisp
│       │   │
│       │   ├── persistence/         # State management
│       │   │   ├── checkpoint.lisp  # Image checkpointing
│       │   │   └── wal.lisp         # Write-ahead logging
│       │   │
│       │   └── main.lisp            # Entry point
│       │
│       ├── test/                    # Test suite
│       │   ├── tree-tests.lisp
│       │   ├── routing-tests.lisp
│       │   └── integration-tests.lisp
│       │
│       ├── examples/                # Example usage
│       │   ├── two-swarm.lisp
│       │   ├── microservices.lisp
│       │   └── hierarchical.lisp
│       │
│       └── Dockerfile               # SBCL + Quicklisp container
│
├── protocols/
│   └── cross-swarm.proto            # gRPC interface definition
│
└── documentation/
    └── protocols/
        └── tree-orchestration.md    # Protocol specification
```

### 3.3 Core Data Types

```lisp
;;;; tree/types.lisp

(in-package :sw4rm-orchestrator)

;;; Envelope for cross-swarm communication
(defstruct (cross-swarm-envelope (:conc-name envelope-))
  (id (make-uuid) :type string :read-only t)
  (correlation-id nil :type (or null string))
  (idempotency-token nil :type (or null string))
  (source-swarm nil :type (or null string))
  (target-swarm nil :type (or null string))
  (sender nil :type (or null string))
  (recipient nil :type (or null string))
  (payload nil :type t)
  (path nil :type list)          ; Route taken: ("root" "cluster-a" "leaf-1")
  (hop-count 0 :type fixnum)
  (max-hops 10 :type fixnum)
  (created-at (get-universal-time) :type integer)
  (deadline nil :type (or null integer)))

;;; Routing decision
(deftype routing-decision ()
  '(member :local :child :parent :broadcast :reject))

(defstruct routing-result
  (decision :reject :type routing-decision)
  (target nil :type (or null string swarm-tree))
  (reason nil :type (or null string)))

;;; Tree node protocol
(defgeneric route-envelope (node envelope)
  (:documentation "Route envelope through this node"))

(defgeneric receive-envelope (node envelope)
  (:documentation "Receive envelope at this node"))

(defgeneric register-child (node child)
  (:documentation "Register a child node"))

(defgeneric unregister-child (node child-id)
  (:documentation "Unregister a child node"))

(defgeneric get-child (node child-id)
  (:documentation "Get child by ID"))

(defgeneric list-children (node)
  (:documentation "List all children"))

(defgeneric node-depth (node)
  (:documentation "Depth of node in tree"))
```

### 3.4 Routing Algorithm

```lisp
;;;; routing/router.lisp

(defmethod route-envelope ((node swarm-node) envelope)
  "Route envelope through orchestrator node."
  (let ((target-swarm (envelope-target-swarm envelope)))
    (cond
      ;; Check hop limit
      ((>= (envelope-hop-count envelope) (envelope-max-hops envelope))
       (make-routing-result :decision :reject
                            :reason "Max hops exceeded"))

      ;; Target is this node itself (rare, but valid for meta-operations)
      ((string= target-swarm (swarm-id node))
       (receive-envelope node envelope)
       (make-routing-result :decision :local :target node))

      ;; Target is a direct child
      ((get-child node target-swarm)
       (let ((child (get-child node target-swarm)))
         (push (swarm-id node) (envelope-path envelope))
         (incf (envelope-hop-count envelope))
         (route-envelope child envelope)
         (make-routing-result :decision :child :target child)))

      ;; Target might be under a child (check routing table)
      ((lookup-route (routing-table node) target-swarm)
       (let* ((next-hop (lookup-route (routing-table node) target-swarm))
              (child (get-child node next-hop)))
         (push (swarm-id node) (envelope-path envelope))
         (incf (envelope-hop-count envelope))
         (route-envelope child envelope)
         (make-routing-result :decision :child :target child)))

      ;; Route to parent (if we have one)
      ((parent-node node)
       (push (swarm-id node) (envelope-path envelope))
       (incf (envelope-hop-count envelope))
       (route-envelope (parent-node node) envelope)
       (make-routing-result :decision :parent :target (parent-node node)))

      ;; Broadcast to all children (for discovery)
      ((eq target-swarm :broadcast)
       (dolist (child (list-children node))
         (let ((envelope-copy (copy-cross-swarm-envelope envelope)))
           (route-envelope child envelope-copy)))
       (make-routing-result :decision :broadcast))

      ;; Target not found
      (t
       (make-routing-result :decision :reject
                            :reason (format nil "Swarm ~A not found" target-swarm))))))

(defmethod route-envelope ((leaf swarm-leaf) envelope)
  "Route envelope to Python sw4rm leaf via gRPC."
  (let ((target-swarm (envelope-target-swarm envelope)))
    (cond
      ;; This is the target leaf
      ((string= target-swarm (swarm-id leaf))
       (deliver-to-python-swarm leaf envelope)
       (make-routing-result :decision :local :target leaf))

      ;; Not for this leaf, route back to parent
      ((parent-node leaf)
       (route-envelope (parent-node leaf) envelope))

      ;; Orphan leaf, cannot route
      (t
       (make-routing-result :decision :reject
                            :reason "Orphan leaf cannot route")))))
```

---

## Part 4: gRPC Bridge to Python

### 4.1 Proto Definition

```protobuf
// protocols/cross-swarm.proto

syntax = "proto3";

package sw4rm.orchestrator;

// Cross-swarm envelope
message CrossSwarmEnvelope {
  string id = 1;
  string correlation_id = 2;
  string idempotency_token = 3;
  string source_swarm = 4;
  string target_swarm = 5;
  string sender = 6;
  string recipient = 7;
  bytes payload = 8;  // JSON-encoded payload
  repeated string path = 9;
  int32 hop_count = 10;
  int32 max_hops = 11;
  int64 created_at = 12;
  int64 deadline = 13;
}

// Registration request from Python leaf
message LeafRegistration {
  string swarm_id = 1;
  string host = 2;
  int32 port = 3;
  repeated string capabilities = 4;
}

// Heartbeat from Python leaf
message Heartbeat {
  string swarm_id = 1;
  int64 timestamp = 2;
  map<string, string> metrics = 3;
}

// Routing result
message RoutingResult {
  enum Decision {
    LOCAL = 0;
    CHILD = 1;
    PARENT = 2;
    BROADCAST = 3;
    REJECT = 4;
  }
  Decision decision = 1;
  string target = 2;
  string reason = 3;
}

// Orchestrator service (called by Python leaves)
service OrchestratorService {
  // Register a Python sw4rm as leaf
  rpc RegisterLeaf(LeafRegistration) returns (RegistrationResponse);

  // Unregister a leaf
  rpc UnregisterLeaf(LeafId) returns (UnregistrationResponse);

  // Route envelope from Python to another swarm
  rpc RouteEnvelope(CrossSwarmEnvelope) returns (RoutingResult);

  // Heartbeat stream
  rpc HeartbeatStream(stream Heartbeat) returns (stream HeartbeatAck);
}

// Leaf service (called by Lisp orchestrator)
service LeafService {
  // Deliver envelope to Python sw4rm
  rpc DeliverEnvelope(CrossSwarmEnvelope) returns (DeliveryAck);

  // Query leaf status
  rpc GetStatus(StatusRequest) returns (LeafStatus);

  // Trigger graceful shutdown
  rpc Shutdown(ShutdownRequest) returns (ShutdownResponse);
}
```

### 4.2 Lisp gRPC Client

```lisp
;;;; grpc/client.lisp

(in-package :sw4rm-orchestrator.grpc)

(defclass leaf-grpc-client ()
  ((swarm-id :initarg :swarm-id :accessor client-swarm-id)
   (host :initarg :host :accessor client-host)
   (port :initarg :port :accessor client-port)
   (channel :accessor client-channel :initform nil)
   (stub :accessor client-stub :initform nil)
   (connected-p :accessor client-connected-p :initform nil))
  (:documentation "gRPC client for communicating with Python sw4rm leaf"))

(defmethod connect ((client leaf-grpc-client))
  "Establish gRPC connection to Python leaf."
  (let* ((address (format nil "~A:~A" (client-host client) (client-port client)))
         (channel (grpc:make-channel address)))
    (setf (client-channel client) channel
          (client-stub client) (make-leaf-service-stub channel)
          (client-connected-p client) t)
    (log:info "Connected to leaf ~A at ~A" (client-swarm-id client) address)
    client))

(defmethod disconnect ((client leaf-grpc-client))
  "Close gRPC connection."
  (when (client-channel client)
    (grpc:close-channel (client-channel client))
    (setf (client-connected-p client) nil)
    (log:info "Disconnected from leaf ~A" (client-swarm-id client))))

(defmethod deliver-envelope ((client leaf-grpc-client) envelope)
  "Deliver envelope to Python leaf via gRPC."
  (unless (client-connected-p client)
    (error 'swarm-disconnected :swarm-id (client-swarm-id client)))
  (let ((proto-envelope (envelope-to-proto envelope)))
    (grpc:call (client-stub client) 'deliver-envelope proto-envelope)))

(defun envelope-to-proto (envelope)
  "Convert Lisp envelope to protobuf."
  (make-instance 'cross-swarm-envelope-proto
    :id (envelope-id envelope)
    :correlation-id (or (envelope-correlation-id envelope) "")
    :idempotency-token (or (envelope-idempotency-token envelope) "")
    :source-swarm (or (envelope-source-swarm envelope) "")
    :target-swarm (or (envelope-target-swarm envelope) "")
    :sender (or (envelope-sender envelope) "")
    :recipient (or (envelope-recipient envelope) "")
    :payload (json:encode (envelope-payload envelope))
    :path (envelope-path envelope)
    :hop-count (envelope-hop-count envelope)
    :max-hops (envelope-max-hops envelope)
    :created-at (envelope-created-at envelope)
    :deadline (or (envelope-deadline envelope) 0)))
```

---

## Part 5: Tooling to Build

Since you're willing to invest in tooling, here's what we need:

### 5.1 Required Libraries (Existing)

| Library | Purpose | Status |
|---------|---------|--------|
| SBCL | Common Lisp implementation | Mature |
| Quicklisp | Package manager | Mature |
| cl-json / jonathan | JSON serialization | Mature |
| bordeaux-threads | Threading | Mature |
| lparallel | Parallel execution | Mature |
| cl-store | Object serialization | Mature |
| log4cl | Logging | Mature |
| fiveam | Testing | Mature |

### 5.2 Libraries to Build/Adapt

| Library | Purpose | Effort |
|---------|---------|--------|
| **cl-grpc** | gRPC client/server | Medium (use grpc-common-lisp or build) |
| **cl-prometheus** | Metrics export | Small (wrap prom.io) |
| **cl-k8s-client** | Kubernetes API | Medium (generate from OpenAPI) |
| **sw4rm-proto** | Proto3 message types | Small (generate from .proto) |

### 5.3 Development Infrastructure

```dockerfile
# Dockerfile for sw4rm-orchestrator

FROM debian:bookworm-slim

# Install SBCL and dependencies
RUN apt-get update && apt-get install -y \
    sbcl \
    curl \
    git \
    libssl-dev \
    libprotobuf-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Install Quicklisp
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp && \
    sbcl --load quicklisp.lisp \
         --eval '(quicklisp-quickstart:install)' \
         --eval '(ql:add-to-init-file)' \
         --quit

# Copy source
WORKDIR /app
COPY . .

# Load dependencies and build
RUN sbcl --eval '(ql:quickload :sw4rm-orchestrator)' \
         --eval '(sw4rm-orchestrator:build-image)' \
         --quit

# Run orchestrator
ENTRYPOINT ["./sw4rm-orchestrator"]
```

### 5.4 Testing Infrastructure

```lisp
;;;; test/integration-tests.lisp

(in-package :sw4rm-orchestrator.test)

(def-suite integration-tests
  :description "Integration tests with Python sw4rm leaves")

(in-suite integration-tests)

(defvar *test-orchestrator* nil)
(defvar *python-leaf-a* nil)
(defvar *python-leaf-b* nil)

(def-fixture two-leaf-setup ()
  "Setup orchestrator with two Python leaves."
  (setf *test-orchestrator* (make-instance 'swarm-node :id "root"))
  ;; Start Python leaves in Docker
  (setf *python-leaf-a* (start-python-leaf "leaf-a" :port 50051))
  (setf *python-leaf-b* (start-python-leaf "leaf-b" :port 50052))
  ;; Register with orchestrator
  (register-leaf *test-orchestrator* *python-leaf-a*)
  (register-leaf *test-orchestrator* *python-leaf-b*)
  ;; Run test
  (unwind-protect
      (&body)
    ;; Cleanup
    (stop-python-leaf *python-leaf-a*)
    (stop-python-leaf *python-leaf-b*)))

(test cross-swarm-message-delivery
  "Test message routing between two Python leaves via Lisp orchestrator."
  (with-fixture two-leaf-setup ()
    (let ((envelope (make-cross-swarm-envelope
                      :source-swarm "leaf-a"
                      :target-swarm "leaf-b"
                      :sender "agent-1"
                      :recipient "agent-2"
                      :payload '(:message "hello"))))
      (let ((result (route-envelope *test-orchestrator* envelope)))
        (is (eq (routing-result-decision result) :child))
        (is (string= (swarm-id (routing-result-target result)) "leaf-b"))
        ;; Verify Python leaf-b received the message
        (is (envelope-received-p *python-leaf-b* (envelope-id envelope)))))))
```

---

## Part 6: Implementation Roadmap

### Phase 1: Foundation (Weeks 1-3)

1. **Setup project structure**
   - ASDF system definition
   - Package structure
   - CI/CD pipeline

2. **Core data types**
   - `swarm-tree`, `swarm-leaf`, `swarm-node`
   - `cross-swarm-envelope`
   - Reader macros `#E{}` and `#X{}`

3. **Basic routing**
   - Tree traversal
   - Local/child/parent routing decisions
   - Routing table management

### Phase 2: gRPC Bridge (Weeks 4-6)

1. **Proto compilation**
   - Generate Lisp stubs from proto3
   - Envelope serialization

2. **gRPC client**
   - Connection management
   - Envelope delivery to Python

3. **gRPC server**
   - Registration endpoint
   - Heartbeat handling

### Phase 3: Integration Testing (Weeks 7-8)

1. **Two-leaf scenario**
   - Python leaf A → Lisp orchestrator → Python leaf B

2. **Failure scenarios**
   - Leaf disconnection
   - Routing failures
   - Timeout handling

### Phase 4: Advanced Features (Weeks 9-12)

1. **Checkpointing**
   - State serialization
   - Recovery from checkpoint

2. **Nested orchestrators**
   - Orchestrator as child of another orchestrator
   - Multi-level routing

3. **Cross-swarm coordination**
   - Barrier synchronization
   - Shared artifact registry

---

## Part 7: Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| gRPC library immaturity | Medium | High | Build minimal wrapper, contribute upstream |
| Performance overhead | Low | Medium | Benchmark early, optimize hot paths |
| Debugging complexity | Medium | Medium | Extensive logging, SLIME integration |
| Team unfamiliarity with Lisp | High | Medium | Documentation, pair programming, training |
| Deployment complexity | Medium | Medium | Docker images, k8s operators |

---

## Part 8: Success Criteria

### Milestone 1: Basic Routing (Week 3)
- [ ] SwarmTree ADT implemented
- [ ] Reader macros working
- [ ] In-memory routing tests pass

### Milestone 2: Python Bridge (Week 6)
- [ ] gRPC client connects to Python leaf
- [ ] Envelope delivered from Lisp to Python
- [ ] Heartbeat monitoring working

### Milestone 3: Two-Leaf Integration (Week 8)
- [ ] Message routes: Python A → Lisp → Python B
- [ ] Failure handling with conditions/restarts
- [ ] Metrics exported to Prometheus

### Milestone 4: Production Ready (Week 12)
- [ ] Checkpointing and recovery
- [ ] 3-level hierarchy (root → orchestrator → leaves)
- [ ] Performance benchmarks acceptable
- [ ] Documentation complete

---

## Appendix A: Quick Start Guide

```lisp
;;; Load the system
(ql:quickload :sw4rm-orchestrator)
(in-package :sw4rm-orchestrator)

;;; Create a simple two-leaf tree
(defparameter *root*
  (make-instance 'swarm-node :id "root"))

;;; Register Python leaves (assumes they're running)
(register-leaf *root*
  (make-instance 'swarm-leaf
    :id "frontend"
    :host "localhost"
    :port 50051))

(register-leaf *root*
  (make-instance 'swarm-leaf
    :id "backend"
    :host "localhost"
    :port 50052))

;;; Route a message
(route-envelope *root*
  #X{:source-swarm "frontend"
     :target-swarm "backend"
     :sender "ui-agent"
     :recipient "api-agent"
     :payload {:event "user-login" :user-id 42}})

;;; Check routing table
(print-routing-table (routing-table *root*))
```

---

## Appendix B: Comparison with Alternatives

### B.1 Why Not Clojure?

| Factor | Common Lisp | Clojure |
|--------|-------------|---------|
| Macro power | Reader + compiler macros | Compiler macros only |
| Startup time | Fast (native image) | Slow (JVM) or medium (GraalVM) |
| Runtime modification | Full | Limited |
| Memory footprint | Lower | Higher (JVM) |
| Condition system | Full conditions/restarts | Exceptions only |

**Decision:** Common Lisp's reader macros and conditions/restarts provide unique advantages for orchestration.

### B.2 Why Not Stay Pure Python?

| Factor | Common Lisp | Python |
|--------|-------------|--------|
| Macro system | Full | None (decorators only) |
| Custom syntax | Reader macros | No |
| Error handling | Conditions/restarts | Exceptions |
| Performance | SBCL is fast | Slower |
| Type system | CLOS + MOP | Limited |

**Decision:** Python is excellent for leaf-level agent execution; Lisp is better for meta-level orchestration.

---

*This proposal is a living document. Updates will be tracked in version control.*
