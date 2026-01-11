;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; SW4RM Common Lisp Orchestrator SDK - Package Definitions
;;;;
;;;; This file defines all packages for the SW4RM Common Lisp orchestration layer.
;;;; The orchestrator manages hierarchical sw4rm systems where each node is either
;;;; a leaf (complete Python sw4rm instance) or an inner node (orchestrator coordinating
;;;; child sw4rms).
;;;;
;;;; Package Structure:
;;;;   :sw4rm-orchestrator           - Main package, re-exports public API
;;;;   :sw4rm-orchestrator.tree      - SwarmTree ADT (algebraic data type)
;;;;   :sw4rm-orchestrator.envelope  - Cross-swarm envelope handling
;;;;   :sw4rm-orchestrator.routing   - Cross-swarm routing algorithms
;;;;   :sw4rm-orchestrator.errors    - Condition system and error handling
;;;;   :sw4rm-orchestrator.coordination - Cross-swarm synchronization primitives
;;;;   :sw4rm-orchestrator.grpc      - gRPC bridge to Python sw4rm instances
;;;;   :sw4rm-orchestrator.persistence - Checkpoint and recovery infrastructure
;;;;
;;;; See documentation in ../../../documentation/protocol/spec.md and
;;;; ../../../COMMON_LISP_PLAN.md for architectural overview.
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :cl-user)

;;;; ============================================================================
;;;; Package 1: :sw4rm-orchestrator.errors
;;;; ============================================================================
;;;;
;;;; Defines the condition system for sophisticated distributed error handling.
;;;;
;;;; The Common Lisp condition/restart mechanism is uniquely powerful for
;;;; distributed systems because it separates error DETECTION from error
;;;; HANDLING. Code that detects a problem (e.g., "swarm unreachable") signals
;;;; a condition. Higher-level code (handlers) can then decide how to handle it
;;;; (retry, alternative route, queue for later, dead-letter, drop).
;;;;
;;;; This is more powerful than exception-based approaches because the handler
;;;; can invoke restarts that alter the control flow of the detecting code
;;;; without requiring try-catch in every layer.

(defpackage :sw4rm-orchestrator.errors
  (:documentation
   "Error handling via conditions and restarts for distributed orchestration.

    Exports:
    - Condition types: SW4RM-ERROR, SWARM-UNREACHABLE, SWARM-DISCONNECTED,
                       ROUTING-ERROR, ENVELOPE-ERROR
    - Restart names: RETRY-WITH-BACKOFF, ROUTE-TO-ALTERNATIVE, QUEUE-FOR-RETRY,
                     DEAD-LETTER, DROP-MESSAGE

    Example:
      (handler-bind
          ((swarm-unreachable
             (lambda (c)
               (invoke-restart 'retry-with-backoff 5))))
        (route-envelope orchestrator envelope))")
  (:use :cl)
  (:export
   ;; Condition types
   #:sw4rm-error
   #:sw4rm-error-message
   #:swarm-unreachable
   #:swarm-unreachable-swarm-id
   #:swarm-unreachable-last-seen
   #:swarm-disconnected
   #:swarm-disconnected-swarm-id
   #:swarm-disconnected-reason
   #:routing-error
   #:routing-error-source
   #:routing-error-target
   #:routing-error-reason
   #:envelope-error
   #:envelope-error-envelope-id
   #:envelope-error-reason
   #:max-hops-exceeded
   #:max-hops-exceeded-envelope-id
   #:max-hops-exceeded-hop-count
   #:max-hops-exceeded-max-hops
   #:deadline-exceeded
   #:deadline-exceeded-deadline
   #:deadline-exceeded-current-time
   #:idempotent-delivery-error
   #:idempotent-delivery-error-envelope-id
   #:idempotent-delivery-error-previous-result
   #:coordination-error

   ;; Restart names (symbols to pass to invoke-restart)
   #:retry-with-backoff
   #:route-to-alternative
   #:queue-for-retry
   #:dead-letter
   #:drop-message))

;;;; ============================================================================
;;;; Package 2: :sw4rm-orchestrator.tree
;;;; ============================================================================
;;;;
;;;; Defines the SwarmTree algebraic data type.
;;;;
;;;; The tree structure is the core of the orchestrator architecture:
;;;;   SwarmTree = Leaf(SwarmInstance) | Node(Orchestrator, [SwarmTree])
;;;;
;;;; This enables:
;;;;   - Arbitrary nesting depth (practical systems use 2-4 levels)
;;;;   - Independent sw4rm instances as composable units
;;;;   - Hierarchical routing with path-based message delivery
;;;;   - Failure isolation at sw4rm boundaries
;;;;
;;;; We use CLOS (Common Lisp Object System) with a protocol hierarchy:
;;;;   swarm-tree (base)
;;;;   +-- swarm-leaf (wraps Python sw4rm)
;;;;   +-- swarm-node (orchestrator)

(defpackage :sw4rm-orchestrator.tree
  (:documentation
   "SwarmTree algebraic data type for hierarchical orchestration.

    Core types:
    - SWARM-TREE: Base class for all tree nodes
    - SWARM-LEAF: Leaf node wrapping a Python sw4rm instance
    - SWARM-NODE: Inner orchestrator node coordinating children

    Generic functions (protocol):
    - ROUTE-ENVELOPE: Route envelope through this node
    - RECEIVE-ENVELOPE: Receive envelope at this node
    - REGISTER-CHILD: Register a child node
    - UNREGISTER-CHILD: Remove child by ID
    - GET-CHILD: Retrieve child by ID
    - LIST-CHILDREN: List all children
    - NODE-DEPTH: Compute depth in tree

    Accessors for swarm-tree:
    - SWARM-ID: Unique identifier for this node
    - PARENT-NODE: Parent node (nil for root)
    - NODE-METRICS: Metrics collector for this node

    Accessors for swarm-leaf (extends swarm-tree):
    - LEAF-SCHEDULER: Reference to Python scheduler (via gRPC)
    - LEAF-ROUTER: Reference to Python router (via gRPC)
    - LEAF-REGISTRY: Reference to Python registry (via gRPC)
    - LEAF-AGENTS: List of agent registrations
    - GRPC-CHANNEL: Active gRPC channel to Python instance

    Accessors for swarm-node (extends swarm-tree):
    - NODE-CHILDREN: Hash table of child nodes (id -> swarm-tree)
    - ROUTING-TABLE: Routing table for cross-swarm messages
    - NODE-POLICY: Orchestration policy for this node

    Example:
      (defparameter *root* (make-instance 'swarm-node :id \"root\"))
      (register-child *root* (make-instance 'swarm-leaf :id \"leaf-a\"))
      (route-envelope *root* envelope)")
  (:use :cl)
  (:export
   ;; Classes (types)
   #:swarm-tree
   #:swarm-leaf
   #:swarm-node

   ;; Type predicates
   #:swarm-tree-p
   #:swarm-node-p
   #:swarm-leaf-p

   ;; Constructor functions
   #:make-swarm-leaf
   #:make-swarm-node

   ;; Accessors common to all nodes
   #:swarm-id
   #:parent-node
   #:node-metrics
   #:node-status
   #:record-metric

   ;; Accessors for swarm-leaf
   #:leaf-host
   #:leaf-port
   #:leaf-capabilities
   #:leaf-last-heartbeat
   #:leaf-scheduler
   #:leaf-router
   #:leaf-registry
   #:leaf-agents
   #:grpc-channel
   #:leaf-grpc-client
   #:leaf-grpc-client

   ;; Accessors for swarm-node
   #:node-children
   #:routing-table
   #:node-policy

   ;; Generic functions (protocol methods)
   #:route-envelope
   #:receive-envelope
   #:register-child
   #:unregister-child
   #:get-child
   #:list-children
   #:node-depth

   ;; Utility functions
   #:find-leaf-by-id
   #:find-ancestor-of-type
   #:subtree-nodes
   #:subtree-depth

   ;; Path operations (from traversal.lisp)
   #:node-path
   #:path-to-node
   #:common-ancestor
   #:distance-between

   ;; Tree walking (functional traversal)
   #:walk-tree
   #:walk-leaves
   #:walk-nodes
   #:map-tree
   #:filter-tree

   ;; Depth-first operations
   #:dfs-traverse
   #:find-node
   #:collect-nodes

   ;; Breadth-first operations
   #:bfs-traverse
   #:nodes-at-depth
   #:find-nearest

   ;; Tree statistics
   #:tree-height
   #:tree-size
   #:leaf-count
   #:node-count
   #:tree-balanced-p

   ;; Tree modification
   #:prune-subtree
   #:copy-swarm-tree

   ;; Path-based queries
   #:resolve-path
   #:node-to-path-string
   #:path-matches-p

   ;; Tree validation
   #:validate-tree
   #:detect-cycles
   #:find-orphans
   #:find-root))

;;;; ============================================================================
;;;; Package 3: :sw4rm-orchestrator.envelope
;;;; ============================================================================
;;;;
;;;; Defines envelope types and operations for cross-swarm communication.
;;;;
;;;; An envelope carries a message across swarm boundaries with metadata:
;;;;   - IDs (message-id, correlation-id, idempotency-token)
;;;;   - Routing (source-swarm, target-swarm, sender, recipient)
;;;;   - Payload (typed data)
;;;;   - Path tracking (route taken, hop count, deadline)
;;;;
;;;; Envelopes are structured to enable:
;;;;   - Idempotent delivery (idempotency-token)
;;;;   - Correlation tracking (correlation-id for workflows)
;;;;   - Deadline enforcement (timeout protection)
;;;;   - Hop limiting (prevent infinite loops)

(defpackage :sw4rm-orchestrator.envelope
  (:documentation
   "Cross-swarm envelope data types and operations.

    Main type: CROSS-SWARM-ENVELOPE

    IDs (three-ID model):
    - ENVELOPE-ID: Unique message identifier (UUID)
    - ENVELOPE-CORRELATION-ID: Tracks related messages in workflow
    - ENVELOPE-IDEMPOTENCY-TOKEN: Enables idempotent delivery

    Routing:
    - ENVELOPE-SOURCE-SWARM: Originating swarm
    - ENVELOPE-TARGET-SWARM: Destination swarm
    - ENVELOPE-SENDER: Agent sending from source swarm
    - ENVELOPE-RECIPIENT: Agent receiving at target swarm

    Payload:
    - ENVELOPE-PAYLOAD: Typed message data (any Lisp object or JSON)

    Path tracking:
    - ENVELOPE-PATH: Breadcrumb trail of nodes visited
    - ENVELOPE-HOP-COUNT: Current hop count (incremented at each node)
    - ENVELOPE-MAX-HOPS: Maximum allowed hops (default 10)

    Lifecycle:
    - ENVELOPE-CREATED-AT: Timestamp of creation
    - ENVELOPE-DEADLINE: Absolute deadline (nil = no deadline)

    Functions:
    - MAKE-CROSS-SWARM-ENVELOPE: Create new envelope
    - COPY-CROSS-SWARM-ENVELOPE: Deep copy
    - ENVELOPE-EXPIRED-P: Check if past deadline
    - ENVELOPE-HOP-LIMIT-EXCEEDED-P: Check if hops exhausted

    Reader macros:
    - #X{...} : Cross-swarm envelope shorthand
    - #E{...} : Generic envelope shorthand

    Example:
      #X{:source-swarm frontend
         :target-swarm backend
         :sender ui-agent
         :recipient api-agent
         :payload {:event \"user-login\"}}")
  (:use :cl)
  (:export
   ;; Type definition
   #:cross-swarm-envelope

   ;; Constructor and copy
   #:make-cross-swarm-envelope
   #:copy-cross-swarm-envelope

   ;; ID accessors (three-ID model)
   #:envelope-id
   #:envelope-correlation-id
   #:envelope-idempotency-token

   ;; Routing accessors
   #:envelope-source-swarm
   #:envelope-target-swarm
   #:envelope-sender
   #:envelope-recipient

   ;; Payload accessor
   #:envelope-payload

   ;; Path tracking accessors
   #:envelope-path
   #:envelope-hop-count
   #:envelope-max-hops

   ;; Lifecycle accessors
   #:envelope-created-at
   #:envelope-deadline

   ;; Predicates
   #:envelope-expired-p
   #:envelope-hop-limit-exceeded-p
   #:envelope-is-local-p

   ;; Utility functions
   #:envelope-add-to-path
   #:envelope-increment-hop-count
   #:envelope-set-deadline
   #:envelope-set_deadline
   #:envelope-remaining-ttl

   ;; Validation helpers
   #:validate-envelope
   #:envelope-valid-for-routing-p

   ;; Routing result helpers (defined in types.lisp)
   #:routing-result
   #:make-routing-result
   #:routing-result-decision
   #:routing-result-target
   #:routing-result-reason
   #:routing-result-latency-ms
   #:routing-result-latency-ms

   ;; Serialization helpers (defined in serialization.lisp)
   #:envelope-to-json
   #:envelope-from-json
   #:json-to-envelope
   #:envelope-to-plist
   #:envelope-from-plist
   #:plist-to-envelope
   #:envelope-to-octets
   #:octets-to-envelope
   #:envelope-to-binary
   #:envelope-from-binary

   ;; Reader macro support
   #:enable-envelope-syntax
   #:disable-envelope-syntax
   #:with-envelope-syntax
   #:*envelope-readtable*))

;;;; ============================================================================
;;;; Package 4: :sw4rm-orchestrator.routing
;;;; ============================================================================
;;;;
;;;; Defines routing algorithms and routing table management.
;;;;
;;;; The routing system decides how to forward envelopes through the tree:
;;;;   - LOCAL: Envelope is for this node
;;;;   - CHILD: Forward to child node
;;;;   - PARENT: Forward to parent node
;;;;   - BROADCAST: Deliver to all children
;;;;   - REJECT: Cannot deliver
;;;;
;;;; Routing decisions are based on:
;;;;   1. Direct children (check node-children hash table)
;;;;   2. Known descendants (check routing table)
;;;;   3. Parent node (if we have one)
;;;;   4. Broadcast/discovery patterns
;;;;
;;;; Routing tables are built by:
;;;;   - Automatic registration when children join
;;;;   - Gossip protocol (children advertise their subtrees)
;;;;   - Topology discovery

(defpackage :sw4rm-orchestrator.routing
  (:documentation
   "Cross-swarm routing algorithms and table management.

    Core types:
    - ROUTING-DECISION: Enum (:LOCAL, :CHILD, :PARENT, :BROADCAST, :REJECT)
    - ROUTING-RESULT: Structure with decision, target, and reason
    - ROUTING-TABLE: Data structure mapping swarm IDs to next hops

    Main functions:
    - COMPUTE-ROUTING-DECISION: Determine routing decision for envelope
    - LOOKUP-ROUTE: Find next hop for target swarm
    - ADD-ROUTE: Register new route
    - REMOVE-ROUTE: Deregister route
    - REBUILD-ROUTING-INDEXES: Update after topology changes

    Routing table operations:
    - MAKE-ROUTING-TABLE: Create empty routing table
    - ROUTING-TABLE-CONTAINS-P: Check if route exists
    - ROUTING-TABLE-LOCAL-ROUTES: Get all direct children
    - ROUTING-TABLE-EXTERNAL-ROUTES: Get all descendants

    Advanced:
    - COMPUTE-BROADCAST-TARGETS: Get all children for broadcast
    - DETECT-ROUTING-LOOP: Check for cycles
    - GET-ALTERNATIVE-ROUTES: Get backup paths (for failure recovery)

    Example:
      (let ((result (compute-routing-decision node envelope)))
        (ecase (routing-result-decision result)
          (:local (receive-envelope node envelope))
          (:child (route-to-child (routing-result-target result) envelope))
          (:parent (route-to-parent envelope))
          (:reject (handle-routing-failure envelope))))")
  (:use :cl)
  (:import-from :sw4rm-orchestrator.envelope
   #:routing-result
   #:make-routing-result
   #:routing-result-decision
   #:routing-result-target
   #:routing-result-reason
   #:routing-result-latency-ms
   #:envelope-target-swarm
   #:envelope-hop-limit-exceeded-p
   #:envelope-hop-count
   #:envelope-max-hops
   #:envelope-expired-p
   #:envelope-deadline
   #:envelope-path)
  (:import-from :sw4rm-orchestrator.tree
   #:swarm-id
   #:swarm-node
   #:swarm-leaf
   #:parent-node
   #:get-child
   #:list-children
   #:node-metrics)
  (:export
   ;; Type definitions
   #:routing-decision
   #:routing-result
   #:routing-table

   ;; Constructor
   #:make-routing-result
   #:make-routing-table

   ;; Result accessors
   #:routing-result-decision
   #:routing-result-target
   #:routing-result-reason

   ;; Routing table operations
   #:lookup-route
   #:add-route
   #:remove-route
   #:routing-table-contains-p
   #:routing-table-local-routes
   #:routing-table-external-routes

   ;; Main routing logic
   #:compute-routing-decision
   #:rebuild-routing-indexes
   #:compute-broadcast-targets

   ;; Advanced routing
   #:detect-routing-loop
   #:get-alternative-routes
   #:find-shortest-path
   #:get-route-metrics
   #:find-shortest-path
   #:get-route-metrics

   ;; Routing strategies (from strategies.lisp)
   #:routing-strategy
   #:select-route
   #:strategy-name
   #:strategy-priority
   #:strategy-metrics

   ;; Built-in strategies
   #:direct-routing-strategy
   #:round-robin-strategy
   #:least-loaded-strategy
   #:latency-based-strategy
   #:weighted-random-strategy
   #:failover-strategy
   #:broadcast-strategy

   ;; Strategy composition
   #:composite-strategy
   #:make-composite-strategy
   #:fallback-strategy
   #:make-fallback-strategy
   #:conditional-strategy
   #:make-conditional-strategy

   ;; Health checking (for failover)
   #:route-healthy-p
   #:mark-route-healthy
   #:mark-route-unhealthy
   #:reset-route-health

   ;; Latency tracking (for latency-based)
   #:record-latency

   ;; Weight management (for weighted-random)
   #:set-route-weight
   #:get-route-weight

   ;; Strategy factory and registry
   #:make-strategy
   #:*default-routing-strategy*
   #:*registered-strategies*
   #:register-strategy
   #:get-strategy
   #:unregister-strategy
   #:with-routing-strategy

   ;; Strategy metrics and introspection
   #:get-strategy-statistics
   #:reset-strategy-statistics
   #:describe-strategy))

;;;; ============================================================================
;;;; Package 5: :sw4rm-orchestrator.coordination
;;;; ============================================================================
;;;;
;;;; Defines cross-swarm coordination primitives.
;;;;
;;;; Enables sophisticated multi-swarm coordination:
;;;;   - Barriers: Synchronize across multiple leaves
;;;;   - Shared artifact registry: Publish and discover artifacts
;;;;   - Leases: Distributed locks with timeout
;;;;   - Semaphores: Resource counting across swarms
;;;;
;;;; These are higher-level than basic routing and provide structured
;;;; coordination for common patterns.

(defpackage :sw4rm-orchestrator.coordination
  (:documentation
   "Cross-swarm coordination primitives.

    Core types:
    - BARRIER: Multi-swarm synchronization point
    - SHARED-ARTIFACT-REGISTRY: Publish/discover shared artifacts
    - DISTRIBUTED-LEASE: Timeout-bound lock
    - SEMAPHORE: Resource counter across swarms

    Barrier operations:
    - CREATE-BARRIER: Create new barrier for participant set
    - BARRIER-ARRIVE: Participant signals it reached barrier
    - BARRIER-WAIT: Block until all participants arrive
    - BARRIER-RESET: Reset barrier for reuse
    - BARRIER-CANCEL: Cancel barrier and wake all waiters

    Artifact registry:
    - REGISTER-ARTIFACT: Publish artifact with metadata
    - UNREGISTER-ARTIFACT: Unpublish artifact
    - QUERY-ARTIFACTS: Find artifacts by criteria
    - GET-ARTIFACT: Retrieve artifact by ID

    Distributed leases:
    - ACQUIRE-LEASE: Request distributed lock
    - RELEASE-LEASE: Release distributed lock
    - EXTEND-LEASE: Renew lock expiration
    - LEASE-HELD-P: Check if currently held

    Example:
      ;; Synchronize work across three swarms
      (let ((barrier (create-barrier '(\"leaf-a\" \"leaf-b\" \"leaf-c\")
                                     :timeout 30)))
        (route-envelope orchestrator
          (make-envelope
            :target-swarm \"leaf-a\"
            :payload (list :barrier-id (barrier-id barrier))))
        (barrier-wait barrier)  ; Block until all arrive
        ...process results...)")
  (:use :cl)
  (:export
   ;; Barrier operations
   #:barrier
   #:create-barrier
   #:barrier-id
   #:barrier-participants
   #:barrier-participants-arrived
   #:barrier-arrive
   #:barrier-wait
   #:barrier-reset
   #:barrier-cancel
   #:barrier-open-p

   ;; Shared artifact registry
   #:shared-artifact-registry
   #:make-registry
   #:register-artifact
   #:unregister-artifact
   #:query-artifacts
   #:get-artifact
   #:artifact-metadata
   #:artifact-updated-at

   ;; Distributed leases
   #:distributed-lease
   #:acquire-lease
   #:release-lease
   #:extend-lease
   #:lease-held-p
   #:lease-holder
   #:lease-expiration

   ;; Distributed semaphores
   #:distributed-semaphore
   #:create-semaphore
   #:semaphore-acquire
   #:semaphore-release
   #:semaphore-value))

;;;; ============================================================================
;;;; Package 6: :sw4rm-orchestrator.grpc
;;;; ============================================================================
;;;;
;;;; Defines gRPC bridge for communication with Python sw4rm instances.
;;;;
;;;; The gRPC layer is the critical bridge between the Lisp orchestrator
;;;; and Python sw4rm leaves. It handles:
;;;;   - Connection management (establish, monitor, reconnect)
;;;;   - Envelope serialization/deserialization
;;;;   - Proto message conversion
;;;;   - Service stubs (leaf callbacks to orchestrator)
;;;;   - Streaming for heartbeats and events

(defpackage :sw4rm-orchestrator.grpc
  (:documentation
   "gRPC bridge to Python sw4rm instances.

    Core types:
    - LEAF-GRPC-CLIENT: Client for communicating with Python leaf

    Connection management:
    - CONNECT: Establish gRPC channel to Python leaf
    - DISCONNECT: Close gRPC channel
    - IS-CONNECTED-P: Check connection status
    - WAIT-FOR-CONNECTION: Block until connected
    - HEARTBEAT-STREAM: Monitor leaf health via heartbeats

    Envelope delivery:
    - DELIVER-ENVELOPE: Send envelope to Python leaf
    - DELIVER-ENVELOPES-BATCH: Send multiple envelopes
    - REGISTER-ENVELOPE-CALLBACK: Register handler for delivery ACK

    Service implementation:
    - START-GRPC-SERVER: Start orchestrator gRPC service
    - STOP-GRPC-SERVER: Shutdown orchestrator service
    - REGISTER-ROUTING-HANDLER: Register handler for routing requests

    Serialization:
    - ENVELOPE-TO-PROTO: Convert Lisp envelope to protobuf
    - PROTO-TO-ENVELOPE: Convert protobuf to Lisp envelope
    - PAYLOAD-TO-JSON: Serialize payload to JSON
    - PAYLOAD-FROM-JSON: Deserialize from JSON

    Example:
      (let ((client (make-instance 'leaf-grpc-client
                                   :swarm-id \"leaf-a\"
                                   :host \"localhost\"
                                   :port 50051)))
        (connect client)
        (deliver-envelope client envelope)
        (disconnect client))")
  (:use :cl)
  (:export
   ;; Client type
   #:leaf-grpc-client
   #:client-swarm-id
   #:client-host
   #:client-port
   #:client-channel
   #:client-connected-p

   ;; Connection management
   #:connect
   #:disconnect
   #:is-connected-p
   #:reconnect
   #:wait-for-connection
   #:with-connected-client

   ;; Envelope delivery
   #:deliver-envelope
   #:deliver-envelopes-batch
   #:register-delivery-callback
   #:delivery-acknowledgement

   ;; Server operations (orchestrator as service)
   #:start-grpc-server
   #:stop-grpc-server
   #:grpc-server-address
   #:grpc-server-running-p

   ;; Handlers
   #:register-routing-handler
   #:register-leaf-status-handler
   #:register-heartbeat-handler

   ;; Serialization
   #:envelope-to-proto
   #:proto-to-envelope
   #:payload-to-json
   #:payload-from-json
   #:heartbeat-to-proto
   #:proto-to-heartbeat

   ;; Streaming
   #:start-heartbeat-stream
   #:stop-heartbeat-stream
   #:heartbeat-stream-active-p))

;;;; ============================================================================
;;;; Package 7: :sw4rm-orchestrator.persistence
;;;; ============================================================================
;;;;
;;;; Defines checkpoint and recovery infrastructure.
;;;;
;;;; Common Lisp's image-based development model enables:
;;;;   - Save entire orchestrator state to disk
;;;;   - Restore from checkpoint on startup
;;;;   - Write-ahead logging for crash recovery
;;;;   - Incremental snapshots
;;;;
;;;; This is unique compared to other languages and provides powerful
;;;; fault tolerance guarantees.

(defpackage :sw4rm-orchestrator.persistence
  (:documentation
   "State management, checkpointing, and recovery.

    Core operations:
    - CAPTURE-ORCHESTRATOR-STATE: Snapshot current state
    - SAVE-ORCHESTRATOR-CHECKPOINT: Write checkpoint to disk
    - RESTORE-FROM-CHECKPOINT: Restore from saved checkpoint
    - RESTORE-ORCHESTRATOR-STATE: Apply checkpoint to running instance

    Write-ahead logging:
    - ENABLE-WAL: Start write-ahead log
    - DISABLE-WAL: Stop write-ahead log
    - WAL-ENABLED-P: Check if WAL active
    - FLUSH-WAL: Force WAL to disk

    Incremental snapshots:
    - CREATE-SNAPSHOT: Create named snapshot
    - LIST-SNAPSHOTS: List all saved snapshots
    - DELETE-SNAPSHOT: Remove snapshot
    - DIFF-SNAPSHOTS: Compare two snapshots

    Configuration:
    - SET-CHECKPOINT-INTERVAL: Configure auto-checkpoint timing
    - SET-CHECKPOINT-PATH: Configure where to save checkpoints
    - SET-COMPRESSION: Enable/disable compression

    Example:
      ;; Save checkpoint before shutdown
      (defun graceful-shutdown ()
        (save-orchestrator-checkpoint \"/var/sw4rm/checkpoint.bin\")
        (stop-grpc-server)
        (exit 0))

      ;; Restore on startup
      (defun main ()
        (restore-from-checkpoint \"/var/sw4rm/checkpoint.bin\")
        (start-grpc-server)
        ...)")
  (:use :cl)
  (:export
   ;; State capture
   #:capture-orchestrator-state
   #:orchestrator-state
   #:orchestrator-state-tree
   #:orchestrator-state-routing-tables
   #:orchestrator-state-connections
   #:orchestrator-state-timestamp
   #:orchestrator-state-version

   ;; Checkpoint operations
   #:save-orchestrator-checkpoint
   #:restore-from-checkpoint
   #:restore-orchestrator-state
   #:checkpoint-file-valid-p
   #:checkpoint-version
   #:checkpoint-timestamp

   ;; Write-ahead logging
   #:enable-wal
   #:disable-wal
   #:wal-enabled-p
   #:flush-wal

   ;; WAL types and accessors
   #:wal-log
   #:make-wal-log
   #:wal-entry
   #:make-wal-entry
   #:wal-entry-sequence
   #:wal-entry-timestamp
   #:wal-entry-operation
   #:wal-entry-data
   #:wal-entry-checksum
   #:wal-entry-swarm-id

   ;; WAL operations
   #:wal-append
   #:wal-flush
   #:wal-close
   #:wal-replay
   #:wal-entries
   #:wal-truncate
   #:wal-compact
   #:wal-rotate
   #:wal-size
   #:wal-last-sequence
   #:wal-get-stats

   ;; WAL configuration
   #:*wal-sync-mode*
   #:*wal-context*

   ;; WAL sharding (P2-3/P3-10)
   #:wal-sharding-enabled
   #:compute-shard-index
   #:total-shard-entries

   ;; CRC32 checksum utilities
   #:crc32

   ;; Snapshots
   #:create-snapshot
   #:list-snapshots
   #:delete-snapshot
   #:diff-snapshots
   #:snapshot-info
   #:snapshot-size

   ;; Configuration
   #:set-checkpoint-interval
   #:set-checkpoint-path
   #:set-compression
   #:set-max-wal-size

   ;; Utilities
   #:automatic-checkpoint-enabled-p
   #:trigger-checkpoint
   #:verify-checkpoint-integrity))

;;;; ============================================================================
;;;; Package 8: :sw4rm-orchestrator.metrics
;;;; ============================================================================
;;;;
;;;; Production metrics collection for observability and monitoring.
;;;;
;;;; Provides Prometheus-compatible metrics with counters, gauges, and histograms.
;;;; Designed for production deployment with thread-safe operations and efficient
;;;; label-based dimensionality.

(defpackage :sw4rm-orchestrator.metrics
  (:documentation
   "Production metrics collection and Prometheus export.

    Core types:
    - COUNTER: Monotonically increasing metric
    - GAUGE: Point-in-time value that can go up or down
    - HISTOGRAM: Distribution tracking with configurable buckets

    Operations:
    - MAKE-COUNTER, MAKE-GAUGE, MAKE-HISTOGRAM: Create metrics
    - INC-COUNTER: Increment counter
    - SET-GAUGE, INC-GAUGE, DEC-GAUGE: Modify gauges
    - OBSERVE-HISTOGRAM: Record histogram observation

    Export:
    - EXPORT-PROMETHEUS-FORMAT: Export all metrics in Prometheus text format

    Standard metrics:
    - INITIALIZE-STANDARD-METRICS: Create all SW4RM metrics

    Example:
      ;; Initialize standard metrics
      (initialize-standard-metrics)

      ;; Increment counter
      (inc-counter \"sw4rm_messages_total\"
                   :label-values '(:source-swarm \"leaf-a\"))

      ;; Time an operation
      (with-timing (\"sw4rm_wal_write_latency_seconds\"
                    :label-values '(:operation \"append\"))
        (wal-append wal :route data))

      ;; Export to Prometheus
      (with-output-to-string (s)
        (export-prometheus-format *default-registry* s))")
  (:use :cl)
  (:export
   ;; Core types
   #:metric
   #:counter
   #:gauge
   #:histogram
   #:metrics-registry

   ;; Registry management
   #:*default-registry*
   #:register-metric
   #:get-metric
   #:unregister-metric
   #:make-counter
   #:make-gauge
   #:make-histogram

   ;; Counter operations
   #:inc-counter

   ;; Gauge operations
   #:set-gauge
   #:inc-gauge
   #:dec-gauge

   ;; Histogram operations
   #:observe-histogram
   #:+default-histogram-buckets+

   ;; Export
   #:export-prometheus-format
   #:export-metric-prometheus

   ;; Convenience macros
   #:with-timing

   ;; Standard metrics
   #:initialize-standard-metrics))

;;;; ============================================================================
;;;; Package 9: :sw4rm-orchestrator (Main package)
;;;; ============================================================================
;;;;
;;;; Main package that re-exports the public API from subpackages.
;;;;
;;;; This is the primary entry point for users of the SDK. It re-exports
;;;; all the important symbols from the subpackages for convenience.
;;;;
;;;; Usage:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (in-package :sw4rm-orchestrator)
;;;;   (make-instance 'swarm-node :id "root")

(defpackage :sw4rm-orchestrator
  (:documentation
   "SW4RM Common Lisp Orchestrator SDK.

    Main entry point for hierarchical sw4rm orchestration.

    This package re-exports the public API from subpackages:
      :sw4rm-orchestrator.tree - SwarmTree ADT
      :sw4rm-orchestrator.envelope - Cross-swarm envelopes
      :sw4rm-orchestrator.routing - Routing algorithms
      :sw4rm-orchestrator.errors - Error handling
      :sw4rm-orchestrator.coordination - Sync primitives
      :sw4rm-orchestrator.grpc - Python bridge
      :sw4rm-orchestrator.persistence - Checkpointing

    Quick start:
      (in-package :sw4rm-orchestrator)

      ;; Create root orchestrator
      (defparameter *root* (make-instance 'swarm-node :id \"root\"))

      ;; Register Python leaves
      (register-child *root*
        (make-instance 'swarm-leaf
          :id \"frontend\"
          :host \"localhost\"
          :port 50051))

      ;; Route messages
      (route-envelope *root*
        #X{:source-swarm frontend
           :target-swarm backend
           :sender ui-agent
           :recipient api-agent
           :payload {:event \"user-login\"}})

    See documentation at:
      - ../../../COMMON_LISP_PLAN.md (architecture)
      - ../../../documentation/protocol/spec.md (protocol spec)
      - Inline docstrings in subpackages

    Version: 0.6.0
    License: Apache 2.0")
  (:use :cl :alexandria)

  ;; Re-export from errors package
  (:import-from :sw4rm-orchestrator.errors
   #:sw4rm-error
   #:swarm-unreachable
   #:swarm-disconnected
   #:routing-error
   #:envelope-error
   #:max-hops-exceeded
   #:idempotent-delivery-error)

  ;; Re-export from tree package
  (:import-from :sw4rm-orchestrator.tree
   #:swarm-tree
   #:swarm-leaf
   #:swarm-node
   #:swarm-tree-p
   #:swarm-leaf-p
   #:swarm-node-p
   #:make-swarm-leaf
   #:make-swarm-node
   #:swarm-id
   #:parent-node
   #:node-metrics
   #:node-status
   #:record-metric
   #:leaf-host
   #:leaf-port
   #:leaf-capabilities
   #:leaf-last-heartbeat
   #:leaf-scheduler
   #:leaf-router
   #:leaf-registry
   #:leaf-agents
   #:grpc-channel
   #:leaf-grpc-client
   #:node-children
   ;; Note: routing-table imported from routing package to avoid conflict
   #:node-policy
   #:route-envelope
   #:receive-envelope
   #:register-child
   #:unregister-child
   #:get-child
   #:list-children
   #:node-depth
   #:find-leaf-by-id
   #:find-ancestor-of-type
   #:subtree-nodes
   #:subtree-depth
   ;; Traversal operations
   #:node-path
   #:path-to-node
   #:common-ancestor
   #:distance-between
   #:walk-tree
   #:walk-leaves
   #:walk-nodes
   #:map-tree
   #:filter-tree
   #:dfs-traverse
   #:find-node
   #:collect-nodes
   #:bfs-traverse
   #:nodes-at-depth
   #:find-nearest
   #:tree-height
   #:tree-size
   #:leaf-count
   #:node-count
   #:tree-balanced-p
   #:prune-subtree
   #:copy-swarm-tree
   #:resolve-path
   #:node-to-path-string
   #:path-matches-p
   #:validate-tree
   #:detect-cycles
   #:find-orphans
   #:find-root)

  ;; Re-export from envelope package
  (:import-from :sw4rm-orchestrator.envelope
   #:cross-swarm-envelope
   #:make-cross-swarm-envelope
   #:copy-cross-swarm-envelope
   #:envelope-id
   #:envelope-correlation-id
   #:envelope-idempotency-token
   #:envelope-source-swarm
   #:envelope-target-swarm
   #:envelope-sender
   #:envelope-recipient
   #:envelope-payload
   #:envelope-path
   #:envelope-hop-count
   #:envelope-max-hops
   #:envelope-created-at
   #:envelope-deadline
   #:envelope-expired-p
   #:envelope-hop-limit-exceeded-p
   #:envelope-is-local-p
   #:envelope-add-to-path
   #:envelope-increment-hop-count
   #:envelope-set-deadline
   #:envelope-set_deadline
   #:envelope-remaining-ttl
   #:validate-envelope
   #:envelope-valid-for-routing-p
   #:routing-result
   #:make-routing-result
   #:routing-result-decision
   #:routing-result-target
   #:routing-result-reason
   #:routing-result-latency-ms
   #:envelope-to-json
   #:envelope-from-json
   #:json-to-envelope
   #:envelope-to-plist
   #:envelope-from-plist
   #:plist-to-envelope
   #:envelope-to-octets
   #:octets-to-envelope
   #:envelope-to-binary
   #:envelope-from-binary)

  ;; Re-export from routing package
  (:import-from :sw4rm-orchestrator.routing
   #:routing-decision
   #:routing-result
   #:routing-table
   #:make-routing-result
   #:make-routing-table
   #:routing-result-decision
   #:routing-result-target
   #:routing-result-reason
   #:routing-result-latency-ms
   #:lookup-route
   #:add-route
   #:remove-route
   #:routing-table-contains-p
   #:routing-table-local-routes
   #:routing-table-external-routes
   #:compute-routing-decision
   #:rebuild-routing-indexes
   #:compute-broadcast-targets
   #:detect-routing-loop
   #:get-alternative-routes
   #:find-shortest-path
   #:get-route-metrics
   #:find-shortest-path
   #:get-route-metrics
   #:find-shortest-path
   #:get-route-metrics
   #:find-shortest-path
   #:get-route-metrics
   #:find-shortest-path
   #:get-route-metrics
   ;; Routing strategies
   #:routing-strategy
   #:select-route
   #:strategy-name
   #:strategy-priority
   #:strategy-metrics
   #:direct-routing-strategy
   #:round-robin-strategy
   #:least-loaded-strategy
   #:latency-based-strategy
   #:weighted-random-strategy
   #:failover-strategy
   #:broadcast-strategy
   #:composite-strategy
   #:make-composite-strategy
   #:fallback-strategy
   #:make-fallback-strategy
   #:conditional-strategy
   #:make-conditional-strategy
   #:route-healthy-p
   #:mark-route-healthy
   #:mark-route-unhealthy
   #:reset-route-health
   #:record-latency
   #:set-route-weight
   #:get-route-weight
   #:make-strategy
   #:*default-routing-strategy*
   #:*registered-strategies*
   #:register-strategy
   #:get-strategy
   #:unregister-strategy
   #:with-routing-strategy
   #:get-strategy-statistics
   #:reset-strategy-statistics
   #:describe-strategy)

  ;; Re-export from coordination package
  (:import-from :sw4rm-orchestrator.coordination
   #:barrier
   #:create-barrier
   #:barrier-id
   #:barrier-participants
   #:barrier-participants-arrived
   #:barrier-arrive
   #:barrier-wait
   #:barrier-reset
   #:barrier-cancel
   #:barrier-open-p
   #:shared-artifact-registry
   #:make-registry
   #:register-artifact
   #:unregister-artifact
   #:query-artifacts
   #:get-artifact
   #:artifact-metadata
   #:artifact-updated-at
   #:distributed-lease
   #:acquire-lease
   #:release-lease
   #:extend-lease
   #:lease-held-p
   #:lease-holder
   #:lease-expiration
   #:distributed-semaphore
   #:create-semaphore
   #:semaphore-acquire
   #:semaphore-release
   #:semaphore-value)

  ;; Re-export from grpc package
  (:import-from :sw4rm-orchestrator.grpc
   #:client-swarm-id
   #:client-host
   #:client-port
   #:client-channel
   #:client-connected-p
   #:connect
   #:disconnect
   #:is-connected-p
   #:reconnect
   #:wait-for-connection
   #:with-connected-client
   #:deliver-envelope
   #:deliver-envelopes-batch
   #:register-delivery-callback
   #:delivery-acknowledgement
   #:start-grpc-server
   #:stop-grpc-server
   #:grpc-server-address
   #:grpc-server-running-p
   #:register-routing-handler
   #:register-leaf-status-handler
   #:register-heartbeat-handler
   #:envelope-to-proto
   #:proto-to-envelope
   #:payload-to-json
   #:payload-from-json
   #:heartbeat-to-proto
   #:proto-to-heartbeat
   #:start-heartbeat-stream
   #:stop-heartbeat-stream
   #:heartbeat-stream-active-p)

  ;; Re-export from persistence package
  (:import-from :sw4rm-orchestrator.persistence
   #:capture-orchestrator-state
   #:orchestrator-state
   #:orchestrator-state-tree
   #:orchestrator-state-routing-tables
   #:orchestrator-state-connections
   #:orchestrator-state-timestamp
   #:orchestrator-state-version
   #:save-orchestrator-checkpoint
   #:restore-from-checkpoint
   #:restore-orchestrator-state
   #:checkpoint-file-valid-p
   #:checkpoint-version
   #:checkpoint-timestamp
   #:enable-wal
   #:disable-wal
   #:wal-enabled-p
   #:flush-wal
   ;; WAL types and accessors
   #:wal-log
   #:make-wal-log
   #:wal-entry
   #:make-wal-entry
   #:wal-entry-sequence
   #:wal-entry-timestamp
   #:wal-entry-operation
   #:wal-entry-data
   #:wal-entry-checksum
   #:wal-entry-swarm-id
   ;; WAL operations
   #:wal-append
   #:wal-flush
   #:wal-close
   #:wal-replay
   #:wal-entries
   #:wal-truncate
   #:wal-compact
   #:wal-rotate
   #:wal-size
   #:wal-last-sequence
   #:wal-get-stats
   ;; WAL configuration
   #:*wal-sync-mode*
   ;; WAL sharding (P2-3/P3-10)
   #:wal-sharding-enabled
   #:compute-shard-index
   #:total-shard-entries
   ;; CRC32 utilities
   #:crc32
   ;; Snapshots
   #:create-snapshot
   #:list-snapshots
   #:delete-snapshot
   #:diff-snapshots
   #:snapshot-info
   #:snapshot-size
   #:set-checkpoint-interval
   #:set-checkpoint-path
   #:set-compression
   #:set-max-wal-size
   #:automatic-checkpoint-enabled-p
   #:trigger-checkpoint
   #:verify-checkpoint-integrity)

  ;; Export convenience functions from main module
  (:export
   ;; Core types (re-exported from subpackages)
   #:swarm-tree
   #:swarm-leaf
   #:swarm-node
   #:swarm-tree-p
   #:swarm-leaf-p
   #:swarm-node-p
   #:make-swarm-leaf
   #:make-swarm-node
   #:cross-swarm-envelope
   #:routing-result
   #:routing-table
   #:barrier
   #:shared-artifact-registry
   #:distributed-lease
   #:distributed-semaphore
   #:leaf-grpc-client
   #:orchestrator-state
   #:orchestrator-state-tree
   #:orchestrator-state-routing-tables
   #:orchestrator-state-connections
   #:orchestrator-state-timestamp
   #:orchestrator-state-version

   ;; Tree operations
   #:swarm-id
   #:parent-node
   #:node-metrics
   #:node-status
   #:record-metric
   #:leaf-host
   #:leaf-port
   #:leaf-capabilities
   #:leaf-last-heartbeat
   #:leaf-scheduler
   #:leaf-router
   #:leaf-registry
   #:leaf-agents
   #:grpc-channel
   #:node-children
   #:routing-table
   #:node-policy
   #:route-envelope
   #:receive-envelope
   #:register-child
   #:unregister-child
   #:get-child
   #:list-children
   #:node-depth
   #:find-leaf-by-id
   #:find-ancestor-of-type
   #:subtree-nodes
   #:subtree-depth
   ;; Tree traversal operations
   #:node-path
   #:path-to-node
   #:common-ancestor
   #:distance-between
   #:walk-tree
   #:walk-leaves
   #:walk-nodes
   #:map-tree
   #:filter-tree
   #:dfs-traverse
   #:find-node
   #:collect-nodes
   #:bfs-traverse
   #:nodes-at-depth
   #:find-nearest
   #:tree-height
   #:tree-size
   #:leaf-count
   #:node-count
   #:tree-balanced-p
   #:prune-subtree
   #:copy-swarm-tree
   #:resolve-path
   #:node-to-path-string
   #:path-matches-p
   #:validate-tree
   #:detect-cycles
   #:find-orphans
   #:find-root

   ;; Envelope operations
   #:make-cross-swarm-envelope
   #:copy-cross-swarm-envelope
   #:envelope-id
   #:envelope-correlation-id
   #:envelope-idempotency-token
   #:envelope-source-swarm
   #:envelope-target-swarm
   #:envelope-sender
   #:envelope-recipient
   #:envelope-payload
   #:envelope-path
   #:envelope-hop-count
   #:envelope-max-hops
   #:envelope-created-at
   #:envelope-deadline
   #:envelope-expired-p
   #:envelope-hop-limit-exceeded-p
   #:envelope-is-local-p
   #:envelope-add-to-path
   #:envelope-increment-hop-count
   #:envelope-set-deadline
   #:envelope-set_deadline
   #:envelope-remaining-ttl
   #:validate-envelope
   #:envelope-valid-for-routing-p
   #:routing-result-latency-ms
   #:envelope-to-json
   #:envelope-from-json
   #:json-to-envelope
   #:envelope-to-plist
   #:envelope-from-plist
   #:plist-to-envelope
   #:envelope-to-octets
   #:octets-to-envelope
   #:envelope-to-binary
   #:envelope-from-binary

   ;; Routing operations
   #:make-routing-result
   #:make-routing-table
   #:routing-result-decision
   #:routing-result-target
   #:routing-result-reason
   #:lookup-route
   #:add-route
   #:remove-route
   #:routing-table-contains-p
   #:routing-table-local-routes
   #:routing-table-external-routes
   #:compute-routing-decision
   #:rebuild-routing-indexes
   #:compute-broadcast-targets
   #:detect-routing-loop
   #:get-alternative-routes
   #:find-shortest-path
   #:get-route-metrics

   ;; Routing strategies
   #:routing-strategy
   #:select-route
   #:strategy-name
   #:strategy-priority
   #:strategy-metrics
   #:direct-routing-strategy
   #:round-robin-strategy
   #:least-loaded-strategy
   #:latency-based-strategy
   #:weighted-random-strategy
   #:failover-strategy
   #:broadcast-strategy
   #:composite-strategy
   #:make-composite-strategy
   #:fallback-strategy
   #:make-fallback-strategy
   #:conditional-strategy
   #:make-conditional-strategy
   #:route-healthy-p
   #:mark-route-healthy
   #:mark-route-unhealthy
   #:reset-route-health
   #:record-latency
   #:set-route-weight
   #:get-route-weight
   #:make-strategy
   #:*default-routing-strategy*
   #:*registered-strategies*
   #:register-strategy
   #:get-strategy
   #:unregister-strategy
   #:with-routing-strategy
   #:get-strategy-statistics
   #:reset-strategy-statistics
   #:describe-strategy

   ;; Error conditions
   #:sw4rm-error
   #:swarm-unreachable
   #:swarm-disconnected
   #:routing-error
   #:envelope-error
   #:max-hops-exceeded
   #:idempotent-delivery-error

   ;; Coordination operations
   #:create-barrier
   #:barrier-id
   #:barrier-participants
   #:barrier-participants-arrived
   #:barrier-arrive
   #:barrier-wait
   #:barrier-reset
   #:barrier-cancel
   #:barrier-open-p
   #:make-registry
   #:register-artifact
   #:unregister-artifact
   #:query-artifacts
   #:get-artifact
   #:acquire-lease
   #:release-lease
   #:extend-lease
   #:lease-held-p
   #:create-semaphore
   #:semaphore-acquire
   #:semaphore-release

   ;; gRPC operations
   #:connect
   #:disconnect
   #:is-connected-p
   #:reconnect
   #:wait-for-connection
   #:with-connected-client
   #:deliver-envelope
   #:deliver-envelopes-batch
   #:start-grpc-server
   #:stop-grpc-server
   #:grpc-server-running-p
   #:register-routing-handler
   #:register-leaf-status-handler
   #:register-heartbeat-handler

   ;; Health status and degraded mode (from main.lisp)
   #:*grpc-degraded-mode*
   #:grpc-degraded-mode-p
   #:get-health-status
   #:health-status-string

   ;; Persistence operations
   #:capture-orchestrator-state
   #:save-orchestrator-checkpoint
   #:restore-from-checkpoint
   #:restore-orchestrator-state
   #:checkpoint-file-valid-p
   #:enable-wal
   #:disable-wal
   #:wal-enabled-p
   #:flush-wal
   ;; WAL types and accessors
   #:wal-log
   #:make-wal-log
   #:wal-entry
   #:make-wal-entry
   #:wal-entry-sequence
   #:wal-entry-timestamp
   #:wal-entry-operation
   #:wal-entry-data
   #:wal-entry-checksum
   ;; WAL operations
   #:wal-append
   #:wal-flush
   #:wal-close
   #:wal-replay
   #:wal-entries
   #:wal-truncate
   #:wal-compact
   #:wal-rotate
   #:wal-size
   #:wal-last-sequence
   #:wal-get-stats
   ;; WAL configuration
   #:*wal-sync-mode*
   ;; CRC32 utilities
   #:crc32
   ;; Snapshots
   #:create-snapshot
   #:list-snapshots
   #:delete-snapshot
   #:diff-snapshots
   #:set-checkpoint-interval
   #:set-checkpoint-path
   #:set-compression
   #:automatic-checkpoint-enabled-p
   #:trigger-checkpoint
   #:verify-checkpoint-integrity))


;;;; ============================================================================
;;;; Internal implementation packages (not exported to users)
;;;; ============================================================================

(defpackage :sw4rm-orchestrator.utils
  (:documentation "Internal utility functions for orchestrator.")
  (:use :cl))

(defpackage :sw4rm-orchestrator.metrics
  (:documentation "Internal metrics collection and tracking.")
  (:use :cl))

(defpackage :sw4rm-orchestrator.logging
  (:documentation "Internal logging and tracing infrastructure.")
  (:use :cl))

;;;; ============================================================================
;;;; Test package
;;;; ============================================================================

(defpackage :sw4rm-orchestrator.test
  (:documentation "Test suite for SW4RM orchestrator.")
  (:use :cl :fiveam)
  (:export
   #:run-all-tests
   #:run-tree-tests
   #:run-routing-tests
   #:run-envelope-tests
   #:run-integration-tests))

;;;; End of file
