;;;; voting.lisp
;;;; Voting aggregation strategies for multi-agent decision making

(in-package :sw4rm-sdk)

;;; Vote Structure

(defstruct vote
  "A single vote from an agent."
  (agent-id nil :type (or null string))
  (choice nil :type t)
  (confidence nil :type (or null number))
  (timestamp (get-universal-time) :type integer)
  (metadata nil :type list))

;;; Aggregation Strategy Protocol

(defgeneric aggregate (strategy votes)
  (:documentation "Aggregate votes using the given strategy.

   Args:
     strategy: Aggregation strategy instance
     votes: List of vote structs

   Returns:
     Aggregation result (format depends on strategy)"))

(defgeneric strategy-name (strategy)
  (:documentation "Get the name of the aggregation strategy.

   Args:
     strategy: Aggregation strategy instance

   Returns:
     String name"))

;;; Majority Vote Strategy

(defclass majority-vote-strategy ()
  ()
  (:documentation "Simple majority voting: most common choice wins.
                   Returns the choice with the most votes."))

(defmethod strategy-name ((strategy majority-vote-strategy))
  "majority-vote")

(defmethod aggregate ((strategy majority-vote-strategy) votes)
  "Aggregate votes by simple majority.

   Args:
     strategy: Majority vote strategy instance
     votes: List of vote structs

   Returns:
     Plist with:
       :winner - The winning choice
       :count - Number of votes for winner
       :total - Total number of votes
       :distribution - Hash table of choice -> count"
  (when (null votes)
    (return-from aggregate (list :winner nil :count 0 :total 0 :distribution (make-hash-table :test 'equal))))

  (let ((counts (make-hash-table :test 'equal))
        (total (length votes)))

    ;; Count votes for each choice
    (dolist (vote votes)
      (let ((choice (vote-choice vote)))
        (incf (gethash choice counts 0))))

    ;; Find winner
    (let ((winner nil)
          (max-count 0))
      (maphash (lambda (choice count)
                 (when (> count max-count)
                   (setf winner choice)
                   (setf max-count count)))
               counts)

      (list :winner winner
            :count max-count
            :total total
            :distribution counts))))

;;; Simple Average Strategy

(defclass simple-average-strategy ()
  ()
  (:documentation "Average numeric choices.
                   Assumes all choices are numbers."))

(defmethod strategy-name ((strategy simple-average-strategy))
  "simple-average")

(defmethod aggregate ((strategy simple-average-strategy) votes)
  "Aggregate votes by computing average of numeric choices.

   Args:
     strategy: Simple average strategy instance
     votes: List of vote structs with numeric choices

   Returns:
     Plist with:
       :average - Mean of all choices
       :count - Number of votes
       :min - Minimum choice
       :max - Maximum choice
       :stddev - Standard deviation"
  (when (null votes)
    (return-from aggregate (list :average nil :count 0 :min nil :max nil :stddev nil)))

  (let* ((choices (mapcar #'vote-choice votes))
         (count (length choices))
         (sum (reduce #'+ choices))
         (average (/ sum count))
         (min-val (reduce #'min choices))
         (max-val (reduce #'max choices))
         (variance (/ (reduce #'+ (mapcar (lambda (x) (expt (- x average) 2)) choices))
                     count))
         (stddev (sqrt variance)))

    (list :average average
          :count count
          :min min-val
          :max max-val
          :stddev stddev)))

;;; Borda Count Strategy

(defclass borda-count-strategy ()
  ()
  (:documentation "Borda count voting: choices are ranked preferences.
                   Each choice in a vote should be a list of preferences in order.
                   Points awarded: (n-1) for 1st place, (n-2) for 2nd, etc."))

(defmethod strategy-name ((strategy borda-count-strategy))
  "borda-count")

(defmethod aggregate ((strategy borda-count-strategy) votes)
  "Aggregate votes using Borda count method.

   Args:
     strategy: Borda count strategy instance
     votes: List of vote structs with choice being list of ranked preferences

   Returns:
     Plist with:
       :winner - Choice with highest score
       :scores - Hash table of choice -> score
       :total-votes - Number of votes"
  (when (null votes)
    (return-from aggregate (list :winner nil :scores (make-hash-table :test 'equal) :total-votes 0)))

  (let ((scores (make-hash-table :test 'equal))
        (total-votes (length votes)))

    ;; Calculate scores
    (dolist (vote votes)
      (let* ((preferences (vote-choice vote))
             (n (length preferences)))
        (loop for choice in preferences
              for rank from 0
              for points = (- n rank 1)
              do (incf (gethash choice scores 0) points))))

    ;; Find winner
    (let ((winner nil)
          (max-score 0))
      (maphash (lambda (choice score)
                 (when (> score max-score)
                   (setf winner choice)
                   (setf max-score score)))
               scores)

      (list :winner winner
            :scores scores
            :total-votes total-votes))))

;;; Confidence-Weighted Strategy

(defclass confidence-weighted-strategy ()
  ()
  (:documentation "Weighted voting where each vote is weighted by confidence.
                   Confidence values should be in [0, 1]."))

(defmethod strategy-name ((strategy confidence-weighted-strategy))
  "confidence-weighted")

(defmethod aggregate ((strategy confidence-weighted-strategy) votes)
  "Aggregate votes weighted by confidence.

   Args:
     strategy: Confidence-weighted strategy instance
     votes: List of vote structs with confidence values

   Returns:
     Plist with:
       :winner - Choice with highest weighted score
       :weighted-scores - Hash table of choice -> weighted score
       :total-weight - Sum of all confidence weights
       :total-votes - Number of votes"
  (when (null votes)
    (return-from aggregate (list :winner nil
                                :weighted-scores (make-hash-table :test 'equal)
                                :total-weight 0.0
                                :total-votes 0)))

  (let ((weighted-scores (make-hash-table :test 'equal))
        (total-weight 0.0)
        (total-votes (length votes)))

    ;; Calculate weighted scores
    (dolist (vote votes)
      (let ((choice (vote-choice vote))
            (confidence (or (vote-confidence vote) 1.0)))
        (incf (gethash choice weighted-scores 0.0) confidence)
        (incf total-weight confidence)))

    ;; Find winner
    (let ((winner nil)
          (max-score 0.0))
      (maphash (lambda (choice score)
                 (when (> score max-score)
                   (setf winner choice)
                   (setf max-score score)))
               weighted-scores)

      (list :winner winner
            :weighted-scores weighted-scores
            :total-weight total-weight
            :total-votes total-votes))))

;;; Voting Aggregator Class

(defstruct voting-round
  "Record of a single voting round."
  (round-id nil :type (or null string))
  (timestamp (get-universal-time) :type integer)
  (strategy-name nil :type (or null string))
  (votes nil :type list)
  (result nil :type list))

(defclass voting-aggregator ()
  ((strategy
    :initarg :strategy
    :accessor aggregation-strategy
    :type t
    :initform (make-instance 'majority-vote-strategy)
    :documentation "Current aggregation strategy.")

   (history
    :initarg :history
    :accessor voting-history
    :type list
    :initform nil
    :documentation "History of voting rounds, newest first.")

   (max-history
    :initarg :max-history
    :accessor max-history
    :type (integer 0 *)
    :initform 100
    :documentation "Maximum number of rounds to keep in history.")

   (lock
    :accessor aggregator-lock
    :initform (bt:make-lock "voting-aggregator-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "Voting aggregator that applies strategies to vote collections.
                   Maintains history of voting rounds for audit purposes."))

(defmethod set-strategy ((agg voting-aggregator) strategy)
  "Set the aggregation strategy.

   Args:
     agg: Voting aggregator instance
     strategy: New strategy instance"
  (setf (aggregation-strategy agg) strategy))

(defmethod run-vote ((agg voting-aggregator) votes &key round-id)
  "Run a voting round with the current strategy.

   Args:
     agg: Voting aggregator instance
     votes: List of vote structs
     round-id: Optional identifier for this round

   Returns:
     Aggregation result from the strategy"
  (bt:with-lock-held ((aggregator-lock agg))
    (let* ((strategy (aggregation-strategy agg))
           (result (aggregate strategy votes))
           (round (make-voting-round
                   :round-id round-id
                   :timestamp (get-universal-time)
                   :strategy-name (strategy-name strategy)
                   :votes votes
                   :result result)))

      ;; Add to history
      (push round (voting-history agg))

      ;; Trim history if needed
      (when (> (length (voting-history agg)) (max-history agg))
        (setf (voting-history agg)
              (subseq (voting-history agg) 0 (max-history agg))))

      result)))

(defmethod get-round-history ((agg voting-aggregator) &key (limit nil))
  "Get voting round history.

   Args:
     agg: Voting aggregator instance
     limit: Optional maximum number of rounds to return (newest first)

   Returns:
     List of voting-round structs"
  (if limit
      (subseq (voting-history agg) 0 (min limit (length (voting-history agg))))
      (voting-history agg)))

(defmethod clear-history ((agg voting-aggregator))
  "Clear all voting history.

   Args:
     agg: Voting aggregator instance"
  (bt:with-lock-held ((aggregator-lock agg))
    (setf (voting-history agg) nil)))

;;; Utility Functions

(defun make-vote-from-plist (plist)
  "Create a vote struct from a property list.

   Args:
     plist: Property list with :agent-id, :choice, :confidence, etc.

   Returns:
     vote struct"
  (make-vote
   :agent-id (getf plist :agent-id)
   :choice (getf plist :choice)
   :confidence (getf plist :confidence)
   :timestamp (or (getf plist :timestamp) (get-universal-time))
   :metadata (getf plist :metadata)))

(defun vote-to-plist (vote)
  "Convert a vote struct to a property list.

   Args:
     vote: vote struct

   Returns:
     Property list"
  (list :agent-id (vote-agent-id vote)
        :choice (vote-choice vote)
        :confidence (vote-confidence vote)
        :timestamp (vote-timestamp vote)
        :metadata (vote-metadata vote)))
