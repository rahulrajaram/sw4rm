;;;; negotiation-debate.lisp -- Multi-agent negotiation and debate example
;;;;
;;;; Demonstrates the SW4RM negotiation room pattern for artifact approval:
;;;;   1. Producer submitting an artifact for review
;;;;   2. Multiple critics evaluating and voting on the artifact
;;;;   3. Coordinator aggregating votes and making decisions
;;;;   4. Approval, revision, and HITL escalation scenarios
;;;;   5. Integration with the voting subsystem
;;;;
;;;; This example complements negotiation-voting.lisp (which focuses on the
;;;; event system and voting strategies) by demonstrating the full Negotiation
;;;; Room workflow with producer/critic/coordinator roles.
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed (https://www.quicklisp.org/)
;;;;   - SW4RM SDK on ASDF load path
;;;;
;;;; Run:
;;;;   sbcl --load examples/negotiation-debate.lisp

;;; ---------------------------------------------------------------------------
;;; Step 0: Ensure Quicklisp is available, then load the SDK
;;; ---------------------------------------------------------------------------

#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload :sw4rm-sdk)

(defpackage #:negotiation-debate-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:negotiation-debate-example)

;;; ---------------------------------------------------------------------------
;;; In-Memory Negotiation Room Store
;;; ---------------------------------------------------------------------------
;;; Since the negotiation-room-client uses gRPC stubs, we implement a local
;;; store to demonstrate the full negotiation lifecycle.

(defvar *proposals* (make-hash-table :test 'equal)
  "artifact-id -> proposal plist")
(defvar *votes* (make-hash-table :test 'equal)
  "artifact-id -> list of vote plists")
(defvar *decisions* (make-hash-table :test 'equal)
  "artifact-id -> decision plist")

(defun clear-room-store ()
  "Clear all negotiation room state."
  (clrhash *proposals*)
  (clrhash *votes*)
  (clrhash *decisions*))

(defun store-proposal (proposal)
  "Store a proposal in the room."
  (let ((aid (getf proposal :artifact-id)))
    (setf (gethash aid *proposals*) proposal)
    (setf (gethash aid *votes*) nil)
    aid))

(defun store-vote (vote)
  "Store a critic's vote for an artifact."
  (let ((aid (getf vote :artifact-id)))
    (push vote (gethash aid *votes*))
    nil))

(defun get-votes (artifact-id)
  "Get all votes for an artifact."
  (gethash artifact-id *votes*))

(defun store-decision (decision)
  "Store a decision for an artifact."
  (setf (gethash (getf decision :artifact-id) *decisions*) decision))

(defun get-stored-decision (artifact-id)
  "Get the decision for an artifact."
  (gethash artifact-id *decisions*))

;;; ---------------------------------------------------------------------------
;;; Vote Aggregation
;;; ---------------------------------------------------------------------------

(defun aggregate-debate-votes (votes)
  "Aggregate votes into summary statistics.
Returns a plist with :mean, :weighted-mean, :min-score, :max-score,
:std-dev, and :vote-count."
  (let* ((count (length votes))
         (scores (mapcar (lambda (v) (getf v :score)) votes))
         (confidences (mapcar (lambda (v) (getf v :confidence)) votes))
         (mean (if (zerop count) 0.0
                   (/ (reduce #'+ scores) (float count))))
         ;; Weighted mean (confidence-weighted)
         (total-weight (reduce #'+ confidences))
         (weighted-mean (if (zerop total-weight) 0.0
                            (/ (reduce #'+ (mapcar #'* scores confidences))
                               total-weight)))
         (min-score (if scores (reduce #'min scores) 0.0))
         (max-score (if scores (reduce #'max scores) 0.0))
         ;; Standard deviation
         (variance (if (<= count 1) 0.0
                       (/ (reduce #'+ (mapcar (lambda (s) (expt (- s mean) 2))
                                              scores))
                          (float count))))
         (std-dev (sqrt variance)))
    (list :mean (float mean)
          :weighted-mean (float weighted-mean)
          :min-score (float min-score)
          :max-score (float max-score)
          :std-dev (float std-dev)
          :vote-count count)))

;;; ---------------------------------------------------------------------------
;;; Producer Agent
;;; ---------------------------------------------------------------------------

(defclass producer-agent ()
  ((agent-id :initarg :agent-id :accessor producer-agent-id))
  (:documentation "Agent that produces artifacts and submits them for review."))

(defmethod create-code-proposal ((producer producer-agent) code description
                                 critics room-id)
  "Create and submit a code artifact for review.
Returns the artifact-id."
  (let* ((artifact-id (format nil "code-~A" (subseq (generate-uuid) 0 8)))
         (proposal (list :artifact-type :code
                         :artifact-id artifact-id
                         :producer-id (producer-agent-id producer)
                         :artifact code
                         :artifact-content-type "application/json"
                         :requested-critics critics
                         :negotiation-room-id room-id
                         :submitted-at (get-universal-time))))
    (store-proposal proposal)

    (format t "~&~%;; [Producer ~A] Submitted code proposal: ~A~%"
            (producer-agent-id producer) artifact-id)
    (format t ";;   Description: ~A~%" description)
    (format t ";;   Requested critics: ~A~%" critics)

    artifact-id))

;;; ---------------------------------------------------------------------------
;;; Critic Agent
;;; ---------------------------------------------------------------------------

(defclass critic-agent ()
  ((agent-id :initarg :agent-id :accessor critic-agent-id)
   (expertise :initarg :expertise :initform "general" :accessor critic-expertise))
  (:documentation "Agent that evaluates artifacts and provides votes."))

(defmethod evaluate-artifact ((critic critic-agent) artifact-id room-id
                              &key score confidence passed
                                strengths weaknesses recommendations)
  "Evaluate an artifact and submit a vote."
  (let ((vote (list :artifact-id artifact-id
                    :critic-id (critic-agent-id critic)
                    :score score
                    :confidence confidence
                    :passed passed
                    :strengths strengths
                    :weaknesses weaknesses
                    :recommendations recommendations
                    :negotiation-room-id room-id)))
    (store-vote vote)

    (format t "~&~%;; [Critic ~A] Submitted vote for ~A~%"
            (critic-agent-id critic) artifact-id)
    (format t ";;   Expertise: ~A~%" (critic-expertise critic))
    (format t ";;   Score: ~,1F/10 (confidence: ~,2F)~%" score confidence)
    (format t ";;   Passed: ~A~%" (if passed "yes" "no"))
    (format t ";;   Strengths: ~A~%" strengths)
    (format t ";;   Weaknesses: ~A~%" weaknesses)

    vote))

;;; ---------------------------------------------------------------------------
;;; Coordinator Agent
;;; ---------------------------------------------------------------------------

(defclass coordinator-agent ()
  ((agent-id :initarg :agent-id :accessor coordinator-agent-id)
   (policy-version :initarg :policy-version :initform "v1.0"
                   :accessor coordinator-policy-version)
   ;; Decision thresholds
   (approval-threshold :initform 7.0 :accessor approval-threshold)
   (revision-threshold :initform 5.0 :accessor revision-threshold)
   (min-votes-required :initform 2 :accessor min-votes-required)
   (max-std-dev :initform 2.0 :accessor max-std-dev))
  (:documentation "Agent that aggregates votes and makes final decisions."))

(defmethod apply-policy ((coordinator coordinator-agent) votes aggregated)
  "Apply decision policy to determine outcome.
Returns (values outcome reason)."
  ;; Check for high disagreement => HITL escalation
  (when (> (getf aggregated :std-dev) (max-std-dev coordinator))
    (return-from apply-policy
      (values :escalated-to-hitl
              (format nil "High critic disagreement (std_dev=~,2F), escalating to human"
                      (getf aggregated :std-dev)))))

  ;; Check if all critics passed
  (let ((all-passed (every (lambda (v) (getf v :passed)) votes))
        (wmean (getf aggregated :weighted-mean)))

    ;; Approved if weighted mean meets threshold and all passed
    (when (and (>= wmean (approval-threshold coordinator)) all-passed)
      (return-from apply-policy
        (values :approved
                (format nil "Weighted mean ~,2F meets threshold ~,1F, all critics passed"
                        wmean (approval-threshold coordinator)))))

    ;; Below revision threshold
    (when (< wmean (revision-threshold coordinator))
      (return-from apply-policy
        (values :revision-requested
                (format nil "Weighted mean ~,2F below revision threshold ~,1F"
                        wmean (revision-threshold coordinator)))))

    ;; In between - check for failing critics
    (let ((failing (remove-if (lambda (v) (getf v :passed)) votes)))
      (when failing
        (return-from apply-policy
          (values :revision-requested
                  (format nil "Critics did not pass: ~A"
                          (mapcar (lambda (v) (getf v :critic-id)) failing))))))

    ;; Default: revision requested
    (values :revision-requested
            (format nil "Weighted mean ~,2F did not meet approval threshold ~,1F"
                    wmean (approval-threshold coordinator)))))

(defmethod aggregate-and-decide ((coordinator coordinator-agent) artifact-id room-id)
  "Aggregate votes and make a decision on the artifact."
  (format t "~&~%;; [Coordinator ~A] Aggregating votes for ~A~%"
          (coordinator-agent-id coordinator) artifact-id)

  (let* ((votes (get-votes artifact-id))
         (aggregated (aggregate-debate-votes votes)))

    (when (< (length votes) (min-votes-required coordinator))
      (format t ";;   Warning: Only ~D votes received, ~D required~%"
              (length votes) (min-votes-required coordinator)))

    (format t ";;   Aggregated scores:~%")
    (format t ";;     Mean: ~,2F~%" (getf aggregated :mean))
    (format t ";;     Weighted Mean: ~,2F~%" (getf aggregated :weighted-mean))
    (format t ";;     Min: ~,2F, Max: ~,2F~%"
            (getf aggregated :min-score) (getf aggregated :max-score))
    (format t ";;     Std Dev: ~,2F~%" (getf aggregated :std-dev))
    (format t ";;     Vote count: ~D~%" (getf aggregated :vote-count))

    ;; Apply policy
    (multiple-value-bind (outcome reason)
        (apply-policy coordinator votes aggregated)

      (format t "~&~%;; Decision: ~A~%" outcome)
      (format t ";; Reason: ~A~%" reason)

      ;; Create and store decision
      (let ((decision (list :artifact-id artifact-id
                            :outcome outcome
                            :votes votes
                            :aggregated-score aggregated
                            :policy-version (coordinator-policy-version coordinator)
                            :reason reason
                            :negotiation-room-id room-id)))
        (store-decision decision)
        decision))))

;;; ---------------------------------------------------------------------------
;;; Scenario 1: Full Negotiation Flow (Revision Requested)
;;; ---------------------------------------------------------------------------

(defun run-negotiation-flow ()
  "Run a complete negotiation room flow."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; MULTI-AGENT NEGOTIATION EXAMPLE~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (clear-room-store)
  (let ((room-id (format nil "room-~A" (subseq (generate-uuid) 0 8))))
    (format t "~&~%;; Negotiation Room: ~A~%" room-id)

    ;; Create agents
    (let ((producer (make-instance 'producer-agent :agent-id "producer-1"))
          (critics (list
                    (make-instance 'critic-agent :agent-id "critic-security"
                                                :expertise "security")
                    (make-instance 'critic-agent :agent-id "critic-performance"
                                                :expertise "performance")
                    (make-instance 'critic-agent :agent-id "critic-style"
                                                :expertise "code_style")))
          (coordinator (make-instance 'coordinator-agent :agent-id "coordinator-1")))

      ;; Phase 1: Producer submits artifact
      (format t "~&~%~A~%" (make-string 50 :initial-element #\-))
      (format t ";; PHASE 1: PRODUCER SUBMITS ARTIFACT~%")
      (format t "~A~%" (make-string 50 :initial-element #\-))

      (let ((artifact-id
              (create-code-proposal
               producer
               (format nil "~%~A~%~A~%~A~%~A~%~A~%~A~%~A~%~A~%~A"
                       "(defun process-user-data (user-input)"
                       "  \"Process user data and return structured result.\""
                       "  (let ((data (json:decode-json-from-string user-input)))"
                       "    (list :status \"processed\""
                       "          :original-length (length user-input)"
                       "          :fields (mapcar #'car data))))"
                       ""
                       ";; Note: Missing input validation"
                       ";; Note: No error handling around JSON parsing")
               "User data processing function with JSON parsing"
               (mapcar #'critic-agent-id critics)
               room-id)))

        ;; Phase 2: Critics evaluate
        (format t "~&~%~A~%" (make-string 50 :initial-element #\-))
        (format t ";; PHASE 2: CRITICS EVALUATE ARTIFACT~%")
        (format t "~A~%" (make-string 50 :initial-element #\-))

        ;; Security critic
        (evaluate-artifact
         (first critics) artifact-id room-id
         :score 6.5 :confidence 0.85 :passed nil
         :strengths '("Clear function name" "Has docstring")
         :weaknesses '("No input validation before JSON parsing"
                       "Potential injection vulnerability"
                       "No error handling")
         :recommendations '("Add handler-case around json:decode"
                             "Validate expected data schema"
                             "Sanitize user input"))

        ;; Performance critic
        (evaluate-artifact
         (second critics) artifact-id room-id
         :score 7.5 :confidence 0.78 :passed t
         :strengths '("Simple and efficient implementation"
                      "No unnecessary computations")
         :weaknesses '("No streaming support for large inputs")
         :recommendations '("Consider chunked processing for large data"))

        ;; Style critic
        (evaluate-artifact
         (third critics) artifact-id room-id
         :score 8.0 :confidence 0.92 :passed t
         :strengths '("Good docstring" "Clean variable names"
                      "Appropriate function length")
         :weaknesses '("Inline JSON import not idiomatic")
         :recommendations '("Use ql:quickload for external dependencies"))

        ;; Phase 3: Coordinator decides
        (format t "~&~%~A~%" (make-string 50 :initial-element #\-))
        (format t ";; PHASE 3: COORDINATOR AGGREGATES AND DECIDES~%")
        (format t "~A~%" (make-string 50 :initial-element #\-))

        (let ((decision (aggregate-and-decide coordinator artifact-id room-id)))

          ;; Phase 4: Producer receives decision
          (format t "~&~%~A~%" (make-string 50 :initial-element #\-))
          (format t ";; PHASE 4: PRODUCER RECEIVES DECISION~%")
          (format t "~A~%" (make-string 50 :initial-element #\-))

          (format t "~&~%;; [Producer ~A] Received decision:~%"
                  (producer-agent-id producer))
          (format t ";;   Outcome: ~A~%" (getf decision :outcome))
          (format t ";;   Policy Version: ~A~%" (getf decision :policy-version))
          (format t ";;   Reason: ~A~%" (getf decision :reason))

          (when (eq (getf decision :outcome) :revision-requested)
            (format t "~&~%;; Action Required: Revise and resubmit~%")
            (format t ";; Key feedback to address:~%")
            (dolist (vote (getf decision :votes))
              (when (or (not (getf vote :passed))
                        (getf vote :recommendations))
                (format t ";;   From ~A:~%" (getf vote :critic-id))
                (dolist (rec (subseq (getf vote :recommendations)
                                     0 (min 2 (length (getf vote :recommendations)))))
                  (format t ";;     - ~A~%" rec)))))

          decision)))))

;;; ---------------------------------------------------------------------------
;;; Scenario 2: Approval Scenario
;;; ---------------------------------------------------------------------------

(defun run-approval-scenario ()
  "Run a scenario where the artifact gets approved."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; APPROVAL SCENARIO~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (clear-room-store)
  (let* ((room-id (format nil "room-approve-~A" (subseq (generate-uuid) 0 8)))
         (producer (make-instance 'producer-agent :agent-id "producer-2"))
         (critics (list
                   (make-instance 'critic-agent :agent-id "critic-a")
                   (make-instance 'critic-agent :agent-id "critic-b")))
         (coordinator (make-instance 'coordinator-agent :agent-id "coordinator-2")))

    ;; Submit high-quality artifact
    (let ((artifact-id
            (create-code-proposal producer
                                  ";; Well-tested, secure code"
                                  "Production-ready implementation"
                                  (mapcar #'critic-agent-id critics)
                                  room-id)))
      ;; All critics give high scores
      (evaluate-artifact (first critics) artifact-id room-id
                         :score 9.0 :confidence 0.95 :passed t
                         :strengths '("Excellent security practices" "Comprehensive tests")
                         :weaknesses nil :recommendations nil)

      (evaluate-artifact (second critics) artifact-id room-id
                         :score 8.5 :confidence 0.88 :passed t
                         :strengths '("Great performance" "Clean code")
                         :weaknesses '("Minor style nit")
                         :recommendations '("Consider adding inline comments"))

      (let ((decision (aggregate-and-decide coordinator artifact-id room-id)))
        (format t "~&~%;; Final Outcome: ~A~%" (getf decision :outcome))
        (assert (eq (getf decision :outcome) :approved)
                nil "Expected approval!")))))

;;; ---------------------------------------------------------------------------
;;; Scenario 3: Deadlock / HITL Escalation
;;; ---------------------------------------------------------------------------

(defun run-deadlock-scenario ()
  "Run a scenario that results in HITL escalation due to disagreement."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; DEADLOCK/ESCALATION SCENARIO~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (clear-room-store)
  (let* ((room-id (format nil "room-deadlock-~A" (subseq (generate-uuid) 0 8)))
         (producer (make-instance 'producer-agent :agent-id "producer-3"))
         (critics (list
                   (make-instance 'critic-agent :agent-id "critic-x")
                   (make-instance 'critic-agent :agent-id "critic-y")))
         (coordinator (make-instance 'coordinator-agent :agent-id "coordinator-3")))

    (let ((artifact-id
            (create-code-proposal producer
                                  ";; Controversial implementation"
                                  "Approach with trade-offs"
                                  (mapcar #'critic-agent-id critics)
                                  room-id)))
      ;; Critics strongly disagree
      (evaluate-artifact (first critics) artifact-id room-id
                         :score 9.0 :confidence 0.90 :passed t
                         :strengths '("Innovative approach" "Solves problem elegantly")
                         :weaknesses nil :recommendations nil)

      (evaluate-artifact (second critics) artifact-id room-id
                         :score 3.0 :confidence 0.92 :passed nil
                         :strengths '("Attempts to solve the problem")
                         :weaknesses '("Completely wrong approach" "Major security flaws")
                         :recommendations '("Rewrite from scratch"))

      (let ((decision (aggregate-and-decide coordinator artifact-id room-id)))
        (format t "~&~%;; Final Outcome: ~A~%" (getf decision :outcome))
        (format t ";; Note: High disagreement between critics led to HITL escalation~%")))))

;;; ---------------------------------------------------------------------------
;;; Main Entry Point
;;; ---------------------------------------------------------------------------

(format t "~&~%;; SW4RM Multi-Agent Negotiation Example~%")
(format t ";; This demonstrates the Negotiation Room pattern for artifact approval~%")

(run-negotiation-flow)
(run-approval-scenario)
(run-deadlock-scenario)

(format t "~&~%~A~%" (make-string 70 :initial-element #\=))
(format t ";; ALL NEGOTIATION SCENARIOS COMPLETED~%")
(format t "~A~%" (make-string 70 :initial-element #\=))
(format t "~&~%;; Key takeaways:~%")
(format t ";;   1. Producers submit artifacts via create-code-proposal~%")
(format t ";;   2. Critics evaluate and submit votes with scores and feedback~%")
(format t ";;   3. Coordinators aggregate votes and apply decision policies~%")
(format t ";;   4. High disagreement between critics triggers HITL escalation~%")
(format t ";;   5. Decisions include full audit trail of votes and reasoning~%")
(format t ";;   6. Use the voting module (negotiation-voting.lisp) for strategy variants~%")
