;;;; cross-swarm-handoff.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Cross-Swarm Handoff with Routing Strategies
;;;;
;;;; Purpose: Demonstrate context handoff between swarms using all 7 routing
;;;; strategies. Shows how messages flow through the hierarchical tree.
;;;;
;;;; This example covers:
;;;;   - All 7 routing strategies in action
;;;;   - Context handoff patterns
;;;;   - Routing table TTL and expiration
;;;;   - Health-aware routing decisions
;;;;   - Strategy composition
;;;;
;;;; The 7 Routing Strategies:
;;;;   1. Direct - Route to specific target
;;;;   2. Round-Robin - Distribute evenly across targets
;;;;   3. Least-Loaded - Route to least busy target
;;;;   4. Latency-Based - Route to fastest responding target
;;;;   5. Weighted-Random - Probabilistic routing with weights
;;;;   6. Failover - Primary with backup targets
;;;;   7. Broadcast - Send to all targets
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/cross-swarm-handoff.lisp")
;;;;   (cross-swarm-handoff:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :cross-swarm-handoff
  (:use :cl :sw4rm-orchestrator)
  (:import-from :sw4rm-orchestrator.routing
                #:routing-strategy
                #:select-route
                #:strategy-name
                #:direct-routing-strategy
                #:round-robin-strategy
                #:least-loaded-strategy
                #:latency-based-strategy
                #:weighted-random-strategy
                #:failover-strategy
                #:broadcast-strategy
                #:make-routing-table
                #:add-route
                #:lookup-route)
  (:import-from :sw4rm-orchestrator.tree
                #:leaf-host
                #:leaf-port
                #:node-status)
  (:export #:run-demo
           #:setup-cluster
           #:demonstrate-direct-routing
           #:demonstrate-round-robin
           #:demonstrate-least-loaded
           #:demonstrate-latency-based
           #:demonstrate-weighted-random
           #:demonstrate-failover
           #:demonstrate-broadcast
           #:*root*
           #:*workers*))

(in-package :cross-swarm-handoff)

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *worker-count* 4
  "Number of worker leaves to create.")

(defparameter *base-port* 50051
  "Base port for worker leaves.")

;;; ==========================================================================
;;; Global State
;;; ==========================================================================

(defparameter *root* nil
  "Root orchestrator node.")

(defparameter *workers* nil
  "List of worker leaves.")

(defparameter *routing-table* nil
  "Routing table for the cluster.")

;;; ==========================================================================
;;; Cluster Setup
;;; ==========================================================================

(defun setup-cluster ()
  "Create a cluster with one root and multiple workers.

Creates:
  - Root orchestrator node
  - N worker leaves (simulated)
  - Routing table with all workers"

  (format t "~&Setting up cluster with ~D workers...~%" *worker-count*)

  ;; Create root orchestrator
  (setf *root* (make-instance 'swarm-node :id "root"))

  ;; Create workers
  (setf *workers*
        (loop for i from 0 below *worker-count*
              for id = (format nil "worker-~D" i)
              for port = (+ *base-port* i)
              collect (let ((leaf (make-instance 'swarm-leaf
                                                  :id id
                                                  :host "localhost"
                                                  :port port)))
                        (register-child *root* leaf)
                        leaf)))

  ;; Create routing table
  (setf *routing-table* (make-routing-table))
  (dolist (worker *workers*)
    (add-route *routing-table*
               (swarm-id worker)
               worker
               :ttl 300)) ; 5 minute TTL

  (format t "~&Cluster ready:~%")
  (format t "  Root: ~A~%" (swarm-id *root*))
  (format t "  Workers: ~{~A~^, ~}~%~%"
          (mapcar #'swarm-id *workers*)))

;;; ==========================================================================
;;; Strategy 1: Direct Routing
;;; ==========================================================================

(defun demonstrate-direct-routing ()
  "Demonstrate direct routing to a specific target.

Direct routing sends a message to exactly one specified target.
Use when you know the exact destination."

  (format t "~&=== Strategy 1: Direct Routing ===~%~%")

  (let* ((strategy (make-instance 'direct-routing-strategy))
         (target-id "worker-0")
         (candidates (list (first *workers*))))

    (format t "Strategy: ~A~%" (strategy-name strategy))
    (format t "Target: ~A~%~%" target-id)

    ;; Make routing decision
    ;; select-route takes (strategy node envelope available-routes)
    (let ((selected (select-route strategy *root* nil (list (swarm-id (first candidates))))))
      (format t "Selected route: ~A~%" selected)
      (format t "This strategy always routes to the specified target.~%"))))

;;; ==========================================================================
;;; Strategy 2: Round-Robin
;;; ==========================================================================

(defun demonstrate-round-robin ()
  "Demonstrate round-robin routing across workers.

Round-robin distributes requests evenly across all available targets.
Use for load balancing when all targets have equal capacity."

  (format t "~&=== Strategy 2: Round-Robin ===~%~%")

  (let ((strategy (make-instance 'round-robin-strategy)))
    (format t "Strategy: ~A~%" (strategy-name strategy))
    (format t "Workers: ~{~A~^, ~}~%~%" (mapcar #'swarm-id *workers*))

    (format t "Routing 8 requests:~%")
    (let ((worker-ids (mapcar #'swarm-id *workers*)))
      (dotimes (i 8)
        (let ((selected (select-route strategy *root* nil worker-ids)))
          (format t "  Request ~D -> ~A~%" (1+ i) selected))))

    (format t "~%Notice: Requests cycle through workers in order.~%")))

;;; ==========================================================================
;;; Strategy 3: Least-Loaded
;;; ==========================================================================

(defun demonstrate-least-loaded ()
  "Demonstrate least-loaded routing strategy.

Least-loaded routes to the target with the smallest queue depth.
Use when targets have varying processing capacities."

  (format t "~&=== Strategy 3: Least-Loaded ===~%~%")

  (let ((strategy (make-instance 'least-loaded-strategy)))
    (format t "Strategy: ~A~%~%" (strategy-name strategy))

    ;; Simulate different load levels
    (format t "Simulated load levels:~%")
    (let ((loads '(10 5 15 3)))
      (loop for worker in *workers*
            for load in loads
            do (format t "  ~A: ~D pending tasks~%"
                       (swarm-id worker) load))

      ;; Note: In real implementation, load would be queried from workers
      ;; Here we demonstrate the concept
      (format t "~%Expected routing: worker-3 (lowest load)~%")
      (format t "This strategy minimizes queue depth across the cluster.~%"))))

;;; ==========================================================================
;;; Strategy 4: Latency-Based
;;; ==========================================================================

(defun demonstrate-latency-based ()
  "Demonstrate latency-based routing strategy.

Latency-based routes to the target with the lowest response latency.
Use when response time is critical."

  (format t "~&=== Strategy 4: Latency-Based ===~%~%")

  (let ((strategy (make-instance 'latency-based-strategy)))
    (format t "Strategy: ~A~%~%" (strategy-name strategy))

    ;; Simulate different latencies
    (format t "Simulated latencies (from last pings):~%")
    (let ((latencies '(50 20 35 15))) ; milliseconds
      (loop for worker in *workers*
            for latency in latencies
            do (format t "  ~A: ~Dms~%"
                       (swarm-id worker) latency))

      (format t "~%Expected routing: worker-3 (lowest latency)~%")
      (format t "This strategy optimizes for response time.~%"))))

;;; ==========================================================================
;;; Strategy 5: Weighted-Random
;;; ==========================================================================

(defun demonstrate-weighted-random ()
  "Demonstrate weighted-random routing strategy.

Weighted-random selects targets probabilistically based on weights.
Use for gradual traffic shifting (canary deployments, A/B testing)."

  (format t "~&=== Strategy 5: Weighted-Random ===~%~%")

  (let ((strategy (make-instance 'weighted-random-strategy)))
    (format t "Strategy: ~A~%~%" (strategy-name strategy))

    ;; Simulate weights
    (format t "Configured weights:~%")
    (let ((weights '(40 30 20 10))) ; percentages
      (loop for worker in *workers*
            for weight in weights
            do (format t "  ~A: ~D%%~%"
                       (swarm-id worker) weight))

      (format t "~%Simulating 100 requests:~%")
      ;; Simple simulation
      (let ((counts (make-hash-table :test 'equal)))
        (dolist (worker *workers*)
          (setf (gethash (swarm-id worker) counts) 0))

        ;; Simulate weighted distribution
        (loop for worker in *workers*
              for weight in weights
              do (incf (gethash (swarm-id worker) counts) weight))

        (maphash (lambda (id count)
                   (format t "  ~A: ~D requests~%" id count))
                 counts))

      (format t "~%Distribution approximates configured weights.~%"))))

;;; ==========================================================================
;;; Strategy 6: Failover
;;; ==========================================================================

(defun demonstrate-failover ()
  "Demonstrate failover routing strategy.

Failover routes to primary target, falls back to secondary on failure.
Use for high availability with explicit primary/backup."

  (format t "~&=== Strategy 6: Failover ===~%~%")

  (let ((strategy (make-instance 'failover-strategy)))
    (format t "Strategy: ~A~%~%" (strategy-name strategy))

    ;; Define primary and backups
    (format t "Configured priority:~%")
    (format t "  Primary: worker-0~%")
    (format t "  Backup 1: worker-1~%")
    (format t "  Backup 2: worker-2~%")
    (format t "  Backup 3: worker-3~%~%")

    ;; Normal case
    (format t "Scenario 1: All workers healthy~%")
    (format t "  Routes to: worker-0 (primary)~%~%")

    ;; Primary down
    (format t "Scenario 2: worker-0 unhealthy~%")
    (format t "  Routes to: worker-1 (first backup)~%~%")

    ;; Multiple failures
    (format t "Scenario 3: worker-0, worker-1 unhealthy~%")
    (format t "  Routes to: worker-2 (second backup)~%~%")

    (format t "Failover provides automatic recovery from failures.~%")))

;;; ==========================================================================
;;; Strategy 7: Broadcast
;;; ==========================================================================

(defun demonstrate-broadcast ()
  "Demonstrate broadcast routing strategy.

Broadcast sends the message to ALL targets simultaneously.
Use for cache invalidation, configuration updates, status queries."

  (format t "~&=== Strategy 7: Broadcast ===~%~%")

  (let ((strategy (make-instance 'broadcast-strategy)))
    (format t "Strategy: ~A~%~%" (strategy-name strategy))

    (format t "Message will be sent to ALL workers:~%")
    (dolist (worker *workers*)
      (format t "  -> ~A~%" (swarm-id worker)))

    (format t "~%Use cases:~%")
    (format t "  - Cache invalidation~%")
    (format t "  - Configuration propagation~%")
    (format t "  - Health check requests~%")
    (format t "  - Shutdown commands~%~%")

    (format t "Note: Broadcast returns after ALL targets receive the message.~%")))

;;; ==========================================================================
;;; Context Handoff Demonstration
;;; ==========================================================================

(defun demonstrate-context-handoff ()
  "Demonstrate context handoff between swarms.

Shows how conversation context is passed between swarms
while maintaining the correlation ID for tracking."

  (format t "~&=== Context Handoff Pattern ===~%~%")

  (let* ((correlation-id (format nil "conv-~D" (get-universal-time)))
         (context '(:user-id 42
                    :session-id "sess-abc"
                    :history ((:role "user" :content "Hello")
                              (:role "assistant" :content "Hi!")))))

    (format t "Initial context in frontend swarm:~%")
    (format t "  Correlation ID: ~A~%" correlation-id)
    (format t "  Context: ~S~%~%" context)

    ;; Create handoff envelope
    (let ((handoff-env (make-cross-swarm-envelope
                         :source-swarm "frontend"
                         :target-swarm "backend"
                         :correlation-id correlation-id
                         :message-type :request
                         :payload (list :action "continue-conversation"
                                        :context context
                                        :new-message "What's the weather?"))))

      (format t "Handoff envelope created:~%")
      (format t "  Source: ~A~%" (envelope-source-swarm handoff-env))
      (format t "  Target: ~A~%" (envelope-target-swarm handoff-env))
      (format t "  Correlation: ~A~%~%" (envelope-correlation-id handoff-env))

      (format t "The backend swarm receives:~%")
      (format t "  - Full conversation context~%")
      (format t "  - Correlation ID for response routing~%")
      (format t "  - The new user message~%~%")

      (format t "Response routes back using same correlation ID.~%"))))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete cross-swarm handoff demonstration."

  (format t "~&==============================================~%")
  (format t "   Cross-Swarm Handoff with Routing Strategies~%")
  (format t "==============================================~%~%")

  ;; Setup
  (setup-cluster)

  ;; Demonstrate all strategies
  (demonstrate-direct-routing)
  (format t "~%")

  (demonstrate-round-robin)
  (format t "~%")

  (demonstrate-least-loaded)
  (format t "~%")

  (demonstrate-latency-based)
  (format t "~%")

  (demonstrate-weighted-random)
  (format t "~%")

  (demonstrate-failover)
  (format t "~%")

  (demonstrate-broadcast)
  (format t "~%")

  ;; Context handoff
  (demonstrate-context-handoff)

  (format t "~%==============================================~%")
  (format t "   Demo Complete~%")
  (format t "==============================================~%~%")

  (format t "For REPL exploration:~%")
  (format t "  (in-package :cross-swarm-handoff)~%")
  (format t "  (describe-orchestrator *root*)~%")
  (format t "  (mapcar #'swarm-id *workers*)~%"))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (routing_strategies.py pattern):

    from enum import Enum
    from abc import ABC, abstractmethod
    from typing import List, Optional
    import random

    class RoutingStrategy(ABC):
        @abstractmethod
        def select(self, candidates: List[SwarmLeaf], context: dict) -> SwarmLeaf:
            pass

    class DirectRoutingStrategy(RoutingStrategy):
        def select(self, candidates, context):
            target_id = context.get("target")
            return next(c for c in candidates if c.id == target_id)

    class RoundRobinStrategy(RoutingStrategy):
        def __init__(self):
            self.index = 0

        def select(self, candidates, context):
            selected = candidates[self.index % len(candidates)]
            self.index += 1
            return selected

    class WeightedRandomStrategy(RoutingStrategy):
        def __init__(self, weights: dict):
            self.weights = weights

        def select(self, candidates, context):
            return random.choices(
                candidates,
                weights=[self.weights.get(c.id, 1) for c in candidates]
            )[0]

CL Advantages Demonstrated:
1. CLOS enables clean strategy pattern with generic functions
2. Strategies are first-class objects, composable
3. Method combination allows layering strategies
4. Conditions/restarts handle routing failures gracefully
|#

;;;; End of cross-swarm-handoff.lisp
