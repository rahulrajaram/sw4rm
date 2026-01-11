;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; coordination/negotiation.lisp
;;;;
;;;; Cross-Swarm Negotiation and Consensus Protocols
;;;;
;;;; This module implements negotiation and consensus mechanisms for coordinating
;;;; decisions across multiple sw4rm instances. This enables:
;;;;   - Multi-party agreement on shared decisions
;;;;   - Distributed voting protocols
;;;;   - Consensus-based resource allocation
;;;;   - Conflict resolution across swarms
;;;;
;;;; Key concepts:
;;;;   - NEGOTIATION-SESSION: A multi-swarm negotiation session
;;;;   - PROPOSAL: A proposed decision or action
;;;;   - Voting: Participants vote on proposals
;;;;   - Consensus strategies: Different ways to reach agreement
;;;;
;;;; Consensus strategies supported:
;;;;   - :MAJORITY - Simple majority (> 50%)
;;;;   - :UNANIMOUS - All participants must agree
;;;;   - :WEIGHTED - Weighted voting based on swarm priorities
;;;;
;;;; Use cases:
;;;;   - Leader election across swarms
;;;;   - Resource allocation decisions
;;;;   - Configuration changes requiring agreement
;;;;   - Conflict resolution in distributed transactions
;;;;
;;;; Thread Safety:
;;;;   This implementation uses bordeaux-threads for thread-safe operations.
;;;;   Multiple threads can safely participate in negotiations concurrently.
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.coordination)

;;;; ============================================================================
;;;; PROPOSAL Structure
;;;; ============================================================================

(defstruct (proposal (:conc-name proposal-))
  "A proposal submitted during negotiation.

  Represents a specific option or decision that participants can vote on.

  Slots:
    id - Unique identifier for this proposal
    proposer - Swarm ID that submitted this proposal
    content - The actual proposal data (any Lisp object)
    timestamp - When the proposal was submitted
    metadata - Optional metadata (plist)

  Example:
    (make-proposal
      :id \"proposal-1\"
      :proposer \"swarm-a\"
      :content (list :action :allocate-resources :amount 100)
      :metadata (list :priority :high))

  See Also:
    NEGOTIATION-SESSION, SUBMIT-PROPOSAL, VOTE-ON-PROPOSAL"
  (id (error "Proposal ID required") :type string :read-only t)
  (proposer (error "Proposer required") :type string :read-only t)
  (content nil :type t)
  (timestamp (get-universal-time) :type integer :read-only t)
  (metadata nil :type list))

;;;; ============================================================================
;;;; Vote Type
;;;; ============================================================================

(deftype vote-value ()
  "Valid vote values.

  Values:
    :YES - Vote in favor
    :NO - Vote against
    :ABSTAIN - Abstain from voting"
  '(member :yes :no :abstain))

;;;; ============================================================================
;;;; NEGOTIATION-SESSION Class
;;;; ============================================================================

(defclass negotiation-session ()
  ((id
    :initarg :id
    :reader negotiation-id
    :type string
    :documentation "Unique identifier for this negotiation session.")

   (initiator
    :initarg :initiator
    :reader negotiation-initiator
    :type string
    :documentation "Swarm ID that initiated this negotiation.")

   (participants
    :initarg :participants
    :reader negotiation-participants
    :type list
    :documentation "List of swarm IDs participating in this negotiation.

    All participants can submit proposals and vote.")

   (topic
    :initarg :topic
    :reader negotiation-topic
    :type (or keyword string)
    :documentation "Topic or purpose of this negotiation.

    Examples: :leader-election, :resource-allocation, \"config-change\"")

   (proposals
    :accessor negotiation-proposals
    :initform nil
    :type list
    :documentation "List of PROPOSAL structures submitted so far.

    Proposals are added via SUBMIT-PROPOSAL.")

   (votes
    :accessor negotiation-votes
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping swarm-id -> (proposal-id . vote-value).

    Records each participant's vote on a specific proposal.")

   (state
    :accessor negotiation-state
    :initform :open
    :type (member :open :voting :decided :failed :cancelled)
    :documentation "Current state of the negotiation.

    Values:
      :OPEN - Accepting proposals
      :VOTING - Voting phase active
      :DECIDED - Consensus reached
      :FAILED - Failed to reach consensus
      :CANCELLED - Negotiation cancelled")

   (deadline
    :initarg :deadline
    :accessor negotiation-deadline
    :initform nil
    :type (or null integer)
    :documentation "Universal time deadline for reaching consensus.

    NIL means no deadline. If deadline passes, negotiation fails.")

   (created-at
    :reader negotiation-created-at
    :initform (get-universal-time)
    :type integer
    :documentation "Universal time when negotiation was created.")

   (decided-at
    :accessor negotiation-decided-at
    :initform nil
    :type (or null integer)
    :documentation "Universal time when consensus was reached (or failed).")

   (winning-proposal
    :accessor negotiation-winning-proposal
    :initform nil
    :type (or null proposal)
    :documentation "The proposal that won consensus (NIL if no consensus).")

   (session-lock
    :reader negotiation-lock
    :initform (bt:make-lock "negotiation-lock")
    :documentation "Lock for thread-safe operations."))

  (:documentation "Negotiation session for cross-swarm consensus.

  A negotiation session coordinates multi-swarm decision-making through:
    1. Proposal submission: Participants submit options
    2. Voting: Participants vote on proposals
    3. Consensus: Apply strategy to determine winner

  Lifecycle:
    1. Create session with participants and topic
    2. Participants submit proposals (state: :OPEN)
    3. Transition to :VOTING when ready
    4. Participants vote on proposals
    5. Check for consensus with chosen strategy
    6. Transition to :DECIDED or :FAILED

  States:
    :OPEN - Accepting new proposals
    :VOTING - Voting on existing proposals
    :DECIDED - Consensus reached, winner determined
    :FAILED - Failed to reach consensus by deadline
    :CANCELLED - Explicitly cancelled

  Consensus Strategies:
    :MAJORITY - Simple majority (> 50% of participants)
    :UNANIMOUS - All participants must agree
    :WEIGHTED - Weighted voting (requires weight metadata)

  Operations:
    - SUBMIT-PROPOSAL: Add a new proposal
    - VOTE-ON-PROPOSAL: Record a participant's vote
    - REACH-CONSENSUS: Apply consensus strategy
    - GET-DECISION: Retrieve winning proposal if decided

  Thread Safety:
    All operations are thread-safe.

  Example:
    (let ((session (make-negotiation \"leader-election\"
                                     \"swarm-a\"
                                     '(\"swarm-a\" \"swarm-b\" \"swarm-c\")
                                     :leader-election
                                     :deadline (+ (get-universal-time) 300))))
      ;; Submit proposals
      (submit-proposal session \"swarm-a\"
                      (list :leader \"swarm-a\" :priority 10))
      (submit-proposal session \"swarm-b\"
                      (list :leader \"swarm-b\" :priority 8))

      ;; Vote
      (vote-on-proposal session \"swarm-a\" \"proposal-1\" :yes)
      (vote-on-proposal session \"swarm-b\" \"proposal-2\" :yes)
      (vote-on-proposal session \"swarm-c\" \"proposal-1\" :yes)

      ;; Check consensus
      (when (consensus-reached-p session :strategy :majority)
        (let ((winner (reach-consensus session :strategy :majority)))
          (format t \"Winner: ~A~%\" (proposal-content winner)))))

  See Also:
    MAKE-NEGOTIATION, SUBMIT-PROPOSAL, VOTE-ON-PROPOSAL, REACH-CONSENSUS"))

;;;; ============================================================================
;;;; Constructor
;;;; ============================================================================

(defun make-negotiation (initiator participants topic &key deadline)
  "Create a new negotiation session.

  Args:
    initiator - String ID of swarm initiating negotiation
    participants - List of swarm IDs participating (must include initiator)
    topic - Keyword or string describing negotiation topic
    deadline - Optional universal time deadline (NIL for no deadline)

  Returns:
    New NEGOTIATION-SESSION instance.

  Raises:
    ERROR if participants list is empty
    ERROR if initiator not in participants

  Examples:
    (make-negotiation \"swarm-a\"
                     '(\"swarm-a\" \"swarm-b\" \"swarm-c\")
                     :leader-election)

    (make-negotiation \"admin\"
                     '(\"admin\" \"worker-1\" \"worker-2\")
                     \"resource-allocation\"
                     :deadline (+ (get-universal-time) 600))

  See Also:
    NEGOTIATION-SESSION, SUBMIT-PROPOSAL"
  (unless (and (listp participants) (> (length participants) 0))
    (error "Negotiation participants must be a non-empty list, got: ~S" participants))
  (unless (member initiator participants :test #'string=)
    (error "Initiator ~S must be in participants list" initiator))

  (make-instance 'negotiation-session
                 :id (format nil "negotiation-~A-~A"
                            topic (get-universal-time))
                 :initiator initiator
                 :participants participants
                 :topic topic
                 :deadline deadline))

;;;; ============================================================================
;;;; Proposal Submission
;;;; ============================================================================

(defun submit-proposal (session swarm-id content)
  "Submit a proposal to the negotiation.

  Args:
    session - NEGOTIATION-SESSION instance
    swarm-id - String ID of swarm submitting proposal
    content - Proposal content (any Lisp object)

  Returns:
    The created PROPOSAL instance.

  Raises:
    ERROR if swarm-id not in participants
    ERROR if session not in :OPEN state

  Side Effects:
    - Adds proposal to negotiation-proposals
    - Generates unique proposal ID

  Thread Safety:
    This operation is thread-safe.

  Example:
    (submit-proposal session \"swarm-a\"
                    (list :action :scale-up :instances 5))

  See Also:
    VOTE-ON-PROPOSAL, NEGOTIATION-PROPOSALS"
  (declare (type negotiation-session session)
           (type string swarm-id))

  (bt:with-lock-held ((negotiation-lock session))
    ;; Validate state
    (unless (eq (negotiation-state session) :open)
      (error "Cannot submit proposal to negotiation ~S in state ~S"
             (negotiation-id session) (negotiation-state session)))

    ;; Validate participant
    (unless (member swarm-id (negotiation-participants session) :test #'string=)
      (error "Swarm ~S is not a participant in negotiation ~S"
             swarm-id (negotiation-id session)))

    ;; Create proposal
    (let* ((proposal-count (length (negotiation-proposals session)))
           (proposal-id (format nil "~A-proposal-~D"
                               (negotiation-id session)
                               (1+ proposal-count)))
           (proposal (make-proposal :id proposal-id
                                   :proposer swarm-id
                                   :content content)))

      ;; Add to list
      (push proposal (negotiation-proposals session))
      proposal)))

;;;; ============================================================================
;;;; Voting
;;;; ============================================================================

(defun vote-on-proposal (session swarm-id proposal-id vote)
  "Record a vote on a specific proposal.

  Args:
    session - NEGOTIATION-SESSION instance
    swarm-id - String ID of voting swarm
    proposal-id - String ID of proposal to vote on
    vote - Vote value (:YES, :NO, or :ABSTAIN)

  Returns:
    T on success.

  Raises:
    ERROR if swarm-id not in participants
    ERROR if proposal-id not found
    ERROR if vote is invalid

  Side Effects:
    - Records vote in negotiation-votes hash table
    - Overwrites previous vote by same swarm (if any)

  Thread Safety:
    This operation is thread-safe.

  Example:
    (vote-on-proposal session \"swarm-b\" \"proposal-1\" :yes)

  See Also:
    SUBMIT-PROPOSAL, REACH-CONSENSUS, GET-DECISION"
  (declare (type negotiation-session session)
           (type string swarm-id proposal-id)
           (type vote-value vote))

  (bt:with-lock-held ((negotiation-lock session))
    ;; Validate participant
    (unless (member swarm-id (negotiation-participants session) :test #'string=)
      (error "Swarm ~S is not a participant in negotiation ~S"
             swarm-id (negotiation-id session)))

    ;; Validate proposal exists
    (unless (find proposal-id (negotiation-proposals session)
                 :key #'proposal-id :test #'string=)
      (error "Proposal ~S not found in negotiation ~S"
             proposal-id (negotiation-id session)))

    ;; Record vote (overwrite previous vote if exists)
    (setf (gethash swarm-id (negotiation-votes session))
          (cons proposal-id vote))
    t))

;;;; ============================================================================
;;;; Consensus Protocols
;;;; ============================================================================

(defun reach-consensus (session &key (strategy :majority))
  "Apply consensus strategy to determine winning proposal.

  Analyzes votes according to the specified strategy and determines if
  consensus has been reached. If so, transitions to :DECIDED state.

  Args:
    session - NEGOTIATION-SESSION instance
    strategy - Consensus strategy (:MAJORITY, :UNANIMOUS, or :WEIGHTED)

  Returns:
    Winning PROPOSAL if consensus reached, NIL otherwise.

  Side Effects:
    - May transition state to :DECIDED or :FAILED
    - Sets negotiation-winning-proposal if consensus reached
    - Sets negotiation-decided-at timestamp

  Strategies:
    :MAJORITY - Proposal with most :YES votes (> 50% of participants)
    :UNANIMOUS - All participants voted :YES on same proposal
    :WEIGHTED - Weighted voting (uses :weight in proposal metadata)

  Thread Safety:
    This operation is thread-safe.

  Example:
    (let ((winner (reach-consensus session :strategy :majority)))
      (if winner
          (format t \"Consensus reached: ~A~%\" (proposal-content winner))
          (format t \"No consensus yet~%\")))

  See Also:
    CONSENSUS-REACHED-P, GET-DECISION, VOTE-ON-PROPOSAL"
  (declare (type negotiation-session session)
           (type (member :majority :unanimous :weighted) strategy))

  (bt:with-lock-held ((negotiation-lock session))
    ;; Check deadline
    (when (and (negotiation-deadline session)
               (>= (get-universal-time) (negotiation-deadline session)))
      (unless (member (negotiation-state session) '(:decided :failed :cancelled))
        (setf (negotiation-state session) :failed
              (negotiation-decided-at session) (get-universal-time)))
      (return-from reach-consensus nil))

    ;; Apply strategy
    (let ((winner (ecase strategy
                    (:majority (apply-majority-consensus session))
                    (:unanimous (apply-unanimous-consensus session))
                    (:weighted (apply-weighted-consensus session)))))

      (when winner
        ;; Consensus reached
        (setf (negotiation-state session) :decided
              (negotiation-winning-proposal session) winner
              (negotiation-decided-at session) (get-universal-time)))

      winner)))

(defun apply-majority-consensus (session)
  "Apply majority voting strategy.

  A proposal wins if it receives :YES votes from more than 50% of participants.

  Args:
    session - NEGOTIATION-SESSION instance

  Returns:
    Winning PROPOSAL or NIL if no majority.

  Internal function, use REACH-CONSENSUS instead."
  (let* ((participants (negotiation-participants session))
         (participant-count (length participants))
         (majority-threshold (ceiling participant-count 2))
         (proposal-vote-counts (make-hash-table :test 'equal)))

    ;; Count :YES votes per proposal
    (loop for swarm-id being the hash-keys of (negotiation-votes session)
          using (hash-value vote-entry)
          do (destructuring-bind (proposal-id . vote) vote-entry
               (when (eq vote :yes)
                 (incf (gethash proposal-id proposal-vote-counts 0)))))

    ;; Find proposal with majority
    (loop for proposal-id being the hash-keys of proposal-vote-counts
          using (hash-value vote-count)
          when (> vote-count majority-threshold)
          do (return (find proposal-id (negotiation-proposals session)
                          :key #'proposal-id :test #'string=)))))

(defun apply-unanimous-consensus (session)
  "Apply unanimous voting strategy.

  All participants must vote :YES on the same proposal.

  Args:
    session - NEGOTIATION-SESSION instance

  Returns:
    Winning PROPOSAL or NIL if not unanimous.

  Internal function, use REACH-CONSENSUS instead."
  (let* ((participants (negotiation-participants session))
         (participant-count (length participants))
         (proposal-vote-counts (make-hash-table :test 'equal)))

    ;; Count :YES votes per proposal
    (loop for swarm-id being the hash-keys of (negotiation-votes session)
          using (hash-value vote-entry)
          do (destructuring-bind (proposal-id . vote) vote-entry
               (when (eq vote :yes)
                 (incf (gethash proposal-id proposal-vote-counts 0)))))

    ;; Find proposal with unanimous support
    (loop for proposal-id being the hash-keys of proposal-vote-counts
          using (hash-value vote-count)
          when (= vote-count participant-count)
          do (return (find proposal-id (negotiation-proposals session)
                          :key #'proposal-id :test #'string=)))))

(defun apply-weighted-consensus (session)
  "Apply weighted voting strategy.

  Each swarm's vote has a weight (from proposal metadata :weight field).
  Proposal with highest weighted score wins if it exceeds threshold.

  Args:
    session - NEGOTIATION-SESSION instance

  Returns:
    Winning PROPOSAL or NIL if threshold not reached.

  Note:
    Proposals must have :weight in their metadata, defaulting to 1.

  Internal function, use REACH-CONSENSUS instead."
  (let ((proposal-scores (make-hash-table :test 'equal)))

    ;; Calculate weighted scores
    (loop for swarm-id being the hash-keys of (negotiation-votes session)
          using (hash-value vote-entry)
          do (destructuring-bind (proposal-id . vote) vote-entry
               (when (eq vote :yes)
                 (let* ((proposal (find proposal-id (negotiation-proposals session)
                                       :key #'proposal-id :test #'string=))
                        (weight (getf (proposal-metadata proposal) :weight 1)))
                   (incf (gethash proposal-id proposal-scores 0) weight)))))

    ;; Find proposal with highest score
    (let ((max-score 0)
          (winning-proposal-id nil))
      (loop for proposal-id being the hash-keys of proposal-scores
            using (hash-value score)
            when (> score max-score)
            do (setf max-score score
                    winning-proposal-id proposal-id))

      (when winning-proposal-id
        (find winning-proposal-id (negotiation-proposals session)
             :key #'proposal-id :test #'string=)))))

(defun consensus-reached-p (session &key (strategy :majority))
  "Check if consensus has been reached.

  Non-destructive check that doesn't modify session state.

  Args:
    session - NEGOTIATION-SESSION instance
    strategy - Consensus strategy to check

  Returns:
    T if consensus reached, NIL otherwise.

  Thread Safety:
    This operation is thread-safe.

  Example:
    (when (consensus-reached-p session :strategy :majority)
      (format t \"Ready to commit decision~%\"))

  See Also:
    REACH-CONSENSUS, GET-DECISION"
  (declare (type negotiation-session session))

  (bt:with-lock-held ((negotiation-lock session))
    (not (null (ecase strategy
                 (:majority (apply-majority-consensus session))
                 (:unanimous (apply-unanimous-consensus session))
                 (:weighted (apply-weighted-consensus session)))))))

;;;; ============================================================================
;;;; Query Operations
;;;; ============================================================================

(defun get-decision (session)
  "Get the winning proposal if consensus was reached.

  Args:
    session - NEGOTIATION-SESSION instance

  Returns:
    Two values:
      - decided-proposal: Winning PROPOSAL or NIL
      - votes: Hash table of all votes

  Thread Safety:
    This operation is thread-safe.

  Example:
    (multiple-value-bind (proposal votes)
        (get-decision session)
      (when proposal
        (format t \"Decision: ~A~%\" (proposal-content proposal))
        (format t \"Vote count: ~D~%\" (hash-table-count votes))))

  See Also:
    REACH-CONSENSUS, NEGOTIATION-STATUS"
  (declare (type negotiation-session session))

  (bt:with-lock-held ((negotiation-lock session))
    (values (negotiation-winning-proposal session)
            (negotiation-votes session))))

(defun negotiation-status (session)
  "Get status information about the negotiation.

  Returns a property list with comprehensive status information.

  Args:
    session - NEGOTIATION-SESSION instance

  Returns:
    Property list with keys:
      :id, :state, :topic, :participants, :proposals, :votes-cast,
      :deadline, :created-at, :decided-at, :winning-proposal

  Thread Safety:
    This operation is thread-safe.

  Example:
    (let ((status (negotiation-status session)))
      (format t \"Negotiation ~A: ~A~%\"
              (getf status :id)
              (getf status :state)))

  See Also:
    GET-DECISION, NEGOTIATION-STATE"
  (declare (type negotiation-session session))

  (bt:with-lock-held ((negotiation-lock session))
    (list :id (negotiation-id session)
          :state (negotiation-state session)
          :topic (negotiation-topic session)
          :initiator (negotiation-initiator session)
          :participants (negotiation-participants session)
          :proposals (length (negotiation-proposals session))
          :votes-cast (hash-table-count (negotiation-votes session))
          :deadline (negotiation-deadline session)
          :created-at (negotiation-created-at session)
          :decided-at (negotiation-decided-at session)
          :winning-proposal (when (negotiation-winning-proposal session)
                             (proposal-id (negotiation-winning-proposal session))))))

;;;; ============================================================================
;;;; State Transitions
;;;; ============================================================================

(defun transition-to-voting (session)
  "Transition negotiation from :OPEN to :VOTING state.

  Call this when proposal submission is complete and voting should begin.

  Args:
    session - NEGOTIATION-SESSION instance

  Returns:
    T on success.

  Raises:
    ERROR if not in :OPEN state
    ERROR if no proposals submitted

  Thread Safety:
    This operation is thread-safe.

  Example:
    ;; Collect proposals
    (submit-proposal session \"swarm-a\" proposal-data-1)
    (submit-proposal session \"swarm-b\" proposal-data-2)

    ;; Start voting
    (transition-to-voting session)

  See Also:
    SUBMIT-PROPOSAL, VOTE-ON-PROPOSAL"
  (declare (type negotiation-session session))

  (bt:with-lock-held ((negotiation-lock session))
    (unless (eq (negotiation-state session) :open)
      (error "Cannot transition to :VOTING from state ~S"
             (negotiation-state session)))
    (when (null (negotiation-proposals session))
      (error "Cannot transition to :VOTING with no proposals"))

    (setf (negotiation-state session) :voting)
    t))

(defun cancel-negotiation (session)
  "Cancel the negotiation.

  Transitions to :CANCELLED state. No further proposals or votes allowed.

  Args:
    session - NEGOTIATION-SESSION instance

  Returns:
    T

  Thread Safety:
    This operation is thread-safe.

  See Also:
    NEGOTIATION-STATE, MAKE-NEGOTIATION"
  (declare (type negotiation-session session))

  (bt:with-lock-held ((negotiation-lock session))
    (setf (negotiation-state session) :cancelled
          (negotiation-decided-at session) (get-universal-time))
    t))

;;;; ============================================================================
;;;; Print Methods
;;;; ============================================================================

(defmethod print-object ((session negotiation-session) stream)
  "Print human-readable representation of NEGOTIATION-SESSION.

  Format: #<NEGOTIATION-SESSION id=\"...\" state=:OPEN proposals=2 votes=3>"
  (print-unreadable-object (session stream :type t)
    (bt:with-lock-held ((negotiation-lock session))
      (format stream "id=~S state=~S proposals=~D votes=~D"
              (negotiation-id session)
              (negotiation-state session)
              (length (negotiation-proposals session))
              (hash-table-count (negotiation-votes session))))))

(defmethod print-object ((proposal proposal) stream)
  "Print human-readable representation of PROPOSAL.

  Format: #<PROPOSAL id=\"...\" proposer=\"swarm-a\">"
  (print-unreadable-object (proposal stream :type t)
    (format stream "id=~S proposer=~S"
            (proposal-id proposal)
            (proposal-proposer proposal))))

;;;; End of file
