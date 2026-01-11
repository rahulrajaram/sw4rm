;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; test/tree-tests.lisp
;;;;
;;;; Comprehensive test suite for SwarmTree ADT operations.
;;;;
;;;; Tests cover:
;;;;   - Node creation and initialization
;;;;   - Child registration and unregistration
;;;;   - Tree traversal (DFS, BFS)
;;;;   - Path operations and node depth
;;;;   - Tree statistics (height, size, leaf count)
;;;;   - Tree validation and consistency checks
;;;;   - Edge cases and error handling
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.test)

(in-suite tree-tests)

;;;; ============================================================================
;;;; Fixtures and Setup/Teardown
;;;; ============================================================================

(defun setup-simple-tree ()
  "Create a simple three-level tree for testing.

  Structure:
    root
    +-- leaf-a
    +-- leaf-b
    +-- cluster-1
        +-- leaf-c
        +-- leaf-d"
  (let ((root (make-swarm-node "root"))
        (leaf-a (make-swarm-leaf "leaf-a"))
        (leaf-b (make-swarm-leaf "leaf-b"))
        (cluster-1 (make-swarm-node "cluster-1"))
        (leaf-c (make-swarm-leaf "leaf-c"))
        (leaf-d (make-swarm-leaf "leaf-d")))
    ;; Register leaves at root level
    (register-child root leaf-a)
    (register-child root leaf-b)
    (register-child root cluster-1)
    ;; Register leaves under cluster-1
    (register-child cluster-1 leaf-c)
    (register-child cluster-1 leaf-d)
    ;; Return root and all nodes for verification
    (list root leaf-a leaf-b cluster-1 leaf-c leaf-d)))

;;;; ============================================================================
;;;; Tests: SWARM-LEAF Creation
;;;; ============================================================================

(test swarm-leaf-creation-basic
  "Test creating a basic swarm leaf with defaults."
  (let ((leaf (make-swarm-leaf "leaf-1")))
    (is (string= (swarm-id leaf) "leaf-1"))
    (is (string= (leaf-host leaf) "localhost"))
    (is (= (leaf-port leaf) 50051))
    (is (null (parent-node leaf)))
    (is (null (leaf-agents leaf)))
    (is (null (leaf-grpc-client leaf)))))

(test swarm-leaf-creation-with-args
  "Test creating a swarm leaf with custom arguments."
  (let ((leaf (make-swarm-leaf "leaf-1"
                               :host "10.0.0.5"
                               :port 50052
                               :capabilities '(:nlp :vision))))
    (is (string= (swarm-id leaf) "leaf-1"))
    (is (string= (leaf-host leaf) "10.0.0.5"))
    (is (= (leaf-port leaf) 50052))
    (is (equal (leaf-capabilities leaf) '(:nlp :vision)))))

(test swarm-leaf-validation-host
  "Test that leaf validation rejects invalid host."
  (signals error
    (make-instance 'swarm-leaf :id "leaf-1" :host "")))

(test swarm-leaf-validation-port
  "Test that leaf validation rejects invalid port."
  (signals error
    (make-instance 'swarm-leaf :id "leaf-1" :port 0))
  (signals error
    (make-instance 'swarm-leaf :id "leaf-1" :port 65536)))

(test swarm-leaf-is-leaf-p
  "Test the swarm-leaf-p type predicate."
  (let ((leaf (make-swarm-leaf "leaf-1")))
    (is (swarm-leaf-p leaf))
    (is (swarm-tree-p leaf))
    (is (not (swarm-node-p leaf)))))

;;;; ============================================================================
;;;; Tests: SWARM-NODE Creation
;;;; ============================================================================

(test swarm-node-creation-basic
  "Test creating a basic swarm node."
  (let ((node (make-swarm-node "root")))
    (is (string= (swarm-id node) "root"))
    (is (null (parent-node node)))
    (is (= (hash-table-count (node-children node)) 0))))

(test swarm-node-creation-with-parent
  "Test creating a swarm node with parent."
  (let* ((parent (make-swarm-node "parent"))
         (child (make-swarm-node "child" :parent parent)))
    (is (eq (parent-node child) parent))
    (is (string= (swarm-id (parent-node child)) "parent"))))

(test swarm-node-is-node-p
  "Test the swarm-node-p type predicate."
  (let ((node (make-swarm-node "root")))
    (is (swarm-node-p node))
    (is (swarm-tree-p node))
    (is (not (swarm-leaf-p node)))))

;;;; ============================================================================
;;;; Tests: Child Registration
;;;; ============================================================================

(test register-child-leaf
  "Test registering a leaf child."
  (let ((node (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child node leaf)
    (is (eq (get-child node "leaf-1") leaf))
    (is (eq (parent-node leaf) node))))

(test register-child-node
  "Test registering a node child."
  (let ((parent (make-swarm-node "parent"))
        (child (make-swarm-node "child")))
    (register-child parent child)
    (is (eq (get-child parent "child") child))
    (is (eq (parent-node child) parent))))

(test register-multiple-children
  "Test registering multiple children."
  (let ((node (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-2"))
        (leaf-3 (make-swarm-leaf "leaf-3")))
    (register-child node leaf-1)
    (register-child node leaf-2)
    (register-child node leaf-3)
    (is (= (hash-table-count (node-children node)) 3))
    (is (eq (get-child node "leaf-1") leaf-1))
    (is (eq (get-child node "leaf-2") leaf-2))
    (is (eq (get-child node "leaf-3") leaf-3))))

(test register-child-duplicate-id-error
  "Test that registering duplicate child ID raises error."
  (let ((node (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-1")))  ; Same ID
    (register-child node leaf-1)
    (signals error
      (register-child node leaf-2))))

(test register-child-on-leaf-error
  "Test that registering child on leaf raises error."
  (let ((leaf (make-swarm-leaf "leaf-1"))
        (child (make-swarm-leaf "child")))
    (signals error
      (register-child leaf child))))

(test list-children-empty
  "Test listing children of node with no children."
  (let ((node (make-swarm-node "root")))
    (is (null (list-children node)))))

(test list-children-multiple
  "Test listing multiple children."
  (let ((node (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-2")))
    (register-child node leaf-1)
    (register-child node leaf-2)
    (let ((children (list-children node)))
      (is (= (length children) 2))
      (is (member leaf-1 children))
      (is (member leaf-2 children)))))

;;;; ============================================================================
;;;; Tests: Child Unregistration
;;;; ============================================================================

(test unregister-child-existing
  "Test unregistering an existing child."
  (let ((node (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child node leaf)
    (is (eq (get-child node "leaf-1") leaf))
    ;; Unregister
    (unregister-child node "leaf-1")
    (is (null (get-child node "leaf-1")))
    (is (null (parent-node leaf)))))

(test unregister-child-nonexistent
  "Test unregistering a non-existent child returns nil."
  (let ((node (make-swarm-node "root")))
    (is (null (unregister-child node "nonexistent")))))

(test unregister-child-clears-parent
  "Test that unregistering clears the child's parent reference."
  (let ((node (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child node leaf)
    (is (eq (parent-node leaf) node))
    (unregister-child node "leaf-1")
    (is (null (parent-node leaf)))))

(test unregister-child-reduces-count
  "Test that unregistering reduces child count."
  (let ((node (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-2")))
    (register-child node leaf-1)
    (register-child node leaf-2)
    (is (= (hash-table-count (node-children node)) 2))
    (unregister-child node "leaf-1")
    (is (= (hash-table-count (node-children node)) 1))))

;;;; ============================================================================
;;;; Tests: Node Depth Calculation
;;;; ============================================================================

(test node-depth-root
  "Test depth of root node is 0."
  (let ((root (make-swarm-node "root")))
    (is (= (node-depth root) 0))))

(test node-depth-child
  "Test depth of direct child is 1."
  (let ((root (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child root leaf)
    (is (= (node-depth leaf) 1))))

(test node-depth-grandchild
  "Test depth of grandchild is 2."
  (let ((root (make-swarm-node "root"))
        (cluster (make-swarm-node "cluster"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child root cluster)
    (register-child cluster leaf)
    (is (= (node-depth leaf) 2))))

(test node-depth-multi-level
  "Test depth calculation through multiple levels."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (= (node-depth root) 0))
    (is (= (node-depth leaf-a) 1))
    (is (= (node-depth leaf-b) 1))
    (is (= (node-depth cluster-1) 1))
    (is (= (node-depth leaf-c) 2))
    (is (= (node-depth leaf-d) 2))))

;;;; ============================================================================
;;;; Tests: Tree Statistics
;;;; ============================================================================

(test tree-height-single-node
  "Test tree height with only root node."
  (let ((root (make-swarm-node "root")))
    (is (= (tree-height root) 0))))

(test tree-height-two-levels
  "Test tree height with two levels."
  (let ((root (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child root leaf)
    (is (= (tree-height root) 1))))

(test tree-height-three-levels
  "Test tree height with three levels."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (= (tree-height root) 2))))

(test tree-size-single-node
  "Test tree size with only root node."
  (let ((root (make-swarm-node "root")))
    (is (= (tree-size root) 1))))

(test tree-size-multiple-nodes
  "Test tree size with multiple nodes."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    ;; root + leaf-a + leaf-b + cluster-1 + leaf-c + leaf-d = 6
    (is (= (tree-size root) 6))))

(test leaf-count-no-leaves
  "Test leaf count when node has no leaves (impossible for leaf)."
  (let ((node (make-swarm-node "node")))
    (is (= (leaf-count node) 0))))

(test leaf-count-all-leaves
  "Test leaf count when all children are leaves."
  (let ((root (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-2")))
    (register-child root leaf-1)
    (register-child root leaf-2)
    (is (= (leaf-count root) 2))))

(test leaf-count-mixed
  "Test leaf count with mixed leaves and nodes."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    ;; leaf-a, leaf-b, leaf-c, leaf-d = 4 leaves
    (is (= (leaf-count root) 4))))

(test node-count-no-nodes
  "Test node count with only leaves."
  (let ((root (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-2")))
    (register-child root leaf-1)
    (register-child root leaf-2)
    ;; root + cluster-1 = 2 nodes
    (is (= (node-count root) 1))))  ; Only root

(test node-count-with-inner-nodes
  "Test node count with inner nodes."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    ;; root + cluster-1 = 2 nodes
    (is (= (node-count root) 2))))

;;;; ============================================================================
;;;; Tests: Tree Traversal (DFS)
;;;; ============================================================================

(test dfs-traverse-single-node
  "Test DFS traversal with single node."
  (let ((root (make-swarm-node "root")))
    (let ((visited (dfs-traverse root)))
      (is (= (length visited) 1))
      (is (eq (first visited) root)))))

(test dfs-traverse-multiple-levels
  "Test DFS traversal with multiple levels."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((visited (dfs-traverse root)))
      (is (= (length visited) 6))
      ;; Root should be first
      (is (eq (first visited) root))
      ;; All nodes should be visited
      (is (member root visited))
      (is (member leaf-a visited))
      (is (member leaf-b visited))
      (is (member cluster-1 visited))
      (is (member leaf-c visited))
      (is (member leaf-d visited)))))

(test find-node-by-id
  "Test finding a node by ID in tree."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (eq (find-node root "root") root))
    (is (eq (find-node root "leaf-a") leaf-a))
    (is (eq (find-node root "cluster-1") cluster-1))
    (is (eq (find-node root "leaf-c") leaf-c))))

(test find-node-nonexistent
  "Test finding non-existent node returns nil."
  (let ((root (make-swarm-node "root")))
    (is (null (find-node root "nonexistent")))))

(test collect-nodes-all
  "Test collecting all nodes matching predicate."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((all-nodes (collect-nodes root (constantly t))))
      (is (= (length all-nodes) 6)))))

(test collect-nodes-leaves-only
  "Test collecting only leaf nodes."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((leaves (collect-nodes root #'swarm-leaf-p)))
      (is (= (length leaves) 4))
      (is (member leaf-a leaves))
      (is (member leaf-b leaves))
      (is (member leaf-c leaves))
      (is (member leaf-d leaves)))))

;;;; ============================================================================
;;;; Tests: Tree Traversal (BFS)
;;;; ============================================================================

(test bfs-traverse-single-node
  "Test BFS traversal with single node."
  (let ((root (make-swarm-node "root")))
    (let ((visited (bfs-traverse root)))
      (is (= (length visited) 1))
      (is (eq (first visited) root)))))

(test bfs-traverse-level-order
  "Test BFS traversal visits nodes in level order."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((visited (bfs-traverse root)))
      ;; BFS should visit level 0 first, then level 1, then level 2
      (is (= (length visited) 6))
      (is (eq (first visited) root))
      ;; Level 1 should come before level 2
      (let ((root-idx 0)
            (leaf-a-idx (position leaf-a visited))
            (cluster-1-idx (position cluster-1 visited))
            (leaf-c-idx (position leaf-c visited)))
        (is (< root-idx leaf-a-idx))
        (is (< leaf-a-idx leaf-c-idx))
        (is (< cluster-1-idx leaf-c-idx))))))

(test nodes-at-depth-level-0
  "Test getting nodes at depth 0 (root)."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((nodes (nodes-at-depth root 0)))
      (is (= (length nodes) 1))
      (is (eq (first nodes) root)))))

(test nodes-at-depth-level-1
  "Test getting nodes at depth 1."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((nodes (nodes-at-depth root 1)))
      (is (= (length nodes) 3))
      (is (member leaf-a nodes))
      (is (member leaf-b nodes))
      (is (member cluster-1 nodes)))))

(test nodes-at-depth-level-2
  "Test getting nodes at depth 2."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((nodes (nodes-at-depth root 2)))
      (is (= (length nodes) 2))
      (is (member leaf-c nodes))
      (is (member leaf-d nodes)))))

(test nodes-at-depth-invalid
  "Test getting nodes at invalid depth returns empty."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((nodes (nodes-at-depth root 10)))
      (is (null nodes)))))

;;;; ============================================================================
;;;; Tests: Path Operations
;;;; ============================================================================

(test node-path-root
  "Test path of root is empty list."
  (let ((root (make-swarm-node "root")))
    (is (null (node-path root)))))

(test node-path-child
  "Test path of direct child."
  (let ((root (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child root leaf)
    (let ((path (node-path leaf)))
      (is (= (length path) 1))
      (is (string= (first path) "root")))))

(test node-path-grandchild
  "Test path of grandchild."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((path (node-path leaf-c)))
      (is (= (length path) 2))
      (is (string= (first path) "cluster-1"))
      (is (string= (second path) "root")))))

(test path-to-node
  "Test finding path to specific node."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((path (path-to-node root "leaf-c")))
      (is (not (null path)))
      (is (member "leaf-c" path)))))

(test common-ancestor-sibling
  "Test finding common ancestor of siblings."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((ancestor (common-ancestor leaf-a leaf-b)))
      (is (eq ancestor root)))))

(test common-ancestor-parent-child
  "Test finding common ancestor of parent and child."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((ancestor (common-ancestor root leaf-a)))
      (is (eq ancestor root)))))

(test distance-between-siblings
  "Test distance between sibling nodes."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((dist (distance-between leaf-a leaf-b)))
      (is (= dist 2)))))  ; leaf-a -> root -> leaf-b

(test distance-between-same-node
  "Test distance between same node is 0."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((dist (distance-between leaf-a leaf-a)))
      (is (= dist 0)))))

;;;; ============================================================================
;;;; Tests: Tree Validation
;;;; ============================================================================

(test validate-tree-valid
  "Test validation of valid tree."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (validate-tree root))))

(test validate-tree-single-node
  "Test validation of single node tree."
  (let ((root (make-swarm-node "root")))
    (is (validate-tree root))))

(test detect-cycles-none
  "Test cycle detection on acyclic tree."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (null (detect-cycles root)))))

(test find-orphans_none
  "Test finding orphans when none exist."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (null (find-orphans root)))))

(test find-root-from-child
  "Test finding root from arbitrary child."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (eq (find-root leaf-c) root))))

(test find-root-from-root
  "Test finding root when starting from root."
  (let ((root (make-swarm-node "root")))
    (is (eq (find-root root) root))))

;;;; ============================================================================
;;;; Tests: Tree Copying
;;;; ============================================================================

(test copy-tree-single-node
  "Test copying single node tree."
  (let ((original (make-swarm-node "root")))
    (let ((copy (copy-swarm-tree original)))
      (is (not (eq copy original)))
      (is (string= (swarm-id copy) (swarm-id original)))
      (is (null (parent-node copy))))))

(test copy-tree-structure
  "Test that copy preserves tree structure."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((copy (copy-swarm-tree root)))
      ;; Copy should have same structure
      (is (= (tree-size copy) (tree-size root)))
      (is (= (tree-height copy) (tree-height root)))
      (is (= (leaf-count copy) (leaf-count root))))))

(test copy-tree-independence
  "Test that copy is independent of original."
  (let ((original (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child original leaf)
    (let ((copy (copy-swarm-tree original)))
      ;; Modify copy
      (register-child copy (make-swarm-leaf "leaf-2"))
      ;; Original should be unchanged
      (is (= (hash-table-count (node-children original)) 1))
      (is (= (hash-table-count (node-children copy)) 2)))))

;;;; ============================================================================
;;;; Tests: Tree Pruning
;;;; ============================================================================

(test prune-subtree-leaf
  "Test pruning a leaf node."
  (let ((root (make-swarm-node "root"))
        (leaf-a (make-swarm-leaf "leaf-a"))
        (leaf-b (make-swarm-leaf "leaf-b")))
    (register-child root leaf-a)
    (register-child root leaf-b)
    (is (= (tree-size root) 3))
    ;; Prune leaf-a
    (prune-subtree root "leaf-a")
    (is (= (tree-size root) 2))
    (is (null (get-child root "leaf-a")))))

(test prune-subtree-with-children
  "Test pruning a subtree with children."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (is (= (tree-size root) 6))
    ;; Prune cluster-1 (which has 2 children)
    (prune-subtree root "cluster-1")
    (is (= (tree-size root) 3))  ; root, leaf-a, leaf-b
    (is (null (get-child root "cluster-1")))
    (is (null (find-node root "leaf-c")))))

;;;; ============================================================================
;;;; Tests: Tree Walking (Functional)
;;;; ============================================================================

(test walk-tree-simple
  "Test functional tree walk."
  (let ((root (make-swarm-node "root"))
        (leaf-1 (make-swarm-leaf "leaf-1"))
        (leaf-2 (make-swarm-leaf "leaf-2")))
    (register-child root leaf-1)
    (register-child root leaf-2)
    (let ((ids nil))
      (walk-tree root (lambda (node) (push (swarm-id node) ids)))
      (is (= (length ids) 3))
      (is (member "root" ids))
      (is (member "leaf-1" ids))
      (is (member "leaf-2" ids)))))

(test map-tree-ids
  "Test functional tree mapping."
  (let ((root (make-swarm-node "root"))
        (leaf (make-swarm-leaf "leaf-1")))
    (register-child root leaf)
    (let ((ids (map-tree root #'swarm-id)))
      (is (= (length ids) 2))
      (is (member "root" ids))
      (is (member "leaf-1" ids)))))

(test filter-tree-leaves
  "Test filtering tree for leaf nodes."
  (destructuring-bind (root leaf-a leaf-b cluster-1 leaf-c leaf-d)
      (setup-simple-tree)
    (let ((leaves (filter-tree root #'swarm-leaf-p)))
      (is (= (length leaves) 4))
      (is (every #'swarm-leaf-p leaves)))))

;;;; ============================================================================
;;;; Tests: Edge Cases
;;;; ============================================================================

(test empty-tree-operations
  "Test operations on tree with only root."
  (let ((root (make-swarm-node "root")))
    (is (= (tree-height root) 0))
    (is (= (tree-size root) 1))
    (is (= (leaf-count root) 0))
    (is (= (node-count root) 1))
    (is (null (list-children root)))
    (is (= (length (dfs-traverse root)) 1))))

(test deeply-nested-tree
  "Test operations on deeply nested tree (10 levels)."
  (let ((nodes (list (make-swarm-node "root"))))
    ;; Build chain of 10 nodes
    (dotimes (i 9)
      (let ((new-node (make-swarm-node (format nil "node-~D" (1+ i)))))
        (register-child (first nodes) new-node)
        (push new-node nodes)))
    (let ((root (first (reverse nodes))))
      (let ((deepest (first nodes)))
        (is (= (node-depth deepest) 9))
        (is (= (tree-height root) 9))
        (is (= (tree-size root) 10))))))

(test extreme-tree-depth
  "Stress test recursion with a deep chain (override with SW4RM_TREE_STRESS_DEPTH)."
  (let* ((env-depth (uiop:getenv "SW4RM_TREE_STRESS_DEPTH"))
         (depth (or (and env-depth
                         (> (length env-depth) 0)
                         (parse-integer env-depth :junk-allowed t))
                    200)))
    (when (or (null depth) (<= depth 0))
      (setf depth 200))
    (let ((root (make-swarm-node "root"))
          (current nil))
      (setf current root)
      (dotimes (i depth)
        (let ((child (make-swarm-node (format nil "node-~D" i))))
          (register-child current child)
          (setf current child)))
      (is (= (node-depth current) depth))
      (is (= (tree-height root) depth)))))

(test large-breadth-tree
  "Test tree with many children (100 leaves at one level)."
  (let ((root (make-swarm-node "root")))
    (dotimes (i 100)
      (register-child root (make-swarm-leaf (format nil "leaf-~D" i))))
    (is (= (hash-table-count (node-children root)) 100))
    (is (= (leaf-count root) 100))
    (is (= (tree-size root) 101))))

(test node-with-special-characters-in-id
  "Test nodes with special characters in IDs."
  (let ((node (make-swarm-node "node-with-dashes-and.dots_123")))
    (is (string= (swarm-id node) "node-with-dashes-and.dots_123"))))

;;;; ============================================================================
;;;; Tests: Metrics Collection
;;;; ============================================================================

(test node-metrics-creation
  "Test that node metrics are initialized on creation."
  (let ((node (make-swarm-node "root")))
    (is (not (null (node-metrics node))))))

(test record-metric-gauge
  "Test recording gauge metrics."
  (let ((node (make-swarm-node "root")))
    (record-metric (node-metrics node) :test-metric 42 :type :gauge)
    ;; Verify metric was recorded
    (is (not (null (node-metrics node))))))

(test record-metric-counter
  "Test recording counter metrics."
  (let ((node (make-swarm-node "root")))
    (record-metric (node-metrics node) :counter-test 1 :type :counter)
    (record-metric (node-metrics node) :counter-test 1 :type :counter)
    ;; Counter should be incremented
    (is (not (null (node-metrics node))))))

;;;; ============================================================================
;;;; Tests: Status Management
;;;; ============================================================================

(test node-status-initialization
  "Test that node status defaults to :initializing."
  (let ((node (make-swarm-node "root")))
    (is (eq (node-status node) :initializing))))

(test node-status-transitions
  "Test node status transitions."
  (let ((node (make-swarm-node "root")))
    (setf (node-status node) :ready)
    (is (eq (node-status node) :ready))
    (setf (node-status node) :degraded)
    (is (eq (node-status node) :degraded))
    (setf (node-status node) :shutting-down)
    (is (eq (node-status node) :shutting-down))))

;;;; ============================================================================
;;;; Tests: Print Object Methods
;;;; ============================================================================

(test print-swarm-tree
  "Test printing swarm-tree for REPL debugging."
  (let ((node (make-swarm-node "root")))
    (is (not (null (with-output-to-string (s)
                     (print-object node s)))))))

(test print-swarm-leaf
  "Test printing swarm-leaf for REPL debugging."
  (let ((leaf (make-swarm-leaf "leaf-1")))
    (is (not (null (with-output-to-string (s)
                     (print-object leaf s)))))))

(test print-swarm-node
  "Test printing swarm-node for REPL debugging."
  (let ((node (make-swarm-node "node")))
    (is (not (null (with-output-to-string (s)
                     (print-object node s)))))))

;;;; End of file
