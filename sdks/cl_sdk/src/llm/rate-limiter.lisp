;;;; rate-limiter.lisp - Token bucket rate limiter for LLM API requests
;;;;
;;;; Provides proactive rate limiting to avoid 429 errors.  All LLM clients
;;;; in the process share a global singleton bucket.
;;;;
;;;; Thread-safe via bordeaux-threads locks.
;;;;
;;;; Ported from sdks/py_sdk/sw4rm/llm/rate_limiter.py

(in-package #:sw4rm-sdk)

;;;; ====================================================================
;;;; Internal Time Helpers
;;;; ====================================================================

(defun monotonic-seconds ()
  "Return a monotonic time value in seconds as a double-float.

Uses GET-INTERNAL-REAL-TIME for portability.  The absolute value is
meaningless; only differences between calls are significant."
  (/ (coerce (get-internal-real-time) 'double-float)
     (coerce internal-time-units-per-second 'double-float)))

;;;; ====================================================================
;;;; Token Bucket Class
;;;; ====================================================================

(defclass token-bucket ()
  ((tokens
    :accessor bucket-tokens
    :type double-float
    :documentation "Current available token count.")
   (current-tpm
    :accessor bucket-current-tpm
    :type double-float
    :documentation "Current tokens-per-minute budget (may be adaptively reduced).")
   (base-tpm
    :accessor bucket-base-tpm
    :type double-float
    :documentation "Original tokens-per-minute budget (ceiling for recovery).")
   (min-tpm
    :accessor bucket-min-tpm
    :type double-float
    :documentation "Floor for adaptive reduction (25% of base).")
   (last-refill
    :accessor bucket-last-refill
    :type double-float
    :documentation "Monotonic timestamp of last refill.")
   (lock
    :accessor bucket-lock
    :documentation "Bordeaux-threads lock for thread safety.")
   (last-rate-limit-time
    :accessor bucket-last-rate-limit-time
    :initform nil
    :type (or double-float null)
    :documentation "Monotonic timestamp of last 429 event, or NIL.")
   (successes-since-limit
    :accessor bucket-successes-since-limit
    :initform 0
    :type integer
    :documentation "Successful requests since last rate limit event.")
   (enabled-p
    :accessor bucket-enabled-p
    :initform t
    :type boolean
    :documentation "Whether the rate limiter is active.")
   (adaptive-p
    :accessor bucket-adaptive-p
    :initform t
    :type boolean
    :documentation "Whether adaptive throttling is enabled.")
   (reduction-factor
    :accessor bucket-reduction-factor
    :initform 0.7d0
    :type double-float
    :documentation "Factor to multiply TPM by on a 429 event.")
   (recovery-factor
    :accessor bucket-recovery-factor
    :initform 1.1d0
    :type double-float
    :documentation "Factor to multiply TPM by during recovery.")
   (cooldown-seconds
    :accessor bucket-cooldown-seconds
    :initform 30.0d0
    :type double-float
    :documentation "Seconds to wait after a 429 before attempting recovery.")
   (successes-for-recovery
    :accessor bucket-successes-for-recovery
    :initform 20
    :type integer
    :documentation "Number of successes required before recovery kicks in.")
   (max-wait-seconds
    :accessor bucket-max-wait-seconds
    :initform 120.0d0
    :type double-float
    :documentation "Maximum seconds to wait in acquire before signaling a timeout."))
  (:documentation "Token bucket rate limiter with adaptive throttling.

Refills tokens at a steady rate proportional to current-tpm.  When a
429 is reported via RECORD-RATE-LIMIT, the budget is reduced.  After
enough successes and a cooldown period, the budget recovers towards
base-tpm.

Thread-safe: all mutations are protected by a bordeaux-threads lock."))

(defun make-rate-limiter (&key (tokens-per-minute 250000)
                               (enabled t)
                               (adaptive t)
                               (reduction-factor 0.7d0)
                               (recovery-factor 1.1d0)
                               (cooldown-seconds 30.0d0)
                               (successes-for-recovery 20)
                               (max-wait-seconds 120.0d0))
  "Create a new token-bucket rate limiter.

Args:
  tokens-per-minute:     Integer, base token budget per minute (default: 250000).
  enabled:               Boolean, whether rate limiting is active (default: T).
  adaptive:              Boolean, whether adaptive throttling is enabled (default: T).
  reduction-factor:      Double-float, TPM multiplier on 429 (default: 0.7).
  recovery-factor:       Double-float, TPM multiplier during recovery (default: 1.1).
  cooldown-seconds:      Double-float, seconds before recovery starts (default: 30.0).
  successes-for-recovery: Integer, successes needed before recovery (default: 20).
  max-wait-seconds:      Double-float, max wait in acquire (default: 120.0).

Returns:
  A token-bucket instance."
  (let* ((base (coerce tokens-per-minute 'double-float))
         (bucket (make-instance 'token-bucket)))
    (setf (bucket-base-tpm bucket) base)
    (setf (bucket-current-tpm bucket) base)
    (setf (bucket-min-tpm bucket) (max 1000.0d0 (* base 0.25d0)))
    (setf (bucket-tokens bucket) base)  ; start full
    (setf (bucket-last-refill bucket) (monotonic-seconds))
    (setf (bucket-lock bucket) (bt:make-lock "rate-limiter"))
    (setf (bucket-enabled-p bucket) enabled)
    (setf (bucket-adaptive-p bucket) adaptive)
    (setf (bucket-reduction-factor bucket) (coerce reduction-factor 'double-float))
    (setf (bucket-recovery-factor bucket) (coerce recovery-factor 'double-float))
    (setf (bucket-cooldown-seconds bucket) (coerce cooldown-seconds 'double-float))
    (setf (bucket-successes-for-recovery bucket) successes-for-recovery)
    (setf (bucket-max-wait-seconds bucket) (coerce max-wait-seconds 'double-float))
    (setf (bucket-last-rate-limit-time bucket) nil)
    (setf (bucket-successes-since-limit bucket) 0)
    bucket))

;;;; ====================================================================
;;;; Internal Refill and Recovery
;;;; ====================================================================

(defun %refill-bucket (bucket)
  "Refill tokens based on elapsed time since last refill.  Internal, not
thread-safe -- caller must hold the lock.

Args:
  bucket: A token-bucket instance."
  (let* ((now (monotonic-seconds))
         (elapsed (- now (bucket-last-refill bucket)))
         (refill (* elapsed (/ (bucket-current-tpm bucket) 60.0d0))))
    (setf (bucket-tokens bucket)
          (min (+ (bucket-tokens bucket) refill)
               (bucket-current-tpm bucket)))  ; burst allowance = 1.0
    (setf (bucket-last-refill bucket) now)
    (%maybe-recover bucket now)))

(defun %maybe-recover (bucket now)
  "Attempt adaptive recovery if cooldown and success criteria are met.
Internal, not thread-safe -- caller must hold the lock.

Args:
  bucket: A token-bucket instance.
  now:    Current monotonic time in seconds."
  (when (and (bucket-adaptive-p bucket)
             (< (bucket-current-tpm bucket) (bucket-base-tpm bucket))
             (bucket-last-rate-limit-time bucket)
             (>= (- now (bucket-last-rate-limit-time bucket))
                  (bucket-cooldown-seconds bucket))
             (>= (bucket-successes-since-limit bucket)
                  (bucket-successes-for-recovery bucket)))
    (let ((new-limit (min (bucket-base-tpm bucket)
                          (* (bucket-current-tpm bucket)
                             (bucket-recovery-factor bucket)))))
      (when (> new-limit (bucket-current-tpm bucket))
        (setf (bucket-current-tpm bucket) new-limit)
        (setf (bucket-successes-since-limit bucket) 0)))))

;;;; ====================================================================
;;;; Public API (Generic Functions)
;;;; ====================================================================

(defgeneric acquire (bucket estimated-tokens)
  (:documentation "Acquire tokens from the bucket, blocking if necessary.

Waits (via SLEEP) until enough tokens are available or the maximum
wait time is exceeded.

Args:
  bucket:           A token-bucket instance.
  estimated-tokens: Integer, estimated number of tokens needed.

Returns:
  Double-float, the number of seconds spent waiting (0.0 if immediate).

Signals:
  llm-timeout-error: If max-wait-seconds is exceeded before tokens
                     become available."))

(defmethod acquire ((bucket token-bucket) estimated-tokens)
  "Acquire ESTIMATED-TOKENS from BUCKET, blocking until available."
  (unless (bucket-enabled-p bucket)
    (return-from acquire 0.0d0))
  (let ((needed (max estimated-tokens 100))
        (wait-start (monotonic-seconds)))
    (loop
      (bt:with-lock-held ((bucket-lock bucket))
        (%refill-bucket bucket)
        (when (>= (bucket-tokens bucket) needed)
          (decf (bucket-tokens bucket) needed)
          (return-from acquire (- (monotonic-seconds) wait-start))))
      ;; Check timeout
      (let ((elapsed (- (monotonic-seconds) wait-start)))
        (when (>= elapsed (bucket-max-wait-seconds bucket))
          (error 'llm-timeout-error
                 :message (format nil "Rate limiter: waited ~,1Fs for ~D tokens"
                                  elapsed needed))))
      ;; Sleep briefly before retrying
      (sleep 0.25))))

(defgeneric record-rate-limit (bucket)
  (:documentation "Record a 429 rate-limit event, adaptively reducing the token budget.

Args:
  bucket: A token-bucket instance."))

(defmethod record-rate-limit ((bucket token-bucket))
  "Record a 429 event and reduce the token budget."
  (when (and (bucket-enabled-p bucket) (bucket-adaptive-p bucket))
    (bt:with-lock-held ((bucket-lock bucket))
      (setf (bucket-last-rate-limit-time bucket) (monotonic-seconds))
      (setf (bucket-successes-since-limit bucket) 0)
      (let ((new-limit (max (bucket-min-tpm bucket)
                            (* (bucket-current-tpm bucket)
                               (bucket-reduction-factor bucket)))))
        (when (< new-limit (bucket-current-tpm bucket))
          (setf (bucket-current-tpm bucket) new-limit)
          (setf (bucket-tokens bucket)
                (min (bucket-tokens bucket) (bucket-current-tpm bucket))))))))

(defgeneric record-success (bucket)
  (:documentation "Record a successful request for adaptive recovery tracking.

Args:
  bucket: A token-bucket instance."))

(defmethod record-success ((bucket token-bucket))
  "Record a successful request."
  (when (and (bucket-enabled-p bucket) (bucket-adaptive-p bucket))
    (bt:with-lock-held ((bucket-lock bucket))
      (incf (bucket-successes-since-limit bucket)))))

;;;; ====================================================================
;;;; Global Singleton
;;;; ====================================================================

(defvar *global-rate-limiter* nil
  "Global token-bucket rate limiter shared by all LLM clients in this process.
Use GET-GLOBAL-RATE-LIMITER to access, RESET-GLOBAL-RATE-LIMITER to clear.")

(defun get-global-rate-limiter (&key (tokens-per-minute 250000))
  "Get or create the global rate limiter singleton.

If the global limiter does not exist, creates one with the given
TOKENS-PER-MINUTE budget.  Subsequent calls return the existing
instance (ignoring the parameter).

Args:
  tokens-per-minute: Integer, base token budget for a new limiter (default: 250000).

Returns:
  A token-bucket instance."
  (unless *global-rate-limiter*
    (setf *global-rate-limiter*
          (make-rate-limiter :tokens-per-minute tokens-per-minute)))
  *global-rate-limiter*)

(defun reset-global-rate-limiter ()
  "Reset the global rate limiter to NIL (for testing).

The next call to GET-GLOBAL-RATE-LIMITER will create a fresh instance."
  (setf *global-rate-limiter* nil))
