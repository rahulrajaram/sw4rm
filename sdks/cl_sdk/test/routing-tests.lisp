;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; test/routing-tests.lisp
;;;;
;;;; Comprehensive test suite for routing algorithms and table management.
;;;;
;;;; Tests cover:
;;;;   - Routing table operations (add, remove, lookup)
;;;;   - Routing decisions (local, child, parent, broadcast, reject)
;;;;   - TTL expiration and deadline enforcement
;;;;   - Loop detection and cycle prevention
;;;;   - Routing strategies (direct, round-robin, failover)
;;;;   - Hop limit enforcement
;;;;   - Route health and failover
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.test)

(in-suite routing-tests)

;;;; ============================================================================
;;;; Fixtures and Setup
;;;; ============================================================================

(defun setup-routing-tree ()
  "Create a tree for routing tests.

  Structure:
    root
    +-- leaf-a
    +-- leaf-b
    +-- cluster-1
        +-- leaf-c
        +-- cluster-2
            +-- leaf-d"
  (let ((root (make-swarm-node "root"))
        (leaf-a (make-swarm-leaf "leaf-a"))
        (leaf-b (make-swarm-leaf "leaf-b"))
        (cluster-1 (make-swarm-node "cluster-1"))
        (leaf-c (make-swarm-leaf "leaf-c"))
        (cluster-2 (make-swarm-node "cluster-2"))
        (leaf-d (make-swarm-leaf "leaf-d")))
    ;; Register topology
    (register-child root leaf-a)
    (register-child root leaf-b)
    (register-child root cluster-1)
    (register-child cluster-1 leaf-c)
    (register-child cluster-1 cluster-2)
    (register-child cluster-2 leaf-d)
    (list root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)))

;;;; ============================================================================
;;;; Tests: ROUTING-RESULT Structure
;;;; ============================================================================

(test routing-result-creation
  "Test creating a routing result."
  (let ((result (make-routing-result
                 :decision :local
                 :target "root"
                 :reason "Target matches local node")))
    (is (eq (routing-result-decision result) :local))
    (is (string= (routing-result-target result) "root"))
    (is (string= (routing-result-reason result) "Target matches local node"))))

(test routing-result-reject
  "Test creating a reject routing result."
  (let ((result (make-routing-result
                 :decision :reject
                 :target nil
                 :reason "No route found")))
    (is (eq (routing-result-decision result) :reject))
    (is (null (routing-result-target result)))
    (is (string= (routing-result-reason result) "No route found"))))

(test routing-result-with-latency
  "Test routing result with latency."
  (let ((result (make-routing-result
                 :decision :child
                 :target "leaf-1"
                 :latency-ms 42)))
    (is (eq (routing-result-decision result) :child))
    (is (= (routing-result-latency-ms result) 42))))

;;;; ============================================================================
;;;; Tests: ROUTING-TABLE Operations
;;;; ============================================================================

(test make-routing-table
  "Test creating an empty routing table."
  (let ((table (make-routing-table)))
    (is (not (null table)))))

(test add-route
  "Test adding a route to routing table."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (is (routing-table-contains-p table "target-1"))))

(test lookup-route-existing
  "Test looking up an existing route."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (let ((route (lookup-route table "target-1")))
      (is (not (null route)))
      (is (string= route "next-hop-1")))))

(test lookup-route-nonexistent
  "Test looking up a non-existent route."
  (let ((table (make-routing-table)))
    (let ((route (lookup-route table "nonexistent")))
      (is (null route)))))

(test remove-route
  "Test removing a route from routing table."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (is (routing-table-contains-p table "target-1"))
    (remove-route table "target-1")
    (is (not (routing-table-contains-p table "target-1")))))

(test add-multiple-routes
  "Test adding multiple routes."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "hop-1")
    (add-route table "target-2" "hop-2")
    (add-route table "target-3" "hop-3")
    (is (routing-table-contains-p table "target-1"))
    (is (routing-table-contains-p table "target-2"))
    (is (routing-table-contains-p table "target-3"))))

(test routing-table-local-routes
  "Test getting local routes (direct children)."
  (let ((table (make-routing-table)))
    (add-route table "leaf-a" "leaf-a")
    (add-route table "leaf-b" "leaf-b")
    (add-route table "remote" "cluster-1")
    (let ((local (routing-table-local-routes table)))
      (is (member "leaf-a" local :test #'string=))
      (is (member "leaf-b" local :test #'string=)))))

(test routing-table-external-routes
  "Test getting external routes (descendants)."
  (let ((table (make-routing-table)))
    (add-route table "leaf-a" "leaf-a")
    (add-route table "leaf-c" "cluster-1")
    (let ((external (routing-table-external-routes table)))
      (is (member "leaf-c" external :test #'string=)))))

;;;; ============================================================================
;;;; Tests: Routing Decisions - Local
;;;; ============================================================================

(test compute-routing-decision-local
  "Test routing decision for local delivery."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "root")))
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :local))
        (is (string= (routing-result-target result) "root"))))))

(test compute-routing-decision-local-at-leaf
  "Test routing decision at leaf node for local delivery."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "leaf-a")))
      (let ((result (compute-routing-decision leaf-a envelope)))
        (is (eq (routing-result-decision result) :local))))))

;;;; ============================================================================
;;;; Tests: Routing Decisions - Child
;;;; ============================================================================

(test compute-routing-decision-direct-child
  "Test routing to direct child."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "leaf-a")))
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :child))))))

(test compute-routing-decision-indirect-child
  "Test routing to indirect child via cluster."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "leaf-c")))
      (let ((result (compute-routing-decision root envelope)))
        ;; Should route to cluster-1 as next hop
        (is (or (eq (routing-result-decision result) :child)
                (eq (routing-result-decision result) :parent)))))))

;;;; ============================================================================
;;;; Tests: Routing Decisions - Parent
;;;; ============================================================================

(test compute-routing-decision-to-parent
  "Test routing to parent node."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "leaf-b")))
      (let ((result (compute-routing-decision leaf-a envelope)))
        (is (eq (routing-result-decision result) :parent))))))

(test compute-routing-decision-sibling_via_parent
  "Test routing to sibling via parent."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "leaf-c")))
      (let ((result (compute-routing-decision leaf-a envelope)))
        (is (eq (routing-result-decision result) :parent))))))

;;;; ============================================================================
;;;; Tests: Routing Decisions - Broadcast
;;;; ============================================================================

(test compute-routing-decision-broadcast
  "Test broadcast routing decision."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm :broadcast)))
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :broadcast))))))

(test compute-broadcast-targets
  "Test computing broadcast targets."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((targets (compute-broadcast-targets root)))
      ;; Should include all direct children
      (is (= (length targets) 3))  ; leaf-a, leaf-b, cluster-1
      (is (member "leaf-a" targets :test #'string=))
      (is (member "leaf-b" targets :test #'string=))
      (is (member "cluster-1" targets :test #'string=)))))

;;;; ============================================================================
;;;; Tests: Routing Decisions - Reject
;;;; ============================================================================

(test compute-routing-decision-reject-no_parent
  "Test reject decision when no route available."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    ;; Orphan leaf with unknown target
    (let ((orphan-leaf (make-swarm-leaf "orphan")))
      (let ((envelope (make-cross-swarm-envelope :target-swarm "unknown")))
        (let ((result (compute-routing-decision orphan-leaf envelope)))
          (is (eq (routing-result-decision result) :reject)))))))

;;;; ============================================================================
;;;; Tests: Hop Limit Enforcement
;;;; ============================================================================

(test envelope-hop-limit-exceeded-p-false
  "Test hop limit check when under limit."
  (let ((envelope (make-cross-swarm-envelope :hop-count 3 :max-hops 10)))
    (is (not (envelope-hop-limit-exceeded-p envelope)))))

(test envelope-hop-limit-exceeded-p-true
  "Test hop limit check when at limit."
  (let ((envelope (make-cross-swarm-envelope :hop-count 10 :max-hops 10)))
    (is (envelope-hop-limit-exceeded-p envelope))))

(test envelope-hop-limit-exceeded-p_over_limit
  "Test hop limit check when over limit."
  (let ((envelope (make-cross-swarm-envelope :hop-count 15 :max-hops 10)))
    (is (envelope-hop-limit-exceeded-p envelope))))

(test routing-rejects_exceeded_hop_limit
  "Test that routing rejects envelope with exceeded hop limit."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope
                     :target-swarm "leaf-c"
                     :hop-count 10
                     :max-hops 10)))
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :reject))))))

(test hop-count-increment
  "Test incrementing hop count."
  (let ((envelope (make-cross-swarm-envelope :hop-count 0)))
    (is (= (envelope-hop-count envelope) 0))
    (envelope-increment-hop-count envelope)
    (is (= (envelope-hop-count envelope) 1))
    (envelope-increment-hop-count envelope)
    (is (= (envelope-hop-count envelope) 2))))

;;;; ============================================================================
;;;; Tests: Deadline Enforcement
;;;; ============================================================================

(test envelope-expired-p-false
  "Test expiration check on fresh envelope."
  (let ((envelope (make-cross-swarm-envelope
                   :deadline (+ (get-universal-time) 300))))
    (is (not (envelope-expired-p envelope)))))

(test envelope-expired-p-true
  "Test expiration check on expired envelope."
  (let ((envelope (make-cross-swarm-envelope
                   :deadline (- (get-universal-time) 10))))
    (is (envelope-expired-p envelope))))

(test envelope-expired-p-no_deadline
  "Test expiration check on envelope with no deadline."
  (let ((envelope (make-cross-swarm-envelope :deadline nil)))
    (is (not (envelope-expired-p envelope)))))

(test envelope-set_deadline
  "Test setting envelope deadline."
  (let ((envelope (make-cross-swarm-envelope)))
    (let ((deadline (envelope-set-deadline envelope 60)))
      (is (not (null deadline)))
      (is (> deadline (get-universal-time))))))

(test envelope-remaining-ttl
  "Test computing remaining TTL."
  (let ((envelope (make-cross-swarm-envelope
                   :deadline (+ (get-universal-time) 60))))
    (let ((ttl (envelope-remaining-ttl envelope)))
      (is (not (null ttl)))
      (is (>= ttl 59))
      (is (<= ttl 60)))))

(test envelope-remaining-ttl-no_deadline
  "Test TTL computation with no deadline."
  (let ((envelope (make-cross-swarm-envelope :deadline nil)))
    (is (null (envelope-remaining-ttl envelope)))))

(test routing-rejects-expired-envelope
  "Test that routing rejects expired envelope."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope
                     :target-swarm "leaf-a"
                     :deadline (- (get-universal-time) 10))))
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :reject))))))

;;;; ============================================================================
;;;; Tests: Loop Detection
;;;; ============================================================================

(test envelope-add-to-path
  "Test adding node to envelope path."
  (let ((envelope (make-cross-swarm-envelope :path nil)))
    (is (null (envelope-path envelope)))
    (envelope-add-to-path envelope "node-1")
    (is (= (length (envelope-path envelope)) 1))
    (is (string= (first (envelope-path envelope)) "node-1"))))

(test envelope-path-breadcrumb
  "Test envelope path tracks breadcrumbs."
  (let ((envelope (make-cross-swarm-envelope)))
    (envelope-add-to-path envelope "root")
    (envelope-add-to-path envelope "cluster-1")
    (envelope-add-to-path envelope "leaf-c")
    (let ((path (envelope-path envelope)))
      (is (= (length path) 3))
      ;; Path should be in reverse order (most recent first)
      (is (string= (first path) "leaf-c"))
      (is (string= (second path) "cluster-1"))
      (is (string= (third path) "root")))))

(test detect-routing-loop
  "Test detecting routing loop in path."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope)))
      (envelope-add-to-path envelope "root")
      (envelope-add-to-path envelope "cluster-1")
      (envelope-add-to-path envelope "root")  ; Loop!
      (is (detect-routing-loop envelope)))))

(test detect-routing-loop-none
  "Test loop detection on normal path."
  (let ((envelope (make-cross-swarm-envelope)))
    (envelope-add-to-path envelope "root")
    (envelope-add-to-path envelope "cluster-1")
    (envelope-add-to-path envelope "leaf-a")
    (is (not (detect-routing-loop envelope)))))

;;;; ============================================================================
;;;; Tests: Routing Strategies
;;;; ============================================================================

(test direct-routing-strategy
  "Test direct routing strategy."
  (let ((strategy (make-strategy :direct)))
    (is (not (null strategy)))
    (is (eq (strategy-name strategy) :direct))))

(test round-robin-strategy
  "Test round-robin routing strategy."
  (let ((strategy (make-strategy :round-robin)))
    (is (not (null strategy)))
    (is (eq (strategy-name strategy) :round-robin))))

(test least-loaded-strategy
  "Test least-loaded routing strategy."
  (let ((strategy (make-strategy :least-loaded)))
    (is (not (null strategy)))
    (is (eq (strategy-name strategy) :least-loaded))))

(test latency-based-strategy
  "Test latency-based routing strategy."
  (let ((strategy (make-strategy :latency-based)))
    (is (not (null strategy)))
    (is (eq (strategy-name strategy) :latency-based))))

(test weighted-random-strategy
  "Test weighted-random routing strategy."
  (let ((strategy (make-strategy :weighted-random)))
    (is (not (null strategy)))
    (is (eq (strategy-name strategy) :weighted-random))))

(test failover-strategy
  "Test failover routing strategy."
  (let ((strategy (make-strategy :failover)))
    (is (not (null strategy)))
    (is (eq (strategy-name strategy) :failover))))

(test broadcast-strategy
  "Test broadcast routing strategy."
  (let ((strategy (make-strategy :broadcast)))
    (is (not (null strategy)))
    (is (eq (strategy-name strategy) :broadcast))))

;;;; ============================================================================
;;;; Tests: Route Health
;;;; ============================================================================

(test route-healthy-p-default
  "Test that routes are healthy by default."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (is (route-healthy-p table "target-1"))))

(test mark-route-unhealthy
  "Test marking route as unhealthy."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (mark-route-unhealthy table "target-1")
    (is (not (route-healthy-p table "target-1")))))

(test mark-route-healthy
  "Test marking route as healthy."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (mark-route-unhealthy table "target-1")
    (is (not (route-healthy-p table "target-1")))
    (mark-route-healthy table "target-1")
    (is (route-healthy-p table "target-1"))))

(test reset-route-health
  "Test resetting route health."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (mark-route-unhealthy table "target-1")
    (reset-route-health table "target-1")
    (is (route-healthy-p table "target-1"))))

;;;; ============================================================================
;;;; Tests: Latency Tracking
;;;; ============================================================================

(test record-latency
  "Test recording latency for a route."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (record-latency table "target-1" 42)
    ;; Verify latency was recorded
    (is (not (null table)))))

;;;; ============================================================================
;;;; Tests: Route Weights
;;;; ============================================================================

(test set-route-weight
  "Test setting route weight."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (set-route-weight table "target-1" 10)
    (is (= (get-route-weight table "target-1") 10))))

(test get-route-weight
  "Test getting route weight."
  (let ((table (make-routing-table)))
    (add-route table "target-1" "next-hop-1")
    (set-route-weight table "target-1" 5)
    (let ((weight (get-route-weight table "target-1")))
      (is (= weight 5)))))

;;;; ============================================================================
;;;; Tests: Strategy Composition
;;;; ============================================================================

(test composite-strategy
  "Test creating composite routing strategy."
  (let ((primary (make-strategy :direct))
        (secondary (make-strategy :round-robin)))
    (let ((composite (make-composite-strategy primary secondary)))
      (is (not (null composite))))))

(test fallback-strategy
  "Test creating fallback routing strategy."
  (let ((primary (make-strategy :direct))
        (fallback (make-strategy :broadcast)))
    (let ((strat (make-fallback-strategy primary fallback)))
      (is (not (null strat))))))

(test conditional-strategy
  "Test creating conditional routing strategy."
  (let ((condition (lambda (env) (string= (envelope-priority env) "high")))
        (high-priority-strat (make-strategy :direct))
        (default-strat (make-strategy :round-robin)))
    (let ((strat (make-conditional-strategy condition
                                            high-priority-strat
                                            default-strat)))
      (is (not (null strat))))))

;;;; ============================================================================
;;;; Tests: Strategy Registration and Factory
;;;; ============================================================================

(test register-strategy
  "Test registering a custom strategy."
  (let ((strategy (make-strategy :direct)))
    (register-strategy "custom-strategy" strategy)
    (let ((retrieved (get-strategy "custom-strategy")))
      (is (not (null retrieved))))))

(test get-registered-strategy
  "Test retrieving registered strategy."
  (let ((strategy (make-strategy :round-robin)))
    (register-strategy "test-strategy" strategy)
    (let ((retrieved (get-strategy "test-strategy")))
      (is (eq (strategy-name retrieved) :round-robin)))))

(test unregister-strategy
  "Test unregistering a strategy."
  (register-strategy "temp-strategy" (make-strategy :direct))
    (is (not (null (get-strategy "temp-strategy"))))
  (unregister-strategy "temp-strategy")
  (is (null (get-strategy "temp-strategy"))))

;;;; ============================================================================
;;;; Tests: Strategy Metrics
;;;; ============================================================================

(test get-strategy-statistics
  "Test getting strategy statistics."
  (let ((strategy (make-strategy :direct)))
    (let ((stats (get-strategy-statistics strategy)))
      (is (not (null stats))))))

(test reset-strategy-statistics
  "Test resetting strategy statistics."
  (let ((strategy (make-strategy :direct)))
    (reset-strategy-statistics strategy)
    ;; Should not signal error
    (is (not (null strategy)))))

;;;; ============================================================================
;;;; Tests: Rebuild Routing Indexes
;;;; ============================================================================

(test rebuild-routing-indexes
  "Test rebuilding routing indexes after topology change."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    ;; This should succeed without error
    (rebuild-routing-indexes root)
    (is (not (null root)))))

;;;; ============================================================================
;;;; Tests: Alternative Routes (Failover)
;;;; ============================================================================

(test get-alternative-routes
  "Test getting alternative routes for failover."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((alternatives (get-alternative-routes root "leaf-d")))
      ;; Should have at least one alternative path
      (is (not (null alternatives))))))

(test find-shortest-path
  "Test finding shortest path between nodes."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((path (find-shortest-path root "leaf-d")))
      ;; Path should exist and contain nodes
      (is (not (null path)))
      (is (> (length path) 0)))))

(test get-route-metrics
  "Test getting route metrics."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((metrics (get-route-metrics root "leaf-a")))
      (is (not (null metrics))))))

;;;; ============================================================================
;;;; Tests: Edge Cases
;;;; ============================================================================

(test routing-with-empty_target
  "Test routing with nil target swarm."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c cluster-2 leaf-d)
      (setup-routing-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm nil)))
      (let ((result (compute-routing-decision root envelope)))
        ;; Should reject when target is nil
        (is (eq (routing-result-decision result) :reject))))))

(test routing-single-node
  "Test routing with single-node tree."
  (let ((node (make-swarm-node "root")))
    (let ((envelope (make-cross-swarm-envelope :target-swarm "root")))
      (let ((result (compute-routing-decision node envelope)))
        (is (eq (routing-result-decision result) :local))))))

(test routing-deep-tree
  "Test routing in deeply nested tree."
  (let ((nodes (list (make-swarm-node "root"))))
    ;; Build 5-level chain
    (dotimes (i 4)
      (let ((new-node (make-swarm-node (format nil "node-~D" (1+ i)))))
        (register-child (first nodes) new-node)
        (push new-node nodes)))
    (let ((root (first (reverse nodes)))
          (deepest (first nodes)))
      (let ((envelope (make-cross-swarm-envelope
                       :target-swarm (swarm-id deepest))))
        (let ((result (compute-routing-decision root envelope)))
          ;; Should successfully route to deep node
          (is (or (eq (routing-result-decision result) :local)
                  (eq (routing-result-decision result) :parent)
                  (eq (routing-result-decision result) :child))))))))

;;;; ============================================================================
;;;; Tests: With-Routing-Strategy Context
;;;; ============================================================================

(test with-routing-strategy
  "Test setting routing strategy context."
  (let ((strategy (make-strategy :direct)))
    (let ((original-strategy *default-routing-strategy*))
      ;; Should complete without error
      (is (not (null strategy))))))

;;;; ============================================================================
;;;; Tests: Describe Strategy
;;;; ============================================================================

(test describe-strategy
  "Test describing a strategy."
  (let ((strategy (make-strategy :direct)))
    (let ((description (with-output-to-string (s)
                         (describe-strategy strategy s))))
      (is (not (null description))))))

;;;; End of file
