;;;; negotiation-voting.lisp -- Negotiation events and voting aggregation example
;;;;
;;;; Demonstrates the SW4RM negotiation and voting subsystem:
;;;;   1. Creating a negotiation event emitter and registering listeners
;;;;   2. Emitting negotiation lifecycle events (proposal, critique, vote, approval)
;;;;   3. Casting votes with multiple aggregation strategies
;;;;   4. Running voting rounds and inspecting results
;;;;   5. Using the confidence-weighted and Borda count strategies
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed
;;;;   - SW4RM SDK on ASDF load path
;;;;
;;;; Run:
;;;;   sbcl --load examples/negotiation-voting.lisp

;;; ---------------------------------------------------------------------------
;;; Step 0: Load the SDK
;;; ---------------------------------------------------------------------------

(ql:quickload :sw4rm-sdk)

(defpackage #:negotiation-voting-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:negotiation-voting-example)

;;; ---------------------------------------------------------------------------
;;; Part A: Negotiation Events
;;; ---------------------------------------------------------------------------
;;; The negotiation event system lets agents observe room activity through
;;; typed events. An emitter dispatches events to registered listeners,
;;; maintaining a bounded history for audit purposes.

(format t "~&;; === Part A: Negotiation Event System ===~%")

;; Create an event emitter with a history limit of 500 events.
(defvar *emitter* (make-event-emitter :max-history 500))

;; Define some agent identifiers for our scenario.
(defparameter +architect+  "architect-1")
(defparameter +security+   "security-reviewer")
(defparameter +api-review+  "api-reviewer")
(defparameter +room-id+     "neg-api-design-001")

;; Register a listener for proposal events.
(defvar *proposal-log* nil
  "Accumulator for proposal events received by our listener.")

(defun on-proposal (event)
  "Listener that records proposal-submitted events."
  (push (negotiation-event-event-id event) *proposal-log*)
  (format t ";;   [listener] Proposal received from ~A in room ~A~%"
          (negotiation-event-agent-id event)
          (negotiation-event-room-id event)))

(on *emitter* :proposal-submitted #'on-proposal)

;; Register a global listener that logs every event type.
(defun on-any-event (event)
  "Global listener that prints a one-line summary for every event."
  (format t ";;   [global] Event ~A: type=~A agent=~A~%"
          (negotiation-event-event-id event)
          (negotiation-event-event-type event)
          (negotiation-event-agent-id event)))

(on *emitter* :all #'on-any-event)

(format t ";;   Listener count: ~D (1 typed + 1 global)~%" (listener-count *emitter*))

;; Emit a series of events simulating a negotiation lifecycle.

;; 1. Participants join the room.
(format t "~&;; --- Participants joining ---~%")
(emit *emitter* (make-participant-joined-event +room-id+ +architect+))
(emit *emitter* (make-participant-joined-event +room-id+ +security+))
(emit *emitter* (make-participant-joined-event +room-id+ +api-review+))

;; 2. Architect submits a proposal.
(format t "~&;; --- Proposal submitted ---~%")
(emit *emitter*
      (make-proposal-submitted-event
       +room-id+ +architect+
       '(:endpoint "/api/v2/users"
         :method "POST"
         :auth "bearer-token"
         :rate-limit 100)))

(format t ";;   Proposals logged by typed listener: ~D~%" (length *proposal-log*))

;; 3. Security reviewer adds a critique.
(format t "~&;; --- Critique added ---~%")
(emit *emitter*
      (make-critique-added-event
       +room-id+ +security+
       '(:concern "Missing CSRF protection on POST endpoint"
         :severity :high
         :suggestion "Add X-CSRF-Token header validation")))

;; 4. Agents cast votes (event side -- the aggregation is in Part B).
(format t "~&;; --- Votes cast ---~%")
(emit *emitter*
      (make-vote-cast-event +room-id+ +architect+
                            '(:choice :approve :confidence 0.9)))
(emit *emitter*
      (make-vote-cast-event +room-id+ +security+
                            '(:choice :approve-with-changes :confidence 0.7)))
(emit *emitter*
      (make-vote-cast-event +room-id+ +api-review+
                            '(:choice :approve :confidence 0.85)))

;; 5. Round completes with approval.
(format t "~&;; --- Round complete ---~%")
(emit *emitter*
      (make-round-complete-event +room-id+ 1
                                 '(:outcome :approved-with-changes)))

(emit *emitter*
      (make-approved-event +room-id+
                           '(:endpoint "/api/v2/users"
                             :method "POST"
                             :auth "bearer-token"
                             :rate-limit 100
                             :csrf-protection t)))

;; Query event history with filters.
(format t "~&;; --- Event history ---~%")
(let ((all-events (get-history *emitter*))
      (votes-only (get-history *emitter* :event-type :vote-cast))
      (room-events (get-history *emitter* :room-id +room-id+ :limit 3)))
  (format t ";;   Total events emitted : ~D~%" (length all-events))
  (format t ";;   Vote events          : ~D~%" (length votes-only))
  (format t ";;   Last 3 room events   : ~D~%" (length room-events)))

;;; ---------------------------------------------------------------------------
;;; Part B: Voting Aggregation Strategies
;;; ---------------------------------------------------------------------------
;;; The voting module provides pluggable aggregation strategies for combining
;;; agent votes into a collective decision.

(format t "~&~%;; === Part B: Voting Aggregation ===~%")

;; Create votes representing agent opinions on the API proposal.
(defvar *votes*
  (list
   (make-vote :agent-id +architect+
              :choice :approve
              :confidence 0.9
              :metadata '(:role "architect"))
   (make-vote :agent-id +security+
              :choice :approve-with-changes
              :confidence 0.7
              :metadata '(:role "security"))
   (make-vote :agent-id +api-review+
              :choice :approve
              :confidence 0.85
              :metadata '(:role "api-reviewer"))
   ;; A fourth agent that disagrees.
   (make-vote :agent-id "testing-agent"
              :choice :reject
              :confidence 0.6
              :metadata '(:role "tester"))))

;; --- Strategy 1: Majority Vote ---
(format t "~&;; --- Majority Vote Strategy ---~%")

(let* ((strategy (make-instance 'majority-vote-strategy))
       (result (aggregate strategy *votes*)))
  (format t ";;   Winner     : ~A~%" (getf result :winner))
  (format t ";;   Vote count : ~D / ~D~%" (getf result :count) (getf result :total))
  (format t ";;   Distribution:~%")
  (maphash (lambda (choice count)
             (format t ";;     ~A => ~D votes~%" choice count))
           (getf result :distribution)))

;; --- Strategy 2: Confidence-Weighted ---
(format t "~&;; --- Confidence-Weighted Strategy ---~%")

(let* ((strategy (make-instance 'confidence-weighted-strategy))
       (result (aggregate strategy *votes*)))
  (format t ";;   Winner       : ~A~%" (getf result :winner))
  (format t ";;   Total weight : ~,2F~%" (getf result :total-weight))
  (format t ";;   Weighted scores:~%")
  (maphash (lambda (choice score)
             (format t ";;     ~A => ~,2F~%" choice score))
           (getf result :weighted-scores)))

;; --- Strategy 3: Simple Average (numeric scores) ---
(format t "~&;; --- Simple Average Strategy (numeric scores) ---~%")

(let* ((numeric-votes
         (list
          (make-vote :agent-id +architect+  :choice 8.5 :confidence 0.9)
          (make-vote :agent-id +security+   :choice 7.0 :confidence 0.7)
          (make-vote :agent-id +api-review+  :choice 6.5 :confidence 0.85)
          (make-vote :agent-id "testing-agent" :choice 9.0 :confidence 0.95)))
       (strategy (make-instance 'simple-average-strategy))
       (result (aggregate strategy numeric-votes)))
  (format t ";;   Average : ~,2F~%" (getf result :average))
  (format t ";;   Min     : ~,2F~%" (getf result :min))
  (format t ";;   Max     : ~,2F~%" (getf result :max))
  (format t ";;   Std dev : ~,2F~%" (getf result :stddev))
  (format t ";;   Count   : ~D~%" (getf result :count)))

;; --- Strategy 4: Borda Count (ranked preferences) ---
(format t "~&;; --- Borda Count Strategy (ranked preferences) ---~%")

(let* ((ranked-votes
         (list
          ;; Each choice is a list of options ranked from most to least preferred.
          (make-vote :agent-id +architect+
                     :choice '(:approve :approve-with-changes :reject))
          (make-vote :agent-id +security+
                     :choice '(:approve-with-changes :approve :reject))
          (make-vote :agent-id +api-review+
                     :choice '(:approve :approve-with-changes :reject))
          (make-vote :agent-id "testing-agent"
                     :choice '(:reject :approve-with-changes :approve))))
       (strategy (make-instance 'borda-count-strategy))
       (result (aggregate strategy ranked-votes)))
  (format t ";;   Winner      : ~A~%" (getf result :winner))
  (format t ";;   Total voters: ~D~%" (getf result :total-votes))
  (format t ";;   Borda scores:~%")
  (maphash (lambda (choice score)
             (format t ";;     ~A => ~D points~%" choice score))
           (getf result :scores)))

;;; ---------------------------------------------------------------------------
;;; Part C: Voting Aggregator with History
;;; ---------------------------------------------------------------------------
;;; The voting-aggregator class wraps strategies with round tracking and
;;; history for audit purposes.

(format t "~&~%;; === Part C: Voting Aggregator with Audit History ===~%")

(defvar *aggregator*
  (make-instance 'voting-aggregator
                 :strategy (make-instance 'confidence-weighted-strategy)
                 :max-history 50))

;; Run a voting round.
(let ((result (run-vote *aggregator* *votes* :round-id "round-1")))
  (format t ";;   Round 1 winner: ~A~%" (getf result :winner)))

;; Switch strategy and run another round.
(set-strategy *aggregator* (make-instance 'majority-vote-strategy))

(let ((result (run-vote *aggregator* *votes* :round-id "round-2")))
  (format t ";;   Round 2 winner: ~A (majority)~%" (getf result :winner)))

;; Inspect round history.
(let ((history (get-round-history *aggregator*)))
  (format t ";;   Rounds in history: ~D~%" (length history))
  (dolist (round history)
    (format t ";;     Round ~A: strategy=~A, votes=~D~%"
            (voting-round-round-id round)
            (voting-round-strategy-name round)
            (length (voting-round-votes round)))))

;; Convert a vote to/from plist for serialization.
(format t "~&;; --- Vote serialization ---~%")
(let* ((original (first *votes*))
       (plist (vote-to-plist original))
       (restored (make-vote-from-plist plist)))
  (format t ";;   Original agent-id : ~A~%" (vote-agent-id original))
  (format t ";;   Plist form        : ~S~%" plist)
  (format t ";;   Restored agent-id : ~A~%" (vote-agent-id restored)))

;;; ---------------------------------------------------------------------------
;;; Summary
;;; ---------------------------------------------------------------------------

(format t "~&~%;; Negotiation and voting example complete.~%")
(format t ";; Key takeaways:~%")
(format t ";;   - make-event-emitter / on / emit for negotiation event dispatch~%")
(format t ";;   - make-*-event helpers for typed event construction~%")
(format t ";;   - get-history for filtered event queries~%")
(format t ";;   - make-vote + aggregate for pluggable voting strategies~%")
(format t ";;   - majority-vote, confidence-weighted, simple-average, borda-count~%")
(format t ";;   - voting-aggregator / run-vote for auditable voting rounds~%")
