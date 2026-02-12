;;;; advanced-agent.lisp -- Advanced SW4RM agent example
;;;;
;;;; Demonstrates advanced SDK features using a simulated code-review agent:
;;;;   1. Three-ID envelope construction (message_id, correlation_id, idempotency_token)
;;;;   2. ACK lifecycle management (state machine transitions)
;;;;   3. Activity buffer for tracking in-flight work
;;;;   4. Persistence (save/load agent state across restarts)
;;;;   5. Worktree binding (agent-to-workspace isolation)
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed (https://www.quicklisp.org/)
;;;;   - SW4RM SDK on ASDF load path (e.g., symlink sdks/cl_sdk/ into ~/quicklisp/local-projects/)
;;;;
;;;; Run:
;;;;   sbcl --load examples/advanced-agent.lisp

;;; ---------------------------------------------------------------------------
;;; Step 0: Ensure Quicklisp is available, then load the SDK
;;; ---------------------------------------------------------------------------

;;; Ensure Quicklisp is available
#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload :sw4rm-sdk)

(defpackage #:advanced-agent-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:advanced-agent-example)

;;; ---------------------------------------------------------------------------
;;; Part A: Agent Configuration & Three-ID Envelopes
;;; ---------------------------------------------------------------------------

(format t "~&;; === Part A: Agent Configuration & Three-ID Envelopes ===~%")

(defvar *config*
  (make-agent-config
   :agent-id "reviewer-1"
   :name "CodeReviewAgent"
   :description "Reviews code changes and provides feedback."
   :version "0.5.0"
   :capabilities '("code-review" "static-analysis" "security-audit")
   :endpoints (make-default-endpoints)
   :timeout-ms 30000
   :retry-max-attempts 3
   :heartbeat-interval-ms 30000))

(format t ";;   Agent: ~A (~A)~%"
        (agent-config-agent-id *config*)
        (agent-config-name *config*))

;; Create a sequence tracker for ordering messages.
(defvar *seq* (make-sequence-tracker :start 1))

;; Build a correlation ID for this review session.
(defvar *correlation-id* (generate-uuid))

(format t ";;   Session correlation_id: ~A~%" *correlation-id*)

;; Build an envelope representing a review request.
(defvar *review-envelope*
  (make-envelope
   :producer-id (agent-config-agent-id *config*)
   :message-type +data+
   :content-type "application/json"
   :payload (map 'vector #'char-code "{\"action\":\"review\",\"file\":\"api/handler.py\"}")
   :correlation-id *correlation-id*
   :idempotency-token (make-idempotency-token
                       "reviewer-1" "code-review"
                       (compute-deterministic-hash
                        '(:file "api/handler.py" :commit "abc123")))
   :sequence-number (next-sequence *seq*)
   :retry-count 0
   :ttl-ms 120000
   :state +sent+))

(format t ";;   Envelope message_id       : ~A~%" (getf *review-envelope* :message-id))
(format t ";;   Envelope idempotency_token: ~A~%" (getf *review-envelope* :idempotency-token))

;;; ---------------------------------------------------------------------------
;;; Part B: ACK Lifecycle Management
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part B: ACK Lifecycle Management ===~%")

(defvar *ack-mgr*
  (make-ack-manager "reviewer-1" :auto-ack-p nil :ack-timeout-seconds 60))

;; Track the outgoing review envelope.
(let ((msg-id (getf *review-envelope* :message-id)))
  (track-outgoing *ack-mgr* msg-id)
  (format t ";;   Tracking outgoing: ~A~%" msg-id)

  ;; Simulate receiving ACKs from the recipient.
  (update-ack *ack-mgr* msg-id :received :note "Router delivered")
  (format t ";;   ACK stage -> :RECEIVED~%")

  (update-ack *ack-mgr* msg-id :read :note "Recipient opened")
  (format t ";;   ACK stage -> :READ~%")

  ;; Check unacked messages (should still show since not terminal).
  (let ((unacked (get-unacked *ack-mgr* :direction :outgoing)))
    (format t ";;   Unacked messages: ~D~%" (length unacked)))

  ;; Complete the ACK cycle.
  (update-ack *ack-mgr* msg-id :fulfilled :note "Review processed")
  (format t ";;   ACK stage -> :FULFILLED (terminal)~%")

  ;; Verify terminal state.
  (let ((record (ack-manager-get *ack-mgr* msg-id)))
    (format t ";;   Terminal? ~A~%" (terminal-ack-stage-p (ack-record-stage record)))))

;; Also update the envelope state to match.
(update-envelope-state *review-envelope* +received-envelope+)
(update-envelope-state *review-envelope* +read-envelope+)
(update-envelope-state *review-envelope* +fulfilled-envelope+)
(format t ";;   Envelope terminal? ~A~%" (terminal-state-p (getf *review-envelope* :state)))

;;; ---------------------------------------------------------------------------
;;; Part C: Activity Buffer
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part C: Activity Buffer ===~%")

(defvar *activity-buf*
  (make-instance 'activity-buffer :capacity 100))

;; Record review activities.
(upsert-activity *activity-buf*
                 :task-id "review-pr-42"
                 :repo-id "myorg/backend"
                 :worktree-id "wt-reviewer-1"
                 :branch "feature/auth-refactor"
                 :description "Reviewing authentication middleware changes")

(upsert-activity *activity-buf*
                 :task-id "review-pr-43"
                 :repo-id "myorg/backend"
                 :worktree-id "wt-reviewer-1"
                 :branch "fix/sql-injection"
                 :description "Security audit of query builder")

(format t ";;   Buffer size: ~D~%" (current-size *activity-buf*))
(format t ";;   Buffer full? ~A~%" (if (is-full-p *activity-buf*) "yes" "no"))

;; List activities for the repo.
(let ((activities (list-buffer-activities *activity-buf* :repo-id "myorg/backend")))
  (format t ";;   Activities for myorg/backend: ~D~%" (length activities))
  (dolist (entry activities)
    (format t ";;     task=~A branch=~A~%"
            (activity-entry-task-id entry)
            (activity-entry-branch entry))))

;; Reconcile: mark pr-42 as completed so it gets purged.
(reconcile *activity-buf* '(("review-pr-42" . :completed)))
(format t ";;   After reconcile (pr-42 completed): ~D entries~%" (current-size *activity-buf*))

;;; ---------------------------------------------------------------------------
;;; Part D: Persistence
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part D: Persistence ===~%")

(defvar *persistence* (make-in-memory-persistence))

;; Save agent state: a snapshot of config and recent activities.
(let ((state-records
       (list (list :type "agent-config"
                   :agent-id (agent-config-agent-id *config*)
                   :name (agent-config-name *config*)
                   :version (agent-config-version *config*))
             (list :type "activity-snapshot"
                   :task-id "review-pr-43"
                   :repo-id "myorg/backend"
                   :branch "fix/sql-injection"))))
  (save-records *persistence* state-records :namespace "reviewer-1")
  (format t ";;   Saved ~D records to namespace 'reviewer-1'~%" (length state-records)))

;; Load them back (simulating a restart).
(let ((loaded (load-records *persistence* :namespace "reviewer-1")))
  (format t ";;   Loaded ~D records from persistence~%" (length loaded))
  (dolist (rec loaded)
    (format t ";;     type=~A~%" (getf rec :type))))

;; List namespaces.
(let ((namespaces (list-namespaces *persistence*)))
  (format t ";;   Namespaces: ~{~A~^, ~}~%" namespaces))

;;; ---------------------------------------------------------------------------
;;; Part E: Worktree Binding
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part E: Worktree Binding ===~%")

;; Create a worktree client (uses stub transport like other clients).
(defvar *wt-client*
  (make-instance 'worktree-client
                 :address (endpoints-worktree (agent-config-endpoints *config*))))

(format t ";;   Worktree service: ~A~%" (endpoints-worktree (agent-config-endpoints *config*)))

;; Demonstrate the worktree state machine.
;; In production these RPCs go to a live Worktree Service.
;; Here we show the call pattern and handle the expected stub errors.
(format t ";;   Demonstrating worktree binding pattern:~%")
(format t ";;     1. bind(agent-id, repo-id, worktree-id)  -> :bound-home~%")
(format t ";;     2. switch-request(agent-id, target-wt)   -> :switch-pending~%")
(format t ";;     3. approve-switch(agent-id, target-wt)   -> :bound-non-home~%")
(format t ";;     4. unbind(agent-id)                      -> :unbound~%")

(with-sw4rm-error-handling ()
  (handler-case
      (bind *wt-client* "reviewer-1" "myorg/backend" "wt-reviewer-1")
    (error (e)
      (format t ";;   [expected] bind stub: ~A~%" e))))

;;; ---------------------------------------------------------------------------
;;; Summary
;;; ---------------------------------------------------------------------------

(format t "~&~%;; Advanced agent example complete.~%")
(format t ";; Key takeaways:~%")
(format t ";;   - make-agent-config for agent setup~%")
(format t ";;   - make-envelope with Three-ID model for message construction~%")
(format t ";;   - make-ack-manager / track-outgoing / update-ack for ACK lifecycle~%")
(format t ";;   - activity-buffer / upsert-activity / reconcile for work tracking~%")
(format t ";;   - json-file-persistence or in-memory-persistence for state~%")
(format t ";;   - worktree-client / bind / switch-request for workspace isolation~%")
