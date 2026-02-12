;;;; handoff-example.lisp -- Agent-to-agent handoff example
;;;;
;;;; Demonstrates the SW4RM handoff subsystem:
;;;;   1. Agent-to-agent handoff with context preservation
;;;;   2. Capability matching for target agent selection
;;;;   3. Accept/reject handoff flows
;;;;   4. Context serialization and restoration
;;;;   5. Multi-agent handoff chain concept
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed (https://www.quicklisp.org/)
;;;;   - SW4RM SDK on ASDF load path
;;;;
;;;; Run:
;;;;   sbcl --load examples/handoff-example.lisp

;;; ---------------------------------------------------------------------------
;;; Step 0: Ensure Quicklisp is available, then load the SDK
;;; ---------------------------------------------------------------------------

#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload :sw4rm-sdk)

(defpackage #:handoff-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:handoff-example)

;;; ---------------------------------------------------------------------------
;;; In-Memory Handoff Store
;;; ---------------------------------------------------------------------------
;;; Since the handoff-client uses gRPC stubs, we implement a local in-memory
;;; store to demonstrate the full handoff lifecycle. In production, this would
;;; be handled by the HandoffService.

(defvar *handoff-store* (make-hash-table :test 'equal)
  "In-memory store mapping handoff-id -> handoff record.")

(defun clear-handoff-store ()
  "Clear all handoff records."
  (clrhash *handoff-store*))

(defun store-handoff (handoff-id record)
  "Store a handoff record."
  (setf (gethash handoff-id *handoff-store*) record))

(defun lookup-handoff (handoff-id)
  "Retrieve a handoff record by ID."
  (gethash handoff-id *handoff-store*))

(defun pending-handoffs-for (agent-id)
  "Get all pending handoffs targeting AGENT-ID."
  (let ((results nil))
    (maphash (lambda (id record)
               (declare (ignore id))
               (when (and (string= (getf record :to-agent) agent-id)
                          (eq (getf record :status) :pending))
                 (push record results)))
             *handoff-store*)
    results))

;;; ---------------------------------------------------------------------------
;;; Context Serialization
;;; ---------------------------------------------------------------------------
;;; Context is serialized as a plist encoded to a string. In production,
;;; this would use protobuf or another binary format.

(defun serialize-context (context)
  "Serialize a context plist to a string representation.
Returns the serialized string and its byte length."
  (let ((serialized (prin1-to-string context)))
    (values serialized (length serialized))))

(defun deserialize-context (serialized)
  "Deserialize a context string back to a plist."
  (read-from-string serialized))

;;; ---------------------------------------------------------------------------
;;; Agent Capability Model
;;; ---------------------------------------------------------------------------

(defstruct agent-capabilities
  "Capabilities that an agent can offer."
  (agent-id "" :type string)
  (name "" :type string)
  (capabilities nil :type list)
  (max-concurrent 5 :type integer)
  (current-load 0 :type integer))

(defun can-accept-p (caps required-capabilities)
  "Check if CAPS has all REQUIRED-CAPABILITIES and available capacity."
  (and (< (agent-capabilities-current-load caps)
           (agent-capabilities-max-concurrent caps))
       (every (lambda (req)
                (member req (agent-capabilities-capabilities caps) :test #'string=))
              required-capabilities)))

;;; ---------------------------------------------------------------------------
;;; Source Agent
;;; ---------------------------------------------------------------------------

(defclass source-agent ()
  ((agent-id :initarg :agent-id :accessor source-agent-id)
   (name :initarg :name :accessor source-agent-name)
   (conversation-history :initform nil :accessor conversation-history)
   (active-tools :initform nil :accessor active-tools))
  (:documentation "Agent that initiates handoffs when it cannot complete a task."))

(defmethod add-conversation-turn ((agent source-agent) role content)
  "Add a conversation turn to the agent's history."
  (push (list :role role :content content :timestamp (get-universal-time))
        (conversation-history agent)))

(defmethod request-handoff ((agent source-agent) target-agent-id reason
                            required-capabilities &key (preserve-history t))
  "Request a handoff to TARGET-AGENT-ID.
Creates a handoff record in the local store and returns the response."
  (format t "~&~%;; [~A] Initiating handoff to ~A~%"
          (source-agent-name agent) target-agent-id)
  (format t ";;   Reason: ~A~%" reason)
  (format t ";;   Required capabilities: ~A~%" required-capabilities)

  ;; Build context snapshot
  (let* ((context (list :conversation-history
                        (if preserve-history (conversation-history agent) nil)
                        :tool-state (active-tools agent)
                        :metadata (list :original-agent (source-agent-id agent)
                                        :handoff-timestamp (get-universal-time)
                                        :task-status "in_progress"))))
    (multiple-value-bind (serialized byte-count)
        (serialize-context context)
      (format t ";;   Context size: ~D bytes~%" byte-count)

      ;; Create handoff record
      (let ((handoff-id (generate-uuid)))
        (store-handoff handoff-id
                       (list :handoff-id handoff-id
                             :from-agent (source-agent-id agent)
                             :to-agent target-agent-id
                             :reason reason
                             :context-snapshot serialized
                             :preserve-history preserve-history
                             :capabilities-required required-capabilities
                             :status :pending
                             :metadata (list :urgency "normal"
                                             :conversation-turns
                                             (length (conversation-history agent)))))
        (format t ";;   Handoff ID: ~A~%" handoff-id)
        (format t ";;   Status: PENDING~%")

        ;; Return response
        (list :handoff-id handoff-id :status :pending :accepted t)))))

(defmethod check-handoff-status ((agent source-agent) handoff-id)
  "Check the current status of a handoff."
  (lookup-handoff handoff-id))

;;; ---------------------------------------------------------------------------
;;; Target Agent
;;; ---------------------------------------------------------------------------

(defclass target-agent ()
  ((agent-id :initarg :agent-id :accessor target-agent-id)
   (name :initarg :name :accessor target-agent-name)
   (capabilities :initarg :capabilities :accessor target-capabilities)
   (active-handoffs :initform (make-hash-table :test 'equal)
                    :accessor active-handoffs))
  (:documentation "Agent that receives and processes handoff requests."))

(defmethod check-pending ((agent target-agent))
  "Check for pending handoffs addressed to this agent."
  (let ((pending (pending-handoffs-for (target-agent-id agent))))
    (format t "~&~%;; [~A] Found ~D pending handoffs~%"
            (target-agent-name agent) (length pending))
    pending))

(defmethod evaluate-handoff ((agent target-agent) request)
  "Evaluate whether to accept a handoff request.
Returns (values should-accept reason)."
  (format t "~&~%;; [~A] Evaluating handoff from ~A~%"
          (target-agent-name agent) (getf request :from-agent))
  (format t ";;   Reason: ~A~%" (getf request :reason))
  (format t ";;   Required capabilities: ~A~%" (getf request :capabilities-required))

  (let ((caps (target-capabilities agent))
        (required (getf request :capabilities-required)))
    (if (can-accept-p caps required)
        (values t "Capabilities match and have capacity")
        (let ((missing (set-difference required
                                       (agent-capabilities-capabilities caps)
                                       :test #'string=)))
          (if missing
              (values nil (format nil "Missing capabilities: ~A" missing))
              (values nil "At maximum capacity"))))))

(defmethod accept-handoff-request ((agent target-agent) handoff-id request)
  "Accept a handoff and restore context."
  (format t "~&~%;; [~A] Accepting handoff ~A~%" (target-agent-name agent) handoff-id)

  ;; Update store
  (let ((record (lookup-handoff handoff-id)))
    (setf (getf record :status) :accepted)
    (store-handoff handoff-id record))
  (format t ";;   Status: ACCEPTED~%")

  ;; Deserialize context
  (let* ((snapshot (getf request :context-snapshot))
         (context (when snapshot (deserialize-context snapshot))))
    (when context
      (let ((history (getf context :conversation-history)))
        (format t ";;   Restored ~D conversation turns~%" (length history))
        (format t ";;   Tool state keys: ~A~%"
                (loop for (k v) on (getf context :tool-state) by #'cddr
                      collect k))))

    ;; Track active handoff
    (setf (gethash handoff-id (active-handoffs agent)) context)
    (incf (agent-capabilities-current-load (target-capabilities agent)))

    context))

(defmethod reject-handoff-request ((agent target-agent) handoff-id reason)
  "Reject a handoff request."
  (format t "~&~%;; [~A] Rejecting handoff ~A~%" (target-agent-name agent) handoff-id)
  (format t ";;   Reason: ~A~%" reason)

  (let ((record (lookup-handoff handoff-id)))
    (setf (getf record :status) :rejected)
    (setf (getf record :rejection-reason) reason)
    (store-handoff handoff-id record))
  (format t ";;   Status: REJECTED~%")

  (list :handoff-id handoff-id :status :rejected :rejection-reason reason))

(defmethod complete-handoff-request ((agent target-agent) handoff-id)
  "Mark a handoff as completed."
  (format t "~&~%;; [~A] Completing handoff ~A~%" (target-agent-name agent) handoff-id)

  (let ((record (lookup-handoff handoff-id)))
    (setf (getf record :status) :completed)
    (store-handoff handoff-id record))
  (format t ";;   Status: COMPLETED~%")

  ;; Clean up
  (remhash handoff-id (active-handoffs agent))
  (decf (agent-capabilities-current-load (target-capabilities agent)))

  (list :handoff-id handoff-id :status :completed))

(defmethod process-task ((agent target-agent) context)
  "Process a task using the restored context."
  (format t "~&~%;; [~A] Processing task with restored context~%" (target-agent-name agent))

  ;; Show conversation context
  (let ((history (getf context :conversation-history)))
    (when history
      (format t ";;   Recent conversation:~%")
      (dolist (turn (subseq history 0 (min 3 (length history))))
        (format t ";;     ~A: ~A~%"
                (getf turn :role)
                (subseq (getf turn :content) 0
                        (min 50 (length (getf turn :content))))))))

  ;; Simulate processing
  (sleep 0.1)

  (let ((result (list :status "completed"
                      :processed-by (target-agent-id agent)
                      :conversation-turns-processed
                      (length (getf context :conversation-history))
                      :completed-at (get-universal-time))))
    (format t ";;   Task completed successfully~%")
    result))

;;; ---------------------------------------------------------------------------
;;; Scenario 1: Successful Handoff
;;; ---------------------------------------------------------------------------

(defun run-successful-handoff ()
  "Demonstrate a successful handoff flow."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; SCENARIO 1: Successful Handoff~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (clear-handoff-store)

  ;; Create agents
  (let ((general (make-instance 'source-agent
                                :agent-id "general-agent-1"
                                :name "General Assistant"))
        (code-agent (make-instance 'target-agent
                                   :agent-id "code-agent-1"
                                   :name "Code Specialist"
                                   :capabilities
                                   (make-agent-capabilities
                                    :agent-id "code-agent-1"
                                    :name "Code Specialist"
                                    :capabilities '("code_review" "code_generation" "debugging")))))

    ;; Simulate conversation
    (add-conversation-turn general "user" "Can you help me review this Python code?")
    (add-conversation-turn general "assistant"
                           "I'd be happy to help! Let me connect you with our code specialist.")
    (setf (active-tools general)
          (list :file-reader (list :last-file "main.py")))

    ;; Request handoff
    (let ((response (request-handoff general "code-agent-1"
                                     "User needs code review expertise"
                                     '("code_review")
                                     :preserve-history t)))
      ;; Code agent checks and accepts
      (let ((pending (check-pending code-agent)))
        (dolist (request pending)
          (multiple-value-bind (should-accept reason)
              (evaluate-handoff code-agent request)
            (format t ";;   Decision: ~A - ~A~%"
                    (if should-accept "Accept" "Reject") reason)

            (when should-accept
              (let* ((hid (getf response :handoff-id))
                     (context (accept-handoff-request code-agent hid request))
                     (result (process-task code-agent context)))
                (complete-handoff-request code-agent hid)
                (format t "~&;;   Final result: ~A~%" result)))))))

    (format t "~&~%;; Handoff completed successfully!~%")))

;;; ---------------------------------------------------------------------------
;;; Scenario 2: Rejected Handoff
;;; ---------------------------------------------------------------------------

(defun run-rejected-handoff ()
  "Demonstrate a rejected handoff flow."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; SCENARIO 2: Rejected Handoff~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (clear-handoff-store)

  (let ((general (make-instance 'source-agent
                                :agent-id "general-agent-2"
                                :name "General Assistant"))
        (code-agent (make-instance 'target-agent
                                   :agent-id "code-agent-2"
                                   :name "Code Specialist"
                                   :capabilities
                                   (make-agent-capabilities
                                    :agent-id "code-agent-2"
                                    :name "Code Specialist"
                                    :capabilities '("code_review")))))

    (add-conversation-turn general "user" "I need help with database design")

    ;; Request handoff for capabilities the target doesn't have
    (let ((response (request-handoff general "code-agent-2"
                                     "User needs database expertise"
                                     '("database_design" "schema_optimization")
                                     :preserve-history t)))
      (let ((pending (check-pending code-agent)))
        (dolist (request pending)
          (multiple-value-bind (should-accept reason)
              (evaluate-handoff code-agent request)
            (format t ";;   Decision: ~A - ~A~%"
                    (if should-accept "Accept" "Reject") reason)
            (unless should-accept
              (reject-handoff-request code-agent (getf response :handoff-id) reason)))))

      ;; Check final status
      (let ((final (check-handoff-status general (getf response :handoff-id))))
        (format t "~&~%;; Final status: ~A~%" (getf final :status))
        (format t ";; Rejection reason: ~A~%" (getf final :rejection-reason))))))

;;; ---------------------------------------------------------------------------
;;; Scenario 3: Capability Matching
;;; ---------------------------------------------------------------------------

(defun run-capability-matching ()
  "Demonstrate capability-based agent selection."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; SCENARIO 3: Capability Matching~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (let ((agents
          (list
           (make-agent-capabilities
            :agent-id "security-agent"
            :name "Security Specialist"
            :capabilities '("security_audit" "vulnerability_scan" "penetration_test"))
           (make-agent-capabilities
            :agent-id "performance-agent"
            :name "Performance Engineer"
            :capabilities '("load_testing" "profiling" "optimization"))
           (make-agent-capabilities
            :agent-id "data-agent"
            :name "Data Specialist"
            :capabilities '("database_design" "schema_optimization" "data_migration")))))

    (format t "~&~%;; Available Agents:~%")
    (dolist (a agents)
      (format t ";;   ~A: ~A~%"
              (agent-capabilities-name a)
              (agent-capabilities-capabilities a)))

    (let ((required '("database_design" "schema_optimization")))
      (format t "~&~%;; Looking for agent with: ~A~%" required)
      (let ((match (find-if (lambda (a) (can-accept-p a required)) agents)))
        (if match
            (format t ";;   Found: ~A~%" (agent-capabilities-name match))
            (format t ";;   No matching agent found!~%"))))))

;;; ---------------------------------------------------------------------------
;;; Scenario 4: Context Preservation
;;; ---------------------------------------------------------------------------

(defun run-context-preservation ()
  "Demonstrate context serialization and preservation."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; SCENARIO 4: Context Preservation~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (let ((context
          (list :conversation-history
                (list (list :role "system" :content "You are a helpful coding assistant.")
                      (list :role "user" :content "Help me write a fibonacci function.")
                      (list :role "assistant" :content "Here's an implementation: (defun fib (n) ...)")
                      (list :role "user" :content "Can you make it more efficient?")
                      (list :role "assistant" :content "Let me connect you with our specialist."))
                :tool-state
                (list :code-editor (list :open-files '("main.lisp" "utils.lisp")
                                         :cursor-position (list :line 42 :column 8))
                      :test-runner (list :last-run "2026-01-15T10:30:00Z"
                                         :passed 15 :failed 2))
                :metadata
                (list :session-id "sess-12345"
                      :user-preferences (list :theme "dark" :language "en")
                      :task-priority "high"))))

    (format t "~&~%;; Original context:~%")
    (format t ";;   Conversation turns: ~D~%"
            (length (getf context :conversation-history)))
    (format t ";;   Active tools: ~A~%"
            (loop for (k v) on (getf context :tool-state) by #'cddr collect k))
    (format t ";;   Metadata keys: ~A~%"
            (loop for (k v) on (getf context :metadata) by #'cddr collect k))

    ;; Serialize
    (multiple-value-bind (serialized byte-count)
        (serialize-context context)
      (format t "~&~%;; Serialized size: ~D bytes~%" byte-count)

      ;; Deserialize
      (let ((restored (deserialize-context serialized)))
        (format t "~&~%;; Restored context:~%")
        (format t ";;   Conversation turns: ~D~%"
                (length (getf restored :conversation-history)))
        (format t ";;   Active tools: ~A~%"
                (loop for (k v) on (getf restored :tool-state) by #'cddr collect k))
        (format t ";;   Test runner state: ~A~%"
                (getf (getf restored :tool-state) :test-runner))

        ;; Verify integrity
        (assert (= (length (getf restored :conversation-history))
                   (length (getf context :conversation-history))))
        (assert (equal (getf restored :metadata) (getf context :metadata)))
        (format t "~&~%;; Context integrity verified!~%")))))

;;; ---------------------------------------------------------------------------
;;; Scenario 5: Multi-Agent Handoff Chain
;;; ---------------------------------------------------------------------------

(defun run-handoff-chain ()
  "Demonstrate chained handoffs across multiple agents."
  (format t "~&~%~A~%" (make-string 70 :initial-element #\=))
  (format t ";; SCENARIO 5: Multi-Agent Handoff Chain~%")
  (format t "~A~%" (make-string 70 :initial-element #\=))

  (format t "~&~%;; Task: Complex code refactoring requiring:~%")
  (format t ";;   1. Code analysis~%")
  (format t ";;   2. Performance optimization~%")
  (format t ";;   3. Security review~%")

  (let ((handoff-chain
          '(("analyzer-agent" ("code_analysis" "refactoring"))
            ("optimizer-agent" ("performance_optimization"))
            ("security-agent" ("security_review")))))

    (format t "~&~%;; Handoff chain:~%")
    (loop for (agent-id capabilities) in handoff-chain
          for i from 1
          do (format t ";;   Step ~D: ~A (~A)~%" i agent-id capabilities))))

;;; ---------------------------------------------------------------------------
;;; Main Entry Point
;;; ---------------------------------------------------------------------------

(format t "~&~%;; SW4RM Agent Handoff Example~%")
(format t "~A~%" (make-string 70 :initial-element #\=))
(format t ";; This demonstrates agent-to-agent task handoff with context preservation~%")

(run-successful-handoff)
(run-rejected-handoff)
(run-capability-matching)
(run-context-preservation)
(run-handoff-chain)

(format t "~&~%~A~%" (make-string 70 :initial-element #\=))
(format t ";; ALL HANDOFF SCENARIOS COMPLETED~%")
(format t "~A~%" (make-string 70 :initial-element #\=))
(format t "~&~%;; Key takeaways:~%")
(format t ";;   1. Use request-handoff to initiate handoffs with context~%")
(format t ";;   2. Serialize context with serialize-context for state preservation~%")
(format t ";;   3. Target agents can accept or reject based on capabilities~%")
(format t ";;   4. Check pending handoffs with pending-handoffs-for~%")
(format t ";;   5. Complete the handoff lifecycle with complete-handoff-request~%")
(format t ";;   6. Context includes conversation history, tool state, and metadata~%")
