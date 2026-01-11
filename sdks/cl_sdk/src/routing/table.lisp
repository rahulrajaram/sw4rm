;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; routing/table.lisp
;;;;
;;;; Routing Table Management for SW4RM Orchestrator
;;;;
;;;; This module implements routing table data structures and operations for
;;;; efficient cross-swarm message delivery. The routing table maintains:
;;;;   - Forward routes: target-swarm-id -> next-hop-id
;;;;   - Reverse routes: next-hop-id -> list of target-swarm-ids
;;;;   - TTL tracking: route expiration management
;;;;   - Metrics: lookup/hit/miss statistics
;;;;
;;;; The routing table is the core data structure enabling hierarchical routing
;;;; in the SW4RM tree. It allows orchestrator nodes to efficiently forward
;;;; messages to descendants without performing full tree traversals.
;;;;
;;;; Key operations:
;;;;   - ADD-ROUTE: Register a route with optional TTL
;;;;   - REMOVE-ROUTE: Deregister a route
;;;;   - LOOKUP-ROUTE: Find next-hop for target swarm
;;;;   - EXPIRE-STALE-ROUTES: Remove expired routes
;;;;   - IMPORT-ROUTES/EXPORT-ROUTES: Bulk operations
;;;;   - MERGE-ROUTING-TABLE: Combine two tables
;;;;
;;;; Architecture:
;;;;   The routing table uses three hash tables:
;;;;     1. routes: target-swarm-id -> next-hop-id (forward lookup)
;;;;     2. reverse-routes: next-hop-id -> (list target-swarm-ids) (reverse index)
;;;;     3. ttl-map: target-swarm-id -> expiration-time (TTL tracking)
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.routing)

;;;; ============================================================================
;;;; ROUTING-TABLE Class
;;;; ============================================================================

(defclass routing-table ()
  ((routes
    :accessor routing-table-routes
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Forward routes: target-swarm-id (string) -> next-hop-id (string).

    This is the primary routing data structure. Given a target swarm ID,
    lookup returns the next-hop child ID to route through.")

   (reverse-routes
    :accessor routing-table-reverse-routes
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Reverse index: next-hop-id (string) -> list of target-swarm-ids.

    Enables efficient queries like 'what routes go through child X?'
    Used for cleanup when a child is unregistered.")

   (ttl-map
    :accessor routing-table-ttl-map
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "TTL tracking: target-swarm-id (string) -> expiration-time (universal-time).

    Each route can have an optional expiration time. Routes without TTL
    are not present in this map (they never expire).")

   (default-ttl
    :accessor routing-table-default-ttl
    :initarg :default-ttl
    :initform 300
    :type (integer 0)
    :documentation "Default TTL in seconds for routes added without explicit TTL.

    Default is 300 seconds (5 minutes). Set to 0 for no default TTL.")

   (lookup-count
    :accessor routing-table-lookup-count
    :initform 0
    :type (integer 0)
    :documentation "Total number of route lookups performed.")

   (hit-count
    :accessor routing-table-hit-count
    :initform 0
    :type (integer 0)
    :documentation "Number of successful route lookups (route found).")

   (miss-count
    :accessor routing-table-miss-count
    :initform 0
    :type (integer 0)
    :documentation "Number of failed route lookups (route not found).")

   (health-map
    :accessor routing-table-health-map
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Route health flags: target-swarm-id -> T/NIL.")

   (latency-map
    :accessor routing-table-latency-map
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Route latency metrics: target-swarm-id -> ms.")

   (weight-map
    :accessor routing-table-weight-map
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Route weights: target-swarm-id -> weight."))

  (:documentation "Routing table for efficient cross-swarm message delivery.

  The routing table is a multi-indexed data structure that maps target swarm
  IDs to next-hop child IDs, enabling efficient message routing through the
  SW4RM tree hierarchy.

  Primary operations:
    - LOOKUP-ROUTE: Find next-hop for target (O(1) hash lookup)
    - ADD-ROUTE: Register new route with optional TTL
    - REMOVE-ROUTE: Deregister route and clean up indexes

  Secondary operations:
    - ROUTE-EXISTS-P: Check if route is registered
    - LIST-ROUTES: Export all routes as alist
    - LIST-ROUTES-VIA: Find routes through specific next-hop
    - EXPIRE-STALE-ROUTES: Remove expired routes

  Bulk operations:
    - IMPORT-ROUTES: Add multiple routes from alist
    - EXPORT-ROUTES: Export all routes as alist
    - MERGE-ROUTING-TABLE: Merge two tables

  Metrics:
    - lookup-count: Total lookups
    - hit-count: Successful lookups
    - miss-count: Failed lookups

  TTL Management:
    Routes can optionally expire after a TTL period. Expired routes are
    automatically cleaned up by EXPIRE-STALE-ROUTES or removed lazily
    during lookup.

  Thread Safety:
    This implementation is NOT thread-safe. Callers must use external
    synchronization if concurrent access is required.

  Example:
    (let ((table (make-routing-table :default-ttl 600)))
      ;; Add routes
      (add-route table \"backend\" \"cluster-a\")
      (add-route table \"database\" \"cluster-b\" :ttl 300)

      ;; Lookup
      (lookup-route table \"backend\")  => \"cluster-a\"

      ;; List routes via specific next-hop
      (list-routes-via table \"cluster-a\")  => ((\"backend\" . \"cluster-a\"))

      ;; Expire old routes
      (expire-stale-routes table))

  See Also:
    ADD-ROUTE, LOOKUP-ROUTE, REMOVE-ROUTE, MAKE-ROUTING-TABLE"))

;;;; ============================================================================
;;;; Constructor
;;;; ============================================================================

(defun make-routing-table (&key (default-ttl 300))
  "Create a new routing table.

  Args:
    default-ttl - Default TTL in seconds for routes (default: 300)

  Returns:
    New ROUTING-TABLE instance.

  Examples:
    (make-routing-table)
    (make-routing-table :default-ttl 600)  ; 10 minutes

  See Also:
    ROUTING-TABLE, ADD-ROUTE"
  (make-instance 'routing-table :default-ttl default-ttl))

;;;; ============================================================================
;;;; Core Route Operations
;;;; ============================================================================

(defun add-route (table target-swarm next-hop &key ttl)
  "Add a route to the routing table.

  Registers that messages for TARGET-SWARM should be forwarded to NEXT-HOP.
  Optionally sets a TTL for route expiration.

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm
    next-hop - String ID of next-hop child
    ttl - Optional TTL in seconds (defaults to table's default-ttl if non-zero)

  Returns:
    The next-hop ID (for convenience).

  Side Effects:
    - Updates routes hash table
    - Updates reverse-routes index
    - Sets TTL if provided or default-ttl is non-zero

  Examples:
    (add-route table \"backend\" \"cluster-a\")
    (add-route table \"database\" \"cluster-b\" :ttl 600)
    (add-route table \"temp-service\" \"cluster-c\" :ttl 60)

  See Also:
    REMOVE-ROUTE, LOOKUP-ROUTE, ROUTE-EXISTS-P"
  (declare (type routing-table table)
           (type string target-swarm next-hop)
           (type (or null (integer 0)) ttl))

  ;; Add to forward routes
  (setf (gethash target-swarm (routing-table-routes table)) next-hop)

  ;; Update reverse index
  (pushnew target-swarm
           (gethash next-hop (routing-table-reverse-routes table) nil)
           :test #'string=)

  ;; Set TTL if provided or if default-ttl is non-zero
  (let ((effective-ttl (or ttl
                           (when (> (routing-table-default-ttl table) 0)
                             (routing-table-default-ttl table)))))
    (when effective-ttl
      (setf (gethash target-swarm (routing-table-ttl-map table))
            (+ (get-universal-time) effective-ttl))))

  next-hop)

(defun remove-route (table target-swarm)
  "Remove a route from the routing table.

  Removes the route for TARGET-SWARM and cleans up all indexes.

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm to remove

  Returns:
    The next-hop ID that was removed, or NIL if route didn't exist.

  Side Effects:
    - Removes from routes hash table
    - Removes from reverse-routes index
    - Removes from ttl-map

  Examples:
    (remove-route table \"backend\")
    => \"cluster-a\"

    (remove-route table \"nonexistent\")
    => NIL

  See Also:
    ADD-ROUTE, CLEAR-ROUTES"
  (declare (type routing-table table)
           (type string target-swarm))

  (let ((next-hop (gethash target-swarm (routing-table-routes table))))
    (when next-hop
      ;; Remove from forward routes
      (remhash target-swarm (routing-table-routes table))

      ;; Remove from reverse index
      (let ((targets (gethash next-hop (routing-table-reverse-routes table))))
        (setf (gethash next-hop (routing-table-reverse-routes table))
              (remove target-swarm targets :test #'string=))
        ;; Clean up reverse entry if empty
        (when (null (gethash next-hop (routing-table-reverse-routes table)))
          (remhash next-hop (routing-table-reverse-routes table))))

      ;; Remove from TTL map
      (remhash target-swarm (routing-table-ttl-map table)))

    next-hop))

(defun lookup-route (table target-swarm)
  "Look up the next-hop for a target swarm.

  Finds the next-hop child ID to route messages to TARGET-SWARM.
  Checks TTL and returns NIL if route has expired.

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm

  Returns:
    Next-hop ID (string) if route exists and is not expired, NIL otherwise.

  Side Effects:
    - Increments lookup-count
    - Increments hit-count or miss-count
    - Removes expired route if detected

  Examples:
    (lookup-route table \"backend\")
    => \"cluster-a\"

    (lookup-route table \"nonexistent\")
    => NIL

  Algorithm:
    1. Increment lookup counter
    2. Check if route exists
    3. If exists, check TTL (if route has TTL)
    4. If expired, remove route and return NIL
    5. If valid, increment hit counter and return next-hop
    6. If not found, increment miss counter and return NIL

  See Also:
    ADD-ROUTE, ROUTE-EXISTS-P, EXPIRE-STALE-ROUTES"
  (declare (type routing-table table)
           (type string target-swarm))

  ;; Increment lookup counter
  (incf (routing-table-lookup-count table))

  (let ((next-hop (gethash target-swarm (routing-table-routes table))))
    (cond
      ;; Route not found
      ((null next-hop)
       (incf (routing-table-miss-count table))
       nil)

      ;; Route exists - check TTL
      (t
       (let ((expiration (gethash target-swarm (routing-table-ttl-map table))))
         (if (and expiration (>= (get-universal-time) expiration))
             ;; Route expired - remove and return NIL
             (progn
               (remove-route table target-swarm)
               (incf (routing-table-miss-count table))
               nil)
             ;; Route valid - return next-hop
             (progn
               (incf (routing-table-hit-count table))
               next-hop)))))))

(defun route-exists-p (table target-swarm)
  "Check if a route exists for target swarm.

  Args:
    table - ROUTING-TABLE instance
    target-swarm - String ID of target swarm

  Returns:
    T if route exists and is not expired, NIL otherwise.

  Notes:
    This is equivalent to (not (null (lookup-route table target-swarm)))
    but doesn't increment metrics counters.

  Examples:
    (route-exists-p table \"backend\")
    => T

  See Also:
    LOOKUP-ROUTE, ADD-ROUTE"
  (declare (type routing-table table)
           (type string target-swarm))

  (let ((next-hop (gethash target-swarm (routing-table-routes table))))
    (when next-hop
      ;; Check TTL
      (let ((expiration (gethash target-swarm (routing-table-ttl-map table))))
        (if (and expiration (>= (get-universal-time) expiration))
            nil  ; Expired
            t)))))  ; Valid

(defun clear-routes (table)
  "Remove all routes from the routing table.

  Clears all routes, reverse indexes, and TTL entries. Resets metrics to zero.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    NIL

  Side Effects:
    - Clears all hash tables
    - Resets all metrics to zero

  Examples:
    (clear-routes table)
    => NIL

  See Also:
    REMOVE-ROUTE, MAKE-ROUTING-TABLE"
  (declare (type routing-table table))

  ;; Clear all hash tables
  (clrhash (routing-table-routes table))
  (clrhash (routing-table-reverse-routes table))
  (clrhash (routing-table-ttl-map table))

  ;; Reset metrics
  (setf (routing-table-lookup-count table) 0
        (routing-table-hit-count table) 0
        (routing-table-miss-count table) 0)

  nil)

;;;; ============================================================================
;;;; TTL Management
;;;; ============================================================================

(defun expire-stale-routes (table)
  "Remove all expired routes from the table.

  Scans the TTL map and removes routes that have passed their expiration time.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    List of target-swarm IDs that were removed.

  Side Effects:
    - Removes expired routes
    - Updates reverse indexes
    - Cleans up TTL map

  Examples:
    (expire-stale-routes table)
    => (\"temp-service\" \"short-lived-job\")

  Notes:
    This is an O(n) operation where n is the number of routes with TTL.
    Call periodically to clean up expired routes, or rely on lazy removal
    during lookup.

  See Also:
    LOOKUP-ROUTE, ADD-ROUTE, REMOVE-ROUTE"
  (declare (type routing-table table))

  (let ((now (get-universal-time))
        (expired-routes nil))

    ;; Collect expired routes
    (maphash (lambda (target-swarm expiration)
               (when (>= now expiration)
                 (push target-swarm expired-routes)))
             (routing-table-ttl-map table))

    ;; Remove each expired route
    (dolist (target-swarm expired-routes)
      (remove-route table target-swarm))

    expired-routes))

;;;; ============================================================================
;;;; Query Operations
;;;; ============================================================================

(defun list-routes (table)
  "List all routes in the table.

  Returns all routes as an association list of (target-swarm . next-hop).
  Excludes expired routes.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    Association list of (target-swarm . next-hop) pairs.

  Examples:
    (list-routes table)
    => ((\"backend\" . \"cluster-a\")
        (\"database\" . \"cluster-b\"))

  See Also:
    LIST-ROUTES-VIA, EXPORT-ROUTES, ROUTE-COUNT"
  (declare (type routing-table table))

  (let ((routes nil)
        (now (get-universal-time)))

    (maphash (lambda (target-swarm next-hop)
               ;; Check if expired
               (let ((expiration (gethash target-swarm (routing-table-ttl-map table))))
                 (when (or (null expiration) (< now expiration))
                   (push (cons target-swarm next-hop) routes))))
             (routing-table-routes table))

    (nreverse routes)))

(defun list-routes-via (table next-hop)
  "List all routes that go through a specific next-hop.

  Args:
    table - ROUTING-TABLE instance
    next-hop - String ID of next-hop child

  Returns:
    Association list of (target-swarm . next-hop) pairs for routes via next-hop.
    Excludes expired routes.

  Examples:
    (list-routes-via table \"cluster-a\")
    => ((\"backend\" . \"cluster-a\")
        (\"frontend\" . \"cluster-a\"))

  Notes:
    This uses the reverse-routes index for efficient lookup.

  See Also:
    LIST-ROUTES, LOOKUP-ROUTE"
  (declare (type routing-table table)
           (type string next-hop))

  (let ((target-swarms (gethash next-hop (routing-table-reverse-routes table)))
        (routes nil)
        (now (get-universal-time)))

    (dolist (target-swarm target-swarms)
      ;; Check if expired
      (let ((expiration (gethash target-swarm (routing-table-ttl-map table))))
        (when (or (null expiration) (< now expiration))
          (push (cons target-swarm next-hop) routes))))

    (nreverse routes)))

(defun route-count (table)
  "Count total number of routes (excluding expired).

  Args:
    table - ROUTING-TABLE instance

  Returns:
    Non-negative integer count of active routes.

  Examples:
    (route-count table)
    => 42

  See Also:
    LIST-ROUTES, ROUTE-EXISTS-P"
  (declare (type routing-table table))

  (let ((count 0)
        (now (get-universal-time)))

    (maphash (lambda (target-swarm next-hop)
               (declare (ignore next-hop))
               (let ((expiration (gethash target-swarm (routing-table-ttl-map table))))
                 (when (or (null expiration) (< now expiration))
                   (incf count))))
             (routing-table-routes table))

    count))

;;;; ============================================================================
;;;; Bulk Operations
;;;; ============================================================================

(defun import-routes (table route-list &key ttl)
  "Import multiple routes from an association list.

  Args:
    table - ROUTING-TABLE instance
    route-list - Association list of (target-swarm . next-hop) pairs
    ttl - Optional TTL to apply to all imported routes

  Returns:
    Number of routes imported.

  Examples:
    (import-routes table
      '((\"backend\" . \"cluster-a\")
        (\"database\" . \"cluster-b\"))
      :ttl 600)
    => 2

  See Also:
    EXPORT-ROUTES, ADD-ROUTE"
  (declare (type routing-table table)
           (type list route-list)
           (type (or null (integer 0)) ttl))

  (let ((count 0))
    (dolist (route route-list)
      (destructuring-bind (target-swarm . next-hop) route
        (add-route table target-swarm next-hop :ttl ttl)
        (incf count)))
    count))

(defun export-routes (table)
  "Export all routes as an association list.

  This is equivalent to LIST-ROUTES but has a clearer name for bulk operations.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    Association list of (target-swarm . next-hop) pairs.
    Excludes expired routes.

  Examples:
    (export-routes table)
    => ((\"backend\" . \"cluster-a\")
        (\"database\" . \"cluster-b\"))

  See Also:
    IMPORT-ROUTES, LIST-ROUTES"
  (declare (type routing-table table))

  (list-routes table))

(defun merge-routing-table (target source &key (overwrite t))
  "Merge routes from source table into target table.

  Copies all routes from SOURCE into TARGET. If OVERWRITE is T (default),
  existing routes in TARGET are replaced. If OVERWRITE is NIL, existing
  routes are preserved.

  Args:
    target - ROUTING-TABLE instance (destination)
    source - ROUTING-TABLE instance (source)
    overwrite - If T, overwrite existing routes; if NIL, preserve them

  Returns:
    Number of routes merged.

  Side Effects:
    - Modifies target table
    - Preserves TTL from source routes

  Examples:
    (merge-routing-table target-table source-table)
    => 15  ; Merged 15 routes

    (merge-routing-table target-table source-table :overwrite nil)
    => 8   ; Merged 8 new routes (7 already existed)

  See Also:
    IMPORT-ROUTES, EXPORT-ROUTES"
  (declare (type routing-table target source)
           (type boolean overwrite))

  (let ((count 0)
        (now (get-universal-time)))

    (maphash (lambda (target-swarm next-hop)
               ;; Check if route is expired in source
               (let ((expiration (gethash target-swarm (routing-table-ttl-map source))))
                 (when (or (null expiration) (< now expiration))
                   ;; Skip if route exists and overwrite is NIL
                   (unless (and (not overwrite)
                                (gethash target-swarm (routing-table-routes target)))
                     ;; Calculate remaining TTL
                     (let ((ttl (when expiration
                                  (max 0 (- expiration now)))))
                       (add-route target target-swarm next-hop :ttl ttl)
                       (incf count))))))
             (routing-table-routes source))

    count))

;;;; ============================================================================
;;;; Debugging and Introspection
;;;; ============================================================================

(defun print-routing-table (table &optional (stream *standard-output*))
  "Pretty-print routing table for debugging.

  Prints routes in a human-readable format with metrics.

  Args:
    table - ROUTING-TABLE instance
    stream - Output stream (default: *standard-output*)

  Returns:
    NIL

  Side Effects:
    - Writes to stream

  Example Output:
    Routing Table:
      Routes: 5
      Lookups: 123 (hits: 100, misses: 23, hit-rate: 81.3%)
      Default TTL: 300s

      target-swarm          -> next-hop           TTL
      ================================================
      backend               -> cluster-a          298s
      database              -> cluster-b          (no TTL)
      frontend              -> cluster-a          150s

  See Also:
    LIST-ROUTES, ROUTE-COUNT"
  (declare (type routing-table table)
           (type stream stream))

  (let ((routes (list-routes table))
        (now (get-universal-time))
        (lookup-count (routing-table-lookup-count table))
        (hit-count (routing-table-hit-count table))
        (miss-count (routing-table-miss-count table)))

    ;; Header
    (format stream "~&Routing Table:~%")
    (format stream "  Routes: ~D~%" (length routes))
    (format stream "  Lookups: ~D (hits: ~D, misses: ~D, hit-rate: ~,1F%)~%"
            lookup-count hit-count miss-count
            (if (> lookup-count 0)
                (* 100.0 (/ hit-count lookup-count))
                0.0))
    (format stream "  Default TTL: ~Ds~%~%" (routing-table-default-ttl table))

    ;; Routes table
    (if (null routes)
        (format stream "  (no routes)~%")
        (progn
          (format stream "  target-swarm          -> next-hop           TTL~%")
          (format stream "  ================================================~%")
          (dolist (route routes)
            (destructuring-bind (target-swarm . next-hop) route
              (let ((expiration (gethash target-swarm (routing-table-ttl-map table))))
                (format stream "  ~22A -> ~18A ~A~%"
                        target-swarm
                        next-hop
                        (if expiration
                            (format nil "~Ds" (max 0 (- expiration now)))
                            "(no TTL)")))))))

    nil))

;;;; ============================================================================
;;;; SETF Expander (Auto-update Reverse Indexes)
;;;; ============================================================================
;;;;
;;;; Per COMMON_LISP_PLAN.md line 215-217, we provide a SETF expander that
;;;; auto-updates reverse indexes when the routes hash table is modified.
;;;;
;;;; This allows code to use:
;;;;   (setf (gethash target (routing-table-routes table)) next-hop)
;;;;
;;;; And have the reverse index automatically updated.

(defun rebuild-routing-indexes (table)
  "Rebuild reverse-routes index from routes hash table.

  Scans the routes table and rebuilds the reverse index from scratch.
  This is called automatically by the SETF expander when routes are modified.

  Args:
    table - ROUTING-TABLE instance

  Returns:
    NIL

  Side Effects:
    - Clears and rebuilds reverse-routes hash table

  Notes:
    This is an O(n) operation where n is the number of routes. It's called
    automatically when using SETF on (routing-table-routes table), so direct
    modification of the routes hash table is discouraged.

  See Also:
    ADD-ROUTE, REMOVE-ROUTE"
  (cond
    ((typep table 'routing-table)
     ;; Clear reverse index
     (clrhash (routing-table-reverse-routes table))

     ;; Rebuild from routes
     (maphash (lambda (target-swarm next-hop)
                (pushnew target-swarm
                         (gethash next-hop (routing-table-reverse-routes table) nil)
                         :test #'string=))
              (routing-table-routes table))
     nil)
    ((typep table 'swarm-node)
     (let ((rtable (sw4rm-orchestrator.tree:routing-table table)))
       (when rtable
         (rebuild-routing-indexes rtable))))
    (t
     (error "REBUILD-ROUTING-INDEXES expects ROUTING-TABLE or SWARM-NODE, got: ~S" table))))

;;;; ============================================================================
;;;; PRINT-OBJECT Method
;;;; ============================================================================

(defmethod print-object ((table routing-table) stream)
  "Print routing table in readable format.

  Format:
    #<ROUTING-TABLE routes=5 lookups=123 hit-rate=81.3%>"
  (let ((route-count (route-count table))
        (lookup-count (routing-table-lookup-count table))
        (hit-count (routing-table-hit-count table)))
    (print-unreadable-object (table stream :type t)
      (format stream "routes=~D lookups=~D hit-rate=~,1F%"
              route-count
              lookup-count
              (if (> lookup-count 0)
                  (* 100.0 (/ hit-count lookup-count))
                  0.0)))))

;;;; End of file
