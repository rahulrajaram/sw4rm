;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; routing/router.lisp
;;;;
;;;; Core Routing Logic for SW4RM Orchestrator
;;;;
;;;; This module implements the routing decision algorithm for cross-swarm
;;;; message delivery. It handles:
;;;;   - Routing decisions (local, child, parent, broadcast, reject)
;;;;   - Route validation and loop detection
;;;;   - Route metrics and latency tracking
;;;;   - Route caching and optimization
;;;;
;;;; The routing algorithm follows the specification in COMMON_LISP_PLAN.md
;;;; Part 3.4 (lines 408-480):
;;;;
;;;;   1. Check hop limit (reject if exceeded)
;;;;   2. If target is this node: receive locally
;;;;   3. If target is direct child: route to child
;;;;   4. If target in routing table: route via next-hop
;;;;   5. If parent exists: route upward
;;;;   6. If broadcast target: route to all children
;;;;   7. Otherwise: reject (target not found)
;;;;
;;;; The router also provides validation and safety checks:
;;;;   - Loop detection using path tracking
;;;;   - Deadline enforcement
;;;;   - Hop limit enforcement
;;;;   - Route safety validation
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.routing)

;;;; ============================================================================
;;;; Core Routing Decision Function
;;;; ============================================================================

(defun broadcast-target-p (target)
  "Return T if TARGET represents a broadcast destination."
  (or (eq target :broadcast)
      (eq target :BROADCAST)
      (and (stringp target)
           (member (string-upcase target) '("BROADCAST" ":BROADCAST") :test #'string=))))

(defun next-hop-for-descendant (node target-id)
  "Return direct child ID that leads to TARGET-ID, or NIL."
  (when (typep node 'swarm-node)
    (dolist (child (list-children node))
      (when (string= (swarm-id child) target-id)
        (return (swarm-id child)))
      (when (typep child 'swarm-node)
        (when (next-hop-for-descendant child target-id)
          (return (swarm-id child)))))))

(defun make-routing-decision (node envelope)
  "Make routing decision for envelope at node.

  This is the core routing algorithm that determines how to handle an envelope
  at a given node. It follows the algorithm from COMMON_LISP_PLAN.md Part 3.4:

    1. Check hop limit (reject if exceeded)
    2. Check deadline (reject if expired)
    3. If target is this node: deliver locally (LOCAL)
    4. If target is broadcast: broadcast to all children (BROADCAST)
    5. If target is direct child: route to child (CHILD)
    6. If target in routing table: route via next-hop (CHILD)
    7. If parent exists: route upward (PARENT)
    8. Otherwise: reject (REJECT)

  Args:
    node - SWARM-TREE instance (SWARM-NODE or SWARM-LEAF)
    envelope - CROSS-SWARM-ENVELOPE to route

  Returns:
    ROUTING-RESULT with decision, target, and reason.

  Side Effects:
    - None (read-only operation)

  Examples:
    ;; Local delivery
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (env (make-cross-swarm-envelope :target-swarm \"root\")))
      (make-routing-decision node env))
    => #<ROUTING-RESULT decision=:LOCAL target=\"root\" ...>

    ;; Route to child
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (child (make-instance 'swarm-leaf :id \"leaf-a\"))
           (env (make-cross-swarm-envelope :target-swarm \"leaf-a\")))
      (register-child node child)
      (make-routing-decision node env))
    => #<ROUTING-RESULT decision=:CHILD target=\"leaf-a\" ...>

    ;; Reject (no route)
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (env (make-cross-swarm-envelope :target-swarm \"unknown\")))
      (make-routing-decision node env))
    => #<ROUTING-RESULT decision=:REJECT reason=\"No route to unknown\" ...>

  See Also:
    ROUTE-ENVELOPE, ROUTING-RESULT, VALIDATE-ROUTE-PATH"
  (let* ((target-raw (envelope-target-swarm envelope))
         (target-swarm (if (keywordp target-raw)
                           (symbol-name target-raw)
                           target-raw))
         (node-id (swarm-id node)))

    (cond
      ;; Step 1: Check hop limit
      ((envelope-hop-limit-exceeded-p envelope)
       (make-routing-result
        :decision :reject
        :target nil
        :reason (format nil "Max hops exceeded (~D >= ~D)"
                        (envelope-hop-count envelope)
                        (envelope-max-hops envelope))))

      ;; Step 2: Check deadline
      ((envelope-expired-p envelope)
       (make-routing-result
        :decision :reject
        :target nil
        :reason (format nil "Envelope expired (deadline: ~A, now: ~A)"
                        (envelope-deadline envelope)
                        (get-universal-time))))

      ;; Step 2b: Missing target
      ((null target-swarm)
       (make-routing-result
        :decision :reject
        :target nil
        :reason "No target swarm specified"))

      ;; Step 3: Target is this node - deliver locally
      ((and target-swarm (string= target-swarm node-id))
       (make-routing-result
        :decision :local
        :target node-id
        :reason "Target swarm matches node ID"))

      ;; Step 4: Broadcast target - route to all children
      ((broadcast-target-p target-raw)
       (make-routing-result
        :decision :broadcast
        :target nil
        :reason "Broadcast to all children"))

      ;; For SWARM-NODE: check children and routing table
      ((typep node 'swarm-node)
       (cond
        ;; Step 5: Target is direct child
        ((get-child node target-swarm)
         (make-routing-result
          :decision :child
          :target target-swarm
          :reason "Target is direct child"))

         ;; Step 6: Target in subtree (descendant)
         ((next-hop-for-descendant node target-swarm)
          (let ((next-hop (next-hop-for-descendant node target-swarm)))
            (make-routing-result
             :decision :child
             :target next-hop
             :reason (format nil "Routing via descendant path (next-hop: ~A)" next-hop))))

         ;; Step 7: Target in routing table
         ((and (sw4rm-orchestrator.tree:routing-table node)
               (lookup-route (sw4rm-orchestrator.tree:routing-table node)
                             target-swarm))
          (let ((next-hop (lookup-route (sw4rm-orchestrator.tree:routing-table node)
                                        target-swarm)))
            (make-routing-result
             :decision :child
             :target next-hop
             :reason (format nil "Routing via routing table (next-hop: ~A)" next-hop))))

         ;; Step 8: Parent exists - route upward
         ((parent-node node)
          (make-routing-result
           :decision :parent
           :target (swarm-id (parent-node node))
           :reason "Routing to parent (upward routing)"))

         ;; Step 9: No route found
         (t
          (make-routing-result
           :decision :reject
           :target nil
           :reason (format nil "No route to ~A" target-swarm)))))

      ;; For SWARM-LEAF: only local or parent
      ((typep node 'swarm-leaf)
       (cond
         ;; Already checked local above, so only parent remains
         ((parent-node node)
          (make-routing-result
           :decision :parent
           :target (swarm-id (parent-node node))
           :reason "Routing to parent (leaf upward routing)"))

         ;; Orphan leaf
         (t
          (make-routing-result
           :decision :reject
           :target nil
           :reason "Orphan leaf cannot route"))))

      ;; Unknown node type
      (t
       (make-routing-result
        :decision :reject
        :target nil
        :reason (format nil "Unknown node type: ~A" (type-of node)))))))

;; Alias for tests that use compute-routing-decision instead of make-routing-decision
(setf (fdefinition 'compute-routing-decision) #'make-routing-decision)

;;;; ============================================================================
;;;; Route Validation
;;;; ============================================================================

(defun validate-route-path (envelope)
  "Validate envelope path for routing loops.

  Checks the path (breadcrumb trail) for duplicate node IDs, which would
  indicate a routing loop.

  Args:
    envelope - CROSS-SWARM-ENVELOPE to validate

  Returns:
    T if path is valid (no loops), NIL if loop detected.

  Examples:
    (let ((env (make-cross-swarm-envelope :path '(\"root\" \"cluster-a\"))))
      (validate-route-path env))
    => T

    (let ((env (make-cross-swarm-envelope :path '(\"root\" \"cluster-a\" \"root\"))))
      (validate-route-path env))
    => NIL  ; Loop detected

  See Also:
    DETECT-ROUTING-LOOP, ROUTE-SAFE-P"
  (let ((path (envelope-path envelope)))
    ;; Check for duplicates in path
    (= (length path)
       (length (remove-duplicates path :test #'string=)))))

(defun detect-routing-loop (envelope &optional node)
  "Detect if routing envelope through node would create a loop.

  Checks if NODE's ID already appears in the envelope's path, which would
  indicate that routing through this node would create a loop.

  Args:
    envelope - CROSS-SWARM-ENVELOPE to check
    node - SWARM-TREE instance to check

  Returns:
    T if loop would be created, NIL otherwise.

  Examples:
    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (env (make-cross-swarm-envelope :path '(\"cluster-a\"))))
      (detect-routing-loop env node))
    => NIL

    (let* ((node (make-instance 'swarm-node :id \"root\"))
           (env (make-cross-swarm-envelope :path '(\"root\" \"cluster-a\"))))
      (detect-routing-loop env node))
    => T  ; root already in path

  See Also:
    VALIDATE-ROUTE-PATH, ROUTE-SAFE-P"
  (let ((path (envelope-path envelope)))
    (if node
        (member (swarm-id node) path :test #'string=)
        (not (validate-route-path envelope)))))

(defun route-safe-p (envelope node)
  "Combined safety check: valid path and no loop.

  Checks both:
    1. Path is valid (no duplicates)
    2. Routing through node would not create loop

  Args:
    envelope - CROSS-SWARM-ENVELOPE to check
    node - SWARM-TREE instance to check

  Returns:
    T if safe to route through node, NIL otherwise.

  Examples:
    (route-safe-p envelope node)
    => T

  See Also:
    VALIDATE-ROUTE-PATH, DETECT-ROUTING-LOOP"
  (and (validate-route-path envelope)
       (not (detect-routing-loop envelope node))))

;;;; ============================================================================
;;;; Route Metrics
;;;; ============================================================================

(defun record-routing-decision (node envelope result)
  "Record routing decision metrics.

  Tracks:
    - Routing latency (in result if available)
    - Decision type distribution (local, child, parent, broadcast, reject)
    - Target swarm distribution
    - Error counts (for reject decisions)

  Args:
    node - SWARM-TREE instance
    envelope - CROSS-SWARM-ENVELOPE that was routed
    result - ROUTING-RESULT from routing decision

  Returns:
    NIL

  Side Effects:
    - Updates node metrics
    - Logs routing decision (if tracing enabled)

  Examples:
    (record-routing-decision node envelope result)
    => NIL

  See Also:
    MAKE-ROUTING-DECISION, RECORD-METRIC"
  (let ((decision (routing-result-decision result))
        (target (routing-result-target result))
        (latency-ms (routing-result-latency-ms result))
        (metrics (node-metrics node)))

    ;; Record decision type
    (record-metric metrics
                   (intern (format nil "ROUTING-DECISION-~A" decision) :keyword)
                   1
                   :type :counter)

    ;; Record latency if available
    (when latency-ms
      (record-metric metrics :routing-latency-ms latency-ms :type :histogram))

    ;; Record target swarm (for distribution analysis)
    (when target
      (record-metric metrics
                     (intern (format nil "ROUTING-TARGET-~A" target) :keyword)
                     1
                     :type :counter))

    ;; Record error if rejected
    (when (eq decision :reject)
      (record-metric metrics :routing-errors 1 :type :counter))

    nil))

;;;; ============================================================================
;;;; Route Optimization
;;;; ============================================================================

(defun optimize-route (table target-swarm)
  "Find shortest path to target swarm (if multiple paths exist).

  In the current implementation, this is a no-op because we only maintain
  a single next-hop per target. In future versions, we could:
    - Maintain multiple paths per target
    - Choose based on latency, load, or other metrics
    - Use A* or Dijkstra's algorithm for path selection

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm

  Returns:
    Next-hop ID (string) or NIL if no route exists.

  Notes:
    Currently just delegates to LOOKUP-ROUTE. Future enhancement.

  Examples:
    (optimize-route table \"backend\")
    => \"cluster-a\"

  See Also:
    LOOKUP-ROUTE, FIND-SHORTEST-PATH"
  (lookup-route table target-swarm))

(defun cache-route-lookup (table target-swarm result &key ttl)
  "Cache a route lookup result.

  In the current implementation, this just adds a route to the table.
  This is useful when a route is discovered dynamically (e.g., via
  topology gossip or path discovery).

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm
    result - String ID of next-hop (or NIL if no route)
    ttl - Optional TTL for cached route

  Returns:
    The result (for convenience).

  Side Effects:
    - Adds route to table if result is non-NIL

  Examples:
    (cache-route-lookup table \"backend\" \"cluster-a\" :ttl 300)
    => \"cluster-a\"

  See Also:
    ADD-ROUTE, LOOKUP-ROUTE"
  (when result
    (add-route table target-swarm result :ttl ttl))
  result)

;;;; ============================================================================
;;;; Advanced Routing Queries
;;;; ============================================================================

(defun find-shortest-path (table target-swarm)
  "Find shortest path to target swarm.

  Currently a placeholder that returns the single known route.
  Future enhancement: implement actual pathfinding for multi-path routing.

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm

  Returns:
    List of node IDs representing the path, or NIL if no route.

  Examples:
    (find-shortest-path table \"backend\")
    => (\"cluster-a\")  ; Single-hop path

  Notes:
    This is a placeholder for future multi-path routing. Currently just
    returns a single-element list with the next-hop.

  See Also:
    LOOKUP-ROUTE, OPTIMIZE-ROUTE"
  (cond
    ((typep table 'swarm-node)
     (let ((node (sw4rm-orchestrator.tree:find-node table target-swarm)))
       (when node
         (reverse (cons (swarm-id node)
                        (sw4rm-orchestrator.tree:node-path node))))))
    ((typep table 'routing-table)
     (let ((next-hop (lookup-route table target-swarm)))
       (when next-hop
         (list next-hop))))
    (t nil)))

(defun get-route-metrics (table target-swarm)
  "Get metrics for a specific route.

  Returns metrics about a route, such as:
    - Next-hop ID
    - TTL remaining
    - Lookup count (future)
    - Average latency (future)
    - Success rate (future)

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm

  Returns:
    Property list with route metrics, or NIL if route doesn't exist.

  Examples:
    (get-route-metrics table \"backend\")
    => (:next-hop \"cluster-a\" :ttl-remaining 285 :has-ttl T)

    (get-route-metrics table \"nonexistent\")
    => NIL

  See Also:
    LOOKUP-ROUTE, ROUTE-EXISTS-P"
  (cond
    ((typep table 'swarm-node)
     (let ((node (sw4rm-orchestrator.tree:find-node table target-swarm)))
       (when node
         (list :target target-swarm
               :distance (sw4rm-orchestrator.tree:distance-between table node)
               :found t))))
    ((typep table 'routing-table)
     (let ((next-hop (gethash target-swarm (routing-table-routes table))))
       (when next-hop
         (let* ((expiration (gethash target-swarm (routing-table-ttl-map table)))
                (ttl-remaining (when expiration
                                 (max 0 (- expiration (get-universal-time))))))
           (list :next-hop next-hop
                 :ttl-remaining ttl-remaining
                 :has-ttl (not (null expiration))
                 :expired (and expiration (>= (get-universal-time) expiration)))))))
    (t nil)))

;;;; ============================================================================
;;;; Routing Table Query Helpers
;;;; ============================================================================

(defun routing-table-contains-p (table target-swarm)
  "Check if routing table contains a route for target swarm.

  This is a wrapper around ROUTE-EXISTS-P with a more explicit name.

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm

  Returns:
    T if route exists and is not expired, NIL otherwise.

  Examples:
    (routing-table-contains-p table \"backend\")
    => T

  See Also:
    ROUTE-EXISTS-P, LOOKUP-ROUTE"
  (route-exists-p table target-swarm))

(defun routing-table-local-routes (table)
  "Get all direct child routes (first-hop routes).

  Returns routes where the target and next-hop are the same, indicating
  direct children.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    List of target swarm IDs (strings) where target = next-hop.

  Examples:
    (routing-table-local-routes table)
    => ((\"cluster-a\" . \"cluster-a\")
        (\"cluster-b\" . \"cluster-b\"))

  See Also:
    ROUTING-TABLE-EXTERNAL-ROUTES, LIST-ROUTES"
  (let ((routes (list-routes table))
        (local-routes nil))
    (dolist (route routes)
      (destructuring-bind (target . next-hop) route
        (when (string= target next-hop)
          (push target local-routes))))
    (nreverse local-routes)))

(defun routing-table-external-routes (table)
  "Get all external routes (multi-hop routes).

  Returns routes where the target and next-hop are different, indicating
  routes to descendants beyond direct children.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    List of target swarm IDs (strings) where target != next-hop.

  Examples:
    (routing-table-external-routes table)
    => ((\"backend\" . \"cluster-a\")   ; backend is under cluster-a
        (\"database\" . \"cluster-b\"))  ; database is under cluster-b

  See Also:
    ROUTING-TABLE-LOCAL-ROUTES, LIST-ROUTES"
  (let ((routes (list-routes table))
        (external-routes nil))
    (dolist (route routes)
      (destructuring-bind (target . next-hop) route
        (unless (string= target next-hop)
          (push target external-routes))))
    (nreverse external-routes)))

;;;; ============================================================================
;;;; Broadcast Target Computation
;;;; ============================================================================

(defun compute-broadcast-targets (node)
  "Compute all targets for broadcast operation.

  Returns list of child node IDs that should receive broadcast messages.

  Args:
    node - SWARM-NODE instance

  Returns:
    List of child IDs (strings).

  Examples:
    (compute-broadcast-targets node)
    => (\"cluster-a\" \"cluster-b\" \"leaf-c\")

  See Also:
    LIST-CHILDREN, BROADCAST-TO-CHILDREN"
  (when (typep node 'swarm-node)
    (mapcar #'swarm-id (list-children node))))

;;;; ============================================================================
;;;; Alternative Route Discovery
;;;; ============================================================================

(defun get-alternative-routes (table target-swarm)
  "Get alternative routes to target swarm.

  In the current implementation, we only maintain a single route per target.
  This returns an empty list, but future versions could implement:
    - Multiple paths per target with different priorities
    - Failover routes for redundancy
    - Load-balanced routes

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm

  Returns:
    List of alternative next-hop IDs (currently always empty).

  Examples:
    (get-alternative-routes table \"backend\")
    => ()  ; No alternatives in current implementation

  Notes:
    This is a placeholder for future multi-path routing support.

  See Also:
    LOOKUP-ROUTE, FIND-SHORTEST-PATH"
  (cond
    ((typep table 'swarm-node)
     (let ((next-hop (next-hop-for-descendant table target-swarm)))
       (when next-hop
         (list next-hop))))
    ((typep table 'routing-table)
     nil)
    (t nil)))  ; No alternative routes in current implementation

;;;; ============================================================================
;;;; Routing Decision Helpers
;;;; ============================================================================

(defun routing-decision-to-string (decision)
  "Convert routing decision to human-readable string.

  Args:
    decision - ROUTING-DECISION keyword

  Returns:
    String representation.

  Examples:
    (routing-decision-to-string :local)
    => \"LOCAL\"

    (routing-decision-to-string :reject)
    => \"REJECT\"

  See Also:
    ROUTING-RESULT, MAKE-ROUTING-DECISION"
  (string decision))

(defun routing-result-successful-p (result)
  "Check if routing result represents successful routing.

  A result is successful if the decision is anything other than :REJECT.

  Args:
    result - ROUTING-RESULT instance

  Returns:
    T if successful, NIL if rejected.

  Examples:
    (routing-result-successful-p
      (make-routing-result :decision :child :target \"leaf-a\"))
    => T

    (routing-result-successful-p
      (make-routing-result :decision :reject :reason \"No route\"))
    => NIL

  See Also:
    ROUTING-RESULT, MAKE-ROUTING-DECISION"
  (not (eq (routing-result-decision result) :reject)))

;;;; ============================================================================
;;;; Utility Functions
;;;; ============================================================================

(defun routing-table-hit-rate (table)
  "Calculate routing table hit rate as percentage.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    Hit rate as percentage (0.0 to 100.0), or 0.0 if no lookups.

  Examples:
    (routing-table-hit-rate table)
    => 81.3

  See Also:
    ROUTING-TABLE, LOOKUP-ROUTE"
  (let ((lookup-count (routing-table-lookup-count table))
        (hit-count (routing-table-hit-count table)))
    (if (> lookup-count 0)
        (* 100.0 (/ hit-count lookup-count))
        0.0)))

(defun routing-table-stats (table)
  "Get routing table statistics.

  Returns:
    Property list with statistics.

  Examples:
    (routing-table-stats table)
    => (:routes 5 :lookups 123 :hits 100 :misses 23 :hit-rate 81.3)

  See Also:
    PRINT-ROUTING-TABLE, ROUTING-TABLE-HIT-RATE"
  (list :routes (route-count table)
        :lookups (routing-table-lookup-count table)
        :hits (routing-table-hit-count table)
        :misses (routing-table-miss-count table)
        :hit-rate (routing-table-hit-rate table)))

;;;; End of file
