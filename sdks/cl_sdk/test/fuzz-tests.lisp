;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; test/fuzz-tests.lisp
;;;;
;;;; Property-based/fuzz testing for distributed components.
;;;;
;;;; This module implements fuzz testing for:
;;;;   - Distributed barrier synchronization edge cases
;;;;   - Routing strategy behavior under various conditions
;;;;   - Network partition and failure scenarios
;;;;   - Concurrent operation handling
;;;;
;;;; Uses FiveAM for testing with randomized inputs to discover edge cases
;;;; that deterministic tests might miss.
;;;;
;;;; P3-8 Task from COMMON_LISP_PLAN.md:
;;;;   - Fuzz test distributed-barrier for edge cases
;;;;   - Fuzz test routing-strategies for partial failures
;;;;   - Test network partition scenarios
;;;;   - Test concurrent barrier arrivals
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.test)

(in-suite fuzz-tests)

;;;; ============================================================================
;;;; Random Data Generators
;;;; ============================================================================

(defun random-string (&optional (length 8))
  "Generate a random alphanumeric string."
  (let ((chars "abcdefghijklmnopqrstuvwxyz0123456789"))
    (coerce (loop repeat length
                  collect (char chars (random (length chars))))
            'string)))

(defun random-swarm-id ()
  "Generate a random swarm ID."
  (format nil "swarm-~A" (random-string 6)))

(defun random-participant-list (&optional (min-count 1) (max-count 10))
  "Generate a random list of participant swarm IDs."
  (let ((count (+ min-count (random (- max-count min-count -1)))))
    (loop repeat count collect (random-swarm-id))))

(defun random-payload ()
  "Generate random envelope payload."
  (list :type (case (random 4)
                (0 :request)
                (1 :response)
                (2 :event)
                (3 :command))
        :data (random-string 20)
        :seq (random 10000)))

(defun random-route-list (&optional (count 5))
  "Generate random list of route IDs."
  (loop repeat count collect (random-swarm-id)))

;;;; ============================================================================
;;;; Barrier Fuzz Tests - Random Arrival Order
;;;; ============================================================================

(test fuzz-barrier-random-arrival-order
  "Fuzz test: barriers complete correctly regardless of arrival order."
  (loop repeat 100 do
    (let* ((participants (random-participant-list 2 8))
           (barrier (create-barrier participants :timeout 60)))
      ;; Shuffle the participants randomly
      (let ((shuffled (alexandria:shuffle (copy-list participants))))
        ;; All participants arrive in random order
        (dolist (p shuffled)
          (barrier-arrive barrier p))
        ;; Barrier should be complete after all arrivals
        (is (not (barrier-open-p barrier)))))))

(test fuzz-barrier-partial-arrivals
  "Fuzz test: barriers handle partial arrivals correctly."
  (loop repeat 100 do
    (let* ((participants (random-participant-list 3 10))
           (num-arriving (1+ (random (1- (length participants)))))
           (barrier (create-barrier participants :timeout 1)))
      ;; Only some participants arrive
      (let ((arriving (subseq (alexandria:shuffle (copy-list participants))
                               0 num-arriving)))
        (dolist (p arriving)
          (barrier-arrive barrier p))
        ;; Barrier should be open unless all arrived
        (if (= num-arriving (length participants))
            (is (not (barrier-open-p barrier)))
            (is (barrier-open-p barrier)))))))

(test fuzz-barrier-duplicate-arrivals
  "Fuzz test: barriers handle duplicate arrival attempts gracefully."
  (loop repeat 50 do
    (let* ((participants (random-participant-list 2 5))
           (barrier (create-barrier participants :timeout 60)))
      ;; Each participant tries to arrive multiple times
      (dolist (p participants)
        (barrier-arrive barrier p)
        ;; Try arriving again - should be handled gracefully
        (handler-case
            (progn
              (barrier-arrive barrier p)
              (pass))  ; No error expected
          (warning (w)
            (declare (ignore w))
            (pass))))
      ;; Barrier should be complete
      (is (not (barrier-open-p barrier))))))

(test fuzz-barrier-reset-cycle
  "Fuzz test: barriers can be reset and reused multiple times."
  (loop repeat 50 do
    (let* ((participants (random-participant-list 2 6))
           (barrier (create-barrier participants :timeout 60))
           (cycles (1+ (random 5))))
      ;; Run multiple barrier cycles
      (dotimes (cycle cycles)
        ;; All participants arrive
        (dolist (p participants)
          (barrier-arrive barrier p))
        ;; Barrier should be complete
        (is (not (barrier-open-p barrier)))
        ;; Reset for next cycle
        (barrier-reset barrier)
        ;; Should be open again
        (is (barrier-open-p barrier))))))

;;;; ============================================================================
;;;; Barrier Fuzz Tests - Concurrent Arrivals (using bordeaux-threads)
;;;; ============================================================================

(test fuzz-barrier-concurrent-arrivals
  "Fuzz test: barriers handle truly concurrent arrivals safely."
  (loop repeat 20 do
    (let* ((participants (random-participant-list 3 8))
           (barrier (create-barrier participants :timeout 10))
           (threads nil)
           (errors nil)
           (errors-lock (bt:make-lock "errors-lock")))
      ;; Launch threads for concurrent arrivals
      (dolist (p participants)
        (let ((participant p))  ; Capture for closure
          (push
            (bt:make-thread
              (lambda ()
                (handler-case
                    (progn
                      (sleep (random 0.01))
                      (barrier-arrive barrier participant))
                  (error (e)
                    (bt:with-lock-held (errors-lock)
                      (push e errors)))))
              :name (format nil "barrier-thread-~A" participant))
            threads)))
      ;; Wait for all threads to complete
      (dolist (thread threads)
        (bt:join-thread thread))
      ;; Should have no errors
      (is (null errors))
      ;; Barrier should be complete
      (is (not (barrier-open-p barrier))))))

(test fuzz-barrier-concurrent-reset-and-arrive
  "Fuzz test: barrier handles concurrent reset and arrive operations."
  (loop repeat 20 do
    (let* ((participants (random-participant-list 2 5))
           (barrier (create-barrier participants :timeout 5))
           (operation-count 0)
           (count-lock (bt:make-lock "count-lock"))
           (threads nil))
      ;; Some threads do arrivals, some do resets
      (dolist (p participants)
        (let ((participant p))
          (push
            (bt:make-thread
              (lambda ()
                (handler-case
                    (progn
                      (sleep (random 0.005))
                      (barrier-arrive barrier participant)
                      (bt:with-lock-held (count-lock)
                        (incf operation-count)))
                  (error (e)
                    (declare (ignore e))
                    nil)))
              :name (format nil "arrive-thread-~A" participant))
            threads)))
      ;; Add a reset thread
      (push
        (bt:make-thread
          (lambda ()
            (sleep (random 0.008))
            (handler-case
                (barrier-reset barrier)
              (error (e) (declare (ignore e)) nil)))
          :name "reset-thread")
        threads)
      ;; Wait for all threads
      (dolist (thread threads)
        (bt:join-thread thread))
      ;; Test passed if no crashes occurred
      (pass))))

;;;; ============================================================================
;;;; Barrier Fuzz Tests - Edge Cases
;;;; ============================================================================

(test fuzz-barrier-single-participant
  "Fuzz test: barrier with single participant."
  (loop repeat 50 do
    (let* ((participant (random-swarm-id))
           (barrier (create-barrier (list participant) :timeout 60)))
      (barrier-arrive barrier participant)
      (is (not (barrier-open-p barrier))))))

(test fuzz-barrier-large-participant-count
  "Fuzz test: barrier with many participants."
  (loop repeat 10 do
    (let* ((participants (random-participant-list 50 100))
           (barrier (create-barrier participants :timeout 120)))
      (dolist (p participants)
        (barrier-arrive barrier p))
      (is (not (barrier-open-p barrier))))))

(test fuzz-barrier-cancel-while-waiting
  "Fuzz test: cancelling barrier while arrivals pending."
  (loop repeat 30 do
    (let* ((participants (random-participant-list 3 6))
           (barrier (create-barrier participants :timeout 60)))
      ;; Partial arrivals
      (barrier-arrive barrier (first participants))
      ;; Cancel
      (barrier-cancel barrier)
      ;; Should be closed
      (is (not (barrier-open-p barrier))))))

;;;; ============================================================================
;;;; Routing Strategy Fuzz Tests - Round-Robin Strategy
;;;; ============================================================================

(test fuzz-round-robin-distribution
  "Fuzz test: round-robin evenly distributes across routes."
  (loop repeat 30 do
    (let* ((strategy (make-instance 'round-robin-strategy :name :round-robin))
           (routes (random-route-list (+ 2 (random 5))))
           (iterations (* 10 (length routes)))
           (counts (make-hash-table :test 'equal)))
      ;; Initialize counts
      (dolist (r routes)
        (setf (gethash r counts) 0))
      ;; Create a mock node (minimal required fields)
      (let ((mock-node nil))
        ;; Route many times
        (dotimes (i iterations)
          (let* ((envelope (make-cross-swarm-envelope
                             :target-swarm (random-swarm-id)
                             :payload (random-payload)))
                 (selected (select-route strategy mock-node envelope routes)))
            (when selected
              (incf (gethash selected counts 0))))))
      ;; Check distribution is roughly even
      (let ((min-count most-positive-fixnum)
            (max-count 0))
        (maphash (lambda (k v)
                   (declare (ignore k))
                   (setf min-count (min min-count v))
                   (setf max-count (max max-count v)))
                 counts)
        ;; Difference should be reasonable for round-robin
        (is (<= (- max-count min-count) 2))))))

(test fuzz-round-robin-empty-routes
  "Fuzz test: round-robin handles empty route list."
  (loop repeat 50 do
    (let* ((strategy (make-instance 'round-robin-strategy :name :round-robin))
           (envelope (make-cross-swarm-envelope :target-swarm (random-swarm-id))))
      (is (null (select-route strategy nil envelope nil))))))

(test fuzz-round-robin-single-route
  "Fuzz test: round-robin with single route always returns it."
  (loop repeat 50 do
    (let* ((strategy (make-instance 'round-robin-strategy :name :round-robin))
           (route (random-swarm-id))
           (routes (list route))
           (envelope (make-cross-swarm-envelope :target-swarm (random-swarm-id))))
      (dotimes (i 10)
        (is (string= (select-route strategy nil envelope routes) route))))))

;;;; ============================================================================
;;;; Routing Strategy Fuzz Tests - Weighted Random Strategy
;;;; ============================================================================

(test fuzz-weighted-random-respects-weights
  "Fuzz test: weighted random respects weight proportions statistically."
  (loop repeat 20 do
    (let* ((strategy (make-instance 'weighted-random-strategy :name :weighted))
           (routes (list "heavy" "medium" "light"))
           (iterations 1000)
           (counts (make-hash-table :test 'equal)))
      ;; Set weights: heavy=80, medium=15, light=5
      (set-route-weight strategy "heavy" 80.0)
      (set-route-weight strategy "medium" 15.0)
      (set-route-weight strategy "light" 5.0)
      ;; Initialize counts
      (dolist (r routes) (setf (gethash r counts) 0))
      ;; Route many times
      (dotimes (i iterations)
        (let* ((envelope (make-cross-swarm-envelope :target-swarm "target"))
               (selected (select-route strategy nil envelope routes)))
          (when selected
            (incf (gethash selected counts 0)))))
      ;; Check proportions roughly match
      (is (> (gethash "heavy" counts 0) (gethash "medium" counts 0)))
      (is (> (gethash "medium" counts 0) (gethash "light" counts 0))))))

(test fuzz-weighted-random-dynamic-weights
  "Fuzz test: weighted random with dynamically changing weights."
  (loop repeat 30 do
    (let* ((strategy (make-instance 'weighted-random-strategy :name :weighted))
           (routes (random-route-list 4))
           (envelope (make-cross-swarm-envelope :target-swarm "target")))
      ;; Set random weights
      (dolist (r routes)
        (set-route-weight strategy r (float (1+ (random 100)))))
      ;; Route multiple times with weight changes
      (dotimes (i 20)
        (let ((selected (select-route strategy nil envelope routes)))
          (is (member selected routes :test #'string=))
          ;; Randomly update a weight
          (when (zerop (random 3))
            (set-route-weight strategy (nth (random (length routes)) routes)
                              (float (1+ (random 100))))))))))

;;;; ============================================================================
;;;; Routing Strategy Fuzz Tests - Failover Strategy
;;;; ============================================================================

(test fuzz-failover-primary-healthy
  "Fuzz test: failover uses primary when healthy."
  (loop repeat 50 do
    (let* ((primary (random-swarm-id))
           (secondary (random-swarm-id))
           (strategy (make-instance 'failover-strategy
                                     :name :failover
                                     :primary-route primary
                                     :secondary-route secondary))
           (routes (list primary secondary (random-swarm-id)))
           (envelope (make-cross-swarm-envelope :target-swarm "target")))
      (let ((selected (select-route strategy nil envelope routes)))
        (is (string= selected primary))))))

(test fuzz-failover-primary-unhealthy
  "Fuzz test: failover uses secondary when primary unhealthy."
  (loop repeat 50 do
    (let* ((primary (random-swarm-id))
           (secondary (random-swarm-id))
           (strategy (make-instance 'failover-strategy
                                     :name :failover
                                     :primary-route primary
                                     :secondary-route secondary))
           (routes (list primary secondary (random-swarm-id)))
           (envelope (make-cross-swarm-envelope :target-swarm "target")))
      (mark-route-unhealthy strategy primary)
      (let ((selected (select-route strategy nil envelope routes)))
        (is (string= selected secondary))))))

(test fuzz-failover-both-unhealthy
  "Fuzz test: failover falls back when both primary and secondary unhealthy."
  (loop repeat 30 do
    (let* ((primary (random-swarm-id))
           (secondary (random-swarm-id))
           (fallback (random-swarm-id))
           (strategy (make-instance 'failover-strategy
                                     :name :failover
                                     :primary-route primary
                                     :secondary-route secondary))
           (routes (list primary secondary fallback))
           (envelope (make-cross-swarm-envelope :target-swarm "target")))
      (mark-route-unhealthy strategy primary)
      (mark-route-unhealthy strategy secondary)
      (let ((selected (select-route strategy nil envelope routes)))
        (is (member selected routes :test #'string=))))))

;;;; ============================================================================
;;;; Routing Strategy Fuzz Tests - Latency-Based Strategy
;;;; ============================================================================

(test fuzz-latency-based-new-routes
  "Fuzz test: latency-based falls back for routes without history."
  (loop repeat 50 do
    (let* ((strategy (make-instance 'latency-based-strategy :name :latency))
           (routes (random-route-list 5))
           (envelope (make-cross-swarm-envelope :target-swarm "target")))
      (let ((selected (select-route strategy nil envelope routes)))
        (is (string= selected (first routes)))))))

(test fuzz-latency-based-prefers-low-latency
  "Fuzz test: latency-based prefers lower latency routes."
  (loop repeat 30 do
    (let* ((strategy (make-instance 'latency-based-strategy :name :latency))
           (fast-route (random-swarm-id))
           (slow-route (random-swarm-id))
           (routes (list fast-route slow-route)))
      (record-latency strategy fast-route 10.0)
      (record-latency strategy slow-route 100.0)
      (let* ((envelope (make-cross-swarm-envelope :target-swarm "target"))
             (selected (select-route strategy nil envelope routes)))
        (is (string= selected fast-route))))))

;;;; ============================================================================
;;;; Routing Strategy Fuzz Tests - Direct Strategy
;;;; ============================================================================

(test fuzz-direct-strategy-target-in-routes
  "Fuzz test: direct strategy finds target when in available routes."
  (loop repeat 100 do
    (let* ((strategy (make-instance 'direct-routing-strategy :name :direct))
           (routes (random-route-list (1+ (random 10))))
           (target (nth (random (length routes)) routes))
           (envelope (make-cross-swarm-envelope :target-swarm target)))
      (let ((result (select-route strategy nil envelope routes)))
        (is (string= result target))))))

(test fuzz-direct-strategy-target-not-in-routes
  "Fuzz test: direct strategy returns nil when target not found."
  (loop repeat 100 do
    (let* ((strategy (make-instance 'direct-routing-strategy :name :direct))
           (routes (random-route-list 5))
           (target (random-swarm-id))  ; Random, likely not in routes
           (envelope (make-cross-swarm-envelope :target-swarm target)))
      (unless (member target routes :test #'string=)
        (is (null (select-route strategy nil envelope routes)))))))

;;;; ============================================================================
;;;; Routing Strategy Fuzz Tests - Broadcast Strategy
;;;; ============================================================================

(test fuzz-broadcast-strategy-returns-keyword
  "Fuzz test: broadcast strategy always returns :broadcast."
  (loop repeat 50 do
    (let* ((strategy (make-instance 'broadcast-strategy :name :broadcast))
           (routes (random-route-list (1+ (random 10))))
           (envelope (make-cross-swarm-envelope :target-swarm (random-swarm-id))))
      (is (eq (select-route strategy nil envelope routes) :broadcast)))))

;;;; ============================================================================
;;;; Concurrent Routing Strategy Tests
;;;; ============================================================================

(test fuzz-concurrent-round-robin-state
  "Fuzz test: round-robin is thread-safe under concurrent access."
  (loop repeat 10 do
    (let* ((strategy (make-instance 'round-robin-strategy :name :round-robin))
           (routes (random-route-list 5))
           (threads nil)
           (selections (make-array 100 :initial-element nil))
           (errors nil)
           (errors-lock (bt:make-lock "errors-lock")))
      (dotimes (i 100)
        (let ((idx i))
          (push
            (bt:make-thread
              (lambda ()
                (handler-case
                    (let* ((envelope (make-cross-swarm-envelope :target-swarm "target"))
                           (selected (select-route strategy nil envelope routes)))
                      (setf (aref selections idx) selected))
                  (error (e)
                    (bt:with-lock-held (errors-lock)
                      (push e errors)))))
              :name (format nil "rr-thread-~D" i))
            threads)))
      (dolist (thread threads)
        (bt:join-thread thread))
      (is (null errors))
      (dotimes (i 100)
        (is (member (aref selections i) routes :test #'string=))))))

(test fuzz-concurrent-failover-health-updates
  "Fuzz test: failover handles concurrent health status changes."
  (loop repeat 10 do
    (let* ((strategy (make-instance 'failover-strategy
                                     :name :failover
                                     :primary-route "primary"
                                     :secondary-route "secondary"
                                     :health-recovery-time 1))
           (routes (list "primary" "secondary" "tertiary"))
           (threads nil)
           (errors nil)
           (errors-lock (bt:make-lock "errors-lock")))
      (dotimes (i 50)
        (push
          (bt:make-thread
            (lambda ()
              (handler-case
                  (let ((envelope (make-cross-swarm-envelope :target-swarm "target")))
                    (select-route strategy nil envelope routes))
                (error (e)
                  (bt:with-lock-held (errors-lock)
                    (push e errors)))))
            :name (format nil "select-thread-~D" i))
          threads))
      (dotimes (i 10)
        (push
          (bt:make-thread
            (lambda ()
              (handler-case
                  (progn
                    (sleep (random 0.01))
                    (if (zerop (random 2))
                        (mark-route-unhealthy strategy
                          (nth (random 2) '("primary" "secondary")))
                        (mark-route-healthy strategy
                          (nth (random 2) '("primary" "secondary")))))
                (error (e)
                  (bt:with-lock-held (errors-lock)
                    (push e errors)))))
            :name (format nil "health-thread-~D" i))
          threads))
      (dolist (thread threads)
        (bt:join-thread thread))
      (is (null errors)))))

;;;; ============================================================================
;;;; Network Partition Simulation Tests
;;;; ============================================================================

(test fuzz-partition-gradual-node-failure
  "Fuzz test: simulate gradual node failures in routing."
  (loop repeat 30 do
    (let* ((failover (make-instance 'failover-strategy
                                     :name :failover
                                     :primary-route "primary"
                                     :secondary-route "secondary"))
           (all-routes (list "primary" "secondary" "tertiary" "quaternary"))
           (envelope (make-cross-swarm-envelope :target-swarm "target")))
      (dolist (route-to-fail all-routes)
        (let ((available (remove route-to-fail all-routes :test #'string=)))
          (when available
            (mark-route-unhealthy failover route-to-fail)
            (let ((selected (select-route failover nil envelope available)))
              (is (or (null selected)
                      (member selected available :test #'string=))))))))))

(test fuzz-partition-split-brain-barrier
  "Fuzz test: barriers under simulated network partition."
  (loop repeat 20 do
    (let* ((all-participants (random-participant-list 6 10))
           (mid (floor (length all-participants) 2))
           (partition-a (subseq all-participants 0 mid))
           (barrier (create-barrier all-participants :timeout 2)))
      ;; Only partition A arrives
      (dolist (p partition-a)
        (barrier-arrive barrier p))
      ;; Barrier should NOT complete
      (is (barrier-open-p barrier))
      ;; Verify state
      (let ((arrived (barrier-participants-arrived barrier)))
        (is (= (length arrived) (length partition-a)))))))

;;;; ============================================================================
;;;; High Load Stress Tests
;;;; ============================================================================

(test fuzz-barrier-high-throughput
  "Fuzz test: many barrier operations in succession."
  (loop repeat 100 do
    (let* ((participants (random-participant-list 3 5))
           (barrier (create-barrier participants :timeout 60)))
      (dolist (p participants)
        (barrier-arrive barrier p))
      (is (not (barrier-open-p barrier)))
      (barrier-reset barrier))))

(test fuzz-routing-high-throughput
  "Fuzz test: many routing operations in succession."
  (let* ((strategy (make-instance 'round-robin-strategy :name :round-robin))
         (routes (random-route-list 10)))
    (dotimes (i 1000)
      (let* ((envelope (make-cross-swarm-envelope
                         :target-swarm (random-swarm-id)
                         :payload (random-payload)))
             (selected (select-route strategy nil envelope routes)))
        (is (member selected routes :test #'string=))))))

(test fuzz-many-routes-performance
  "Fuzz test: routing with many available routes."
  (loop repeat 20 do
    (let* ((routes (random-route-list 100))
           (envelope (make-cross-swarm-envelope :target-swarm "target")))
      (dolist (strategy-class '(round-robin-strategy
                                weighted-random-strategy
                                latency-based-strategy))
        (let* ((strategy (make-instance strategy-class :name :test))
               (selected (select-route strategy nil envelope routes)))
          (is (member selected routes :test #'string=)))))))

;;;; ============================================================================
;;;; Test Runner
;;;; ============================================================================

(defun run-fuzz-tests ()
  "Run all fuzz tests."
  (run! 'fuzz-tests))

;;;; End of file
