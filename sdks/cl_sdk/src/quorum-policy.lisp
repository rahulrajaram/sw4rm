;;;; quorum-policy.lisp — runtime-neutral SW4-001 quorum evaluation

(in-package #:sw4rm-sdk)

;;; Rules and outcomes are immutable value objects by convention.  Evaluation
;;; never mutates votes or policy, so callers can safely reuse them.

(defstruct (minimum-votes (:constructor make-minimum-votes (n))) n)
(defstruct (minimum-fraction (:constructor make-minimum-fraction (fraction))) fraction)
(defstruct (require-all (:constructor make-require-all (&optional (enabled t)))) enabled)

(defstruct (quorum-policy (:constructor make-quorum-policy (rule on-failure)))
  rule on-failure)

(defstruct (quorum-outcome (:constructor make-quorum-outcome
                              (met votes-received votes-expected threshold
                               &optional action all-votes)))
  met votes-received votes-expected threshold action all-votes)

(defun default-quorum-policy ()
  "Return the majority, fail-closed policy used by Python and Elixir."
  (make-quorum-policy (make-minimum-fraction 0.5d0) :fail-closed))

(defun %quorum-vote-critic-id (vote)
  (cond
    ((typep vote 'vote) (vote-agent-id vote))
    ((listp vote) (or (getf vote :critic-id) (getf vote :agent-id)))
    (t (error "Vote must be a VOTE struct or plist: ~S" vote))))

(defun %quorum-threshold (rule expected)
  (cond
    ((typep rule 'minimum-votes) (minimum-votes-n rule))
    ((typep rule 'minimum-fraction)
     (ceiling (* expected (minimum-fraction-fraction rule))))
    ((typep rule 'require-all)
     (if (require-all-enabled rule) expected 0))
    (t (error "Unknown quorum rule: ~S" rule))))

(defun %quorum-injected-votes (requested voted-ids)
  "Build zero-score abstain records for REQUESTED critics absent from VOTED-IDS."
  (loop for critic in requested
        unless (member critic voted-ids :test #'equal)
        collect (list :critic-id critic :score 0.0d0
                      :confidence 0.0d0 :passed nil :abstain t)))

(defun %quorum-action (failure requested voted-ids votes injected)
  (ecase failure
    (:fail-closed
     (list :type :escalate-hitl
           :reason "Quorum not met — escalating to HITL"))
    (:fail-with-abstain
     (list :type :decided-with-abstains
           :injected-votes injected
           :all-votes (append votes injected)))
    (:fail-with-available
     (list :type :decided-with-available :all-votes votes))))

(defun evaluate-quorum (votes requested-critics policy)
  "Evaluate VOTES against REQUESTED-CRITICS and a QUORUM-POLICY.

The result mirrors the runtime-neutral Python contract: critic IDs count once
regardless of duplication in VOTES or in REQUESTED-CRITICS, thresholds use
CEILING, and failure actions preserve the received votes for downstream
aggregation.  On the not-met path, injected abstentions join ALL-VOTES so
cross-SDK aggregation sees the same cardinality."
  (let* ((voted-ids (remove-duplicates (mapcar #'%quorum-vote-critic-id votes)
                                      :test #'equal))
         (expected (length requested-critics))
         (distinct-requested
           (remove-duplicates requested-critics :test #'equal))
         (received (count-if (lambda (critic)
                               (member critic voted-ids :test #'equal))
                             distinct-requested))
         (threshold (%quorum-threshold (quorum-policy-rule policy) expected)))
    (if (>= received threshold)
        (make-quorum-outcome t received expected threshold nil votes)
        (let* ((injected
                 (when (eq (quorum-policy-on-failure policy) :fail-with-abstain)
                   (%quorum-injected-votes requested-critics voted-ids)))
               (all-votes (append votes injected)))
          (make-quorum-outcome
           nil received expected threshold
           (%quorum-action (quorum-policy-on-failure policy)
                           requested-critics voted-ids votes injected)
           all-votes)))))
