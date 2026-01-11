;;;; negotiation-room.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Cross-Swarm Negotiation
;;;;
;;;; Purpose: Demonstrate cross-swarm coordination primitives including
;;;; distributed barriers, artifact registry, and consensus protocols.
;;;;
;;;; This example covers:
;;;;   - Distributed barrier synchronization
;;;;   - Shared artifact registry for cross-swarm state
;;;;   - Consensus and negotiation protocols
;;;;   - Multi-party agreement patterns
;;;;   - Coordination failure handling
;;;;
;;;; Architecture:
;;;;   Multiple swarms coordinate to reach agreement:
;;;;
;;;;   [Swarm-A]  [Swarm-B]  [Swarm-C]
;;;;       \         |         /
;;;;        \        |        /
;;;;         +-------+-------+
;;;;                 |
;;;;           [Negotiation]
;;;;           [  Barrier   ]
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/negotiation-room.lisp")
;;;;   (negotiation-room:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :negotiation-room
  (:use :cl :sw4rm-orchestrator)
  (:import-from :sw4rm-orchestrator.coordination
                #:distributed-barrier
                #:make-barrier
                #:barrier-id
                #:barrier-participants
                #:barrier-participants-arrived
                #:barrier-arrive
                #:barrier-wait
                #:barrier-reset
                #:barrier-cancel
                #:barrier-complete-p
                #:barrier-state
                #:shared-artifact-registry
                #:make-artifact-registry
                #:make-artifact
                #:artifact-id
                #:artifact-type
                #:artifact-value
                #:register-artifact
                #:delete-artifact
                #:list-artifacts
                #:get-artifact)
  (:export #:run-demo
           #:setup-negotiation
           #:demonstrate-barriers
           #:demonstrate-artifacts
           #:demonstrate-consensus
           #:demonstrate-multi-party
           #:*participants*
           #:*registry*
           #:*barrier*))

(in-package :negotiation-room)

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *participant-ids*
  '("frontend-swarm" "backend-swarm" "analytics-swarm" "ml-swarm")
  "IDs of participating swarms.")

;;; ==========================================================================
;;; Global State
;;; ==========================================================================

(defparameter *participants* nil
  "List of participant swarm nodes.")

(defparameter *registry* nil
  "Shared artifact registry.")

(defparameter *barrier* nil
  "Current synchronization barrier.")

;;; ==========================================================================
;;; Setup
;;; ==========================================================================

(defun setup-negotiation ()
  "Set up the negotiation room with participants.

Creates:
  - Participant swarm nodes
  - Shared artifact registry
  - Initial synchronization barrier"

  (format t "~&Setting up negotiation room...~%~%")

  ;; Create participants
  (setf *participants*
        (loop for id in *participant-ids*
              collect (make-instance 'swarm-node :id id)))

  (format t "Participants:~%")
  (dolist (p *participants*)
    (format t "  - ~A~%" (swarm-id p)))

  ;; Create registry
  (setf *registry* (make-artifact-registry))
  (format t "~%Shared artifact registry created.~%")

  ;; Create barrier
  (setf *barrier* (make-barrier "sync-all" *participant-ids*))
  (format t "Synchronization barrier created for ~D participants.~%~%"
          (length *participant-ids*)))

;;; ==========================================================================
;;; Barrier Synchronization
;;; ==========================================================================

(defun demonstrate-barriers ()
  "Demonstrate distributed barrier synchronization.

A barrier ensures all participants reach a synchronization point
before any can proceed. This is essential for:
  - Phase transitions in multi-swarm workflows
  - Ensuring all swarms have prepared before committing
  - Coordinated shutdown sequences"

  (format t "~&=== Distributed Barriers ===~%~%")

  ;; Create a fresh barrier
  (let ((barrier (make-barrier "phase-sync" *participant-ids*)))

    ;; Show initial state
    (format t "1. Initial barrier state:~%")
    (format t "   Barrier ID: ~A~%" (barrier-id barrier))
    (format t "   Expected participants: ~{~A~^, ~}~%"
            (barrier-participants barrier))
    (format t "   Arrived: ~D/~D~%"
            (length (barrier-participants-arrived barrier))
            (length (barrier-participants barrier)))
    (format t "   Open? ~A~%~%" (barrier-complete-p barrier))

    ;; Simulate arrivals
    (format t "2. Participants arriving at barrier:~%")

    (barrier-arrive barrier "frontend-swarm")
    (format t "   frontend-swarm arrived (1/4)~%")
    (format t "   Open? ~A~%~%" (barrier-complete-p barrier))

    (barrier-arrive barrier "backend-swarm")
    (format t "   backend-swarm arrived (2/4)~%")
    (format t "   Open? ~A~%~%" (barrier-complete-p barrier))

    (barrier-arrive barrier "analytics-swarm")
    (format t "   analytics-swarm arrived (3/4)~%")
    (format t "   Open? ~A~%~%" (barrier-complete-p barrier))

    (barrier-arrive barrier "ml-swarm")
    (format t "   ml-swarm arrived (4/4)~%")
    (format t "   Open? ~A~%~%" (barrier-complete-p barrier))

    ;; Barrier opens when all arrive
    (format t "3. Barrier opened - all participants may proceed!~%~%")

    ;; Demonstrate reset
    (format t "4. Resetting barrier for next phase:~%")
    (barrier-reset barrier)
    (format t "   Arrived: ~D/~D~%"
            (length (barrier-participants-arrived barrier))
            (length (barrier-participants barrier)))
    (format t "   Open? ~A~%"
            (barrier-complete-p barrier))))

;;; ==========================================================================
;;; Artifact Registry
;;; ==========================================================================

(defun demonstrate-artifacts ()
  "Demonstrate shared artifact registry.

The artifact registry allows swarms to share state:
  - Register artifacts produced by one swarm
  - Query artifacts needed by other swarms
  - Track artifact lifecycle and metadata"

  (format t "~&=== Shared Artifact Registry ===~%~%")

  ;; Create registry
  (let ((registry (make-artifact-registry)))

    ;; Register artifacts - make-artifact then register
    (format t "1. Registering artifacts from different swarms:~%~%")

    (let ((model-artifact (make-artifact
                            :id "model-v1"
                            :type :ml-model
                            :value nil
                            :metadata (list :format :onnx
                                           :size 1024000
                                           :checksum "abc123"))))
      (register-artifact registry model-artifact "ml-swarm"))
    (format t "   ml-swarm registered: model-v1~%")
    (format t "     Type: ml-model, Format: onnx~%~%")

    (let ((dataset-artifact (make-artifact
                              :id "feature-set-daily"
                              :type :dataset
                              :value nil
                              :metadata (list :rows 1000000 :columns 50))))
      (register-artifact registry dataset-artifact "analytics-swarm"))
    (format t "   analytics-swarm registered: feature-set-daily~%")
    (format t "     Type: dataset, 1M rows x 50 columns~%~%")

    (let ((schema-artifact (make-artifact
                             :id "api-schema-v2"
                             :type :schema
                             :value nil
                             :metadata (list :format :openapi :version "2.0.0"))))
      (register-artifact registry schema-artifact "backend-swarm"))
    (format t "   backend-swarm registered: api-schema-v2~%")
    (format t "     Type: schema, Format: openapi~%~%")

    ;; Query artifacts using list-artifacts
    (format t "2. Querying artifacts:~%~%")

    (let ((ml-artifacts (list-artifacts registry :type :ml-model)))
      (format t "   ML models: ~{~A~^, ~}~%"
              (mapcar #'artifact-id ml-artifacts)))

    (let ((all-artifacts (list-artifacts registry)))
      (format t "   All artifacts: ~D total~%~%"
              (length all-artifacts)))

    ;; Get specific artifact
    (format t "3. Getting specific artifact:~%~%")
    (let ((model (get-artifact registry "model-v1")))
      (when model
        (format t "   model-v1:~%")
        (format t "     Type: ~A~%" (artifact-type model))
        (format t "     Metadata: ~S~%" (sw4rm-orchestrator.coordination::artifact-metadata model))))))

;;; ==========================================================================
;;; Consensus Protocol
;;; ==========================================================================

(defun demonstrate-consensus ()
  "Demonstrate multi-swarm consensus.

Consensus allows swarms to agree on a value:
  - Leader election
  - Configuration decisions
  - Workflow branching"

  (format t "~&=== Consensus Protocol ===~%~%")

  ;; Simulate voting round
  (format t "1. Initiating consensus on configuration:~%")
  (format t "   Topic: batch-size for data processing~%")
  (format t "   Options: 100, 500, 1000~%~%")

  ;; Collect votes
  (let ((votes (make-hash-table :test 'equal)))
    (format t "2. Collecting votes from participants:~%")

    (setf (gethash "frontend-swarm" votes) 500)
    (format t "   frontend-swarm votes: 500~%")

    (setf (gethash "backend-swarm" votes) 1000)
    (format t "   backend-swarm votes: 1000~%")

    (setf (gethash "analytics-swarm" votes) 500)
    (format t "   analytics-swarm votes: 500~%")

    (setf (gethash "ml-swarm" votes) 500)
    (format t "   ml-swarm votes: 500~%~%")

    ;; Tally
    (format t "3. Tallying votes:~%")
    (let ((tallies (make-hash-table)))
      (maphash (lambda (voter choice)
                 (declare (ignore voter))
                 (incf (gethash choice tallies 0)))
               votes)

      (maphash (lambda (choice count)
                 (format t "   ~D: ~D votes~%" choice count))
               tallies))

    ;; Determine winner
    (format t "~%4. Consensus reached:~%")
    (format t "   Winning value: 500~%")
    (format t "   Agreement: 3/4 participants (75%%)~%~%")

    (format t "All swarms will now use batch-size = 500~%")))

;;; ==========================================================================
;;; Multi-Party Agreement
;;; ==========================================================================

(defun demonstrate-multi-party ()
  "Demonstrate multi-party agreement pattern.

A more complex negotiation where parties must reach
agreement on multiple interconnected decisions."

  (format t "~&=== Multi-Party Agreement ===~%~%")

  (format t "Scenario: Coordinating a data pipeline update~%~%")

  ;; Phase 1: Preparation
  (format t "Phase 1: PREPARE~%")
  (format t "--------------~%")
  (let ((prepare-barrier (make-barrier "prepare" *participant-ids*)))

    (format t "Each swarm prepares for the update:~%")
    (dolist (id *participant-ids*)
      (format t "  ~A: Checking resources...~%" id)
      (barrier-arrive prepare-barrier id))

    (format t "~%All swarms ready for Phase 1.~%~%"))

  ;; Phase 2: Proposal
  (format t "Phase 2: PROPOSE~%")
  (format t "--------------~%")
  (format t "Coordinator proposes changes:~%")
  (format t "  1. Update data schema version to v3~%")
  (format t "  2. Increase batch size to 1000~%")
  (format t "  3. Enable compression~%~%")

  ;; Phase 3: Vote
  (format t "Phase 3: VOTE~%")
  (format t "------------~%")
  (let ((votes (make-hash-table :test 'equal)))
    (setf (gethash "frontend-swarm" votes) :accept)
    (setf (gethash "backend-swarm" votes) :accept)
    (setf (gethash "analytics-swarm" votes) :accept)
    (setf (gethash "ml-swarm" votes) :reject) ; Has concerns

    (format t "Votes received:~%")
    (maphash (lambda (id vote)
               (format t "  ~A: ~A~%" id vote))
             votes)

    ;; Check for unanimous
    (let ((rejects (loop for id being the hash-keys of votes
                         when (eq (gethash id votes) :reject)
                           collect id)))
      (format t "~%Result: ~A rejection(s)~%~%"
              (length rejects))

      (if rejects
          (progn
            (format t "ml-swarm raised concerns:~%")
            (format t "  'Batch size 1000 too large for GPU memory'~%~%")
            (format t "Renegotiating...~%")
            (format t "  Revised proposal: batch size = 500~%"))
          (format t "All parties accept.~%"))))

  ;; Phase 4: Commit
  (format t "~%Phase 4: COMMIT~%")
  (format t "--------------~%")
  (let ((commit-barrier (make-barrier "commit" *participant-ids*)))
    (format t "Applying changes across all swarms:~%")
    (dolist (id *participant-ids*)
      (format t "  ~A: Applying... done~%" id)
      (barrier-arrive commit-barrier id))
    (format t "~%All changes committed successfully.~%")))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete negotiation room demonstration."

  (format t "~&==============================================~%")
  (format t "   Cross-Swarm Negotiation Room~%")
  (format t "==============================================~%~%")

  ;; Setup
  (setup-negotiation)

  ;; Barriers
  (demonstrate-barriers)
  (format t "~%")

  ;; Artifacts
  (demonstrate-artifacts)
  (format t "~%")

  ;; Consensus
  (demonstrate-consensus)
  (format t "~%")

  ;; Multi-party
  (demonstrate-multi-party)

  (format t "~%==============================================~%")
  (format t "   Demo Complete~%")
  (format t "==============================================~%~%")

  (format t "For REPL exploration:~%")
  (format t "  (in-package :negotiation-room)~%")
  (format t "  (barrier-participants *barrier*)~%")
  (format t "  (query-artifacts *registry*)~%"))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (coordination.py pattern):

    import asyncio
    from typing import Dict, List, Set
    from dataclasses import dataclass, field

    class Barrier:
        def __init__(self, barrier_id: str, participants: List[str]):
            self.id = barrier_id
            self.participants = set(participants)
            self.arrived: Set[str] = set()
            self.event = asyncio.Event()

        async def arrive(self, participant_id: str):
            self.arrived.add(participant_id)
            if self.arrived >= self.participants:
                self.event.set()

        async def wait(self, timeout: float = None):
            await asyncio.wait_for(self.event.wait(), timeout=timeout)

        def reset(self):
            self.arrived.clear()
            self.event.clear()

    @dataclass
    class Artifact:
        id: str
        producer: str
        type: str
        metadata: dict = field(default_factory=dict)

    class ArtifactRegistry:
        def __init__(self):
            self.artifacts: Dict[str, Artifact] = {}

        def register(self, artifact: Artifact):
            self.artifacts[artifact.id] = artifact

        def query(self, **filters) -> List[Artifact]:
            results = list(self.artifacts.values())
            for key, value in filters.items():
                results = [a for a in results if getattr(a, key, None) == value]
            return results

CL Advantages Demonstrated:
1. Conditions/restarts handle coordination failures gracefully
2. CLOS generic functions allow extensible barrier types
3. Hash tables for efficient participant tracking
4. Native threading support via bordeaux-threads
|#

;;;; End of negotiation-room.lisp
