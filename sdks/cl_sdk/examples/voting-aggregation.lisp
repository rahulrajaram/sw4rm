;;;; voting-aggregation.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Voting Aggregation Strategies
;;;;
;;;; Purpose: Demonstrate different voting aggregation strategies for
;;;; combining critic votes in negotiation room scenarios.
;;;;
;;;; This example covers:
;;;;   - Simple average strategy
;;;;   - Confidence-weighted strategy (POMDP-inspired)
;;;;   - Majority vote strategy
;;;;   - Borda count strategy
;;;;   - Vote analysis (entropy, consensus, polarization)
;;;;   - Comprehensive vote summary
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/voting-aggregation.lisp")
;;;;   (voting-aggregation:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :voting-aggregation
  (:use :cl :sw4rm-orchestrator)
  (:export #:run-demo
           #:create-example-votes
           #:demonstrate-strategies
           #:demonstrate-polarization
           #:demonstrate-analysis
           #:*votes*
           #:*aggregator*))

(in-package :voting-aggregation)

;;; ==========================================================================
;;; Data Structures
;;; ==========================================================================

(defstruct negotiation-vote
  "A vote from a critic in a negotiation room.

Slots:
  artifact-id - ID of the artifact being evaluated
  critic-id - ID of the critic casting the vote
  score - Numerical score (0-10)
  confidence - Confidence in the evaluation (0-1)
  passed - Whether the artifact meets minimum criteria
  strengths - List of identified strengths
  weaknesses - List of identified weaknesses
  recommendations - List of suggestions for improvement
  negotiation-room-id - ID of the negotiation room"
  (artifact-id "" :type string)
  (critic-id "" :type string)
  (score 0.0 :type float)
  (confidence 0.0 :type float)
  (passed nil :type boolean)
  (strengths nil :type list)
  (weaknesses nil :type list)
  (recommendations nil :type list)
  (negotiation-room-id "" :type string))

(defstruct aggregated-score
  "Result of aggregating multiple votes.

Slots:
  mean - Simple arithmetic mean
  weighted-mean - Confidence-weighted mean
  min-score - Minimum score received
  max-score - Maximum score received
  std-dev - Standard deviation of scores
  vote-count - Number of votes aggregated"
  (mean 0.0 :type float)
  (weighted-mean 0.0 :type float)
  (min-score 0.0 :type float)
  (max-score 0.0 :type float)
  (std-dev 0.0 :type float)
  (vote-count 0 :type integer))

;;; ==========================================================================
;;; Global State
;;; ==========================================================================

(defparameter *votes* nil
  "List of negotiation-vote structures for demonstration.")

(defparameter *aggregator* nil
  "Current voting aggregator.")

;;; ==========================================================================
;;; Aggregation Strategy Protocol
;;; ==========================================================================

;; We use CLOS generic functions for the strategy pattern

(defgeneric aggregate-votes (strategy votes)
  (:documentation "Aggregate votes using the given strategy.

Args:
  strategy - An aggregation strategy object
  votes - List of negotiation-vote structures

Returns:
  aggregated-score structure"))

(defgeneric strategy-name (strategy)
  (:documentation "Return the name of the strategy."))

;;; ==========================================================================
;;; Strategy 1: Simple Average
;;; ==========================================================================

(defclass simple-average-strategy ()
  ()
  (:documentation "Aggregation strategy that treats all votes equally."))

(defmethod strategy-name ((strategy simple-average-strategy))
  "Simple Average")

(defmethod aggregate-votes ((strategy simple-average-strategy) votes)
  "Aggregate votes using simple arithmetic mean."
  (when (null votes)
    (return-from aggregate-votes
      (make-aggregated-score)))

  (let* ((scores (mapcar #'negotiation-vote-score votes))
         (n (length scores))
         (sum (reduce #'+ scores))
         (mean (/ sum n))
         (min-s (reduce #'min scores))
         (max-s (reduce #'max scores))
         (variance (/ (reduce #'+ (mapcar (lambda (s) (expt (- s mean) 2)) scores))
                      n))
         (std-dev (sqrt variance)))

    (make-aggregated-score
     :mean (float mean)
     :weighted-mean (float mean)
     :min-score (float min-s)
     :max-score (float max-s)
     :std-dev (float std-dev)
     :vote-count n)))

;;; ==========================================================================
;;; Strategy 2: Confidence-Weighted
;;; ==========================================================================

(defclass confidence-weighted-strategy ()
  ()
  (:documentation "Aggregation strategy that weights votes by critic confidence.
This is inspired by POMDP belief state updates."))

(defmethod strategy-name ((strategy confidence-weighted-strategy))
  "Confidence-Weighted")

(defmethod aggregate-votes ((strategy confidence-weighted-strategy) votes)
  "Aggregate votes weighted by confidence."
  (when (null votes)
    (return-from aggregate-votes
      (make-aggregated-score)))

  (let* ((scores (mapcar #'negotiation-vote-score votes))
         (confidences (mapcar #'negotiation-vote-confidence votes))
         (n (length scores))
         (sum (reduce #'+ scores))
         (mean (/ sum n))
         ;; Weighted mean
         (weight-sum (reduce #'+ confidences))
         (weighted-sum (reduce #'+ (mapcar #'* scores confidences)))
         (weighted-mean (if (zerop weight-sum) mean (/ weighted-sum weight-sum)))
         ;; Stats
         (min-s (reduce #'min scores))
         (max-s (reduce #'max scores))
         (variance (/ (reduce #'+ (mapcar (lambda (s) (expt (- s mean) 2)) scores))
                      n))
         (std-dev (sqrt variance)))

    (make-aggregated-score
     :mean (float mean)
     :weighted-mean (float weighted-mean)
     :min-score (float min-s)
     :max-score (float max-s)
     :std-dev (float std-dev)
     :vote-count n)))

;;; ==========================================================================
;;; Strategy 3: Majority Vote
;;; ==========================================================================

(defclass majority-vote-strategy ()
  ()
  (:documentation "Aggregation strategy based on pass/fail count.
Ignores numerical scores, focuses on pass/fail threshold."))

(defmethod strategy-name ((strategy majority-vote-strategy))
  "Majority Vote")

(defmethod aggregate-votes ((strategy majority-vote-strategy) votes)
  "Aggregate votes using majority pass/fail."
  (when (null votes)
    (return-from aggregate-votes
      (make-aggregated-score)))

  (let* ((scores (mapcar #'negotiation-vote-score votes))
         (passed-votes (remove-if-not #'negotiation-vote-passed votes))
         (n (length scores))
         (sum (reduce #'+ scores))
         (mean (/ sum n))
         ;; Majority determines outcome: 10 if majority passed, 0 otherwise
         (majority-passed-p (> (length passed-votes) (/ n 2)))
         (majority-score (if majority-passed-p 10.0 0.0))
         (min-s (reduce #'min scores))
         (max-s (reduce #'max scores))
         (variance (/ (reduce #'+ (mapcar (lambda (s) (expt (- s mean) 2)) scores))
                      n))
         (std-dev (sqrt variance)))

    (make-aggregated-score
     :mean (float mean)
     :weighted-mean majority-score
     :min-score (float min-s)
     :max-score (float max-s)
     :std-dev (float std-dev)
     :vote-count n)))

;;; ==========================================================================
;;; Strategy 4: Borda Count
;;; ==========================================================================

(defclass borda-count-strategy ()
  ()
  (:documentation "Aggregation strategy using ranked voting with position-based points.
Higher scores get more points based on their rank position."))

(defmethod strategy-name ((strategy borda-count-strategy))
  "Borda Count")

(defmethod aggregate-votes ((strategy borda-count-strategy) votes)
  "Aggregate votes using Borda count method."
  (when (null votes)
    (return-from aggregate-votes
      (make-aggregated-score)))

  (let* ((scores (mapcar #'negotiation-vote-score votes))
         (n (length scores))
         (sum (reduce #'+ scores))
         (mean (/ sum n))
         ;; Sort votes by score (descending) and assign Borda points
         (sorted-votes (sort (copy-list votes) #'>
                             :key #'negotiation-vote-score))
         (borda-points (loop for i from (1- n) downto 0 collect i))
         ;; Total Borda score normalized to 0-10 scale
         (max-borda-points (reduce #'+ borda-points))
         (borda-sum (reduce #'+ borda-points :end (ceiling n 2)))
         (borda-score (if (zerop max-borda-points)
                          mean
                          (* 10.0 (/ borda-sum max-borda-points))))
         (min-s (reduce #'min scores))
         (max-s (reduce #'max scores))
         (variance (/ (reduce #'+ (mapcar (lambda (s) (expt (- s mean) 2)) scores))
                      n))
         (std-dev (sqrt variance)))

    (make-aggregated-score
     :mean (float mean)
     :weighted-mean (float borda-score)
     :min-score (float min-s)
     :max-score (float max-s)
     :std-dev (float std-dev)
     :vote-count n)))

;;; ==========================================================================
;;; Vote Analysis Functions
;;; ==========================================================================

(defun compute-entropy (votes)
  "Compute Shannon entropy of vote distribution.

Low entropy = high agreement
High entropy = high disagreement

Args:
  votes - List of negotiation-vote structures

Returns:
  Entropy value in bits"
  (when (null votes)
    (return-from compute-entropy 0.0))

  (let* ((scores (mapcar #'negotiation-vote-score votes))
         (n (length scores))
         ;; Bucket scores into bins (0-2, 2-4, 4-6, 6-8, 8-10)
         (bins (make-hash-table))
         (num-bins 5))

    ;; Count scores in each bin
    (dolist (score scores)
      (let ((bin (min (floor score 2) (1- num-bins))))
        (incf (gethash bin bins 0))))

    ;; Calculate entropy
    (let ((entropy 0.0))
      (maphash (lambda (bin count)
                 (declare (ignore bin))
                 (let ((p (/ count n)))
                   (when (> p 0)
                     (decf entropy (* p (log p 2))))))
               bins)
      (float entropy))))

(defun detect-consensus (votes &key (threshold 1.5))
  "Detect if votes show consensus.

Consensus is detected when:
  - Standard deviation is below threshold
  - All votes are either pass or fail (high agreement)

Args:
  votes - List of negotiation-vote structures
  threshold - Maximum std-dev for consensus

Returns:
  T if consensus detected, NIL otherwise"
  (when (null votes)
    (return-from detect-consensus nil))

  (let* ((scores (mapcar #'negotiation-vote-score votes))
         (passed-count (count-if #'negotiation-vote-passed votes))
         (n (length scores))
         (mean (/ (reduce #'+ scores) n))
         (variance (/ (reduce #'+ (mapcar (lambda (s) (expt (- s mean) 2)) scores))
                      n))
         (std-dev (sqrt variance))
         ;; Check if pass/fail is unanimous or near-unanimous
         (pass-rate (/ passed-count n)))

    (and (< std-dev threshold)
         (or (>= pass-rate 0.9) (<= pass-rate 0.1)))))

(defun detect-polarization (votes &key (gap-threshold 4.0))
  "Detect if votes are polarized (bimodal distribution).

Polarization is detected when there's a significant gap between
high and low scorers.

Args:
  votes - List of negotiation-vote structures
  gap-threshold - Minimum gap between high/low groups

Returns:
  T if polarization detected, NIL otherwise"
  (when (or (null votes) (< (length votes) 2))
    (return-from detect-polarization nil))

  (let* ((scores (sort (mapcar #'negotiation-vote-score votes) #'<))
         (n (length scores))
         (median-idx (floor n 2))
         (low-scores (subseq scores 0 median-idx))
         (high-scores (subseq scores median-idx))
         (low-mean (if low-scores (/ (reduce #'+ low-scores) (length low-scores)) 0))
         (high-mean (if high-scores (/ (reduce #'+ high-scores) (length high-scores)) 0))
         (gap (- high-mean low-mean)))

    (> gap gap-threshold)))

(defun compute-confidence-variance (votes)
  "Compute variance in critic confidence levels.

High variance indicates critics have very different confidence levels.

Args:
  votes - List of negotiation-vote structures

Returns:
  Variance value"
  (when (null votes)
    (return-from compute-confidence-variance 0.0))

  (let* ((confidences (mapcar #'negotiation-vote-confidence votes))
         (n (length confidences))
         (mean (/ (reduce #'+ confidences) n))
         (variance (/ (reduce #'+ (mapcar (lambda (c) (expt (- c mean) 2)) confidences))
                      n)))
    (float variance)))

(defun get-vote-summary (votes)
  "Get comprehensive summary of votes.

Args:
  votes - List of negotiation-vote structures

Returns:
  Plist with summary statistics"
  (when (null votes)
    (return-from get-vote-summary nil))

  (let* ((passed-count (count-if #'negotiation-vote-passed votes))
         (n (length votes))
         (pass-rate (/ passed-count n)))

    (list :pass-rate (float pass-rate)
          :entropy (compute-entropy votes)
          :consensus (detect-consensus votes)
          :polarization (detect-polarization votes)
          :confidence-variance (compute-confidence-variance votes))))

;;; ==========================================================================
;;; Vote Creation Helpers
;;; ==========================================================================

(defun create-example-votes ()
  "Create a realistic set of votes for demonstration."
  (list
   (make-negotiation-vote
    :artifact-id "artifact_123"
    :critic-id "security_critic"
    :score 8.5
    :confidence 0.9
    :passed t
    :strengths '("Strong authentication" "Good input validation")
    :weaknesses '("Missing rate limiting")
    :recommendations '("Add rate limiting to API endpoints")
    :negotiation-room-id "room_001")

   (make-negotiation-vote
    :artifact-id "artifact_123"
    :critic-id "performance_critic"
    :score 7.0
    :confidence 0.75
    :passed t
    :strengths '("Efficient database queries")
    :weaknesses '("No caching strategy")
    :recommendations '("Consider adding Redis cache")
    :negotiation-room-id "room_001")

   (make-negotiation-vote
    :artifact-id "artifact_123"
    :critic-id "code_quality_critic"
    :score 6.5
    :confidence 0.8
    :passed t
    :strengths '("Clean code structure" "Good documentation")
    :weaknesses '("Some functions are too long")
    :recommendations '("Refactor large functions into smaller ones")
    :negotiation-room-id "room_001")

   (make-negotiation-vote
    :artifact-id "artifact_123"
    :critic-id "testing_critic"
    :score 9.0
    :confidence 0.95
    :passed t
    :strengths '("Excellent test coverage" "Good edge case handling")
    :weaknesses nil
    :recommendations '("Add more integration tests")
    :negotiation-room-id "room_001")))

(defun create-polarized-votes ()
  "Create a polarized set of votes for demonstration."
  (list
   (make-negotiation-vote
    :artifact-id "artifact_456"
    :critic-id "critic_1"
    :score 9.0
    :confidence 0.85
    :passed t
    :strengths '("Excellent")
    :weaknesses nil
    :recommendations nil
    :negotiation-room-id "room_002")

   (make-negotiation-vote
    :artifact-id "artifact_456"
    :critic-id "critic_2"
    :score 8.5
    :confidence 0.90
    :passed t
    :strengths '("Very good")
    :weaknesses nil
    :recommendations nil
    :negotiation-room-id "room_002")

   (make-negotiation-vote
    :artifact-id "artifact_456"
    :critic-id "critic_3"
    :score 2.0
    :confidence 0.80
    :passed nil
    :strengths nil
    :weaknesses '("Major issues")
    :recommendations '("Complete rewrite")
    :negotiation-room-id "room_002")

   (make-negotiation-vote
    :artifact-id "artifact_456"
    :critic-id "critic_4"
    :score 1.5
    :confidence 0.75
    :passed nil
    :strengths nil
    :weaknesses '("Critical flaws")
    :recommendations '("Start over")
    :negotiation-room-id "room_002")))

;;; ==========================================================================
;;; Demonstrations
;;; ==========================================================================

(defun demonstrate-strategies ()
  "Demonstrate different aggregation strategies."

  (setf *votes* (create-example-votes))

  (format t "~&==============================================~%")
  (format t "Voting Aggregation Strategies Demonstration~%")
  (format t "==============================================~%~%")

  (format t "Number of votes: ~D~%" (length *votes*))
  (format t "~%Individual votes:~%")
  (dolist (vote *votes*)
    (format t "  ~25A: score=~4,1F, confidence=~4,2F, passed=~A~%"
            (negotiation-vote-critic-id vote)
            (negotiation-vote-score vote)
            (negotiation-vote-confidence vote)
            (negotiation-vote-passed vote)))

  (format t "~%==============================================~%")
  (format t "Strategy Comparison~%")
  (format t "==============================================~%~%")

  ;; 1. Simple Average
  (format t "1. Simple Average Strategy:~%")
  (format t "   Treats all votes equally~%")
  (let* ((strategy (make-instance 'simple-average-strategy))
         (result (aggregate-votes strategy *votes*)))
    (format t "   Mean score: ~4,2F~%" (aggregated-score-mean result))
    (format t "   Weighted mean: ~4,2F~%" (aggregated-score-weighted-mean result))
    (format t "   Std deviation: ~4,2F~%~%" (aggregated-score-std-dev result)))

  ;; 2. Confidence Weighted
  (format t "2. Confidence-Weighted Strategy:~%")
  (format t "   Weights votes by critic confidence (POMDP-based)~%")
  (let* ((strategy (make-instance 'confidence-weighted-strategy))
         (result (aggregate-votes strategy *votes*)))
    (format t "   Mean score: ~4,2F~%" (aggregated-score-mean result))
    (format t "   Weighted mean: ~4,2F~%" (aggregated-score-weighted-mean result))
    (format t "   -> Testing critic (0.95 conf, 9.0 score) has more influence~%~%"))

  ;; 3. Majority Vote
  (format t "3. Majority Vote Strategy:~%")
  (format t "   Based on pass/fail count (ignores numerical scores)~%")
  (let* ((strategy (make-instance 'majority-vote-strategy))
         (result (aggregate-votes strategy *votes*)))
    (format t "   Mean score: ~4,2F~%" (aggregated-score-mean result))
    (format t "   Majority outcome: ~4,2F~%" (aggregated-score-weighted-mean result))
    (format t "   -> All critics passed, so score is 10.0~%~%"))

  ;; 4. Borda Count
  (format t "4. Borda Count Strategy:~%")
  (format t "   Ranked voting with position-based points~%")
  (let* ((strategy (make-instance 'borda-count-strategy))
         (result (aggregate-votes strategy *votes*)))
    (format t "   Mean score: ~4,2F~%" (aggregated-score-mean result))
    (format t "   Borda score: ~4,2F~%" (aggregated-score-weighted-mean result))
    (format t "   -> Ranks: testing(9.0)->security(8.5)->performance(7.0)->quality(6.5)~%")))

(defun demonstrate-analysis ()
  "Demonstrate vote analysis functions."

  (format t "~%==============================================~%")
  (format t "Vote Analysis~%")
  (format t "==============================================~%~%")

  (format t "Entropy: ~4,3F bits~%" (compute-entropy *votes*))
  (format t "  (Low entropy = high agreement, High entropy = high disagreement)~%~%")

  (format t "Consensus detected: ~A~%" (detect-consensus *votes*))
  (format t "  (Low std dev + high pass/fail agreement)~%~%")

  (format t "Polarization detected: ~A~%" (detect-polarization *votes*))
  (format t "  (Bimodal distribution with votes at extremes)~%~%")

  (format t "Confidence variance: ~6,4F~%" (compute-confidence-variance *votes*))
  (format t "  (How much critics' confidence levels vary)~%~%")

  ;; Comprehensive summary
  (format t "==============================================~%")
  (format t "Comprehensive Summary~%")
  (format t "==============================================~%~%")

  (let ((summary (get-vote-summary *votes*)))
    (format t "Pass rate: ~4,1F%~%" (* 100 (getf summary :pass-rate)))
    (format t "Entropy: ~4,3F bits~%" (getf summary :entropy))
    (format t "Consensus: ~A~%" (if (getf summary :consensus) "Yes" "No"))
    (format t "Polarization: ~A~%" (if (getf summary :polarization) "Yes" "No"))
    (format t "Confidence variance: ~6,4F~%" (getf summary :confidence-variance))))

(defun demonstrate-polarization ()
  "Demonstrate polarization detection with a polarized vote set."

  (format t "~%==============================================~%")
  (format t "Polarization Example~%")
  (format t "==============================================~%~%")

  (let ((polarized-votes (create-polarized-votes)))
    (format t "Polarized votes (critics strongly disagree):~%")
    (dolist (vote polarized-votes)
      (format t "  ~A: score=~4,1F, passed=~A~%"
              (negotiation-vote-critic-id vote)
              (negotiation-vote-score vote)
              (negotiation-vote-passed vote)))

    (let* ((strategy (make-instance 'confidence-weighted-strategy))
           (result (aggregate-votes strategy polarized-votes)))
      (format t "~%Simple mean: ~4,2F~%" (aggregated-score-mean result))
      (format t "Std deviation: ~4,2F (high variance)~%" (aggregated-score-std-dev result))
      (format t "Entropy: ~4,3F bits~%" (compute-entropy polarized-votes))
      (format t "Consensus: ~A~%" (detect-consensus polarized-votes))
      (format t "Polarization: ~A <- Detected!~%~%" (detect-polarization polarized-votes))

      (format t "-> This indicates the artifact needs human review (HITL escalation)~%"))))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete voting aggregation demonstration."

  (format t "~&==============================================~%")
  (format t "   Voting Aggregation Strategies~%")
  (format t "==============================================~%~%")

  ;; Strategy comparison
  (demonstrate-strategies)

  ;; Analysis functions
  (demonstrate-analysis)

  ;; Polarization example
  (demonstrate-polarization)

  (format t "~%==============================================~%")
  (format t "   Demo Complete~%")
  (format t "==============================================~%~%")

  (format t "For REPL exploration:~%")
  (format t "  (in-package :voting-aggregation)~%")
  (format t "  (setf *votes* (create-example-votes))~%")
  (format t "  (aggregate-votes (make-instance 'confidence-weighted-strategy) *votes*)~%")
  (format t "  (get-vote-summary *votes*)~%"))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (voting_example.py pattern):

    from sw4rm.negotiation_types import NegotiationVote
    from sw4rm.voting import (
        BordaCountAggregator,
        ConfidenceWeightedAggregator,
        MajorityVoteAggregator,
        SimpleAverageAggregator,
        VotingAggregator,
    )

    def create_example_votes() -> list[NegotiationVote]:
        return [
            NegotiationVote(
                artifact_id="artifact_123",
                critic_id="security_critic",
                score=8.5,
                confidence=0.9,
                passed=True,
                strengths=["Strong authentication", "Good input validation"],
                weaknesses=["Missing rate limiting"],
                recommendations=["Add rate limiting to API endpoints"],
                negotiation_room_id="room_001",
            ),
            # ... more votes
        ]

    def demonstrate_strategies():
        votes = create_example_votes()

        # 1. Simple Average
        simple_agg = VotingAggregator(SimpleAverageAggregator())
        simple_result = simple_agg.aggregate(votes)

        # 2. Confidence Weighted
        conf_agg = VotingAggregator(ConfidenceWeightedAggregator())
        conf_result = conf_agg.aggregate(votes)

        # 3. Majority Vote
        majority_agg = VotingAggregator(MajorityVoteAggregator())
        majority_result = majority_agg.aggregate(votes)

        # 4. Borda Count
        borda_agg = VotingAggregator(BordaCountAggregator())
        borda_result = borda_agg.aggregate(votes)

        # Analysis
        entropy = conf_agg.compute_entropy(votes)
        consensus = conf_agg.detect_consensus(votes)
        polarization = conf_agg.detect_polarization(votes)

CL Advantages Demonstrated:
1. CLOS generic functions provide clean strategy pattern
2. Method dispatch handles strategy selection automatically
3. Structures give efficient vote representation
4. Multiple inheritance could combine strategy behaviors
5. Conditions/restarts for handling edge cases (empty votes, etc.)
|#

;;;; End of voting-aggregation.lisp
