;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; tree/node.lisp
;;;;
;;;; Concrete implementation of SWARM-NODE operations for the SW4RM orchestrator.
;;;;
;;;; This module implements the orchestrator node routing and tree management
;;;; logic. A SWARM-NODE coordinates multiple child swarms (either leaves or
;;;; other orchestrators) and routes cross-swarm messages between them.
;;;;
;;;; Key operations:
;;;;   - ROUTE-ENVELOPE: Route messages through the tree
;;;;   - RECEIVE-ENVELOPE: Handle meta-operations (status queries, tree commands)
;;;;   - Child management: register, unregister, lookup
;;;;   - Tree operations: find descendants, broadcast, collect leaves
;;;;
;;;; Routing behavior for nodes:
;;;;   1. If target is this node: receive locally (meta-operations)
;;;;   2. If target is direct child: route to child
;;;;   3. If target in routing table: route via next-hop
;;;;   4. If broadcast target: copy and route to all children
;;;;   5. If parent exists: route upward
;;;;   6. Otherwise: reject (no route found)
;;;;
;;;; Architecture:
;;;;   SWARM-NODE instances maintain:
;;;;     - Hash table of children (child-id -> swarm-tree)
;;;;     - Routing table (target-swarm -> next-hop-child)
;;;;     - Orchestration policy (load balancing, failover, etc.)
;;;;     - Aggregated metrics from children
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.tree)

;;;; ============================================================================
;;;; ROUTE-ENVELOPE for SWARM-NODE
;;;; ============================================================================

(defmethod route-envelope ((node swarm-node) envelope)
  "Route envelope through this orchestrator node.

  Routing decision algorithm:
    1. Check hop limit (reject if exceeded)
    2. If target is this node: receive locally (meta-operations)
    3. If target is direct child: route to child
    4. If target in routing table: route via next-hop
    5. If broadcast target: route to all children
    6. If parent exists: route upward (parent knows more)
    7. Otherwise: reject (no route found)

  Args:
    node: SWARM-NODE instance
    envelope: CROSS-SWARM-ENVELOPE to route

  Returns:
    ROUTING-RESULT with decision and target.

  Side Effects:
    - Increments hop count in envelope
    - Adds node ID to envelope path
    - Records routing metrics

  Raises:
    MAX-HOPS-EXCEEDED if hop limit reached
    ENVELOPE-EXPIRED if deadline passed

  Examples:
    ;; Local delivery
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (env (make-cross-swarm-envelope :target-swarm \"root\")))
      (route-envelope node env))
    => #<ROUTING-RESULT decision=:LOCAL ...>

    ;; Route to child
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (child (make-instance 'swarm-leaf :id \"leaf-a\"))
           (env (make-cross-swarm-envelope :target-swarm \"leaf-a\")))
      (register-child node child)
      (route-envelope node env))
    => #<ROUTING-RESULT decision=:CHILD target=\"leaf-a\" ...>

    ;; Broadcast
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (env (make-cross-swarm-envelope :target-swarm \":BROADCAST\")))
      (route-envelope node env))
    => #<ROUTING-RESULT decision=:BROADCAST ...>

  See Also:
    RECEIVE-ENVELOPE, ROUTING-RESULT, REGISTER-CHILD"
  (let ((target-swarm (envelope-target-swarm envelope))
        (node-id (swarm-id node)))

    ;; Check hop limit before routing
    (when (envelope-hop-limit-exceeded-p envelope)
      (error "Hop limit exceeded for envelope ~A (hops: ~A, max: ~A)"
             (envelope-id envelope)
             (envelope-hop-count envelope)
             (envelope-max-hops envelope)))

    ;; Check deadline before routing
    (when (envelope-expired-p envelope)
      (error "Envelope ~A expired (deadline: ~A, now: ~A)"
             (envelope-id envelope)
             (envelope-deadline envelope)
             (get-universal-time)))

    ;; Update path tracking
    (envelope-add-to-path envelope node-id)
    (envelope-increment-hop-count envelope)

    ;; Record routing attempt
    (record-metric (node-metrics node) :envelopes-routed 1 :type :counter)

    (cond
      ;; Case 1: Target is this node - deliver locally (meta-operations)
      ((and target-swarm (string= target-swarm node-id))
       (record-metric (node-metrics node) :local-deliveries 1 :type :counter)
       (receive-envelope node envelope)
       (make-routing-result
        :decision :local
        :target node-id
        :reason "Target swarm matches node ID"))

      ;; Case 2: Broadcast target - route to all children
      ((and target-swarm (string= target-swarm ":BROADCAST"))
       (record-metric (node-metrics node) :broadcast-routes 1 :type :counter)
       (broadcast-to-children node envelope)
       (make-routing-result
        :decision :broadcast
        :target nil
        :reason "Broadcast to all children"))

      ;; Case 3: Target is direct child - route to child
      ((get-child node target-swarm)
       (record-metric (node-metrics node) :child-routes 1 :type :counter)
       (make-routing-result
        :decision :child
        :target target-swarm
        :reason "Target is direct child"))

      ;; Case 4: Target in routing table - route via next-hop
      ;; TODO: Implement once routing-table module is ready
      ;; ((and (routing-table node)
      ;;       (lookup-route (routing-table node) target-swarm))
      ;;  (let ((next-hop (lookup-route (routing-table node) target-swarm)))
      ;;    (make-routing-result
      ;;     :decision :child
      ;;     :target next-hop
      ;;     :reason "Routing via routing table")))

      ;; Case 5: Parent exists - route upward
      ((parent-node node)
       (record-metric (node-metrics node) :parent-routes 1 :type :counter)
       (make-routing-result
        :decision :parent
        :target (swarm-id (parent-node node))
        :reason "Routing to parent (upward routing)"))

      ;; Case 6: No route found - reject
      (t
       (record-metric (node-metrics node) :rejected-routes 1 :type :counter)
       (make-routing-result
        :decision :reject
        :target nil
        :reason (format nil "No route to ~A" target-swarm))))))

;;;; ============================================================================
;;;; RECEIVE-ENVELOPE for SWARM-NODE
;;;; ============================================================================

(defmethod receive-envelope ((node swarm-node) envelope)
  "Receive envelope at this node (handle meta-operations).

  Orchestrator nodes typically do not receive application messages. They
  receive meta-operations such as:
    - Status queries (\"list all children\", \"get metrics\")
    - Tree commands (\"register child\", \"unregister child\")
    - Topology discovery (\"broadcast topology\")
    - Administrative commands (\"shutdown\", \"checkpoint\")

  This implementation handles common meta-operations and logs unknown ones.

  Args:
    node: SWARM-NODE instance
    envelope: CROSS-SWARM-ENVELOPE to receive

  Returns:
    Result depends on operation type (often NIL or acknowledgment).

  Side Effects:
    - Records receipt metrics
    - Logs envelope receipt
    - May modify node state (for commands)

  Examples:
    ;; Status query
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (env (make-cross-swarm-envelope
                  :target-swarm \"root\"
                  :payload '(:operation \"list-children\"))))
      (receive-envelope node env))
    => (:children (\"leaf-a\" \"leaf-b\"))

  See Also:
    ROUTE-ENVELOPE, HANDLE-META-OPERATION"
  (let ((node-id (swarm-id node))
        (env-id (envelope-id envelope))
        (payload (envelope-payload envelope)))

    ;; Log receipt
    (log:info "[NODE ~A] Receiving envelope ~A" node-id env-id)

    ;; Record metric
    (record-metric (node-metrics node) :envelopes-received 1 :type :counter)

    ;; Handle meta-operation based on payload
    (cond
      ;; List children operation
      ((and (listp payload)
            (eq (getf payload :operation) "list-children"))
       (log:info "[NODE ~A] Meta-operation: list-children" node-id)
       (list :operation "list-children"
             :result (mapcar #'swarm-id (list-children node))
             :count (hash-table-count (node-children node))))

      ;; Get metrics operation
      ((and (listp payload)
            (eq (getf payload :operation) "get-metrics"))
       (log:info "[NODE ~A] Meta-operation: get-metrics" node-id)
       (list :operation "get-metrics"
             :node-id node-id
             :metrics (node-metrics node)))

      ;; Get status operation
      ((and (listp payload)
            (eq (getf payload :operation) "get-status"))
       (log:info "[NODE ~A] Meta-operation: get-status" node-id)
       (list :operation "get-status"
             :node-id node-id
             :status (node-status node)
             :children-count (hash-table-count (node-children node))
             :depth (node-depth node)))

      ;; Unknown operation - log and acknowledge
      (t
       (log:warn "[NODE ~A] Received envelope with unknown payload: ~S"
                 node-id payload)
       (list :operation "unknown"
             :envelope-id env-id
             :acknowledged t)))))

;;;; ============================================================================
;;;; Child Management Methods
;;;; ============================================================================

;; Note: Basic REGISTER-CHILD and UNREGISTER-CHILD are already implemented
;; in types.lisp. We extend them here with additional functionality.

(defmethod register-child :after ((node swarm-node) (child swarm-tree))
  "After-method for register-child: update metrics and log.

  This runs after the primary method in types.lisp completes.

  Side effects:
    - Records child registration metric
    - Logs registration event
    - Updates last-modified timestamp"
  (let ((node-id (swarm-id node))
        (child-id (swarm-id child)))

    ;; Record metric
    (record-metric (node-metrics node) :children-registered 1 :type :counter)
    (record-metric (node-metrics node) :children-count
                   (hash-table-count (node-children node))
                   :type :gauge)

    ;; Log registration (DEBUG level to reduce test noise)
    (log:debug "[NODE ~A] Registered child: ~A (type: ~A)"
               node-id child-id (type-of child))))

(defmethod unregister-child :after ((node swarm-node) (child-id string))
  "After-method for unregister-child: update metrics and log.

  This runs after the primary method in types.lisp completes.

  Side effects:
    - Records child unregistration metric
    - Logs unregistration event
    - Updates last-modified timestamp"
  (let ((node-id (swarm-id node)))

    ;; Record metric
    (record-metric (node-metrics node) :children-unregistered 1 :type :counter)
    (record-metric (node-metrics node) :children-count
                   (hash-table-count (node-children node))
                   :type :gauge)

    ;; Log unregistration (DEBUG level to reduce test noise)
    (log:debug "[NODE ~A] Unregistered child: ~A"
               node-id child-id)))

;;;; ============================================================================
;;;; Tree Operations
;;;; ============================================================================

(defun find-descendant (node path)
  "Find descendant node by path.

  A path is a list of node IDs representing the route from this node
  to the target descendant.

  Args:
    node: SWARM-NODE instance (starting point)
    path: List of node IDs (e.g., '(\"cluster-a\" \"leaf-1\"))

  Returns:
    SWARM-TREE instance if found, NIL otherwise.

  Examples:
    ;; Find direct child
    (find-descendant root '(\"leaf-a\"))
    => #<SWARM-LEAF id=\"leaf-a\" ...>

    ;; Find grandchild
    (find-descendant root '(\"cluster-a\" \"leaf-1\"))
    => #<SWARM-LEAF id=\"leaf-1\" ...>

    ;; Not found
    (find-descendant root '(\"nonexistent\"))
    => NIL

  Algorithm:
    1. If path is empty, return this node
    2. Otherwise, get first element of path
    3. Look up child with that ID
    4. If child is SWARM-NODE, recursively search with rest of path
    5. If child is SWARM-LEAF and path has one element, return child
    6. Otherwise return NIL (path extends beyond leaf)

  See Also:
    GET-CHILD, LIST-CHILDREN, COLLECT-ALL-LEAVES"
  (cond
    ;; Base case: empty path means we found it (this node)
    ((null path)
     node)

    ;; Recursive case: navigate to first child in path
    (t
     (let* ((first-id (first path))
            (child (get-child node first-id)))
       (cond
         ;; Child not found
         ((null child)
          nil)

         ;; Child is a node - recurse with rest of path
         ((typep child 'swarm-node)
          (find-descendant child (rest path)))

         ;; Child is a leaf - return it if path is length 1
         ((and (typep child 'swarm-leaf)
               (null (rest path)))
          child)

         ;; Path extends beyond leaf - not found
         (t
          nil))))))

(defun broadcast-to-children (node envelope)
  "Broadcast envelope to all children.

  Creates a copy of the envelope for each child and routes it.
  This implements broadcast semantics for discovery and notifications.

  Args:
    node: SWARM-NODE instance
    envelope: CROSS-SWARM-ENVELOPE to broadcast

  Returns:
    List of routing results (one per child).

  Side Effects:
    - Creates copies of envelope
    - Routes to each child
    - Records broadcast metrics

  Notes:
    Each child receives an independent copy of the envelope with:
      - Same correlation-id (to track related messages)
      - Different message-id (each copy is unique)
      - Target-swarm set to child's ID

  Examples:
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (leaf-a (make-instance 'swarm-leaf :id \"leaf-a\"))
           (leaf-b (make-instance 'swarm-leaf :id \"leaf-b\"))
           (env (make-cross-swarm-envelope
                  :target-swarm \":BROADCAST\"
                  :payload '(:announcement \"hello\"))))
      (register-child node leaf-a)
      (register-child node leaf-b)
      (broadcast-to-children node env))
    => (#<ROUTING-RESULT ...> #<ROUTING-RESULT ...>)

  See Also:
    ROUTE-ENVELOPE, LIST-CHILDREN, COPY-CROSS-SWARM-ENVELOPE"
  (let ((children (list-children node))
        (results nil))

    (log:info "[NODE ~A] Broadcasting envelope ~A to ~A children"
              (swarm-id node)
              (envelope-id envelope)
              (length children))

    ;; Record broadcast metric
    (record-metric (node-metrics node) :broadcast-sends 1 :type :counter)

    ;; Route to each child
    (dolist (child children)
      (let* ((child-id (swarm-id child))
             ;; Create copy of envelope for this child
             (child-envelope (copy-cross-swarm-envelope envelope)))

        ;; Set target to this specific child
        (setf (envelope-target-swarm child-envelope) child-id)

        (log:info "[NODE ~A] Broadcasting to child ~A"
                  (swarm-id node) child-id)

        ;; Route to child and collect result
        (push (route-envelope child child-envelope) results)))

    ;; Return results (in reverse order to match child order)
    (nreverse results)))

(defun collect-all-leaves (node)
  "Collect all leaf descendants of this node.

  Returns a flat list of all SWARM-LEAF instances in the subtree
  rooted at this node. Useful for:
    - Topology discovery
    - Health monitoring (check all leaves)
    - Broadcast to leaves only (skip intermediate orchestrators)

  Args:
    node: SWARM-NODE instance

  Returns:
    List of SWARM-LEAF instances.

  Algorithm:
    1. Initialize empty result list
    2. For each child:
       - If child is SWARM-LEAF, add to result
       - If child is SWARM-NODE, recursively collect its leaves
    3. Return flattened result

  Examples:
    ;; Flat tree
    (let ((node (make-instance 'swarm-node :id \"root\")))
      (register-child node (make-instance 'swarm-leaf :id \"leaf-a\"))
      (register-child node (make-instance 'swarm-leaf :id \"leaf-b\"))
      (collect-all-leaves node))
    => (#<SWARM-LEAF id=\"leaf-a\" ...> #<SWARM-LEAF id=\"leaf-b\" ...>)

    ;; Nested tree
    (let ((root (make-instance 'swarm-node :id \"root\"))
          (cluster (make-instance 'swarm-node :id \"cluster-a\")))
      (register-child cluster (make-instance 'swarm-leaf :id \"leaf-1\"))
      (register-child root cluster)
      (collect-all-leaves root))
    => (#<SWARM-LEAF id=\"leaf-1\" ...>)

  See Also:
    LIST-CHILDREN, FIND-DESCENDANT"
  (let ((leaves nil))
    (dolist (child (list-children node))
      (cond
        ;; Child is a leaf - add it
        ((typep child 'swarm-leaf)
         (push child leaves))

        ;; Child is a node - recurse and append results
        ((typep child 'swarm-node)
         (setf leaves (append (collect-all-leaves child) leaves)))))

    ;; Return in original order
    (nreverse leaves)))

(defun collect-all-nodes (node)
  "Collect all node descendants (excluding leaves).

  Returns a flat list of all SWARM-NODE instances in the subtree
  rooted at this node (including the node itself).

  Args:
    node: SWARM-NODE instance

  Returns:
    List of SWARM-NODE instances.

  Examples:
    (let ((root (make-instance 'swarm-node :id \"root\"))
          (cluster (make-instance 'swarm-node :id \"cluster-a\")))
      (register-child root cluster)
      (collect-all-nodes root))
    => (#<SWARM-NODE id=\"root\" ...> #<SWARM-NODE id=\"cluster-a\" ...>)

  See Also:
    COLLECT-ALL-LEAVES, LIST-CHILDREN"
  (let ((nodes (list node)))  ; Include this node
    (dolist (child (list-children node))
      (when (typep child 'swarm-node)
        (setf nodes (append nodes (collect-all-nodes child)))))
    nodes))

(defun subtree-size (node)
  "Count total number of descendants (nodes + leaves).

  Args:
    node: SWARM-NODE instance

  Returns:
    Integer count of all descendants (including this node).

  Examples:
    (let ((node (make-instance 'swarm-node :id \"root\")))
      (register-child node (make-instance 'swarm-leaf :id \"leaf-a\"))
      (register-child node (make-instance 'swarm-leaf :id \"leaf-b\"))
      (subtree-size node))
    => 3  ; root + leaf-a + leaf-b

  See Also:
    COLLECT-ALL-LEAVES, COLLECT-ALL-NODES"
  (let ((count 1))  ; Count this node
    (dolist (child (list-children node))
      (incf count
            (if (typep child 'swarm-node)
                (subtree-size child)
                1)))  ; Leaf contributes 1
    count))

(defun subtree-depth (node)
  "Calculate maximum depth of subtree rooted at this node.

  Depth is defined as:
    - Node with no children: depth 0
    - Node with only leaf children: depth 1
    - Node with node children: 1 + max(child depths)

  Args:
    node: SWARM-NODE instance

  Returns:
    Non-negative integer representing maximum depth.

  Examples:
    ;; No children
    (subtree-depth (make-instance 'swarm-node :id \"empty\"))
    => 0

    ;; Only leaves
    (let ((node (make-instance 'swarm-node :id \"root\")))
      (register-child node (make-instance 'swarm-leaf :id \"leaf-a\"))
      (subtree-depth node))
    => 1

    ;; Nested nodes
    (let ((root (make-instance 'swarm-node :id \"root\"))
          (cluster (make-instance 'swarm-node :id \"cluster\")))
      (register-child cluster (make-instance 'swarm-leaf :id \"leaf\"))
      (register-child root cluster)
      (subtree-depth root))
    => 2

  See Also:
    NODE-DEPTH, SUBTREE-SIZE"
  (let ((children (list-children node)))
    (if (null children)
        0
        (1+ (reduce #'max
                    (mapcar (lambda (child)
                              (if (typep child 'swarm-node)
                                  (subtree-depth child)
                                  0))
                            children)
                    :initial-value 0)))))

;;;; ============================================================================
;;;; Tree Traversal and Search
;;;; ============================================================================

(defun find-leaf-by-id (node leaf-id)
  "Find a leaf descendant by ID.

  Searches the entire subtree rooted at this node for a leaf with
  the given ID.

  Args:
    node: SWARM-NODE instance (search root)
    leaf-id: String ID of leaf to find

  Returns:
    SWARM-LEAF instance if found, NIL otherwise.

  Algorithm:
    Performs depth-first search of the tree.

  Examples:
    (find-leaf-by-id root \"leaf-a\")
    => #<SWARM-LEAF id=\"leaf-a\" ...>

  See Also:
    FIND-DESCENDANT, COLLECT-ALL-LEAVES"
  (cond
    ;; Check direct children first
    ((get-child node leaf-id)
     (let ((child (get-child node leaf-id)))
       (when (typep child 'swarm-leaf)
         child)))

    ;; Recursively search child nodes
    (t
     (dolist (child (list-children node))
       (when (typep child 'swarm-node)
         (let ((found (find-leaf-by-id child leaf-id)))
           (when found
             (return found))))))))

(defun find-node-by-id (node target-id)
  "Find a node descendant by ID.

  Searches the entire subtree rooted at this node for a node with
  the given ID.

  Args:
    node: SWARM-NODE instance (search root)
    target-id: String ID of node to find

  Returns:
    SWARM-NODE instance if found, NIL otherwise.

  Examples:
    (find-node-by-id root \"cluster-a\")
    => #<SWARM-NODE id=\"cluster-a\" ...>

  See Also:
    FIND-LEAF-BY-ID, FIND-DESCENDANT"
  (cond
    ;; Base case: this node matches
    ((string= (swarm-id node) target-id)
     node)

    ;; Check direct children
    ((get-child node target-id)
     (let ((child (get-child node target-id)))
       (when (typep child 'swarm-node)
         child)))

    ;; Recursively search child nodes
    (t
     (dolist (child (list-children node))
       (when (typep child 'swarm-node)
         (let ((found (find-node-by-id child target-id)))
           (when found
             (return found))))))))

;;;; ============================================================================
;;;; :AROUND Methods for Metrics and Tracing
;;;; ============================================================================

(defmethod route-envelope :around ((node swarm-node) envelope)
  "Metrics and tracing wrapper for node routing.

  Records:
    - Routing latency (histogram)
    - Routing attempts (counter)
    - Routing decision distribution (by decision type)

  Also adds trace logging for debugging."
  (let ((start-time (get-internal-real-time))
        (node-id (swarm-id node))
        (env-id (envelope-id envelope)))

    ;; Trace: routing start
    (log:debug "Routing envelope ~A through node ~A"
               env-id node-id)

    ;; Call primary method
    (let ((result (call-next-method)))

      ;; Calculate latency
      (let ((latency-ms (/ (* (- (get-internal-real-time) start-time) 1000)
                           internal-time-units-per-second)))

        ;; Record latency
        (record-metric (node-metrics node) :route-latency-ms latency-ms
                       :type :histogram)

        ;; Trace: routing complete
        (log:debug "Routed envelope ~A via node ~A: decision=~A latency=~Ams"
                   env-id node-id
                   (routing-result-decision result)
                   latency-ms))

      ;; Return result
      result)))

(defmethod receive-envelope :around ((node swarm-node) envelope)
  "Metrics and tracing wrapper for node receive.

  Records:
    - Receive latency (histogram)
    - Receive attempts (counter)

  Also adds trace logging for debugging."
  (let ((start-time (get-internal-real-time))
        (node-id (swarm-id node))
        (env-id (envelope-id envelope)))

    ;; Trace: receive start
    (log:debug "Receiving envelope ~A at node ~A"
               env-id node-id)

    (let ((result (call-next-method)))

      ;; Calculate latency
      (let ((latency-ms (/ (* (- (get-internal-real-time) start-time) 1000)
                           internal-time-units-per-second)))

        ;; Record latency
        (record-metric (node-metrics node) :receive-latency-ms latency-ms
                       :type :histogram)

        ;; Trace: receive complete
        (log:debug "Received envelope ~A at node ~A: latency=~Ams"
                   env-id node-id latency-ms))

      result)))

;;;; End of file
