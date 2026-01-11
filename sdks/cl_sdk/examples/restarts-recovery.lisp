;;;; restarts-recovery.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Conditions & Restarts Example
;;;;
;;;; Purpose: THE distinguishing CL example - demonstrates how the
;;;; conditions/restarts system enables sophisticated error recovery
;;;; that is impossible in Python's try/except model.
;;;;
;;;; Key Insight: In Python, when an error occurs deep in a call stack,
;;;; you have two choices: handle it there or propagate it up. CL's
;;;; restarts allow the ERROR HANDLER to decide the recovery strategy
;;;; while the error is still "live" in the call stack.
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/restarts-recovery.lisp")
;;;;   (restarts-example:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :restarts-example
  (:use :cl :sw4rm-orchestrator)
  (:export #:run-demo
           #:demonstrate-basic-restarts
           #:demonstrate-distributed-recovery
           #:demonstrate-interactive-recovery
           #:demonstrate-hitl-escalation))

(in-package :restarts-example)

;;; ==========================================================================
;;; Condition Types
;;; ==========================================================================

#|
SW4RM defines a hierarchy of condition types for distributed errors.
Unlike Python exceptions, conditions don't unwind the stack until handled.

Condition Hierarchy:
  sw4rm-error (root)
  ├── routing-error
  │   ├── leaf-unreachable
  │   ├── route-not-found
  │   └── route-timeout
  ├── coordination-error
  │   ├── barrier-timeout
  │   ├── consensus-failed
  │   └── artifact-conflict
  └── persistence-error
      ├── wal-corruption
      └── checkpoint-failed
|#

;; We'll define some example conditions for this demo
(define-condition demo-routing-error (error)
  ((target :initarg :target :reader error-target)
   (reason :initarg :reason :reader error-reason))
  (:report (lambda (condition stream)
             (format stream "Routing to ~A failed: ~A"
                     (error-target condition)
                     (error-reason condition)))))

(define-condition demo-leaf-unreachable (demo-routing-error)
  ((attempts :initarg :attempts :reader error-attempts :initform 1))
  (:report (lambda (condition stream)
             (format stream "Leaf ~A unreachable after ~D attempts"
                     (error-target condition)
                     (error-attempts condition)))))

(define-condition demo-consensus-failed (error)
  ((topic :initarg :topic :reader error-topic)
   (votes :initarg :votes :reader error-votes))
  (:report (lambda (condition stream)
             (format stream "Consensus on ~A failed. Votes: ~A"
                     (error-topic condition)
                     (error-votes condition)))))

;;; ==========================================================================
;;; Basic Restarts Demonstration
;;; ==========================================================================

(defun demonstrate-basic-restarts ()
  "Show the fundamental restart mechanism.

   This demonstrates how restarts separate error DETECTION from
   error HANDLING. The low-level code signals an error and offers
   recovery options. The high-level code chooses which option to use.

   Python comparison:
     try:
         result = risky_operation()
     except NetworkError:
         # You MUST decide here, can't ask caller
         result = fallback()

   CL with restarts:
     (handler-bind ((network-error #'choose-retry-or-fallback))
       (risky-operation))
     ;; The handler can invoke ANY restart offered by risky-operation"

  (format t "~&=== Basic Restarts Demonstration ===~%~%")

  ;; Example 1: Simple restart selection
  (format t "1. Automatic retry selection:~%")
  (let ((result
          (handler-bind ((demo-routing-error
                           #'(lambda (c)
                               (declare (ignore c))
                               ;; Automatically choose to retry
                               (invoke-restart 'retry-operation))))
            (simulate-flaky-operation "leaf-1"))))
    (format t "   Result: ~A~%~%" result))

  ;; Example 2: Use fallback value
  (format t "2. Fallback value selection:~%")
  (let ((result
          (handler-bind ((demo-routing-error
                           #'(lambda (c)
                               (declare (ignore c))
                               ;; Use a fallback value
                               (invoke-restart 'use-fallback :value "cached-data"))))
            (simulate-flaky-operation "leaf-1"))))
    (format t "   Result: ~A~%~%" result))

  ;; Example 3: Skip and continue
  (format t "3. Skip and continue:~%")
  (let ((results
          (handler-bind ((demo-routing-error
                           #'(lambda (c)
                               (format t "   Skipping failed target: ~A~%"
                                       (error-target c))
                               (invoke-restart 'skip-item))))
            (simulate-batch-operation '("leaf-1" "leaf-2" "leaf-3")))))
    (format t "   Results: ~A~%~%" results)))

(defun simulate-flaky-operation (target)
  "Simulate an operation that might fail, with restarts.

   This function offers THREE recovery options via restarts:
   1. RETRY-OPERATION: Try again
   2. USE-FALLBACK: Use a provided fallback value
   3. ABORT-OPERATION: Give up entirely"

  (let ((fail-p (zerop (random 2))))  ; 50% chance of failure

    (restart-case
        (if fail-p
            (error 'demo-routing-error
                   :target target
                   :reason "connection refused")
            (format nil "success:~A" target))

      ;; Restart 1: Retry the operation
      (retry-operation ()
        :report "Retry the operation"
        (format t "   Retrying ~A...~%" target)
        (format nil "retry-success:~A" target))

      ;; Restart 2: Use a fallback value
      (use-fallback (&key value)
        :report "Use a fallback value"
        :interactive (lambda ()
                       (format t "   Enter fallback value: ")
                       (list :value (read-line)))
        (format nil "fallback:~A" value))

      ;; Restart 3: Abort entirely
      (abort-operation ()
        :report "Abort the operation"
        nil))))

(defun simulate-batch-operation (targets)
  "Process multiple targets, with skip capability.

   Demonstrates how restarts enable partial failure handling."
  (let ((results nil))
    (dolist (target targets)
      (restart-case
          (let ((result (simulate-flaky-operation target)))
            (when result
              (push result results)))

        ;; Skip this item and continue with the rest
        (skip-item ()
          :report "Skip this item and continue"
          nil)))
    (nreverse results)))

;;; ==========================================================================
;;; Distributed Recovery Demonstration
;;; ==========================================================================

(defun demonstrate-distributed-recovery ()
  "Show recovery strategies for distributed system failures.

   Demonstrates the 5 standard SW4RM restart strategies:
   1. RETRY-WITH-BACKOFF: Wait and try again
   2. SKIP-AND-LOG: Log the failure, continue with others
   3. USE-FALLBACK-ROUTE: Try an alternative path
   4. ESCALATE-TO-HITL: Request human intervention
   5. ABORT-WORKFLOW: Clean abort of the entire workflow"

  (format t "~&=== Distributed Recovery Demonstration ===~%~%")

  ;; Simulate a multi-swarm workflow with various failure scenarios
  (let ((workflow-results nil))

    ;; Strategy 1: Retry with exponential backoff
    (format t "1. Retry with backoff:~%")
    (push
     (handler-bind
         ((demo-leaf-unreachable
            #'(lambda (c)
                (let ((attempts (error-attempts c)))
                  (if (< attempts 3)
                      (progn
                        (format t "   Attempt ~D failed, backing off ~D seconds...~%"
                                attempts (expt 2 attempts))
                        (invoke-restart 'retry-with-backoff
                                        :delay (expt 2 attempts)))
                      (invoke-restart 'use-fallback-route))))))
       (route-with-recovery "primary-leaf" "backup-leaf"))
     workflow-results)
    (format t "~%")

    ;; Strategy 2: Fallback route
    (format t "2. Fallback routing:~%")
    (push
     (handler-bind
         ((demo-routing-error
            #'(lambda (c)
                (format t "   Primary route failed: ~A~%" (error-target c))
                (invoke-restart 'use-fallback-route))))
       (route-with-recovery "primary-leaf" "backup-leaf"))
     workflow-results)
    (format t "~%")

    ;; Strategy 3: Skip and log
    (format t "3. Skip and log (batch processing):~%")
    (let ((batch-result
            (handler-bind
                ((demo-routing-error
                   #'(lambda (c)
                       (format t "   Logging failure for ~A: ~A~%"
                               (error-target c) (error-reason c))
                       (invoke-restart 'skip-and-log))))
              (process-batch-with-recovery
               '("leaf-a" "leaf-b" "leaf-c" "leaf-d")))))
      (push batch-result workflow-results))
    (format t "   Processed: ~D items~%~%" (car (last workflow-results)))

    (format t "Workflow completed with ~D operations~%"
            (length workflow-results))))

(defun route-with-recovery (primary fallback)
  "Route to primary, with fallback option.

   Demonstrates multi-strategy restart offering."
  (let ((attempt-count 0))
    (restart-case
        (progn
          (incf attempt-count)
          ;; Simulate failure
          (when (< (random 10) 7)  ; 70% fail rate
            (error 'demo-leaf-unreachable
                   :target primary
                   :reason "connection timeout"
                   :attempts attempt-count))
          (format nil "routed-to:~A" primary))

      ;; Retry with delay
      (retry-with-backoff (&key delay)
        :report "Retry after backoff"
        (sleep (or delay 1))
        (route-with-recovery primary fallback))

      ;; Use fallback route
      (use-fallback-route ()
        :report "Use fallback route"
        (format t "   Switching to fallback: ~A~%" fallback)
        (format nil "routed-to:~A" fallback))

      ;; Abort
      (abort-routing ()
        :report "Abort routing"
        nil))))

(defun process-batch-with-recovery (items)
  "Process a batch of items with skip capability."
  (let ((processed 0)
        (skipped 0))
    (dolist (item items)
      (restart-case
          (progn
            ;; Simulate sometimes failing
            (when (zerop (random 3))
              (error 'demo-routing-error
                     :target item
                     :reason "transient error"))
            (incf processed))

        (skip-and-log ()
          :report "Skip item and log"
          (incf skipped))))
    (list processed skipped)))

;;; ==========================================================================
;;; Interactive Recovery Demonstration
;;; ==========================================================================

(defun demonstrate-interactive-recovery ()
  "Show how restarts enable operator intervention.

   The key insight: when using INVOKE-RESTART-INTERACTIVELY, the
   operator (human or automation system) can choose from available
   restarts and provide values, even for errors deep in the call stack.

   This is impossible in Python without pre-planned hooks at every level."

  (format t "~&=== Interactive Recovery Demonstration ===~%~%")

  (format t "In a REPL session, you would use:~%")
  (format t "  (handler-bind ((error #'invoke-debugger))~%")
  (format t "    (run-workflow))~%~%")

  (format t "When an error occurs, the debugger shows available restarts:~%")
  (format t "  0: [RETRY-WITH-BACKOFF] Retry after exponential backoff~%")
  (format t "  1: [USE-FALLBACK-ROUTE] Switch to backup route~%")
  (format t "  2: [SKIP-AND-LOG] Skip this item and continue~%")
  (format t "  3: [ESCALATE-TO-HITL] Request human approval~%")
  (format t "  4: [ABORT-WORKFLOW] Abort the entire workflow~%~%")

  (format t "The operator types the restart number and execution continues!~%~%")

  ;; Simulate automatic restart selection
  (format t "Simulating automatic selection:~%")
  (let ((result
          (handler-bind
              ((demo-consensus-failed
                 #'(lambda (c)
                     ;; In real use, this could prompt the operator
                     (format t "   Consensus failed on: ~A~%"
                             (error-topic c))
                     (format t "   Votes were: ~A~%"
                             (error-votes c))
                     (format t "   Automatically selecting OVERRIDE-DECISION~%")
                     (invoke-restart 'override-decision :decision :approved))))
            (simulate-consensus-workflow))))
    (format t "   Final result: ~A~%" result)))

(defun simulate-consensus-workflow ()
  "Simulate a workflow that requires consensus."
  (restart-case
      (let ((votes '(:approve :reject :approve :abstain)))
        ;; Simulate failed consensus
        (error 'demo-consensus-failed
               :topic "deployment-approval"
               :votes votes))

    ;; Restart: Manual override
    (override-decision (&key decision)
      :report "Override with manual decision"
      :interactive (lambda ()
                     (format t "Enter decision (approved/rejected): ")
                     (list :decision (intern (string-upcase (read-line)) :keyword)))
      (format nil "decision:~A" decision))

    ;; Restart: Retry voting
    (retry-voting ()
      :report "Initiate another voting round"
      (format nil "decision:retry-pending"))

    ;; Restart: Abort
    (abort-workflow ()
      :report "Abort the workflow"
      nil)))

;;; ==========================================================================
;;; HITL Escalation Demonstration
;;; ==========================================================================

(defun demonstrate-hitl-escalation ()
  "Show Human-in-the-Loop escalation pattern.

   Compares to Python's hitl_escalation_example.py but with
   restarts providing more flexible control flow."

  (format t "~&=== HITL Escalation Demonstration ===~%~%")

  (format t "Escalation types:~%")
  (format t "  - TASK_ESCALATION: Task needs human review~%")
  (format t "  - CONFLICT: Agents disagree, need resolution~%")
  (format t "  - DEBATE_DEADLOCK: Negotiation stalled~%")
  (format t "  - SECURITY_APPROVAL: Sensitive operation~%~%")

  ;; Simulate HITL escalation flow
  (format t "Simulating escalation flow:~%~%")

  (let ((result
          (handler-bind
              ;; High-level policy: how to handle escalations
              ((demo-consensus-failed
                 #'(lambda (c)
                     (format t "   Consensus failed, escalating to HITL...~%")
                     (let ((hitl-decision (simulate-hitl-approval
                                           (error-topic c)
                                           (error-votes c))))
                       (format t "   HITL decision: ~A~%" hitl-decision)
                       (invoke-restart 'override-decision
                                       :decision hitl-decision)))))
            ;; Low-level operation
            (perform-sensitive-operation "deploy-to-production"))))
    (format t "~%   Operation result: ~A~%" result)))

(defun perform-sensitive-operation (operation)
  "Perform operation that might need HITL escalation."
  (restart-case
      (progn
        (format t "   Requesting consensus for: ~A~%" operation)
        ;; Simulate consensus failure
        (error 'demo-consensus-failed
               :topic operation
               :votes '(:approve :reject :abstain)))

    (override-decision (&key decision)
      :report "Apply HITL override decision"
      (format nil "completed-with-hitl:~A:~A" operation decision))

    (abort-operation ()
      :report "Abort the operation"
      (format nil "aborted:~A" operation))))

(defun simulate-hitl-approval (topic votes)
  "Simulate HITL approval process.

   In production, this would:
   1. Send notification to operator queue
   2. Wait for response (with timeout)
   3. Return decision"
  (declare (ignore topic votes))
  (format t "   [HITL] Reviewing request...~%")
  (format t "   [HITL] Request approved by operator~%")
  :approved)

;;; ==========================================================================
;;; Python Comparison
;;; ==========================================================================

#|
Python (hitl_escalation_example.py):

    try:
        result = perform_operation()
    except ConsensusError as e:
        # Must handle HERE - can't delegate to caller
        if should_escalate(e):
            decision = await hitl_service.request_approval(e.topic)
            # Now restart... but how? Call perform_operation again?
            result = perform_operation_with_override(decision)
        else:
            raise  # Only other option

The problem: In Python, error handling is tightly coupled to the call site.
The function that catches the error MUST know how to recover.

CL with restarts:

    (handler-bind
        ;; Policy defined at top level
        ((consensus-error #'escalate-to-hitl))
      ;; Operation defined anywhere in the stack
      (perform-operation))

    ;; escalate-to-hitl can invoke ANY restart that
    ;; perform-operation offers, even though it's defined
    ;; elsewhere in the codebase.

Benefits:
1. Separation of concerns: detection vs handling
2. Composability: policies can be layered
3. Interactivity: operator can choose restart in debugger
4. No stack unwinding until restart is chosen
5. Context preserved: handler sees full error context
|#

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete restarts/recovery demo.

   This demonstrates:
   1. Basic restart mechanism
   2. Distributed recovery strategies
   3. Interactive recovery
   4. HITL escalation pattern"

  (format t "~&================================================~%")
  (format t "SW4RM Conditions & Restarts Demo~%")
  (format t "================================================~%~%")

  (format t "This is THE distinguishing feature of Common Lisp.~%")
  (format t "Restarts enable error recovery patterns impossible~%")
  (format t "in Python's try/except model.~%~%")

  ;; Demo sections
  (demonstrate-basic-restarts)
  (terpri)

  (demonstrate-distributed-recovery)
  (terpri)

  (demonstrate-interactive-recovery)
  (terpri)

  (demonstrate-hitl-escalation)

  (format t "~&================================================~%")
  (format t "Demo Complete~%")
  (format t "================================================~%~%")

  (format t "Key Takeaways:~%")
  (format t "1. Restarts separate error DETECTION from HANDLING~%")
  (format t "2. Handlers can choose recovery without unwinding~%")
  (format t "3. Interactive recovery via debugger is built-in~%")
  (format t "4. HITL escalation is natural with restarts~%")
  (format t "5. Policies compose: wrap handlers around handlers~%~%")

  (format t "For interactive exploration:~%")
  (format t "  (in-package :restarts-example)~%")
  (format t "  (handler-bind ((error #'invoke-debugger))~%")
  (format t "    (simulate-flaky-operation \"test\"))~%"))

;;; ==========================================================================
;;; Advanced: Restart Composition
;;; ==========================================================================

#|
Restarts can be composed through handler layering:

(defun high-level-policy (operation)
  "Business logic decides recovery strategy."
  (handler-bind
      ((demo-routing-error
         #'(lambda (c)
             (if (critical-target-p (error-target c))
                 ;; Critical targets: retry aggressively
                 (invoke-restart 'retry-with-backoff :delay 1)
                 ;; Non-critical: skip
                 (invoke-restart 'skip-and-log)))))
    (operation)))

(defun low-level-operation ()
  "Implementation offers recovery options."
  (restart-case
      (risky-network-call)
    (retry-with-backoff (&key delay) ...)
    (skip-and-log () ...)
    (abort-operation () ...)))

;; Compose them:
(high-level-policy #'low-level-operation)

This pattern enables:
- Library code to offer recovery options
- Application code to choose policy
- No tight coupling between the two
|#

;;; End of restarts-recovery.lisp
