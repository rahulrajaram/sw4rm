;;;; hitl-escalation.lisp -- Human-in-the-Loop escalation example
;;;;
;;;; Demonstrates the SW4RM HITL escalation subsystem:
;;;;   1. TASK_ESCALATION for low-confidence decisions
;;;;   2. CONFLICT escalation for unresolved disputes between agents
;;;;   3. DEBATE_DEADLOCK handling when multi-agent debates fail to converge
;;;;   4. SECURITY_APPROVAL for high-risk actions
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed (https://www.quicklisp.org/)
;;;;   - SW4RM SDK on ASDF load path
;;;;
;;;; Run:
;;;;   sbcl --load examples/hitl-escalation.lisp

;;; ---------------------------------------------------------------------------
;;; Step 0: Ensure Quicklisp is available, then load the SDK
;;; ---------------------------------------------------------------------------

#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload :sw4rm-sdk)

(defpackage #:hitl-escalation-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:hitl-escalation-example)

;;; ---------------------------------------------------------------------------
;;; Mock HITL Service
;;; ---------------------------------------------------------------------------
;;; In production, HITL invocations would be submitted via the hitl-client
;;; to a gRPC HitlService. This mock simulates human decision-making with
;;; configurable auto-decisions for demonstration purposes.

(defvar *pending-invocations* (make-hash-table :test 'equal))
(defvar *decided-invocations* (make-hash-table :test 'equal))

(defstruct hitl-invocation
  "A request for human-in-the-loop decision."
  (correlation-id "" :type string)
  (reason-type :unspecified :type keyword)
  (context nil :type list)
  (options nil :type list)
  (timeout-ms 30000 :type integer)
  (metadata nil :type list))

(defstruct hitl-decision
  "Human decision in response to a HITL invocation."
  (invocation-id "" :type string)
  (chosen-option "" :type string)
  (confidence 0.0 :type float)
  (reason "" :type string)
  (timestamp (get-universal-time) :type integer))

(defun clear-hitl-state ()
  "Reset all HITL state."
  (clrhash *pending-invocations*)
  (clrhash *decided-invocations*))

(defun submit-hitl (invocation &key auto-decision)
  "Submit a HITL invocation. Returns invocation-id.
When AUTO-DECISION is non-nil, automatically resolves with that option."
  (let ((invocation-id (generate-uuid)))
    (setf (gethash invocation-id *pending-invocations*) invocation)

    (format t "~&~%;; [HITL] New invocation submitted: ~A~%" invocation-id)
    (format t ";;   Reason: ~A~%" (hitl-invocation-reason-type invocation))
    (format t ";;   Options: ~A~%" (hitl-invocation-options invocation))

    ;; Auto-decide if configured
    (when auto-decision
      (let* ((options (hitl-invocation-options invocation))
             (chosen (if (member auto-decision options :test #'string=)
                         auto-decision
                         (first options)))
             (decision (make-hitl-decision
                        :invocation-id invocation-id
                        :chosen-option chosen
                        :confidence 0.9
                        :reason "Auto-decided by test configuration")))
        (remhash invocation-id *pending-invocations*)
        (setf (gethash invocation-id *decided-invocations*) decision)

        (format t "~&~%;; [HITL] Decision received for ~A~%" invocation-id)
        (format t ";;   Chosen: ~A~%" (hitl-decision-chosen-option decision))
        (format t ";;   Confidence: ~,2F~%" (hitl-decision-confidence decision))
        (format t ";;   Reason: ~A~%" (hitl-decision-reason decision))))

    invocation-id))

(defun get-hitl-decision (invocation-id)
  "Retrieve the decision for an invocation, or NIL if still pending."
  (gethash invocation-id *decided-invocations*))

;;; ---------------------------------------------------------------------------
;;; Escalation Handler
;;; ---------------------------------------------------------------------------
;;; Provides patterns for escalating to HITL when automated decision-making
;;; fails. Uses the HitlReasonType constants from the SDK.

(defclass escalation-handler ()
  ((agent-id :initarg :agent-id :accessor handler-agent-id)
   (escalation-count :initform 0 :accessor escalation-count))
  (:documentation "Handles escalation flows for agents."))

(defmethod escalate-uncertainty ((handler escalation-handler)
                                 task-description confidence options
                                 &key (threshold 0.7) (auto-decision nil))
  "Escalate to HITL when confidence is below threshold.
Returns the human's chosen option, or NIL if no escalation was needed."
  (when (>= confidence threshold)
    (format t "~&;; [Escalation] Confidence ~,2F >= threshold ~,2F, no escalation needed~%"
            confidence threshold)
    (return-from escalate-uncertainty nil))

  (format t "~&~%;; [Escalation] Low confidence (~,2F) detected for: ~A~%"
          confidence task-description)
  (format t ";; [Escalation] Escalating to HITL for human decision...~%")

  (let* ((invocation (make-hitl-invocation
                      :correlation-id (generate-uuid)
                      :reason-type :task-escalation
                      :context (list :agent-id (handler-agent-id handler)
                                     :task task-description
                                     :agent-confidence confidence
                                     :threshold threshold
                                     :escalation-reason "Agent confidence below threshold")
                      :options options))
         (inv-id (submit-hitl invocation :auto-decision auto-decision))
         (decision (get-hitl-decision inv-id)))
    (when decision
      (incf (escalation-count handler))
      (hitl-decision-chosen-option decision))))

(defmethod escalate-conflict ((handler escalation-handler)
                              agents-involved conflicting-proposals
                              conflict-description
                              &key (auto-decision nil))
  "Escalate unresolved conflict between agents to HITL.
Returns the winning proposal ID, or NIL if timeout."
  (format t "~&~%;; [Escalation] Conflict detected between agents: ~A~%"
          agents-involved)
  (format t ";; [Escalation] Description: ~A~%" conflict-description)
  (format t ";; [Escalation] Conflicting proposals:~%")
  (loop for (agent . proposal) in conflicting-proposals
        do (format t ";;   ~A: ~A~%" agent proposal))

  (let* ((options (append (mapcar (lambda (agent)
                                    (format nil "accept_~A" agent))
                                  agents-involved)
                          '("reject_all" "merge_proposals")))
         (invocation (make-hitl-invocation
                      :correlation-id (generate-uuid)
                      :reason-type :conflict
                      :context (list :escalating-agent (handler-agent-id handler)
                                     :agents-involved agents-involved
                                     :proposals conflicting-proposals
                                     :conflict-description conflict-description)
                      :options options
                      :metadata (list :priority "high"
                                      :category "multi_agent_conflict")))
         (inv-id (submit-hitl invocation :auto-decision auto-decision))
         (decision (get-hitl-decision inv-id)))
    (when decision
      (incf (escalation-count handler))
      (hitl-decision-chosen-option decision))))

(defmethod escalate-debate-deadlock ((handler escalation-handler)
                                     debate-id debate-rounds final-positions
                                     &key (max-rounds 5) (auto-decision nil))
  "Escalate when a multi-agent debate fails to converge.
Returns the resolution decision, or NIL if timeout."
  (format t "~&~%;; [Escalation] Debate deadlock detected!~%")
  (format t ";;   Debate ID: ~A~%" debate-id)
  (format t ";;   Rounds completed: ~D/~D~%" debate-rounds max-rounds)
  (format t ";;   Final positions:~%")
  (loop for (agent . position) in final-positions
        do (format t ";;     ~A:~%" agent)
           (format t ";;       Stance: ~A~%"
                   (getf position :stance))
           (format t ";;       Confidence: ~,2F~%"
                   (getf position :confidence))
           (format t ";;       Key arguments: ~A~%"
                   (getf position :arguments)))

  (let* ((options (append (mapcar #'car final-positions)
                          '("compromise" "defer_decision")))
         (invocation (make-hitl-invocation
                      :correlation-id (generate-uuid)
                      :reason-type :debate-deadlock
                      :context (list :debate-id debate-id
                                     :rounds-completed debate-rounds
                                     :max-rounds max-rounds
                                     :final-positions final-positions
                                     :escalating-agent (handler-agent-id handler))
                      :options options
                      :timeout-ms 60000
                      :metadata (list :debate-intensity "high"
                                      :requires-domain-expertise t)))
         (inv-id (submit-hitl invocation :auto-decision auto-decision))
         (decision (get-hitl-decision inv-id)))
    (when decision
      (incf (escalation-count handler))
      (hitl-decision-chosen-option decision))))

(defmethod escalate-high-risk ((handler escalation-handler)
                                action-description risk-assessment proposed-action
                                &key (auto-decision nil))
  "Escalate for approval when proposed action is high-risk.
Returns T if action is approved, NIL otherwise."
  (format t "~&~%;; [Escalation] High-risk action requiring approval~%")
  (format t ";;   Action: ~A~%" action-description)
  (format t ";;   Risk level: ~A~%" (getf risk-assessment :level))
  (format t ";;   Potential impacts: ~A~%" (getf risk-assessment :impacts))

  (let* ((invocation (make-hitl-invocation
                      :correlation-id (generate-uuid)
                      :reason-type :security-approval
                      :context (list :agent-id (handler-agent-id handler)
                                     :action action-description
                                     :proposed-action proposed-action
                                     :risk-assessment risk-assessment)
                      :options '("approve" "reject" "modify")
                      :metadata (list :requires-immediate-attention
                                      (string= (getf risk-assessment :level) "critical"))))
         (inv-id (submit-hitl invocation :auto-decision auto-decision))
         (decision (get-hitl-decision inv-id)))
    (cond
      ((and decision (string= (hitl-decision-chosen-option decision) "approve"))
       (incf (escalation-count handler))
       (format t "~&;; [Escalation] Action APPROVED by human operator~%")
       t)
      (t
       (format t "~&;; [Escalation] Action NOT approved: ~A~%"
               (if decision (hitl-decision-chosen-option decision) "timeout"))
       nil))))

;;; ---------------------------------------------------------------------------
;;; Scenario 1: Uncertainty Escalation
;;; ---------------------------------------------------------------------------

(defun demo-uncertainty-escalation ()
  "Demonstrate escalation due to low confidence."
  (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
  (format t ";; SCENARIO 1: Uncertainty Escalation~%")
  (format t "~A~%" (make-string 60 :initial-element #\=))

  (clear-hitl-state)
  (let ((handler (make-instance 'escalation-handler
                                :agent-id "classifier-agent-1")))
    (let ((result (escalate-uncertainty
                   handler
                   "Classify document XYZ-123 as either 'public', 'internal', or 'confidential'"
                   0.45  ;; Low confidence
                   '("public" "internal" "confidential")
                   :threshold 0.7
                   :auto-decision "internal")))
      (format t "~&~%;; Result: Document classified as '~A'~%" result))))

;;; ---------------------------------------------------------------------------
;;; Scenario 2: Conflict Escalation
;;; ---------------------------------------------------------------------------

(defun demo-conflict-escalation ()
  "Demonstrate escalation due to agent conflict."
  (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
  (format t ";; SCENARIO 2: Multi-Agent Conflict Escalation~%")
  (format t "~A~%" (make-string 60 :initial-element #\=))

  (clear-hitl-state)
  (let ((handler (make-instance 'escalation-handler
                                :agent-id "orchestrator-1")))
    (let ((result (escalate-conflict
                   handler
                   '("performance-agent" "security-agent")
                   '(("performance-agent" .
                      (:recommendation "Enable caching for faster response"
                       :justification "Reduces latency by 40%"
                       :risk-score 0.2))
                     ("security-agent" .
                      (:recommendation "Disable caching to prevent data leaks"
                       :justification "Cache could expose sensitive data"
                       :risk-score 0.7)))
                   "Performance vs Security trade-off for API caching"
                   :auto-decision "accept_security-agent")))
      (format t "~&~%;; Result: Conflict resolved with decision: '~A'~%" result))))

;;; ---------------------------------------------------------------------------
;;; Scenario 3: Debate Deadlock
;;; ---------------------------------------------------------------------------

(defun demo-debate-deadlock ()
  "Demonstrate escalation due to debate deadlock."
  (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
  (format t ";; SCENARIO 3: Debate Deadlock Escalation~%")
  (format t "~A~%" (make-string 60 :initial-element #\=))

  (clear-hitl-state)
  (let ((handler (make-instance 'escalation-handler
                                :agent-id "moderator-1")))
    (let ((result (escalate-debate-deadlock
                   handler
                   "debate-2026-001"
                   5  ;; 5 rounds completed
                   '(("agent-alpha" .
                      (:stance "Use microservices architecture"
                       :confidence 0.85
                       :arguments ("Better scalability"
                                   "Independent deployments"
                                   "Technology flexibility")))
                     ("agent-beta" .
                      (:stance "Use monolithic architecture"
                       :confidence 0.78
                       :arguments ("Simpler to develop"
                                   "Lower operational overhead"
                                   "Better for small team")))
                     ("agent-gamma" .
                      (:stance "Use modular monolith"
                       :confidence 0.72
                       :arguments ("Best of both worlds"
                                   "Easier migration path"
                                   "Lower complexity initially"))))
                   :max-rounds 5
                   :auto-decision "compromise")))
      (format t "~&~%;; Result: Debate resolved with decision: '~A'~%" result))))

;;; ---------------------------------------------------------------------------
;;; Scenario 4: High-Risk Action Approval
;;; ---------------------------------------------------------------------------

(defun demo-high-risk-approval ()
  "Demonstrate escalation for high-risk action approval."
  (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
  (format t ";; SCENARIO 4: High-Risk Action Approval~%")
  (format t "~A~%" (make-string 60 :initial-element #\=))

  (clear-hitl-state)
  (let ((handler (make-instance 'escalation-handler
                                :agent-id "deploy-agent-1")))
    (let ((approved (escalate-high-risk
                     handler
                     "Deploy version 2.5.0 to production during peak hours"
                     (list :level "high"
                           :impacts '("Service disruption possible"
                                      "10,000+ active users affected"
                                      "Rollback required if issues")
                           :mitigations '("Canary deployment available"
                                          "Rollback tested"
                                          "Monitoring alerts configured"))
                     "kubectl apply -f production-deployment.yaml"
                     :auto-decision "approve")))
      (format t "~&~%;; Result: Deployment ~A~%"
              (if approved "APPROVED" "REJECTED")))))

;;; ---------------------------------------------------------------------------
;;; Main Entry Point
;;; ---------------------------------------------------------------------------

(format t "~&;; SW4RM HITL Escalation Example~%")
(format t "~A~%" (make-string 60 :initial-element #\=))
(format t ";; This demonstrates various HITL escalation scenarios~%")
(format t ";; that agents use when automated decision-making fails.~%")

(demo-uncertainty-escalation)
(demo-conflict-escalation)
(demo-debate-deadlock)
(demo-high-risk-approval)

(format t "~&~%~A~%" (make-string 60 :initial-element #\=))
(format t ";; All HITL escalation scenarios completed!~%")
(format t "~A~%" (make-string 60 :initial-element #\=))
(format t "~&~%;; Key takeaways:~%")
(format t ";;   1. Use :task-escalation when agent confidence is below threshold~%")
(format t ";;   2. Use :conflict when agents cannot agree~%")
(format t ";;   3. Use :debate-deadlock when multi-round debates fail to converge~%")
(format t ";;   4. Use :security-approval for actions requiring explicit human approval~%")
(format t ";;   5. Always provide clear context and options for human operators~%")
(format t ";;   6. HitlReasonType constants: +conflict+, +security-approval+, etc.~%")
