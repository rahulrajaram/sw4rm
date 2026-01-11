;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; tree/traversal.lisp
;;;;
;;;; Tree Traversal and Manipulation Operations for SW4RM Orchestrator
;;;;
;;;; This module provides comprehensive tree traversal, query, and manipulation
;;;; operations for the SwarmTree ADT. These operations enable:
;;;;   - Path-based navigation (node-path, path-to-node, common-ancestor)
;;;;   - Functional traversal (walk-tree, map-tree, filter-tree)
;;;;   - Depth-first operations (dfs-traverse, find-node, collect-nodes)
;;;;   - Breadth-first operations (bfs-traverse, nodes-at-depth)
;;;;   - Tree statistics (tree-height, tree-size, tree-balanced-p)
;;;;   - Tree modification (prune-subtree, graft-subtree, copy-swarm-tree)
;;;;   - Path-based queries (resolve-path, path-matches-p)
;;;;   - Tree validation (validate-tree, detect-cycles)
;;;;
;;;; These operations are essential for:
;;;;   - Topology discovery and visualization
;;;;   - Advanced routing algorithms
;;;;   - Tree maintenance and rebalancing
;;;;   - Diagnostic and debugging tools
;;;;   - Meta-operations on tree structure
;;;;
;;;; Architecture:
;;;;   All operations are pure functions (except tree modification ops) that
;;;;   operate on the SwarmTree ADT without side effects. They use the generic
;;;;   function protocol defined in types.lisp:
;;;;     - LIST-CHILDREN: Get children of a node
;;;;     - GET-CHILD: Get child by ID
;;;;     - SWARM-ID: Get node ID
;;;;     - PARENT-NODE: Get parent reference
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.tree)

;;;; ============================================================================
;;;; Path Operations
;;;; ============================================================================

(defun node-path (node)
  "Return ancestor path from node's parent up to root.

  Args:
    node - SWARM-TREE instance

  Returns:
    List of ancestor node IDs (strings), starting with the parent.

  Examples:
    (node-path root) => NIL
    (node-path child) => (\"root\")
    (node-path grandchild) => (\"cluster\" \"root\")"
  (declare (type swarm-tree node))

  (let ((path nil))
    (loop for current = (parent-node node) then (parent-node current)
          while current
          do (push (swarm-id current) path))
    (nreverse path)))

(defun path-to-node (root path)
  "Navigate from root via path list, or compute path to node ID.

  Traverses the tree from ROOT following the sequence of node IDs in PATH.
  Returns the node at the end of the path, or NIL if path is invalid.

  Args:
    root - SWARM-TREE instance (starting point)
    path - List of node IDs to follow (strings)

  Returns:
    SWARM-TREE instance at end of path, or NIL if path not found.

  Examples:
    ;; Navigate to direct child
    (path-to-node root '(\"leaf-a\"))
    => #<SWARM-LEAF id=\"leaf-a\" ...>

    ;; Navigate to grandchild
    (path-to-node root '(\"cluster-a\" \"leaf-1\"))
    => #<SWARM-LEAF id=\"leaf-1\" ...>

    ;; Empty path returns root
    (path-to-node root '())
    => root

    ;; Invalid path
    (path-to-node root '(\"nonexistent\"))
    => NIL

  Algorithm:
    1. If path is empty, return root
    2. Otherwise, get child with first ID in path
    3. Recursively navigate to child with rest of path
    4. Return NIL if any step fails

  See Also:
    NODE-PATH, RESOLVE-PATH, FIND-DESCENDANT"
  (declare (type swarm-tree root))

  (cond
    ((stringp path)
     (let ((node (find-node root path)))
       (when node
         (cons (swarm-id node) (node-path node)))))
    ((listp path)
     (cond
       ((null path)
        root)
       (t
        (let ((child-id (first path)))
          (cond
            ((typep root 'swarm-leaf)
             nil)
            ((typep root 'swarm-node)
             (let ((child (get-child root child-id)))
               (when child
                 (path-to-node child (rest path)))))
            (t nil))))))
    (t
     (error "PATH-TO-NODE expects a path list or node ID string, got: ~S" path))))

(defun common-ancestor (node1 node2)
  "Find lowest common ancestor of two nodes.

  Returns the deepest node that is an ancestor of both NODE1 and NODE2.
  If one node is an ancestor of the other, returns that ancestor.

  Args:
    node1 - SWARM-TREE instance
    node2 - SWARM-TREE instance

  Returns:
    SWARM-TREE instance that is lowest common ancestor, or NIL if nodes
    are in different trees (no common ancestor).

  Examples:
    ;; Siblings
    (common-ancestor leaf-a leaf-b)
    => #<SWARM-NODE id=\"root\" ...>

    ;; Parent-child
    (common-ancestor root leaf-a)
    => root

    ;; Same node
    (common-ancestor leaf-a leaf-a)
    => leaf-a

  Algorithm:
    1. Get paths from root for both nodes
    2. Find longest common prefix of paths
    3. Return node at end of common prefix

  Notes:
    This is O(depth1 + depth2) in time and space.

  See Also:
    NODE-PATH, DISTANCE-BETWEEN"
  (declare (type swarm-tree node1 node2))

  (let ((seen (make-hash-table :test #'eq)))
    (loop for current = node1 then (parent-node current)
          while current
          do (setf (gethash current seen) t))
    (loop for current = node2 then (parent-node current)
          while current
          do (when (gethash current seen)
               (return current)))))

(defun distance-between (node1 node2)
  "Calculate number of hops between two nodes.

  Returns the minimum number of edges to traverse from NODE1 to NODE2
  through their tree structure. Distance is symmetric.

  Args:
    node1 - SWARM-TREE instance
    node2 - SWARM-TREE instance

  Returns:
    Non-negative integer representing hop distance, or NIL if nodes are
    in different trees.

  Examples:
    ;; Same node
    (distance-between leaf-a leaf-a)
    => 0

    ;; Parent-child
    (distance-between root leaf-a)
    => 1

    ;; Siblings
    (distance-between leaf-a leaf-b)
    => 2  ; up to root, down to sibling

  Algorithm:
    1. Find common ancestor
    2. Distance = (depth of node1 - depth of ancestor) +
                  (depth of node2 - depth of ancestor)

  See Also:
    COMMON-ANCESTOR, NODE-DEPTH"
  (declare (type swarm-tree node1 node2))

  (let ((ancestor (common-ancestor node1 node2)))
    (when ancestor
      (let ((path1 (node-path node1))
            (path2 (node-path node2))
            (ancestor-path (node-path ancestor)))
        (+ (- (length path1) (length ancestor-path))
           (- (length path2) (length ancestor-path)))))))

;;;; ============================================================================
;;;; Tree Walking (Functional Traversal)
;;;; ============================================================================

(defun walk-tree (root fn &key (order :pre))
  "Call function FN on each node in tree.

  Traverses the tree rooted at ROOT and applies FN to each node.
  The traversal order is controlled by the ORDER keyword.

  Args:
    root - SWARM-TREE instance (starting point)
    fn - Function of one argument (node) to call on each node
    order - Traversal order (:PRE, :POST, or :LEVEL)
      :PRE - Visit parent before children (default)
      :POST - Visit children before parent
      :LEVEL - Visit nodes level-by-level (breadth-first)

  Returns:
    NIL (called for side effects).

  Side Effects:
    - Calls FN on each node in specified order

  Examples:
    ;; Print all node IDs in pre-order
    (walk-tree root (lambda (node) (format t \"~A~%\" (swarm-id node))))

    ;; Collect all node IDs in post-order
    (let ((ids nil))
      (walk-tree root (lambda (node) (push (swarm-id node) ids))
                 :order :post)
      ids)

    ;; Level-order traversal
    (walk-tree root #'process-node :order :level)

  See Also:
    MAP-TREE, FILTER-TREE, DFS-TRAVERSE, BFS-TRAVERSE"
  (declare (type swarm-tree root)
           (type function fn)
           (type (member :pre :post :level) order))

  (ecase order
    (:pre
     ;; Pre-order: parent before children
     (funcall fn root)
     (when (typep root 'swarm-node)
       (dolist (child (list-children root))
         (walk-tree child fn :order :pre))))

    (:post
     ;; Post-order: children before parent
     (when (typep root 'swarm-node)
       (dolist (child (list-children root))
         (walk-tree child fn :order :post)))
     (funcall fn root))

    (:level
     ;; Level-order: breadth-first
     (let ((queue (list root)))
       (loop while queue
             do (let ((node (pop queue)))
                  (funcall fn node)
                  (when (typep node 'swarm-node)
                    (setf queue (append queue (list-children node))))))))))

(defun walk-leaves (root fn)
  "Call function FN on each leaf node.

  Traverses the tree rooted at ROOT and applies FN only to leaf nodes
  (SWARM-LEAF instances).

  Args:
    root - SWARM-TREE instance (starting point)
    fn - Function of one argument (leaf) to call on each leaf

  Returns:
    NIL (called for side effects).

  Examples:
    ;; Print all leaf IDs
    (walk-leaves root (lambda (leaf) (format t \"Leaf: ~A~%\" (swarm-id leaf))))

    ;; Collect leaf capabilities
    (let ((caps nil))
      (walk-leaves root (lambda (leaf) (push (leaf-capabilities leaf) caps)))
      caps)

  See Also:
    WALK-NODES, WALK-TREE, COLLECT-ALL-LEAVES"
  (declare (type swarm-tree root)
           (type function fn))

  (walk-tree root
             (lambda (node)
               (when (typep node 'swarm-leaf)
                 (funcall fn node)))))

(defun walk-nodes (root fn)
  "Call function FN on each non-leaf node (orchestrator nodes).

  Traverses the tree rooted at ROOT and applies FN only to inner nodes
  (SWARM-NODE instances).

  Args:
    root - SWARM-TREE instance (starting point)
    fn - Function of one argument (node) to call on each non-leaf

  Returns:
    NIL (called for side effects).

  Examples:
    ;; Print all orchestrator node IDs
    (walk-nodes root (lambda (node) (format t \"Node: ~A~%\" (swarm-id node))))

  See Also:
    WALK-LEAVES, WALK-TREE, COLLECT-ALL-NODES"
  (declare (type swarm-tree root)
           (type function fn))

  (walk-tree root
             (lambda (node)
               (when (typep node 'swarm-node)
                 (funcall fn node)))))

(defun map-tree (root fn)
  "Map function FN over tree, return new tree structure.

  Creates a new tree with the same structure as ROOT, where each node
  is the result of applying FN to the corresponding node in ROOT.

  Args:
    root - SWARM-TREE instance (source tree)
    fn - Function of one argument (node) that returns new node value

  Returns:
    New tree structure with same topology, transformed nodes.

  Notes:
    This creates a new tree structure. The original tree is not modified.
    The function FN should return values suitable for tree nodes.

  Examples:
    ;; Create tree of node IDs
    (map-tree root #'swarm-id)
    => (\"root\" (\"cluster-a\" (\"leaf-1\") (\"leaf-2\")) ...)

    ;; Create tree of node depths
    (map-tree root #'node-depth)
    => (0 (1 (2) (2)) ...)

  See Also:
    WALK-TREE, FILTER-TREE"
  (declare (type swarm-tree root)
           (type function fn))

  (let ((value (funcall fn root)))
    (if (typep root 'swarm-node)
        (cons value
              (mapcar (lambda (child) (map-tree child fn))
                      (list-children root)))
        value)))

(defun filter-tree (root predicate)
  "Filter tree nodes matching predicate, return matching nodes as flat list.

  Traverses the tree rooted at ROOT and collects all nodes for which
  PREDICATE returns true.

  Args:
    root - SWARM-TREE instance (starting point)
    predicate - Function of one argument (node) returning boolean

  Returns:
    List of SWARM-TREE instances matching predicate.

  Examples:
    ;; Find all leaves
    (filter-tree root (lambda (node) (typep node 'swarm-leaf)))

    ;; Find all ready nodes
    (filter-tree root (lambda (node) (eq (node-status node) :ready)))

    ;; Find all nodes at depth 2
    (filter-tree root (lambda (node) (= (node-depth node) 2)))

  See Also:
    WALK-TREE, MAP-TREE, FIND-NODE"
  (declare (type swarm-tree root)
           (type function predicate))

  (let ((matches nil))
    (walk-tree root
               (lambda (node)
                 (when (funcall predicate node)
                   (push node matches))))
    (nreverse matches)))

;;;; ============================================================================
;;;; Depth-First Operations
;;;; ============================================================================

(defun dfs-traverse (root &key visitor)
  "Depth-first traversal with visitor pattern.

  Performs depth-first traversal of the tree, calling VISITOR functions
  at key points. The visitor is a plist with optional function keys:
    :PRE-VISIT - Called before visiting children
    :POST-VISIT - Called after visiting children
    :LEAF-VISIT - Called on leaf nodes

  Args:
    root - SWARM-TREE instance (starting point)
    visitor - Plist of visitor functions

  Returns:
    NIL (called for side effects).

  Examples:
    ;; Track traversal path
    (let ((path nil))
      (dfs-traverse root
        :visitor (list :pre-visit (lambda (node)
                                    (push (swarm-id node) path))
                       :post-visit (lambda (node)
                                     (pop path)))))

    ;; Collect leaves and compute stats
    (let ((leaf-count 0))
      (dfs-traverse root
        :visitor (list :leaf-visit (lambda (leaf)
                                     (incf leaf-count)))))

  See Also:
    BFS-TRAVERSE, WALK-TREE"
  (declare (type swarm-tree root)
           (type list visitor))

  (let ((visited nil))
    (labels ((visit-node (node)
               (let ((pre-visit (getf visitor :pre-visit))
                     (post-visit (getf visitor :post-visit))
                     (leaf-visit (getf visitor :leaf-visit)))
                 ;; Record visit in pre-order
                 (push node visited)
                 (when pre-visit
                   (funcall pre-visit node))
                 (cond
                   ((typep node 'swarm-leaf)
                    (when leaf-visit
                      (funcall leaf-visit node)))
                   ((typep node 'swarm-node)
                    (dolist (child (list-children node))
                      (visit-node child))))
                 (when post-visit
                   (funcall post-visit node)))))
      (visit-node root)
      (nreverse visited))))

(defun find-node (root predicate)
  "Find first node matching predicate using depth-first search.

  Searches the tree rooted at ROOT in depth-first order and returns
  the first node for which PREDICATE returns true.

  Args:
    root - SWARM-TREE instance (starting point)
    predicate - Function of one argument (node) returning boolean

  Returns:
    First SWARM-TREE instance matching predicate, or NIL if none found.

  Examples:
    ;; Find node by ID
    (find-node root (lambda (node) (string= (swarm-id node) \"leaf-a\")))
    => #<SWARM-LEAF id=\"leaf-a\" ...>

    ;; Find first degraded node
    (find-node root (lambda (node) (eq (node-status node) :degraded)))

    ;; Find first leaf with capability
    (find-node root (lambda (node)
                      (and (typep node 'swarm-leaf)
                           (member :nlp (leaf-capabilities node)))))

  See Also:
    COLLECT-NODES, FILTER-TREE, FIND-LEAF-BY-ID"
  (declare (type swarm-tree root))

  (let ((pred (if (stringp predicate)
                  (lambda (node)
                    (string= (swarm-id node) predicate))
                  predicate)))
    (unless (functionp pred)
      (error "FIND-NODE expects a predicate function or node ID string, got: ~S"
             predicate))

    (cond
      ;; Check if root matches
      ((funcall pred root)
       root)

      ;; If root is a node, search children
      ((typep root 'swarm-node)
       (dolist (child (list-children root))
         (let ((found (find-node child pred)))
           (when found
             (return-from find-node found)))))

      ;; Not found
      (t nil))))

(defun collect-nodes (root predicate)
  "Collect all nodes matching predicate using depth-first search.

  This is equivalent to FILTER-TREE but with a clearer name for
  DFS-specific usage.

  Args:
    root - SWARM-TREE instance (starting point)
    predicate - Function of one argument (node) returning boolean

  Returns:
    List of SWARM-TREE instances matching predicate.

  Examples:
    ;; Collect all leaves
    (collect-nodes root #'swarm-leaf-p)

    ;; Collect all ready nodes
    (collect-nodes root (lambda (node) (eq (node-status node) :ready)))

  See Also:
    FIND-NODE, FILTER-TREE"
  (filter-tree root predicate))

;;;; ============================================================================
;;;; Breadth-First Operations
;;;; ============================================================================

(defun bfs-traverse (root &key visitor)
  "Breadth-first traversal with visitor pattern.

  Performs breadth-first (level-order) traversal of the tree, calling
  VISITOR function on each node.

  Args:
    root - SWARM-TREE instance (starting point)
    visitor - Function of one argument (node), or plist with :VISIT key

  Returns:
    NIL (called for side effects).

  Examples:
    ;; Print nodes level by level
    (bfs-traverse root (lambda (node) (format t \"~A~%\" (swarm-id node))))

    ;; Track depth during traversal
    (bfs-traverse root
      :visitor (list :visit (lambda (node)
                              (format t \"Depth ~D: ~A~%\"
                                      (node-depth node)
                                      (swarm-id node)))))

  See Also:
    DFS-TRAVERSE, WALK-TREE, NODES-AT-DEPTH"
  (declare (type swarm-tree root))

  (let ((visit-fn (if (functionp visitor)
                      visitor
                      (getf visitor :visit)))
        (queue (list root))
        (visited nil))
    (loop while queue
          do (let ((node (pop queue)))
               (push node visited)
               (when visit-fn
                 (funcall visit-fn node))
               (when (typep node 'swarm-node)
                 (setf queue (append queue (list-children node))))))
    (nreverse visited)))

(defun nodes-at-depth (root depth)
  "Return all nodes at given depth.

  Depth is defined as:
    - Root node: depth 0
    - Direct children of root: depth 1
    - Grandchildren of root: depth 2
    - etc.

  Args:
    root - SWARM-TREE instance (starting point)
    depth - Non-negative integer depth level

  Returns:
    List of SWARM-TREE instances at specified depth.

  Examples:
    ;; Get root
    (nodes-at-depth root 0)
    => (#<SWARM-NODE id=\"root\" ...>)

    ;; Get direct children
    (nodes-at-depth root 1)
    => (#<SWARM-NODE id=\"cluster-a\" ...> #<SWARM-LEAF id=\"leaf-b\" ...>)

    ;; Get nodes at depth 2
    (nodes-at-depth root 2)
    => (#<SWARM-LEAF id=\"leaf-1\" ...> ...)

  See Also:
    BFS-TRAVERSE, NODE-DEPTH, TREE-HEIGHT"
  (declare (type swarm-tree root)
           (type (integer 0) depth))

  (cond
    ;; Depth 0 - return root
    ((zerop depth)
     (list root))

    ;; Depth > 0 - recurse to children
    ((typep root 'swarm-node)
     (let ((nodes nil))
       (dolist (child (list-children root))
         (setf nodes (append nodes (nodes-at-depth child (1- depth)))))
       nodes))

    ;; Leaf at depth > 0 - no nodes at that depth
    (t nil)))

(defun find-nearest (root predicate)
  "Find nearest node matching predicate using breadth-first search.

  Searches the tree rooted at ROOT in breadth-first order and returns
  the first node (nearest to root) for which PREDICATE returns true.

  Args:
    root - SWARM-TREE instance (starting point)
    predicate - Function of one argument (node) returning boolean

  Returns:
    Nearest SWARM-TREE instance matching predicate, or NIL if none found.

  Examples:
    ;; Find nearest degraded node
    (find-nearest root (lambda (node) (eq (node-status node) :degraded)))

    ;; Find nearest leaf
    (find-nearest root #'swarm-leaf-p)

  See Also:
    FIND-NODE, BFS-TRAVERSE"
  (declare (type swarm-tree root)
           (type function predicate))

  (let ((queue (list root)))
    (loop while queue
          do (let ((node (pop queue)))
               (cond
                 ;; Found match
                 ((funcall predicate node)
                  (return-from find-nearest node))

                 ;; Add children to queue
                 ((typep node 'swarm-node)
                  (setf queue (append queue (list-children node)))))))

    ;; Not found
    nil))

;;;; ============================================================================
;;;; Tree Statistics
;;;; ============================================================================

(defun tree-height (root)
  "Calculate maximum depth of tree.

  Returns the length of the longest path from ROOT to any leaf.

  Args:
    root - SWARM-TREE instance

  Returns:
    Non-negative integer representing tree height.

  Examples:
    ;; Leaf node has height 0
    (tree-height leaf)
    => 0

    ;; Node with only leaf children has height 1
    (tree-height node-with-leaves)
    => 1

  See Also:
    TREE-SIZE, SUBTREE-DEPTH, NODE-DEPTH"
  (declare (type swarm-tree root))

  (cond
    ;; Leaf has height 0
    ((typep root 'swarm-leaf)
     0)

    ;; Node height is 1 + max child height
    ((typep root 'swarm-node)
     (let ((children (list-children root)))
       (if (null children)
           0
           (1+ (reduce #'max (mapcar #'tree-height children)
                       :initial-value 0)))))

    (t 0)))

(defun tree-size (root)
  "Calculate total number of nodes in tree.

  Counts all nodes in the tree rooted at ROOT (including ROOT itself).

  Args:
    root - SWARM-TREE instance

  Returns:
    Positive integer representing total node count.

  Examples:
    ;; Single leaf
    (tree-size leaf)
    => 1

    ;; Node with 3 children
    (tree-size node-with-3-children)
    => 4  ; node + 3 children

  See Also:
    LEAF-COUNT, NODE-COUNT, SUBTREE-SIZE"
  (declare (type swarm-tree root))

  (cond
    ;; Leaf counts as 1
    ((typep root 'swarm-leaf)
     1)

    ;; Node counts as 1 + sum of child sizes
    ((typep root 'swarm-node)
     (1+ (reduce #'+ (mapcar #'tree-size (list-children root))
                 :initial-value 0)))

    (t 1)))

(defun leaf-count (root)
  "Count number of leaf nodes in tree.

  Counts all SWARM-LEAF instances in the tree rooted at ROOT.

  Args:
    root - SWARM-TREE instance

  Returns:
    Non-negative integer count of leaf nodes.

  Examples:
    ;; Leaf itself
    (leaf-count leaf)
    => 1

    ;; Node with mixed children
    (leaf-count root)
    => 5  ; total leaves across entire tree

  See Also:
    NODE-COUNT, TREE-SIZE, COLLECT-ALL-LEAVES"
  (declare (type swarm-tree root))

  (cond
    ;; Leaf counts as 1
    ((typep root 'swarm-leaf)
     1)

    ;; Node: sum leaf counts of children
    ((typep root 'swarm-node)
     (reduce #'+ (mapcar #'leaf-count (list-children root))
             :initial-value 0))

    (t 0)))

(defun node-count (root)
  "Count number of non-leaf (orchestrator) nodes in tree.

  Counts all SWARM-NODE instances in the tree rooted at ROOT
  (including ROOT itself if it's a node).

  Args:
    root - SWARM-TREE instance

  Returns:
    Non-negative integer count of orchestrator nodes.

  Examples:
    ;; Leaf itself
    (node-count leaf)
    => 0

    ;; Node with children
    (node-count root)
    => 3  ; root + 2 child nodes

  See Also:
    LEAF-COUNT, TREE-SIZE, COLLECT-ALL-NODES"
  (declare (type swarm-tree root))

  (cond
    ;; Leaf doesn't count
    ((typep root 'swarm-leaf)
     0)

    ;; Node counts as 1 + sum of child node counts
    ((typep root 'swarm-node)
     (1+ (reduce #'+ (mapcar #'node-count (list-children root))
                 :initial-value 0)))

    (t 0)))

(defun tree-balanced-p (root &optional (threshold 2))
  "Check if tree is reasonably balanced.

  A tree is considered balanced if the difference between the heights
  of any two subtrees is within THRESHOLD.

  Args:
    root - SWARM-TREE instance
    threshold - Maximum allowed height difference (default: 2)

  Returns:
    T if tree is balanced within threshold, NIL otherwise.

  Examples:
    ;; Perfectly balanced tree
    (tree-balanced-p balanced-tree)
    => T

    ;; Unbalanced tree
    (tree-balanced-p linear-tree)
    => NIL

    ;; Check with custom threshold
    (tree-balanced-p tree :threshold 3)

  Notes:
    This uses a simple heuristic comparing child subtree heights.
    For production use, consider more sophisticated balance metrics.

  See Also:
    TREE-HEIGHT, SUBTREE-DEPTH"
  (declare (type swarm-tree root)
           (type (integer 0) threshold))

  (cond
    ;; Leaf is always balanced
    ((typep root 'swarm-leaf)
     t)

    ;; Check node balance
    ((typep root 'swarm-node)
     (let* ((children (list-children root))
            (heights (mapcar #'tree-height children)))
       (cond
         ;; No children or one child is balanced
         ((< (length heights) 2)
          t)

         ;; Check height difference
         (t
          (let ((max-height (reduce #'max heights :initial-value 0))
                (min-height (reduce #'min heights :initial-value most-positive-fixnum)))
            (and (<= (- max-height min-height) threshold)
                 ;; Recursively check all children
                 (every (lambda (child) (tree-balanced-p child threshold))
                        children)))))))

    (t t)))

;;;; ============================================================================
;;;; Tree Modification
;;;; ============================================================================

(defun prune-subtree (root node-id)
  "Remove subtree rooted at node with NODE-ID.

  This operation removes nodes in place.

  Args:
    root - SWARM-TREE instance (original tree)
    node-id - String ID of node to prune

  Returns:
    ROOT if still present, or NIL if the root itself was pruned.

  Examples:
    ;; Remove a leaf
    (prune-subtree root \"leaf-a\")
    => #<SWARM-NODE ...> ; new tree without leaf-a

  See Also:
    GRAFT-SUBTREE, UNREGISTER-CHILD"
  (declare (type swarm-tree root)
           (type string node-id))

  (cond
    ((string= (swarm-id root) node-id)
     nil)
    ((typep root 'swarm-leaf)
     root)
    ((typep root 'swarm-node)
     (when (get-child root node-id)
       (unregister-child root node-id)
       (return-from prune-subtree root))
     (dolist (child (list-children root))
       (prune-subtree child node-id))
     root)
    (t root)))

(defun copy-swarm-tree (root)
  "Deep copy entire tree structure.

  Creates a complete copy of the tree rooted at ROOT, including all
  descendant nodes. The copy has the same structure but is independent
  of the original.

  Args:
    root - SWARM-TREE instance to copy

  Returns:
    New SWARM-TREE instance with same structure.

  Notes:
    This creates new node instances but preserves IDs, status, and other
    attributes. Parent references are updated to point within the new tree.

  Examples:
    ;; Copy entire tree
    (let ((tree-copy (copy-swarm-tree root)))
      ;; Modifications to tree-copy don't affect root
      ...)

  See Also:
    PRUNE-SUBTREE, GRAFT-SUBTREE"
  (declare (type swarm-tree root))

  (cond
    ;; Copy leaf
    ((typep root 'swarm-leaf)
     (make-instance 'swarm-leaf
                    :id (swarm-id root)
                    :host (leaf-host root)
                    :port (leaf-port root)
                    :capabilities (copy-list (leaf-capabilities root))))

    ;; Copy node
    ((typep root 'swarm-node)
     (let ((new-node (make-instance 'swarm-node
                                    :id (swarm-id root)
                                    :policy (node-policy root))))

       ;; Recursively copy and register children
       (dolist (child (list-children root))
         (register-child new-node (copy-swarm-tree child)))

       new-node))

    (t root)))

;;;; ============================================================================
;;;; Path-Based Queries
;;;; ============================================================================

(defun resolve-path (root path-string)
  "Parse and resolve path string like \"root/cluster/leaf\".

  Parses a slash-separated path string and navigates to the node at
  that path.

  Args:
    root - SWARM-TREE instance (starting point)
    path-string - String path in format \"id1/id2/id3\"

  Returns:
    SWARM-TREE instance at end of path, or NIL if path invalid.

  Examples:
    ;; Navigate to leaf
    (resolve-path root \"root/cluster-a/leaf-1\")
    => #<SWARM-LEAF id=\"leaf-1\" ...>

    ;; Navigate to intermediate node
    (resolve-path root \"root/cluster-a\")
    => #<SWARM-NODE id=\"cluster-a\" ...>

    ;; Root path
    (resolve-path root \"root\")
    => root

  Notes:
    The first element of the path should match the root node ID.
    Empty path components are ignored.

  See Also:
    NODE-TO-PATH-STRING, PATH-TO-NODE"
  (declare (type swarm-tree root)
           (type string path-string))

  ;; Split path string on '/'
  (let* ((path-parts (split-sequence:split-sequence #\/ path-string
                                                     :remove-empty-subseqs t))
         (first-part (first path-parts)))

    ;; Check if first part matches root
    (if (string= first-part (swarm-id root))
        ;; Navigate using rest of path
        (path-to-node root (rest path-parts))
        ;; First part doesn't match root
        nil)))

(defun node-to-path-string (node)
  "Convert node path to \"root/cluster/leaf\" string format.

  Returns the path from root to NODE as a slash-separated string.

  Args:
    node - SWARM-TREE instance

  Returns:
    String path from root to node.

  Examples:
    ;; Root node
    (node-to-path-string root)
    => \"root\"

    ;; Leaf node
    (node-to-path-string leaf)
    => \"root/cluster-a/leaf-1\"

  See Also:
    RESOLVE-PATH, NODE-PATH"
  (declare (type swarm-tree node))

  (let ((path (node-path node)))
    (format nil "~{~A~^/~}" path)))

(defun path-matches-p (path pattern)
  "Check if path matches glob pattern.

  Supports basic glob patterns:
    * - matches any sequence of characters
    ? - matches any single character

  Args:
    path - List of path components (strings)
    pattern - List of pattern components (strings with wildcards)

  Returns:
    T if path matches pattern, NIL otherwise.

  Examples:
    ;; Exact match
    (path-matches-p '(\"root\" \"cluster\" \"leaf\")
                    '(\"root\" \"cluster\" \"leaf\"))
    => T

    ;; Wildcard match
    (path-matches-p '(\"root\" \"cluster-a\" \"leaf-1\")
                    '(\"root\" \"*\" \"leaf-*\"))
    => T

  See Also:
    RESOLVE-PATH, NODE-PATH"
  (declare (type list path pattern))

  (cond
    ;; Both empty - match
    ((and (null path) (null pattern))
     t)

    ;; One empty, other not - no match
    ((or (null path) (null pattern))
     nil)

    ;; Match first components
    (t
     (let ((path-first (first path))
           (pattern-first (first pattern)))
       (cond
         ;; Pattern is * - matches entire rest of path
         ((string= pattern-first "*")
          (or (path-matches-p (rest path) (rest pattern))
              (path-matches-p (rest path) pattern)))

         ;; Exact match - continue
         ((string= path-first pattern-first)
          (path-matches-p (rest path) (rest pattern)))

         ;; No match
         (t nil))))))

;;;; ============================================================================
;;;; Tree Validation
;;;; ============================================================================

(defun validate-tree (root)
  "Check tree consistency and return errors.

  Validates the tree structure and returns any errors found:
    - Orphan nodes (parent reference doesn't match actual parent)
    - Cycles in tree structure
    - Duplicate node IDs
    - Invalid parent-child relationships

  Args:
    root - SWARM-TREE instance to validate

  Returns:
    (values valid-p error-list)
    valid-p - T if tree is valid, NIL if errors found
    error-list - List of error descriptions (strings)

  Examples:
    ;; Valid tree
    (validate-tree root)
    => T, NIL

    ;; Invalid tree
    (validate-tree broken-tree)
    => NIL, (\"Duplicate node ID: leaf-a\" ...)

  See Also:
    DETECT-CYCLES, FIND-ORPHANS"
  (declare (type swarm-tree root))

  (let ((errors nil)
        (seen-ids (make-hash-table :test 'equal)))

    ;; Check for duplicate IDs
    (walk-tree root
               (lambda (node)
                 (let ((node-id (swarm-id node)))
                   (if (gethash node-id seen-ids)
                       (push (format nil "Duplicate node ID: ~A" node-id) errors)
                       (setf (gethash node-id seen-ids) t)))))

    ;; Check parent-child consistency
    (walk-nodes root
                (lambda (node)
                  (dolist (child (list-children node))
                    (unless (eq (parent-node child) node)
                      (push (format nil "Inconsistent parent for child ~A"
                                    (swarm-id child))
                            errors)))))

    ;; Check for cycles
    (let ((cycles (detect-cycles root)))
      (when cycles
        (push (format nil "Cycles detected: ~{~A~^, ~}" cycles) errors)))

    ;; Return validation result
    (values (null errors) (nreverse errors))))

(defun detect-cycles (root)
  "Find any cycles in tree (should be none in valid tree).

  Detects cycles by tracking visited nodes during traversal.

  Args:
    root - SWARM-TREE instance

  Returns:
    List of node IDs involved in cycles, or NIL if no cycles found.

  Examples:
    ;; Valid tree
    (detect-cycles root)
    => NIL

    ;; Tree with cycle
    (detect-cycles broken-tree)
    => (\"node-a\" \"node-b\")

  See Also:
    VALIDATE-TREE"
  (declare (type swarm-tree root))

  (let ((visited (make-hash-table :test 'eq))
        (cycles nil))

    (labels ((visit (node)
               (cond
                 ;; Already visited - cycle detected
                 ((gethash node visited)
                  (push (swarm-id node) cycles))

                 ;; Not visited - mark and recurse
                 (t
                  (setf (gethash node visited) t)
                  (when (typep node 'swarm-node)
                    (dolist (child (list-children node))
                      (visit child)))))))

      (visit root)
      cycles)))

(defun find-orphans (root)
  "Find nodes with parent not in tree.

  Identifies nodes whose parent reference points to a node that is not
  actually an ancestor in the tree structure.

  Args:
    root - SWARM-TREE instance

  Returns:
    List of orphan nodes (SWARM-TREE instances).

  Examples:
    ;; Valid tree
    (find-orphans root)
    => NIL

    ;; Tree with orphan
    (find-orphans broken-tree)
    => (#<SWARM-LEAF id=\"orphan\" ...>)

  See Also:
    VALIDATE-TREE"
  (declare (type swarm-tree root))

  (let ((orphans nil)
        (tree-nodes (make-hash-table :test 'eq)))

    ;; Collect all nodes in tree
    (walk-tree root (lambda (node) (setf (gethash node tree-nodes) t)))

    ;; Check parent references
    (walk-tree root
               (lambda (node)
                 (let ((parent (parent-node node)))
                   (when (and parent
                              (not (gethash parent tree-nodes)))
                     (push node orphans)))))

    orphans))

;;;; ============================================================================
;;;; Helper Functions
;;;; ============================================================================

(defun find-root (node)
  "Find root of tree containing NODE.

  Traverses upward from NODE until a node with no parent is found.

  Args:
    node - SWARM-TREE instance

  Returns:
    SWARM-TREE instance that is root of tree.

  Examples:
    (find-root leaf)
    => #<SWARM-NODE id=\"root\" ...>

  See Also:
    NODE-PATH, NODE-DEPTH"
  (declare (type swarm-tree node))

  (loop for current = node then (parent-node current)
        while (parent-node current)
        finally (return current)))

;;;; End of file
