;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; routing/strategies.lisp
;;;;
;;;; Routing Strategy Patterns for SW4RM Orchestrator
;;;;
;;;; This module implements pluggable routing strategies that determine how
;;;; messages are routed through the sw4rm tree. Strategies are composable,
;;;; extensible objects that can be combined and customized for different
;;;; deployment scenarios.
;;;;
;;;; Routing Strategies:
;;;;
;;;;   1. DIRECT-ROUTING-STRATEGY
;;;;      Routes to exact target match, falls back to parent if no match.
;;;;      Default strategy used by the orchestrator.
;;;;
;;;;   2. ROUND-ROBIN-STRATEGY
;;;;      Cycles through available routes in round-robin fashion.
;;;;      Maintains per-destination counter, thread-safe.
;;;;
;;;;   3. LEAST-LOADED-STRATEGY
;;;;      Routes to child with lowest queue depth.
;;;;      Requires metrics from children.
;;;;
;;;;   4. LATENCY-BASED-STRATEGY
;;;;      Routes based on historical latency data.
;;;;      Maintains exponential moving average, falls back to round-robin.
;;;;
;;;;   5. WEIGHTED-RANDOM-STRATEGY
;;;;      Routes randomly with weights based on capacity/priority.
;;;;
;;;;   6. FAILOVER-STRATEGY
;;;;      Tries primary route first, falls back to secondary on failure.
;;;;      Maintains health status per route.
;;;;
;;;;   7. BROADCAST-STRATEGY
;;;;      Routes to ALL matching destinations, creates envelope copies.
;;;;      Used for fanout operations and discovery.
;;;;
;;;; Composition Patterns:
;;;;
;;;;   - Composite strategies chain multiple strategies
;;;;   - Fallback strategies try primary, then secondary on failure
;;;;   - Conditional strategies apply based on predicate
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.routing)

;;;; ============================================================================
;;;; Base Strategy Protocol
;;;; ============================================================================

(defclass routing-strategy ()
  ((name
    :initarg :name
    :accessor strategy-name
    :type keyword
    :documentation "Symbolic name for this strategy")

   (priority
    :initarg :priority
    :accessor strategy-priority
    :initform 0
    :type integer
    :documentation "Priority level (used when multiple strategies compete)")

   (metrics
    :accessor strategy-metrics
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Metrics collected by this strategy"))

  (:documentation "Base class for all routing strategies.

  A routing strategy is an object that determines how to route envelopes
  through the sw4rm tree. Different strategies implement different algorithms
  (direct, round-robin, least-loaded, etc.).

  Subclasses must implement:
    - SELECT-ROUTE: Choose next hop for envelope

  See Also:
    SELECT-ROUTE, DIRECT-ROUTING-STRATEGY, ROUND-ROBIN-STRATEGY"))

(defgeneric select-route (strategy node envelope available-routes)
  (:documentation "Select the best route for an envelope.

  This is the core method that each strategy must implement to decide
  which route to use.

  Args:
    strategy - ROUTING-STRATEGY instance
    node - SWARM-NODE performing the routing
    envelope - CROSS-SWARM-ENVELOPE being routed
    available-routes - List of available next-hop IDs (strings)

  Returns:
    A next-hop ID (string) to route through, or NIL if no route selected.

  Side Effects:
    May update strategy metrics and state.

  Notes:
    Implementations should be idempotent when possible (for replay scenarios).
    If no route is appropriate, return NIL to allow fallback strategies.

  See Also:
    ROUTING-STRATEGY, APPLY-STRATEGY"))

;;;; ============================================================================
;;;; Built-in Strategy 1: DIRECT-ROUTING-STRATEGY
;;;; ============================================================================

(defclass direct-routing-strategy (routing-strategy)
  ()
  (:documentation "Direct routing strategy (default).

  Routes to the exact target match. If target is not a direct child,
  checks routing table for next-hop, then falls back to parent.

  This is the simplest and most predictable strategy, suitable for
  most orchestration scenarios.

  Example:
    (make-instance 'direct-routing-strategy :name :direct)

  See Also:
    ROUTING-STRATEGY, SELECT-ROUTE"))

(defmethod select-route ((strategy direct-routing-strategy) node envelope available-routes)
  "Direct routing: exact match or fall back to parent."
  (declare (ignore strategy))

  (let ((target-swarm (envelope-target-swarm envelope))
        (selected nil))

    ;; Record metric
    (incf (gethash "direct-attempts" (strategy-metrics strategy) 0))

    ;; Check if target is in available routes
    (when (and target-swarm
               (member target-swarm available-routes :test #'string=))
      (setf selected target-swarm)
      (incf (gethash "direct-hits" (strategy-metrics strategy) 0)))

    selected))

;;;; ============================================================================
;;;; Built-in Strategy 2: ROUND-ROBIN-STRATEGY
;;;; ============================================================================

(defclass round-robin-strategy (routing-strategy)
  ((counters
    :accessor rr-counters
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Per-destination counter for round-robin state")

   (lock
    :accessor rr-lock
    :initform (bordeaux-threads:make-lock "round-robin-lock")
    :documentation "Lock for thread-safe counter updates"))

  (:documentation "Round-robin routing strategy.

  Distributes traffic evenly across available routes by cycling through them
  in sequence. Maintains a per-destination counter to track position in list.

  Thread-safe: Uses a lock to protect counter updates.

  Suitable for load balancing across multiple children with similar capacity.

  Example:
    (make-instance 'round-robin-strategy :name :round-robin :priority 1)

  See Also:
    ROUTING-STRATEGY, LEAST-LOADED-STRATEGY"))

(defmethod select-route ((strategy round-robin-strategy) node envelope available-routes)
  "Round-robin routing: cycle through available routes."
  (declare (ignore node envelope))

  (when (null available-routes)
    (return-from select-route nil))

  (incf (gethash "rr-attempts" (strategy-metrics strategy) 0))

  ;; Use a single counter so routing is evenly distributed across routes.
  (let ((state-key "rr-counter"))
    (bordeaux-threads:with-lock-held ((rr-lock strategy))
      ;; Get current counter value
      (let ((current-idx (gethash state-key (rr-counters strategy) 0))
            (num-routes (length available-routes)))

        ;; Bounds check
        (when (>= current-idx num-routes)
          (setf current-idx 0))

        ;; Select route at current index
        (let ((selected (nth current-idx available-routes)))
          ;; Update counter for next time
          (setf (gethash state-key (rr-counters strategy))
                (mod (1+ current-idx) num-routes))

          (incf (gethash "rr-selections" (strategy-metrics strategy) 0))
          selected)))))

;;;; ============================================================================
;;;; Built-in Strategy 3: LEAST-LOADED-STRATEGY
;;;; ============================================================================

(defclass least-loaded-strategy (routing-strategy)
  ((queue-depths
    :accessor ll-queue-depths
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Cached queue depth for each child"))

  (:documentation "Least-loaded routing strategy.

  Routes to the child with the lowest queue depth (fewest pending messages).
  Queue depth is obtained from child metrics.

  Falls back to first available route if metrics unavailable.

  Suitable for scenarios where children have variable load and we want to
  balance across them.

  Example:
    (make-instance 'least-loaded-strategy :name :least-loaded :priority 2)

  See Also:
    ROUTING-STRATEGY, ROUND-ROBIN-STRATEGY"))

(defmethod select-route ((strategy least-loaded-strategy) node envelope available-routes)
  "Least-loaded routing: choose child with lowest queue depth."
  (declare (ignore envelope))

  (when (null available-routes)
    (return-from select-route nil))

  (incf (gethash "ll-attempts" (strategy-metrics strategy) 0))

  ;; Find child with minimum queue depth
  (let ((best-route nil)
        (min-depth most-positive-fixnum))

    (dolist (route-id available-routes)
      ;; Get queue depth from child metrics (if available)
      (let ((child (get-child node route-id))
            (depth 0))

        (when child
          ;; Try to get queue depth from child's metrics
          ;; This is a placeholder - actual implementation would query gRPC
          (setf depth (gethash (format nil "queue-depth-~A" route-id)
                               (ll-queue-depths strategy) 0)))

        ;; Track minimum
        (when (< depth min-depth)
          (setf min-depth depth
                best-route route-id))))

    (when best-route
      (incf (gethash "ll-selections" (strategy-metrics strategy) 0)))

    best-route))

;;;; ============================================================================
;;;; Built-in Strategy 4: LATENCY-BASED-STRATEGY
;;;; ============================================================================

(defclass latency-based-strategy (routing-strategy)
  ((latency-history
    :accessor lat-latency-history
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Route ID -> exponential moving average of latency")

   (history-alpha
    :initarg :history-alpha
    :accessor lat-history-alpha
    :initform 0.3
    :type float
    :documentation "Smoothing factor for exponential moving average (0.0 to 1.0)"))

  (:documentation "Latency-based routing strategy.

  Routes based on historical latency measurements. Uses exponential moving
  average to track latency for each route, choosing the route with lowest
  average latency.

  Falls back to round-robin for new routes without history.

  Suitable for scenarios where routes have different latency profiles and
  we want to minimize end-to-end latency.

  Args (when creating):
    history-alpha - EMA smoothing factor (default 0.3)
                    Higher = more weight on recent measurements
                    Lower = more weight on historical average

  Example:
    (make-instance 'latency-based-strategy :name :latency :priority 3
                   :history-alpha 0.2)

  See Also:
    ROUTING-STRATEGY, LEAST-LOADED-STRATEGY"))

(defmethod select-route ((strategy latency-based-strategy) node envelope available-routes)
  "Latency-based routing: choose route with lowest historical latency."
  (declare (ignore node))

  (when (null available-routes)
    (return-from select-route nil))

  (incf (gethash "lat-attempts" (strategy-metrics strategy) 0))

  ;; Find route with minimum latency history
  (let ((best-route nil)
        (min-latency most-positive-single-float))

    (dolist (route-id available-routes)
      (let ((latency (gethash route-id (lat-latency-history strategy)
                              nil)))

        ;; New route without history - skip for now (try others first)
        (when latency
          (when (< latency min-latency)
            (setf min-latency latency
                  best-route route-id)))))

    ;; If no historical data, fall back to first available route
    (unless best-route
      (setf best-route (first available-routes))
      (incf (gethash "lat-fallback-rr" (strategy-metrics strategy) 0)))

    (when best-route
      (incf (gethash "lat-selections" (strategy-metrics strategy) 0)))

    best-route))

(defun record-latency (strategy route-id latency-ms)
  "Record a latency measurement for a route.

  Updates the exponential moving average for the route.

  Args:
    strategy - LATENCY-BASED-STRATEGY instance
    route-id - String ID of the route
    latency-ms - Latency measurement in milliseconds

  Returns:
    The updated EMA value.

  Side Effects:
    Updates strategy's latency history.

  Example:
    (record-latency strategy \"cluster-a\" 45.2)

  See Also:
    LATENCY-BASED-STRATEGY, SELECT-ROUTE"
  (declare (type string route-id)
           (type number latency-ms))

  (cond
    ((typep strategy 'latency-based-strategy)
     (let ((alpha (lat-history-alpha strategy))
           (history (lat-latency-history strategy)))
       (let ((previous-ema (gethash route-id history latency-ms)))
         (let ((new-ema (+ (* alpha latency-ms)
                           (* (- 1.0 alpha) previous-ema))))
           (setf (gethash route-id history) new-ema)
           new-ema))))
    ((typep strategy 'routing-table)
     (setf (gethash route-id (routing-table-latency-map strategy)) latency-ms)
     latency-ms)
    (t latency-ms)))

;;;; ============================================================================
;;;; Built-in Strategy 5: WEIGHTED-RANDOM-STRATEGY
;;;; ============================================================================

(defclass weighted-random-strategy (routing-strategy)
  ((route-weights
    :accessor wr-route-weights
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Route ID -> weight (higher = more likely)"))

  (:documentation "Weighted random routing strategy.

  Routes randomly with weights. Each route has an associated weight,
  and selection probability is proportional to weight.

  Weights can be based on:
    - Child capacity (max agents)
    - Child priority
    - Manual configuration

  Example:
    (let ((strategy (make-instance 'weighted-random-strategy :name :weighted)))
      (set-route-weight strategy \"cluster-a\" 70)  ; 70% of traffic
      (set-route-weight strategy \"cluster-b\" 30))  ; 30% of traffic

  See Also:
    ROUTING-STRATEGY, SET-ROUTE-WEIGHT, GET-ROUTE-WEIGHT"))

(defmethod select-route ((strategy weighted-random-strategy) node envelope available-routes)
  "Weighted random routing: random selection with weights."
  (declare (ignore node envelope))

  (when (null available-routes)
    (return-from select-route nil))

  (incf (gethash "wr-attempts" (strategy-metrics strategy) 0))

  ;; Build weighted list
  (let ((weighted-list nil)
        (total-weight 0))

    (dolist (route-id available-routes)
      (let ((weight (gethash route-id (wr-route-weights strategy) 1)))
        ;; Default weight is 1 if not specified
        (incf total-weight weight)
        (push (cons route-id weight) weighted-list)))

    ;; Select randomly based on weights
    (let ((random-value (random (float total-weight)))
          (cumulative 0.0)
          (selected nil))

      (dolist (entry (nreverse weighted-list))
        (destructuring-bind (route-id . weight) entry
          (incf cumulative (float weight))
          (when (and (null selected) (<= random-value cumulative))
            (setf selected route-id))))

      (when selected
        (incf (gethash "wr-selections" (strategy-metrics strategy) 0)))

      selected)))

(defun set-route-weight (strategy route-id weight)
  "Set the weight for a route in weighted-random strategy.

  Args:
    strategy - WEIGHTED-RANDOM-STRATEGY instance
    route-id - String ID of route
    weight - Numeric weight (higher = more likely to be selected)

  Returns:
    The weight value.

  Side Effects:
    Updates route weight in strategy.

  Example:
    (set-route-weight strategy \"cluster-a\" 75)

  See Also:
    GET-ROUTE-WEIGHT, WEIGHTED-RANDOM-STRATEGY"
  (declare (type string route-id)
           (type number weight))

  (cond
    ((typep strategy 'weighted-random-strategy)
     (setf (gethash route-id (wr-route-weights strategy)) weight))
    ((typep strategy 'routing-table)
     (setf (gethash route-id (routing-table-weight-map strategy)) weight))
    (t weight)))

(defun get-route-weight (strategy route-id)
  "Get the weight for a route in weighted-random strategy.

  Args:
    strategy - WEIGHTED-RANDOM-STRATEGY instance
    route-id - String ID of route

  Returns:
    Numeric weight, or 1 (default) if not set.

  Example:
    (get-route-weight strategy \"cluster-a\")
    => 75

  See Also:
    SET-ROUTE-WEIGHT, WEIGHTED-RANDOM-STRATEGY"
  (declare (type string route-id))

  (cond
    ((typep strategy 'weighted-random-strategy)
     (gethash route-id (wr-route-weights strategy) 1))
    ((typep strategy 'routing-table)
     (gethash route-id (routing-table-weight-map strategy) 1))
    (t 1)))

;;;; ============================================================================
;;;; Built-in Strategy 6: FAILOVER-STRATEGY
;;;; ============================================================================

(defclass failover-strategy (routing-strategy)
  ((primary-route
    :initarg :primary-route
    :accessor failover-primary-route
    :type string
    :documentation "ID of primary route to try first")

   (secondary-route
    :initarg :secondary-route
    :accessor failover-secondary-route
    :initform nil
    :type (or null string)
    :documentation "ID of secondary route (fallback)")

   (route-health
    :accessor failover-route-health
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Route ID -> health status (T=healthy, NIL=unhealthy)")

   (health-recovery-time
    :initarg :health-recovery-time
    :accessor failover-health-recovery-time
    :initform 60
    :type integer
    :documentation "Seconds before marking unhealthy route as eligible again")

   (last-unhealthy-time
    :accessor failover-last-unhealthy-time
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Route ID -> timestamp when marked unhealthy"))

  (:documentation "Failover routing strategy.

  Maintains a primary route and optional secondary route. Routes to primary
  first; if primary is unhealthy, tries secondary.

  Routes can be marked healthy or unhealthy, with automatic recovery after
  a specified duration.

  Suitable for critical paths that must maintain availability.

  Args (when creating):
    primary-route - String ID of primary route (required)
    secondary-route - String ID of secondary route (optional)
    health-recovery-time - Seconds before recovery attempt (default 60)

  Example:
    (make-instance 'failover-strategy
      :name :failover
      :primary-route \"cluster-a\"
      :secondary-route \"cluster-b\"
      :health-recovery-time 120)

  See Also:
    ROUTING-STRATEGY, MARK-ROUTE-HEALTHY, MARK-ROUTE-UNHEALTHY"))

(defmethod select-route ((strategy failover-strategy) node envelope available-routes)
  "Failover routing: try primary, fall back to secondary if unhealthy."
  (declare (ignore node envelope))

  (when (null available-routes)
    (return-from select-route nil))

  (incf (gethash "fo-attempts" (strategy-metrics strategy) 0))

  ;; Check if primary is available and healthy
  (let ((primary (failover-primary-route strategy))
        (secondary (failover-secondary-route strategy))
        (selected nil))

    ;; Try primary first
    (when (and primary
               (member primary available-routes :test #'string=)
               (route-healthy-p strategy primary))
      (setf selected primary)
      (incf (gethash "fo-primary-used" (strategy-metrics strategy) 0)))

    ;; Try secondary if primary unavailable
    (when (null selected)
      (when (and secondary
                 (member secondary available-routes :test #'string=)
                 (route-healthy-p strategy secondary))
        (setf selected secondary)
        (incf (gethash "fo-secondary-used" (strategy-metrics strategy) 0))))

    ;; Fall back to any available route
    (when (null selected)
      (setf selected (first available-routes))
      (incf (gethash "fo-fallback-any" (strategy-metrics strategy) 0)))

    selected))

(defun route-healthy-p (strategy route-id)
  "Check if a route is healthy in failover strategy.

  A route is healthy if:
    1. Explicitly marked as healthy, OR
    2. Was marked unhealthy but recovery time has elapsed

  Args:
    strategy - FAILOVER-STRATEGY instance
    route-id - String ID of route

  Returns:
    T if route is healthy, NIL if unhealthy.

  Example:
    (route-healthy-p strategy \"cluster-a\")
    => T

  See Also:
    MARK-ROUTE-HEALTHY, MARK-ROUTE-UNHEALTHY, FAILOVER-STRATEGY"
  (declare (type string route-id))

  (cond
    ((typep strategy 'failover-strategy)
     (let ((health (gethash route-id (failover-route-health strategy) T)))
       (when health
         (return-from route-healthy-p T))
       (let ((unhealthy-time (gethash route-id (failover-last-unhealthy-time strategy))))
         (when unhealthy-time
           (let ((elapsed (- (get-universal-time) unhealthy-time))
                 (recovery-time (failover-health-recovery-time strategy)))
             (if (>= elapsed recovery-time)
                 (progn
                   (mark-route-healthy strategy route-id)
                   T)
                 NIL))))))
    ((typep strategy 'routing-table)
     (gethash route-id (routing-table-health-map strategy) T))
    (t
     T)))

(defun mark-route-healthy (strategy route-id)
  "Mark a route as healthy in failover strategy.

  Args:
    strategy - FAILOVER-STRATEGY instance
    route-id - String ID of route

  Returns:
    NIL

  Side Effects:
    Updates route health status.

  Example:
    (mark-route-healthy strategy \"cluster-a\")

  See Also:
    MARK-ROUTE-UNHEALTHY, ROUTE-HEALTHY-P, FAILOVER-STRATEGY"
  (declare (type string route-id))

  (cond
    ((typep strategy 'failover-strategy)
     (setf (gethash route-id (failover-route-health strategy)) T))
    ((typep strategy 'routing-table)
     (setf (gethash route-id (routing-table-health-map strategy)) T))
    (t nil)))

(defun mark-route-unhealthy (strategy route-id &key (duration 60))
  "Mark a route as unhealthy in failover strategy.

  Args:
    strategy - FAILOVER-STRATEGY instance
    route-id - String ID of route
    duration - Seconds to keep marked unhealthy (default 60)

  Returns:
    NIL

  Side Effects:
    Updates route health status and records timestamp.

  Example:
    (mark-route-unhealthy strategy \"cluster-a\" :duration 120)

  See Also:
    MARK-ROUTE-HEALTHY, ROUTE-HEALTHY-P, FAILOVER-STRATEGY"
  (declare (type string route-id)
           (type (integer 0) duration))

  (cond
    ((typep strategy 'failover-strategy)
     (setf (gethash route-id (failover-route-health strategy)) NIL)
     (setf (gethash route-id (failover-last-unhealthy-time strategy))
           (get-universal-time)))
    ((typep strategy 'routing-table)
     (setf (gethash route-id (routing-table-health-map strategy)) NIL))
    (t nil)))

(defun reset-route-health (strategy route-id)
  "Reset health status for a route (mark as healthy and clear history).

  Args:
    strategy - FAILOVER-STRATEGY instance
    route-id - String ID of route

  Returns:
    NIL

  Side Effects:
    Clears health status and unhealthy timestamp.

  Example:
    (reset-route-health strategy \"cluster-a\")

  See Also:
    MARK-ROUTE-HEALTHY, MARK-ROUTE-UNHEALTHY, FAILOVER-STRATEGY"
  (declare (type string route-id))

  (cond
    ((typep strategy 'failover-strategy)
     (remhash route-id (failover-route-health strategy))
     (remhash route-id (failover-last-unhealthy-time strategy)))
    ((typep strategy 'routing-table)
     (remhash route-id (routing-table-health-map strategy)))
    (t nil)))

;;;; ============================================================================
;;;; Built-in Strategy 7: BROADCAST-STRATEGY
;;;; ============================================================================

(defclass broadcast-strategy (routing-strategy)
  ()
  (:documentation "Broadcast routing strategy.

  Routes to ALL matching destinations, creating envelope copies for each.
  Used for fanout operations and discovery patterns.

  This strategy doesn't select a single route - instead, it returns a special
  marker that tells the router to broadcast.

  Example:
    (make-instance 'broadcast-strategy :name :broadcast)

  See Also:
    ROUTING-STRATEGY, SELECT-ROUTE"))

(defmethod select-route ((strategy broadcast-strategy) node envelope available-routes)
  "Broadcast routing: special marker for broadcasting to all routes."
  (declare (ignore strategy node envelope available-routes))

  ;; Return special keyword to indicate broadcast
  ;; The router will handle this specially
  :broadcast)

;;;; ============================================================================
;;;; Strategy Composition: Composite Strategy
;;;; ============================================================================

(defclass composite-strategy (routing-strategy)
  ((strategies
    :initarg :strategies
    :accessor composite-strategies
    :type list
    :documentation "List of child strategies to try in order"))

  (:documentation "Composite strategy that chains multiple strategies.

  Tries each strategy in order until one returns a non-NIL route.
  Useful for combining strategies (e.g., try least-loaded, fall back to round-robin).

  Example:
    (make-instance 'composite-strategy
      :name :combined
      :strategies (list
        (make-instance 'least-loaded-strategy)
        (make-instance 'round-robin-strategy)))

  See Also:
    ROUTING-STRATEGY, MAKE-COMPOSITE-STRATEGY, FALLBACK-STRATEGY"))

(defmethod select-route ((strategy composite-strategy) node envelope available-routes)
  "Composite routing: try each strategy in order."
  (incf (gethash "composite-attempts" (strategy-metrics strategy) 0))

  ;; Try each child strategy in order
  (dolist (child-strategy (composite-strategies strategy))
    (let ((result (select-route child-strategy node envelope available-routes)))
      (when result
        (incf (gethash "composite-selections" (strategy-metrics strategy) 0))
        (return-from select-route result))))

  ;; No strategy succeeded
  nil)

(defun make-composite-strategy (&rest args)
  "Create a composite strategy that chains multiple strategies.

  Accepts either (NAME STRATEGY...) or (STRATEGY...).
  Defaults name to :composite when omitted."
  (cond
    ((and args (typep (first args) 'routing-strategy))
     (make-instance 'composite-strategy
                    :name :composite
                    :strategies args))
    (t
     (let ((name (first args))
           (strategies (rest args)))
       (make-instance 'composite-strategy
                      :name name
                      :strategies strategies)))))

;;;; ============================================================================
;;;; Strategy Composition: Fallback Strategy
;;;; ============================================================================

(defclass fallback-strategy (routing-strategy)
  ((primary-strategy
    :initarg :primary-strategy
    :accessor fallback-primary-strategy
    :type routing-strategy
    :documentation "Primary strategy to try first")

   (fallback-strategy
    :initarg :fallback-strategy
    :accessor fallback-fallback-strategy
    :type routing-strategy
    :documentation "Fallback strategy if primary returns NIL"))

  (:documentation "Fallback strategy that uses secondary strategy on failure.

  Tries primary strategy first. If it returns NIL, tries fallback strategy.
  Useful for best-effort routing with graceful degradation.

  Example:
    (make-instance 'fallback-strategy
      :name :best-effort
      :primary-strategy (make-instance 'latency-based-strategy)
      :fallback-strategy (make-instance 'round-robin-strategy))

  See Also:
    ROUTING-STRATEGY, MAKE-FALLBACK-STRATEGY, COMPOSITE-STRATEGY"))

(defmethod select-route ((strategy fallback-strategy) node envelope available-routes)
  "Fallback routing: try primary, use fallback if primary returns NIL."
  (incf (gethash "fallback-attempts" (strategy-metrics strategy) 0))

  ;; Try primary strategy
  (let ((result (select-route (fallback-primary-strategy strategy)
                              node envelope available-routes)))
    (if result
        (progn
          (incf (gethash "fallback-primary-used" (strategy-metrics strategy) 0))
          result)
        ;; Primary failed, try fallback
        (progn
          (incf (gethash "fallback-fallback-used" (strategy-metrics strategy) 0))
          (select-route (fallback-fallback-strategy strategy)
                        node envelope available-routes)))))

(defun make-fallback-strategy (&rest args)
  "Create a fallback strategy.

  Accepts either (NAME PRIMARY FALLBACK) or (PRIMARY FALLBACK).
  Defaults name to :fallback when omitted."
  (cond
    ((and (= (length args) 2)
          (typep (first args) 'routing-strategy)
          (typep (second args) 'routing-strategy))
     (make-instance 'fallback-strategy
                    :name :fallback
                    :primary-strategy (first args)
                    :fallback-strategy (second args)))
    ((= (length args) 3)
     (make-instance 'fallback-strategy
                    :name (first args)
                    :primary-strategy (second args)
                    :fallback-strategy (third args)))
    (t
     (error "MAKE-FALLBACK-STRATEGY expects (PRIMARY FALLBACK) or (NAME PRIMARY FALLBACK)."))))

;;;; ============================================================================
;;;; Strategy Composition: Conditional Strategy
;;;; ============================================================================

(defclass conditional-strategy (routing-strategy)
  ((predicate
    :initarg :predicate
    :accessor conditional-predicate
    :type function
    :documentation "Predicate function (node, envelope) -> boolean")

   (true-strategy
    :initarg :true-strategy
    :accessor conditional-true-strategy
    :type routing-strategy
    :documentation "Strategy to use if predicate is true")

   (false-strategy
    :initarg :false-strategy
    :accessor conditional-false-strategy
    :initform nil
    :type (or null routing-strategy)
    :documentation "Strategy to use if predicate is false (optional)"))

  (:documentation "Conditional strategy that chooses based on a predicate.

  Evaluates a predicate with node and envelope, then uses true-strategy
  or false-strategy based on result.

  Useful for context-aware routing (e.g., route differently based on
  envelope priority, source swarm, payload type, etc.).

  Example:
    (make-instance 'conditional-strategy
      :name :priority-aware
      :predicate (lambda (node envelope)
                   (let ((payload (envelope-payload envelope)))
                     (eq (getf payload :priority) :high)))
      :true-strategy (make-instance 'least-loaded-strategy)
      :false-strategy (make-instance 'round-robin-strategy))

  See Also:
    ROUTING-STRATEGY, MAKE-CONDITIONAL-STRATEGY"))

(defmethod select-route ((strategy conditional-strategy) node envelope available-routes)
  "Conditional routing: choose strategy based on predicate."
  (incf (gethash "conditional-attempts" (strategy-metrics strategy) 0))

  ;; Evaluate predicate
  (let ((predicate-result (funcall (conditional-predicate strategy)
                                   node envelope)))

    ;; Choose strategy based on predicate
    (let ((chosen-strategy (if predicate-result
                              (conditional-true-strategy strategy)
                              (conditional-false-strategy strategy))))

      (if chosen-strategy
          (progn
            (if predicate-result
                (incf (gethash "conditional-true" (strategy-metrics strategy) 0))
                (incf (gethash "conditional-false" (strategy-metrics strategy) 0)))
            (select-route chosen-strategy node envelope available-routes))
          nil))))

(defun make-conditional-strategy (&rest args)
  "Create a conditional strategy.

  Accepts either (PREDICATE TRUE FALSE) or (NAME PREDICATE TRUE FALSE).
  Defaults name to :conditional when omitted."
  (cond
    ((and (>= (length args) 2)
          (functionp (first args))
          (typep (second args) 'routing-strategy))
     (make-instance 'conditional-strategy
                    :name :conditional
                    :predicate (first args)
                    :true-strategy (second args)
                    :false-strategy (third args)))
    ((>= (length args) 3)
     (make-instance 'conditional-strategy
                    :name (first args)
                    :predicate (second args)
                    :true-strategy (third args)
                    :false-strategy (fourth args)))
    (t
     (error "MAKE-CONDITIONAL-STRATEGY expects (PREDICATE TRUE [FALSE]) or (NAME PREDICATE TRUE [FALSE])."))))

;;;; ============================================================================
;;;; Strategy Configuration Management
;;;; ============================================================================

(defvar *default-routing-strategy* nil
  "Default routing strategy for new orchestrator nodes.

  When a node is created without an explicit strategy, this strategy is used.
  Initially NIL (uses DIRECT-ROUTING-STRATEGY).

  Example:
    (setf *default-routing-strategy*
          (make-instance 'round-robin-strategy :name :default))")

(defvar *registered-strategies* (make-hash-table :test 'equal)
  "Global registry of named strategies.

  Maps strategy names (strings) to ROUTING-STRATEGY instances.
  Allows strategies to be registered globally and referenced by name.

  See Also:
    REGISTER-STRATEGY, GET-STRATEGY")

(defun register-strategy (name strategy)
  "Register a strategy with a global name.

  Args:
    name - String or keyword identifying the strategy
    strategy - ROUTING-STRATEGY instance

  Returns:
    The strategy (for convenience).

  Side Effects:
    Adds strategy to global registry.

  Example:
    (register-strategy \"my-strategy\"
      (make-instance 'round-robin-strategy))

    (let ((strat (get-strategy \"my-strategy\")))
      ...)

  See Also:
    GET-STRATEGY, UNREGISTER-STRATEGY, *REGISTERED-STRATEGIES*"
  (declare (type (or string keyword) name))

  (let ((key (if (keywordp name) (string-downcase (symbol-name name)) name)))
    (setf (gethash key *registered-strategies*) strategy))
  strategy)

(defun get-strategy (name)
  "Retrieve a registered strategy by name.

  Args:
    name - String or keyword identifying the strategy

  Returns:
    ROUTING-STRATEGY instance, or NIL if not found.

  Example:
    (let ((strategy (get-strategy \"my-strategy\")))
      (if strategy
          (route-with-strategy strategy ...)
          (error \"Strategy not found\")))

  See Also:
    REGISTER-STRATEGY, UNREGISTER-STRATEGY, *REGISTERED-STRATEGIES*"
  (declare (type (or string keyword) name))

  (let ((key (if (keywordp name) (string-downcase (symbol-name name)) name)))
    (gethash key *registered-strategies*)))

(defun unregister-strategy (name)
  "Remove a strategy from the global registry.

  Args:
    name - String or keyword identifying the strategy

  Returns:
    NIL

  Side Effects:
    Removes strategy from global registry.

  Example:
    (unregister-strategy \"old-strategy\")

  See Also:
    REGISTER-STRATEGY, GET-STRATEGY"
  (declare (type (or string keyword) name))

  (let ((key (if (keywordp name) (string-downcase (symbol-name name)) name)))
    (remhash key *registered-strategies*))
  nil)

;;;; ============================================================================
;;;; Strategy Context Manager
;;;; ============================================================================

(defmacro with-routing-strategy ((strategy) &body body)
  "Temporarily change the default routing strategy within a scope.

  Args:
    strategy - ROUTING-STRATEGY instance to use as default
    body - Forms to execute with strategy active

  Returns:
    Result of last form in body.

  Side Effects:
    Temporarily binds *DEFAULT-ROUTING-STRATEGY*.

  Example:
    (with-routing-strategy ((make-instance 'round-robin-strategy))
      (route-envelope *root* envelope))

  See Also:
    *DEFAULT-ROUTING-STRATEGY*, ROUTING-STRATEGY"
  `(let ((*default-routing-strategy* ,strategy))
     ,@body))

(defun %ensure-strategy-name (args default-name)
  "Ensure ARGS contains a :name keyword, appending DEFAULT-NAME if missing."
  (if (member :name args)
      args
      (append args (list :name default-name))))

;;;; ============================================================================
;;;; Strategy Factory
;;;; ============================================================================

(defun make-strategy (type &rest args)
  "Create a strategy instance by type.

  Factory function for creating strategies by keyword type.

  Args:
    type - Keyword type (:direct, :round-robin, :least-loaded, :latency,
                        :weighted, :failover, :broadcast)
    args - Strategy-specific arguments

  Returns:
    New ROUTING-STRATEGY instance.

  Examples:
    (make-strategy :direct :name :default)
    (make-strategy :round-robin :name :balanced)
    (make-strategy :latency :name :fast :history-alpha 0.2)
    (make-strategy :failover :name :resilient
                   :primary-route \"cluster-a\"
                   :secondary-route \"cluster-b\")

  Supported types:
    :direct              -> DIRECT-ROUTING-STRATEGY
    :round-robin         -> ROUND-ROBIN-STRATEGY
    :least-loaded        -> LEAST-LOADED-STRATEGY
    :latency             -> LATENCY-BASED-STRATEGY
    :weighted            -> WEIGHTED-RANDOM-STRATEGY
    :failover            -> FAILOVER-STRATEGY
    :broadcast           -> BROADCAST-STRATEGY

  See Also:
    ROUTING-STRATEGY, REGISTER-STRATEGY"
  (let ((normalized-type (case type
                           (:latency-based :latency)
                           (:weighted-random :weighted)
                           (t type))))
    (ecase normalized-type
      (:direct
       (apply #'make-instance 'direct-routing-strategy
              (%ensure-strategy-name args :direct)))

      (:round-robin
       (apply #'make-instance 'round-robin-strategy
              (%ensure-strategy-name args :round-robin)))

      (:least-loaded
       (apply #'make-instance 'least-loaded-strategy
              (%ensure-strategy-name args :least-loaded)))

      (:latency
       (apply #'make-instance 'latency-based-strategy
              (%ensure-strategy-name args :latency-based)))

      (:weighted
       (apply #'make-instance 'weighted-random-strategy
              (%ensure-strategy-name args :weighted-random)))

      (:failover
       (apply #'make-instance 'failover-strategy
              (%ensure-strategy-name args :failover)))

      (:broadcast
       (apply #'make-instance 'broadcast-strategy
              (%ensure-strategy-name args :broadcast))))))

;;;; ============================================================================
;;;; Strategy Metrics and Statistics
;;;; ============================================================================

(defun get-strategy-statistics (strategy)
  "Get statistics collected by a strategy.

  Returns:
    Property list of metric name -> value pairs.

  Examples:
    (get-strategy-statistics strategy)
    => (:direct-attempts 100 :direct-hits 95
        :rr-attempts 50 :rr-selections 50)

  See Also:
    STRATEGY-METRICS, RECORD-STRATEGY-METRIC"
  (declare (type routing-strategy strategy))

  (let ((result nil))
    (maphash (lambda (key value)
               (push (intern (string-upcase key) :keyword) result)
               (push value result))
             (strategy-metrics strategy))
    (or result (list :metrics 0))))

(defun reset-strategy-statistics (strategy)
  "Reset all collected statistics for a strategy.

  Args:
    strategy - ROUTING-STRATEGY instance

  Returns:
    NIL

  Side Effects:
    Clears all metrics from strategy.

  Example:
    (reset-strategy-statistics strategy)

  See Also:
    GET-STRATEGY-STATISTICS, STRATEGY-METRICS"
  (declare (type routing-strategy strategy))

  (clrhash (strategy-metrics strategy))
  nil)

;;;; ============================================================================
;;;; Strategy Introspection and Debugging
;;;; ============================================================================

(defmethod print-object ((strategy routing-strategy) stream)
  "Print strategy in readable format.

  Format:
    #<STRATEGY-TYPE name strategy-name priority=N>"
  (print-unreadable-object (strategy stream :type t)
    (format stream "~A priority=~D"
            (strategy-name strategy)
            (strategy-priority strategy))))

(defun describe-strategy (strategy &optional (stream *standard-output*))
  "Print detailed description of a strategy.

  Args:
    strategy - ROUTING-STRATEGY instance
    stream - Output stream (default: *standard-output*)

  Returns:
    NIL

  Side Effects:
    Writes to stream.

  Example:
    (describe-strategy my-strategy)

  See Also:
    PRINT-OBJECT, GET-STRATEGY-STATISTICS"
  (declare (type routing-strategy strategy)
           (type stream stream))

  (format stream "~&Strategy: ~A~%" (strategy-name strategy))
  (format stream "  Type: ~A~%" (type-of strategy))
  (format stream "  Priority: ~D~%" (strategy-priority strategy))
  (format stream "  Metrics:~%")

  (let ((stats (get-strategy-statistics strategy)))
    (if (null stats)
        (format stream "    (none)~%")
        (loop for (key value) on stats by #'cddr
              do (format stream "    ~A: ~D~%" key value))))

  nil)

;;;; End of file
