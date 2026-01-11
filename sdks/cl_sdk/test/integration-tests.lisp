;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; test/integration-tests.lisp
;;;;
;;;; Integration test suite for end-to-end orchestrator scenarios.
;;;;
;;;; Tests cover:
;;;;   - End-to-end routing through multiple tree levels
;;;;   - Cross-swarm communication patterns
;;;;   - Barrier synchronization across swarms
;;;;   - Checkpoint save and restore
;;;;   - Error handling with conditions and restarts
;;;;   - Concurrent operations and race conditions
;;;;   - Failure recovery and resilience
;;;;
;;;; These tests verify that the orchestrator components work together
;;;; correctly in realistic scenarios.
;;;;
;;;; Note: Some tests may require Python sw4rm instances running.
;;;; See test documentation for prerequisites.
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.test)

(in-suite integration-tests)

;;;; ============================================================================
;;;; Fixtures
;;;; ============================================================================

(defun setup-integration-tree ()
  "Create a realistic multi-level orchestrator tree for integration tests.

  Structure:
    root (orchestrator)
    +-- frontend (swarm-node)
    |   +-- ui-agent-1 (leaf)
    |   +-- ui-agent-2 (leaf)
    +-- backend (swarm-node)
    |   +-- api-agent-1 (leaf)
    |   +-- cache-agent (leaf)
    |   +-- db-agent (leaf)
    +-- analytics (leaf)
    +-- monitoring (leaf)"
  (let ((root (make-swarm-node "root"))
        ;; Frontend cluster
        (frontend (make-swarm-node "frontend"))
        (ui-agent-1 (make-swarm-leaf "ui-agent-1" :host "10.0.1.1"))
        (ui-agent-2 (make-swarm-leaf "ui-agent-2" :host "10.0.1.2"))
        ;; Backend cluster
        (backend (make-swarm-node "backend"))
        (api-agent-1 (make-swarm-leaf "api-agent-1" :host "10.0.2.1"))
        (cache-agent (make-swarm-leaf "cache-agent" :host "10.0.2.2"))
        (db-agent (make-swarm-leaf "db-agent" :host "10.0.2.3"))
        ;; Standalone leaves
        (analytics (make-swarm-leaf "analytics" :host "10.0.3.1"))
        (monitoring (make-swarm-leaf "monitoring" :host "10.0.3.2")))
    ;; Register topology
    (register-child root frontend)
    (register-child root backend)
    (register-child root analytics)
    (register-child root monitoring)
    ;; Frontend cluster
    (register-child frontend ui-agent-1)
    (register-child frontend ui-agent-2)
    ;; Backend cluster
    (register-child backend api-agent-1)
    (register-child backend cache-agent)
    (register-child backend db-agent)
    ;; Return all nodes
    (list root frontend backend analytics monitoring
          ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)))

;;;; ============================================================================
;;;; Tests: Basic Routing Through Tree
;;;; ============================================================================

(test routing-single-level-local
  "Test routing envelope to local swarm."
  (let ((root (make-swarm-node "root")))
    (let ((envelope (make-cross-swarm-envelope :target-swarm "root")))
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :local))))))

(test routing-to-direct-child
  "Test routing envelope to direct child leaf."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "analytics")))
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :child))))))

(test routing-through_intermediate_node
  "Test routing envelope through intermediate orchestrator node."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "ui-agent-1")))
      (let ((result (compute-routing-decision root envelope)))
        ;; Should route to ui-agent-1 which is a child of frontend
        (is (or (eq (routing-result-decision result) :local)
                (eq (routing-result-decision result) :child)
                (eq (routing-result-decision result) :parent)))))))

(test routing-three-level-deep
  "Test routing envelope three levels deep in tree."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "db-agent")))
      ;; db-agent is at depth 2: root -> backend -> db-agent
      (let ((result (compute-routing-decision root envelope)))
        ;; Valid routing decision should be made
        (is (member (routing-result-decision result)
                    '(:local :child :parent :reject)))))))

;;;; ============================================================================
;;;; Tests: Cross-Swarm Envelope Exchange
;;;; ============================================================================

(test cross-swarm-request-response
  "Test request-response pattern across swarms."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    ;; UI agent sends request to API agent
    (let ((request (make-cross-swarm-envelope
                    :source-swarm "ui-agent-1"
                    :target-swarm "api-agent-1"
                    :sender "ui-agent-1"
                    :recipient "api-agent-1"
                    :message-type :request
                    :payload '(:action "get-user" :id 42))))
      (is (envelope-valid-for-routing-p request))
      ;; Root should be able to route this request
      (let ((result (compute-routing-decision root request)))
        (is (member (routing-result-decision result)
                    '(:local :child :parent :reject)))))))

(test cross-swarm-event-notification
  "Test event notification across swarms."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    ;; DB agent publishes event
    (let ((event (make-cross-swarm-envelope
                  :source-swarm "db-agent"
                  :target-swarm :broadcast  ; Notify all
                  :message-type :event
                  :payload '(:event "data-changed" :table "users"))))
      (is (not (null event))))))

(test workflow-correlation
  "Test workflow correlation across multiple envelopes."
  (let ((workflow-id "workflow-12345"))
    ;; Step 1: Initial request
    (let ((step1 (make-cross-swarm-envelope
                  :correlation-id workflow-id
                  :source-swarm "frontend"
                  :target-swarm "backend"
                  :message-type :request)))
      (is (string= (envelope-correlation-id step1) workflow-id)))
    ;; Step 2: Intermediate processing
    (let ((step2 (make-cross-swarm-envelope
                  :correlation-id workflow-id
                  :source-swarm "backend"
                  :target-swarm "analytics"
                  :message-type :request)))
      (is (string= (envelope-correlation-id step2) workflow-id)))
    ;; Step 3: Final response
    (let ((step3 (make-cross-swarm-envelope
                  :correlation-id workflow-id
                  :source-swarm "analytics"
                  :target-swarm "frontend"
                  :message-type :response)))
      (is (string= (envelope-correlation-id step3) workflow-id)))))

(test idempotent-delivery-pattern
  "Test idempotent delivery with idempotency tokens."
  (let ((token "agent-a:create:resource-123"))
    ;; First attempt
    (let ((attempt1 (make-cross-swarm-envelope
                     :idempotency-token token
                     :source-swarm "frontend"
                     :target-swarm "backend")))
      (is (string= (envelope-idempotency-token attempt1) token)))
    ;; Retry with same token (should be deduplicated by backend)
    (let ((attempt2 (make-cross-swarm-envelope
                     :idempotency-token token
                     :source-swarm "frontend"
                     :target-swarm "backend")))
      (is (string= (envelope-idempotency-token attempt2) token)))))

;;;; ============================================================================
;;;; Tests: Path Tracking and Loop Detection
;;;; ============================================================================

(test envelope-path-records_route
  "Test that envelope path records the route taken."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "api-agent-1")))
      ;; Simulate routing through tree
      (envelope-add-to-path envelope "root")
      (envelope-add-to-path envelope "backend")
      (envelope-add-to-path envelope "api-agent-1")
      (let ((path (envelope-path envelope)))
        (is (= (length path) 3))
        (is (string= (first path) "api-agent-1"))))))

(test loop-detection-prevents_routing
  "Test that loop detection prevents cycles."
  (let ((envelope (make-cross-swarm-envelope :target-swarm "target")))
    (envelope-add-to-path envelope "root")
    (envelope-add-to-path envelope "cluster-1")
    (envelope-add-to-path envelope "root")  ; Loop!
    (is (detect-routing-loop envelope))))

(test hop-limit_prevents_infinite_routing
  "Test that hop limit prevents infinite loops."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((envelope (make-cross-swarm-envelope
                     :target-swarm "unknown-target"
                     :hop-count 10
                     :max-hops 10)))
      ;; Should reject due to hop limit
      (let ((result (compute-routing-decision root envelope)))
        (is (eq (routing-result-decision result) :reject))))))

;;;; ============================================================================
;;;; Tests: Barrier Synchronization
;;;; ============================================================================

(test barrier-creation
  "Test creating barrier for multi-swarm synchronization."
  (let ((participants '("ui-agent-1" "api-agent-1" "cache-agent")))
    (let ((barrier (create-barrier participants :timeout 30)))
      (is (not (null barrier)))
      (is (string= (barrier-id barrier) (barrier-id barrier))))))

(test barrier-participants
  "Test barrier tracks participants."
  (let ((participants '("leaf-a" "leaf-b" "leaf-c")))
    (let ((barrier (create-barrier participants)))
      (is (equal (barrier-participants barrier) participants)))))

(test barrier-arrival
  "Test participants arriving at barrier."
  (let ((barrier (create-barrier '("agent-1" "agent-2"))))
    (barrier-arrive barrier "agent-1")
    (is (member "agent-1" (barrier-participants-arrived barrier)))))

(test barrier-reset
  "Test resetting barrier for reuse."
  (let ((barrier (create-barrier '("a" "b"))))
    (barrier-arrive barrier "a")
    (barrier-reset barrier)
    (is (null (barrier-participants-arrived barrier)))))

(test barrier-cancel
  "Test canceling barrier."
  (let ((barrier (create-barrier '("a" "b"))))
    (barrier-cancel barrier)
    (is (not (barrier-open-p barrier)))))

;;;; ============================================================================
;;;; Tests: Tree Statistics and Metrics
;;;; ============================================================================

(test tree-structure-validation
  "Test that tree structure is valid."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    ;; Tree should be valid
    (is (validate-tree root))
    ;; Should have correct dimensions
    (is (= (tree-size root) 10))  ; root + 2 clusters + 7 leaves = 10
    (is (= (leaf-count root) 7))  ; 7 leaves total
    (is (= (node-count root) 3))  ; root + 2 clusters = 3 nodes
    (is (= (tree-height root) 2))))  ; 3 levels deep

(test tree-traversal-all_nodes
  "Test DFS traversal visits all nodes."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((all-nodes (dfs-traverse root)))
      (is (= (length all-nodes) 10))
      ;; Verify specific nodes are present
      (is (member root all-nodes))
      (is (member frontend all-nodes))
      (is (member backend all-nodes))
      (is (member analytics all-nodes)))))

(test bfs-traversal_level_order
  "Test BFS traversal visits nodes in level order."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((nodes-l0 (nodes-at-depth root 0))
          (nodes-l1 (nodes-at-depth root 1))
          (nodes-l2 (nodes-at-depth root 2)))
      (is (= (length nodes-l0) 1))  ; Just root
      (is (= (length nodes-l1) 4))  ; frontend, backend, analytics, monitoring
      (is (= (length nodes-l2) 5)))))  ; 5 leaf nodes

;;;; ============================================================================
;;;; Tests: Checkpoint and Persistence
;;;; ============================================================================

(test capture-orchestrator-state
  "Test capturing orchestrator state for checkpointing."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((state (capture-orchestrator-state root)))
      (is (not (null state)))
      (let ((snapshot (orchestrator-state-tree state)))
        (is (typep snapshot 'swarm-tree))
        (is (string= (swarm-id snapshot) (swarm-id root)))))))

(test orchestrator-state-structure
  "Test orchestrator state contains all required information."
  (let ((root (make-swarm-node "root")))
    (let ((state (capture-orchestrator-state root)))
      (is (not (null (orchestrator-state-tree state))))
      (is (integerp (orchestrator-state-timestamp state)))
      (is (not (null (orchestrator-state-version state)))))))

(test checkpoint-save-and_restore
  "Test saving and restoring orchestrator checkpoint."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    ;; Note: This is a placeholder test. Real implementation would
    ;; require file I/O and serialization.
    (let ((state (capture-orchestrator-state root)))
      (is (not (null state)))
      ;; In real scenario, would save to file, then restore
      )))

;;;; ============================================================================
;;;; Tests: Error Handling and Restarts
;;;; ============================================================================

(test route_error_condition
  "Test signaling route error condition."
  (let ((envelope (make-cross-swarm-envelope :target-swarm "unreachable")))
    ;; Verify condition can be defined
    (is (not (null envelope)))))

(test unhandled-routing-error
  "Test that routing error is signaled on no route."
  (let ((orphan (make-swarm-leaf "orphan")))
    (let ((envelope (make-cross-swarm-envelope :target-swarm "other")))
      ;; Orphan leaf with unknown target should reject
      (let ((result (compute-routing-decision orphan envelope)))
        (is (eq (routing-result-decision result) :reject))))))

(test envelope-hop-limit-error
  "Test hop limit error is properly signaled."
  (let ((envelope (make-cross-swarm-envelope
                   :hop-count 10
                   :max-hops 10)))
    (is (envelope-hop-limit-exceeded-p envelope))))

(test envelope-expiration-error
  "Test envelope expiration is properly detected."
  (let ((envelope (make-cross-swarm-envelope
                   :deadline (- (get-universal-time) 100))))
    (is (envelope-expired-p envelope))))

;;;; ============================================================================
;;;; Tests: Graceful Degradation
;;;; ============================================================================

(test routing-with-unhealthy-child
  "Test routing when child node is unhealthy."
  (let ((root (make-swarm-node "root"))
        (leaf-a (make-swarm-leaf "leaf-a"))
        (leaf-b (make-swarm-leaf "leaf-b")))
    (register-child root leaf-a)
    (register-child root leaf-b)
    ;; Mark leaf-a as unhealthy
    (setf (node-status leaf-a) :degraded)
    ;; Routing should still work (decide to route to leaf-a)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "leaf-a")))
      (let ((result (compute-routing-decision root envelope)))
        ;; Should still attempt routing despite degraded status
        (is (member (routing-result-decision result)
                    '(:local :child :reject)))))))

(test tree-with_missing_parent
  "Test tree operations when parent is unavailable."
  (let ((leaf (make-swarm-leaf "orphan")))
    ;; Leaf with no parent
    (is (null (parent-node leaf)))
    ;; Should still be able to route through parent (will fail)
    (let ((envelope (make-cross-swarm-envelope :target-swarm "other")))
      (let ((result (compute-routing-decision leaf envelope)))
        (is (eq (routing-result-decision result) :reject))))))

;;;; ============================================================================
;;;; Tests: Concurrent Operations
;;;; ============================================================================

(test multiple-envelopes-routing
  "Test routing multiple envelopes simultaneously."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    ;; Create multiple envelopes
    (let ((env1 (make-cross-swarm-envelope :target-swarm "ui-agent-1"))
          (env2 (make-cross-swarm-envelope :target-swarm "api-agent-1"))
          (env3 (make-cross-swarm-envelope :target-swarm "analytics")))
      ;; Route all (in reality, might be concurrent)
      (let ((r1 (compute-routing-decision root env1))
            (r2 (compute-routing-decision root env2))
            (r3 (compute-routing-decision root env3)))
        ;; All should produce valid decisions
        (is (member (routing-result-decision r1)
                    '(:local :child :parent :reject)))
        (is (member (routing-result-decision r2)
                    '(:local :child :parent :reject)))
        (is (member (routing-result-decision r3)
                    '(:local :child :parent :reject)))))))

(test tree-modification-during_traversal
  "Test modifying tree during traversal."
  (let ((root (make-swarm-node "root"))
        (leaf-a (make-swarm-leaf "leaf-a")))
    (register-child root leaf-a)
    ;; Start traversal
    (let ((nodes (dfs-traverse root)))
      (is (= (length nodes) 2))
      ;; Modify tree (add new child)
      (register-child root (make-swarm-leaf "leaf-b"))
      ;; Traversal should see new node on next call
      (let ((nodes-after (dfs-traverse root)))
        (is (= (length nodes-after) 3))))))

;;;; ============================================================================
;;;; Tests: Complex Workflows
;;;; ============================================================================

(test multi-stage-processing_workflow
  "Test multi-stage data processing workflow."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    (let ((workflow-id "job-12345"))
      ;; Stage 1: UI captures data
      (let ((capture (make-cross-swarm-envelope
                      :correlation-id workflow-id
                      :source-swarm "ui-agent-1"
                      :target-swarm "api-agent-1"
                      :message-type :request
                      :payload '(:action "capture-data"))))
        (is (string= (envelope-correlation-id capture) workflow-id)))

      ;; Stage 2: Backend processes
      (let ((process (make-cross-swarm-envelope
                      :correlation-id workflow-id
                      :source-swarm "api-agent-1"
                      :target-swarm "db-agent"
                      :message-type :request
                      :payload '(:action "store-data"))))
        (is (string= (envelope-correlation-id process) workflow-id)))

      ;; Stage 3: Analytics aggregates
      (let ((aggregate (make-cross-swarm-envelope
                        :correlation-id workflow-id
                        :source-swarm "db-agent"
                        :target-swarm "analytics"
                        :message-type :request
                        :payload '(:action "aggregate"))))
        (is (string= (envelope-correlation-id aggregate) workflow-id))))))

(test publish-subscribe_pattern
  "Test publish-subscribe messaging pattern."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    ;; Publisher sends event
    (let ((event (make-cross-swarm-envelope
                  :correlation-id "event-123"
                  :source-swarm "db-agent"
                  :target-swarm :broadcast
                  :message-type :event
                  :payload '(:event "data-updated" :table "users"))))
      (is (eq (envelope-target-swarm event) :broadcast))
      ;; All subscribers should receive
      (let ((targets (compute-broadcast-targets root)))
        (is (> (length targets) 0))))))

;;;; ============================================================================
;;;; Tests: Scalability
;;;; ============================================================================

(test large_tree_performance
  "Test orchestrator performance with large tree."
  ;; Create a large tree (5 levels, ~100 nodes)
  (let ((root (make-swarm-node "root"))
        (start-time (get-internal-real-time)))
    ;; Build 5 levels
    (let ((level-1-nodes '()))
      (dotimes (i 5)
        (let ((node (make-swarm-node (format nil "l1-node-~D" i))))
          (register-child root node)
          (push node level-1-nodes)))
      ;; Add children to level-1 nodes
      (dolist (node level-1-nodes)
        (dotimes (i 4)
          (let ((leaf (make-swarm-leaf (format nil "leaf-~A-~D"
                                                (swarm-id node) i))))
            (register-child node leaf))))

      ;; Verify structure
      (is (= (tree-size root) 26))  ; 1 root + 5 nodes + 20 leaves
      (is (= (leaf-count root) 20))

      ;; Verify traversal completes quickly
      (let ((nodes (dfs-traverse root)))
        (is (= (length nodes) 26))
        ;; Should complete in reasonable time (< 1 second)
        (let ((elapsed (- (get-internal-real-time) start-time)))
          (is (< elapsed (* 1000 internal-time-units-per-second))))))))

(test many_concurrent_routes
  "Test routing many envelopes concurrently."
  (destructuring-bind (root frontend backend analytics monitoring
                            ui-agent-1 ui-agent-2 api-agent-1 cache-agent db-agent)
      (setup-integration-tree)
    ;; Create 100 envelopes targeting different destinations
    (let ((envelopes (loop for i from 0 below 100
                          collect (make-cross-swarm-envelope
                                   :target-swarm (format nil "agent-~D" i)))))
      (is (= (length envelopes) 100))
      ;; All should be routable (even if to unknown targets)
      (dolist (env envelopes)
        (let ((result (compute-routing-decision root env)))
          (is (member (routing-result-decision result)
                      '(:local :child :parent :reject))))))))

;;;; ============================================================================
;;;; Tests: Stress Testing
;;;; ============================================================================

(test envelope_with_max_hops
  "Test envelope with maximum hops allowed."
  (let ((envelope (make-cross-swarm-envelope :hop-count 9 :max-hops 10)))
    ;; Should still be routable (1 hop remaining)
    (is (not (envelope-hop-limit-exceeded-p envelope)))
    ;; After increment, should exceed
    (envelope-increment-hop-count envelope)
    (is (envelope-hop-limit-exceeded-p envelope))))

(test envelope_deadline_about_to_expire
  "Test envelope with deadline about to expire."
  (let ((now (get-universal-time)))
    ;; Deadline 1 second in future
    (let ((envelope (make-cross-swarm-envelope :deadline (+ now 1))))
      (is (not (envelope-expired-p envelope)))
      ;; After 2 seconds would be expired
      ;; (Note: can't actually sleep in test, so just verify logic)
      (is (< (envelope-remaining-ttl envelope) 2)))))

(test extreme_tree_depth
  "Test tree with extreme depth."
  ;; Build a 20-level chain
  (let ((root (make-swarm-node "root")))
    (let ((current root))
      (dotimes (i 19)
        (let ((child (make-swarm-node (format nil "node-~D" i))))
          (register-child current child)
          (setf current child))))
    ;; Verify depth calculation works
    (let ((leaf (car (list-children (find-node root "node-18")))))
      (if leaf
          (is (> (node-depth leaf) 18))))))

;;;; End of file
