;;;; hierarchical.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Hierarchical Tree Example
;;;;
;;;; Purpose: Demonstrates multi-level tree orchestration with nested nodes,
;;;; showcasing the SwarmTree ADT (Leaf | Node) and tree traversal operations.
;;;;
;;;; This example builds a 3-level hierarchy:
;;;;
;;;;                        [root]
;;;;                       /      \
;;;;               [region-us]   [region-eu]
;;;;               /    |   \        |    \
;;;;         [leaf1] [leaf2] [leaf3] [leaf4] [leaf5]
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/hierarchical.lisp")
;;;;   (hierarchical-example:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :hierarchical-example
  (:use :cl :sw4rm-orchestrator)
  (:export #:run-demo
           #:build-hierarchy
           #:*root*
           #:demonstrate-traversal
           #:demonstrate-routing
           #:demonstrate-aggregation
           #:demonstrate-checkpointing))

(in-package :hierarchical-example)

;;; ==========================================================================
;;; Global State
;;; ==========================================================================

(defparameter *root* nil
  "The root of the hierarchical tree. Set by BUILD-HIERARCHY.")

(defparameter *checkpoint-path* "/tmp/sw4rm-hierarchical-checkpoint.bin"
  "Path for checkpoint demonstration.")

;;; ==========================================================================
;;; SwarmTree ADT
;;; ==========================================================================

#|
The SwarmTree is an Algebraic Data Type (ADT) with two variants:

  SwarmTree = Leaf(SwarmInstance)
            | Node(Orchestrator, children: [SwarmTree])

In Common Lisp, we implement this with CLOS:
  - swarm-leaf: Wraps a Python sw4rm instance
  - swarm-node: Contains children (mix of leaves and nodes)

This enables recursive composition where orchestrators can manage
other orchestrators, creating arbitrary hierarchies.
|#

;;; ==========================================================================
;;; Hierarchy Construction
;;; ==========================================================================

(defun make-leaf (id name port)
  "Create a swarm-leaf with common defaults."
  (make-instance 'swarm-leaf
                 :id id
                 :name name
                 :host "localhost"
                 :port port))

(defun make-node (id name)
  "Create a swarm-node (sub-orchestrator)."
  (make-instance 'swarm-node
                 :id id
                 :name name))

(defun build-hierarchy ()
  "Build a 3-level hierarchical tree structure.

   Structure:
                        [root]
                       /      \\
               [region-us]   [region-eu]
               /    |   \\        |    \\
         [leaf1] [leaf2] [leaf3] [leaf4] [leaf5]

   This demonstrates:
   - Nested orchestrators (nodes containing nodes)
   - Mixed trees (nodes containing both nodes and leaves)
   - Geographic/organizational partitioning pattern"

  ;; Level 3: Leaf nodes (Python sw4rm instances)
  (let ((leaf1 (make-leaf "us-east-1" "US East Worker 1" 50051))
        (leaf2 (make-leaf "us-east-2" "US East Worker 2" 50052))
        (leaf3 (make-leaf "us-west-1" "US West Worker 1" 50053))
        (leaf4 (make-leaf "eu-west-1" "EU West Worker 1" 50054))
        (leaf5 (make-leaf "eu-west-2" "EU West Worker 2" 50055)))

    ;; Level 2: Regional orchestrators
    (let ((region-us (make-node "region-us" "US Region Orchestrator"))
          (region-eu (make-node "region-eu" "EU Region Orchestrator")))

      ;; Register US leaves
      (register-child region-us leaf1)
      (register-child region-us leaf2)
      (register-child region-us leaf3)

      ;; Register EU leaves
      (register-child region-eu leaf4)
      (register-child region-eu leaf5)

      ;; Level 1: Root orchestrator
      (setf *root* (make-node "root" "Global Orchestrator"))
      (register-child *root* region-us)
      (register-child *root* region-eu)

      (format t "~&Hierarchy built:~%")
      (print-tree *root*)

      *root*)))

;;; ==========================================================================
;;; Tree Visualization
;;; ==========================================================================

(defun print-tree (node &optional (indent 0))
  "Pretty-print the tree structure with indentation.

   This is a simple recursive traversal for visualization."
  (let ((prefix (make-string indent :initial-element #\Space)))
    (etypecase node
      (swarm-leaf
       (format t "~A[Leaf] ~A (~A:~D)~%"
               prefix
               (swarm-id node)
               (leaf-host node)
               (leaf-port node)))
      (swarm-node
       (format t "~A[Node] ~A~%"
               prefix
               (swarm-id node))
       (dolist (child (list-children node))
         (print-tree child (+ indent 2)))))))

;;; ==========================================================================
;;; Tree Traversal Operations
;;; ==========================================================================

;; fold-tree: A utility function for aggregating tree values
;; Not in SDK, so we define it locally for this example
(defun fold-tree (node leaf-fn node-fn)
  "Fold a tree by applying LEAF-FN to leaves and NODE-FN to nodes.

   LEAF-FN: (leaf) -> value
   NODE-FN: (node child-values) -> value

   This is a classic catamorphism over the SwarmTree ADT."
  (etypecase node
    (swarm-leaf (funcall leaf-fn node))
    (swarm-node (funcall node-fn node
                         (mapcar (lambda (child)
                                   (fold-tree child leaf-fn node-fn))
                                 (list-children node))))))

(defun demonstrate-traversal ()
  "Demonstrate tree traversal operations.

   Shows:
   - map-tree: Apply function to each node
   - fold-tree: Aggregate values from leaves to root
   - find-node: Search for specific nodes
   - count-leaves: Count total leaves"

  (format t "~&=== Tree Traversal Demonstrations ===~%~%")

  ;; Count leaves using fold-tree
  (format t "1. Counting leaves with FOLD-TREE:~%")
  (let ((leaf-count (fold-tree *root*
                               #'(lambda (leaf) (declare (ignore leaf)) 1)
                               #'(lambda (node counts)
                                   (declare (ignore node))
                                   (reduce #'+ counts :initial-value 0)))))
    (format t "   Total leaves: ~D~%~%" leaf-count))

  ;; Collect all node IDs using map-tree
  (format t "2. Collecting IDs with MAP-TREE:~%")
  (let ((all-ids (map-tree *root* #'swarm-id)))
    (format t "   All IDs: ~{~A~^, ~}~%~%" all-ids))

  ;; Find specific node
  (format t "3. Finding node 'region-us' with FIND-NODE:~%")
  (let ((found (find-node *root* (lambda (n) (string= (swarm-id n) "region-us")))))
    (if found
        (format t "   Found: ~A (type: ~A, children: ~D)~%~%"
                (swarm-id found)
                (type-of found)
                (length (list-children found)))
        (format t "   Not found~%~%")))

  ;; Calculate tree depth
  (format t "4. Calculating tree depth:~%")
  (let ((depth (fold-tree *root*
                          #'(lambda (leaf) (declare (ignore leaf)) 1)
                          #'(lambda (node depths)
                              (declare (ignore node))
                              (1+ (if depths (apply #'max depths) 0))))))
    (format t "   Max depth: ~D~%~%" depth))

  ;; Get all leaves as flat list
  (format t "5. Flattening to leaves:~%")
  (let ((leaves (collect-leaves *root*)))
    (format t "   Leaves: ~{~A~^, ~}~%"
            (mapcar #'swarm-id leaves))))

(defun collect-leaves (node)
  "Collect all leaf nodes into a flat list.

   Demonstrates pattern matching on SwarmTree ADT."
  (etypecase node
    (swarm-leaf (list node))
    (swarm-node (mapcan #'collect-leaves (list-children node)))))

;;; ==========================================================================
;;; Hierarchical Routing
;;; ==========================================================================

(defun demonstrate-routing ()
  "Demonstrate routing through the hierarchy.

   Shows:
   - Cross-region routing (US -> EU)
   - Broadcast to all leaves
   - Region-specific routing"

  (format t "~&=== Hierarchical Routing Demonstrations ===~%~%")

  ;; Cross-region routing
  (format t "1. Cross-region routing (US -> EU):~%")
  (let ((envelope (make-cross-swarm-envelope
                   :source-swarm "us-east-1"
                   :target-swarm "eu-west-1"
                   :sender "data-processor"
                   :recipient "data-store"
                   :payload '(:action "sync" :records 1000))))
    (format t "   Envelope: ~A -> ~A~%"
            (envelope-source-swarm envelope)
            (envelope-target-swarm envelope))
    (let ((route (compute-route *root* envelope)))
      (format t "   Computed route: ~{~A~^ -> ~}~%~%"
              (mapcar #'swarm-id route))))

  ;; Broadcast to region
  (format t "2. Broadcast to US region:~%")
  (let ((us-node (find-node *root* "region-us")))
    (when us-node
      (let ((targets (collect-leaves us-node)))
        (format t "   Broadcasting to: ~{~A~^, ~}~%~%"
                (mapcar #'swarm-id targets)))))

  ;; Failover routing
  (format t "3. Failover strategy demonstration:~%")
  (format t "   Primary: us-east-1~%")
  (format t "   Fallback order: us-east-2, us-west-1~%")
  (format t "   (Would try each in sequence on failure)~%"))

(defun compute-route (root envelope)
  "Compute the routing path through the hierarchy.

   Returns list of nodes from root to target."
  (let ((target-id (envelope-target-swarm envelope)))
    (labels ((find-path (node path)
               (cond
                 ((string= (swarm-id node) target-id)
                  (reverse (cons node path)))
                 ((typep node 'swarm-node)
                  (some #'(lambda (child)
                            (find-path child (cons node path)))
                        (list-children node)))
                 (t nil))))
      (or (find-path root nil)
          (list root)))))  ; Return just root if not found

;;; ==========================================================================
;;; Parallel Aggregation
;;; ==========================================================================

(defun demonstrate-aggregation ()
  "Demonstrate parallel result aggregation from leaves.

   Shows:
   - Fan-out query to all leaves
   - Parallel execution simulation
   - Hierarchical result aggregation"

  (format t "~&=== Parallel Aggregation Demonstration ===~%~%")

  ;; Simulate querying all leaves for metrics
  (format t "1. Fan-out metrics query:~%")
  (let ((results (simulate-parallel-query *root*)))
    (format t "   Raw results: ~A~%~%" results)

    ;; Aggregate by region
    (format t "2. Regional aggregation:~%")
    (let ((us-total 0)
          (eu-total 0))
      (dolist (result results)
        (if (search "us-" (car result))
            (incf us-total (cdr result))
            (incf eu-total (cdr result))))
      (format t "   US total: ~D~%" us-total)
      (format t "   EU total: ~D~%" eu-total)
      (format t "   Global total: ~D~%~%" (+ us-total eu-total))))

  ;; Hierarchical aggregation pattern
  (format t "3. Hierarchical aggregation with FOLD-TREE:~%")
  (let ((aggregated
          (fold-tree *root*
                     #'(lambda (leaf)
                         ;; Each leaf returns its "metrics"
                         (list (cons (swarm-id leaf)
                                     (random 100))))
                     #'(lambda (node child-results)
                         ;; Node aggregates children
                         (cons (cons (swarm-id node)
                                     (reduce #'+
                                             (mapcar #'cdar child-results)
                                             :initial-value 0))
                               (apply #'append child-results))))))
    (format t "   Aggregated tree: ~A~%" aggregated)))

(defun simulate-parallel-query (root)
  "Simulate querying all leaves in parallel.

   Returns alist of (leaf-id . metric-value)."
  (let ((leaves (collect-leaves root)))
    (mapcar #'(lambda (leaf)
                (cons (swarm-id leaf)
                      (random 100)))  ; Simulate metric
            leaves)))

;;; ==========================================================================
;;; Checkpointing
;;; ==========================================================================

(defun demonstrate-checkpointing ()
  "Demonstrate image-based checkpointing.

   Shows:
   - Save entire tree state
   - Restore from checkpoint
   - CL's ability to serialize arbitrary objects"

  (format t "~&=== Checkpointing Demonstration ===~%~%")

  (format t "1. Current tree state:~%")
  (print-tree *root*)
  (format t "~%")

  ;; Save checkpoint
  (format t "2. Saving checkpoint to ~A~%" *checkpoint-path*)
  (handler-case
      (progn
        (save-tree-checkpoint *root* *checkpoint-path*)
        (format t "   Checkpoint saved successfully~%~%"))
    (error (e)
      (format t "   Save failed: ~A~%~%" e)))

  ;; Demonstrate restore
  (format t "3. Checkpoint restore demonstration:~%")
  (format t "   In production, restore with:~%")
  (format t "   (setf *root* (restore-tree-checkpoint ~S))~%~%"
          *checkpoint-path*)

  ;; Show what's preserved
  (format t "4. What gets checkpointed:~%")
  (format t "   - Complete tree structure~%")
  (format t "   - All node/leaf configurations~%")
  (format t "   - Routing table state~%")
  (format t "   - In-flight operation state~%")
  (format t "   - Custom slot values~%"))

(defun save-tree-checkpoint (root path)
  "Save tree state to file using cl-store.

   cl-store can serialize arbitrary CL objects, including CLOS instances."
  (ensure-directories-exist path)
  (cl-store:store root path))

(defun restore-tree-checkpoint (path)
  "Restore tree state from checkpoint file."
  (cl-store:restore path))

;;; ==========================================================================
;;; Advanced: Generic Function Dispatch
;;; ==========================================================================

#|
CLOS generic functions enable polymorphic operations on the tree.
Different node types can have specialized behavior.

(defgeneric process-request (node request)
  (:documentation "Process a request at this node."))

(defmethod process-request ((node swarm-leaf) request)
  "Leaves forward to Python sw4rm instance."
  (forward-to-grpc node request))

(defmethod process-request ((node swarm-node) request)
  "Nodes route to appropriate child."
  (let ((target (select-child node request)))
    (process-request target request)))

This pattern naturally handles the Leaf | Node ADT without explicit
type checking or pattern matching syntax.
|#

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete hierarchical tree demo.

   Demonstrates:
   1. Building a 3-level hierarchy
   2. Tree traversal operations
   3. Hierarchical routing
   4. Parallel aggregation
   5. Checkpointing"

  (format t "~&========================================~%")
  (format t "SW4RM Hierarchical Tree Demo~%")
  (format t "========================================~%~%")

  ;; Step 1: Build the hierarchy
  (format t "Building hierarchy...~%~%")
  (build-hierarchy)
  (format t "~%")

  ;; Step 2: Traversal
  (demonstrate-traversal)
  (format t "~%")

  ;; Step 3: Routing
  (demonstrate-routing)
  (format t "~%")

  ;; Step 4: Aggregation
  (demonstrate-aggregation)
  (format t "~%")

  ;; Step 5: Checkpointing
  (demonstrate-checkpointing)

  (format t "~&========================================~%")
  (format t "Demo Complete~%")
  (format t "========================================~%~%")

  (format t "For interactive exploration:~%")
  (format t "  (in-package :hierarchical-example)~%")
  (format t "  (print-tree *root*)~%")
  (format t "  (find-node *root* \"region-us\")~%")
  (format t "  (collect-leaves *root*)~%"))

;;; ==========================================================================
;;; Python Comparison
;;; ==========================================================================

#|
Python Equivalent (workflow_orchestration_example.py pattern):

    class SwarmTree:
        pass

    class SwarmLeaf(SwarmTree):
        def __init__(self, id, host, port):
            self.id = id
            self.host = host
            self.port = port

    class SwarmNode(SwarmTree):
        def __init__(self, id):
            self.id = id
            self.children = []

        def add_child(self, child):
            self.children.append(child)

    def fold_tree(node, leaf_fn, node_fn):
        if isinstance(node, SwarmLeaf):
            return leaf_fn(node)
        else:
            child_results = [fold_tree(c, leaf_fn, node_fn) for c in node.children]
            return node_fn(node, child_results)

CL Advantages:
1. CLOS provides cleaner ADT representation than Python classes
2. Generic functions enable open extension without modifying classes
3. Image-based checkpointing with cl-store is simpler than pickle
4. Pattern matching via ETYPECASE is concise and exhaustive
5. REPL allows interactive tree exploration
|#

;;; End of hierarchical.lisp
