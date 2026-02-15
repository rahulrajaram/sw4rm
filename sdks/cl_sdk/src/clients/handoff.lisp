;;;; handoff.lisp - Handoff Service client for SW4RM
;;
;;;; Local in-memory SW4-004/SW4-005-compatible handoff behavior.

(in-package :sw4rm-sdk)

(defconstant +default-max-retries-on-overloaded+ 2
  "Default SW4-004 retry count for OVERLOADED.")

(defconstant +default-initial-backoff-ms+ 250
  "Default SW4-004 initial retry backoff in milliseconds.")

(defconstant +default-backoff-multiplier+ 2.0d0
  "Default SW4-004 retry backoff multiplier.")

(defconstant +default-max-backoff-ms+ 2000
  "Default SW4-004 max retry backoff in milliseconds.")

(defconstant +default-allow-spillover-routing+ nil
  "Default SW4-005 spillover routing policy.")

(defconstant +default-max-redirects+ 0
  "Default SW4-005 max redirect hops.")

(defconstant +retry-after-jitter-ratio+ 0.2d0
  "Jitter ratio used with retry-after hints for overloaded retries.")

(defconstant +default-effective-max-redirects+ 2
  "Effective default redirect follow bound when max-redirects is unset/zero.")

(defconstant +min-cancel-grace-period-ms+ 5000
  "Minimum cancellation grace period in milliseconds (SW4-004 §5).")

(defclass handoff-client (base-client)
  ((handoffs
    :initform (make-hash-table :test 'equal)
    :accessor handoff-client-handoffs
    :documentation "Map: handoff-id -> (:request plist :response plist).")
   (pending-by-agent
    :initform (make-hash-table :test 'equal)
    :accessor handoff-client-pending-by-agent
    :documentation "Map: to-agent -> list of pending handoff IDs.")
   (child-delegations
    :initform (make-hash-table :test 'equal)
    :accessor handoff-client-child-delegations
    :documentation "Map: parent-correlation-id -> list of child correlation IDs.")
   (cancellation-flags
    :initform (make-hash-table :test 'equal)
    :accessor handoff-client-cancellation-flags
    :documentation "Map: correlation-id -> cancellation flag plist."))
  (:documentation "In-memory handoff client with SW4-004/SW4-005 extensions."))

(defun %required-string (plist key)
  "Read KEY from PLIST and require a non-empty string value."
  (let ((value (getf plist key)))
    (unless (and (stringp value) (> (length value) 0))
      (error 'validation-error
             :message (format nil "~A is required and must be a non-empty string" key)
             :field (string-downcase (symbol-name key))
             :constraint "non-empty string"))
    value))

(defun %now-ms ()
  "Current wall time in milliseconds."
  (current-time-ms))

(defun %copy-plist (plist)
  "Return a shallow copy of PLIST."
  (copy-list plist))

(defun %normalize-positive-integer (value fallback)
  "Return VALUE when it is a positive integer, otherwise FALLBACK."
  (if (and (integerp value) (> value 0))
      value
      fallback))

(defun %normalize-positive-number (value fallback)
  "Return VALUE when it is a positive real, otherwise FALLBACK."
  (if (and (realp value) (> value 0))
      value
      fallback))

(defun handoff-default-delegation-policy ()
  "Build default SW4-004/SW4-005 delegation policy plist."
  (list :max-retries-on-overloaded +default-max-retries-on-overloaded+
        :initial-backoff-ms +default-initial-backoff-ms+
        :backoff-multiplier +default-backoff-multiplier+
        :max-backoff-ms +default-max-backoff-ms+
        :allow-spillover-routing +default-allow-spillover-routing+
        :max-redirects +default-max-redirects+))

(defun %normalize-delegation-policy (policy)
  "Normalize optional delegation policy values with protocol defaults."
  (let ((defaults (handoff-default-delegation-policy)))
    (list :max-retries-on-overloaded
          (if (and (integerp (getf policy :max-retries-on-overloaded))
                   (>= (getf policy :max-retries-on-overloaded) 0))
              (getf policy :max-retries-on-overloaded)
              (getf defaults :max-retries-on-overloaded))
          :initial-backoff-ms
          (%normalize-positive-integer
           (getf policy :initial-backoff-ms)
           (getf defaults :initial-backoff-ms))
          :backoff-multiplier
          (%normalize-positive-number
           (getf policy :backoff-multiplier)
           (getf defaults :backoff-multiplier))
          :max-backoff-ms
          (%normalize-positive-integer
           (getf policy :max-backoff-ms)
           (getf defaults :max-backoff-ms))
          :allow-spillover-routing
          (if (null (getf policy :allow-spillover-routing))
              (getf defaults :allow-spillover-routing)
              (not (null (getf policy :allow-spillover-routing))))
          :max-redirects
          (if (and (integerp (getf policy :max-redirects))
                   (>= (getf policy :max-redirects) 0))
              (getf policy :max-redirects)
              (getf defaults :max-redirects)))))

(defun %default-sleep-seconds (seconds)
  "Sleep for SECONDS."
  (sleep seconds))

(defun %default-rand-uniform (low high)
  "Sample uniformly in [LOW, HIGH), clamped when HIGH <= LOW."
  (let ((low-float (coerce low 'double-float))
        (high-float (coerce high 'double-float)))
    (if (<= high-float low-float)
        low-float
        (+ low-float (* (random 1.0d0) (- high-float low-float))))))

(defun %deadline-exhausted-response (request-id)
  "Build an ACK_TIMEOUT handoff response for exhausted delegation budget."
  (list :request-id request-id
        :handoff-id request-id
        :accepted nil
        :status :rejected
        :rejection-reason "Delegation deadline exhausted before handoff acceptance"
        :rejection-code +ack-timeout+
        :retry-after-ms nil
        :redirect-to-agent-id nil))

(defun %invalid-redirect-response (request-id reason)
  "Build a validation-error handoff response for invalid redirect metadata."
  (list :request-id request-id
        :handoff-id request-id
        :accepted nil
        :status :rejected
        :rejection-reason reason
        :rejection-code +validation-error+
        :retry-after-ms nil
        :redirect-to-agent-id nil))

(defun %effective-max-redirects (policy)
  "Return configured max redirects, or effective default when not positive."
  (let ((configured (getf policy :max-redirects)))
    (if (and (integerp configured) (> configured 0))
        configured
        +default-effective-max-redirects+)))

(defun %budget-exhausted-p (budget now-ms)
  "Return T when BUDGET cannot fund additional handoff attempts."
  (let ((wall-time (getf budget :wall-time-remaining-ms))
        (deadline (getf budget :deadline-epoch-ms)))
    (or (and (integerp wall-time) (<= wall-time 0))
        (> now-ms deadline))))

(defun %consume-wall-time (budget elapsed-ms)
  "Deduct ELAPSED-MS from BUDGET wall-time in place when present."
  (let ((remaining (getf budget :wall-time-remaining-ms)))
    (when (integerp remaining)
      (setf (getf budget :wall-time-remaining-ms)
            (max 0 (- remaining (max elapsed-ms 0)))))))

(defun %next-retry-wait-ms (response retry-index policy rand-uniform-fn)
  "Compute overloaded retry wait with retry-after+jitter or exponential backoff."
  (let ((retry-after-ms (getf response :retry-after-ms)))
    (if (and (integerp retry-after-ms) (> retry-after-ms 0))
        (let* ((retry-after (coerce retry-after-ms 'double-float))
               (jitter (funcall rand-uniform-fn
                                0.0d0
                                (* retry-after +retry-after-jitter-ratio+))))
          (max 0 (floor (+ retry-after (max jitter 0.0d0)))))
        (let* ((initial-backoff-ms
                 (coerce (getf policy :initial-backoff-ms) 'double-float))
               (backoff-multiplier
                 (coerce (getf policy :backoff-multiplier) 'double-float))
               (max-backoff-ms
                 (coerce (getf policy :max-backoff-ms) 'double-float))
               (exponential (* initial-backoff-ms (expt backoff-multiplier retry-index)))
               (bounded (max 0.0d0 (min exponential max-backoff-ms))))
          (max 0 (floor (max 0.0d0 (funcall rand-uniform-fn 0.0d0 bounded))))))))

(defun delegate-to-swarm
    (send-handoff-fn
     &key
       from-agent
       to-agent
       reason
       budget
       delegation-policy
       request-id
       (context-snapshot "")
       (capabilities-required '())
       (priority 0)
       timeout-ms
       now-ms-fn
       sleep-seconds-fn
       rand-uniform-fn)
  "Execute caller-side SW4-005 delegation redirect/retry semantics.

SEND-HANDOFF-FN receives a normalized handoff request plist and must return a
handoff response plist."
  (%required-string (list :value from-agent) :value)
  (%required-string (list :value to-agent) :value)
  (%required-string (list :value reason) :value)
  (unless (listp budget)
    (error 'validation-error
           :message "budget plist is required for cross-swarm delegation"
           :field "budget"
           :constraint "plist"))
  (let ((deadline (getf budget :deadline-epoch-ms)))
    (unless (and (integerp deadline) (> deadline 0))
      (error 'validation-error
             :message "budget.deadline-epoch-ms is required for cross-swarm delegation"
             :field "budget.deadline-epoch-ms"
             :constraint "positive integer")))
  (when (and timeout-ms (or (not (integerp timeout-ms)) (< timeout-ms 0)))
    (error 'validation-error
           :message "timeout-ms must be >= 0"
           :field "timeout-ms"
           :constraint "non-negative integer"))

  (let* ((now-fn (or now-ms-fn #'%now-ms))
         (sleep-fn (or sleep-seconds-fn #'%default-sleep-seconds))
         (rand-fn (or rand-uniform-fn #'%default-rand-uniform))
         (policy (%normalize-delegation-policy delegation-policy))
         (request-budget (%copy-plist budget))
         (request-id-value (or request-id (generate-uuid)))
         (request (list :request-id request-id-value
                        :handoff-id request-id-value
                        :from-agent from-agent
                        :to-agent to-agent
                        :reason reason
                        :context-snapshot context-snapshot
                        :capabilities-required (copy-list capabilities-required)
                        :priority priority
                        :budget request-budget
                        :delegation-policy policy))
         (max-retries-on-overloaded (getf policy :max-retries-on-overloaded))
         (redirect-bound (%effective-max-redirects policy))
         (visited-agents (list to-agent))
         (retry-index 0)
         (redirect-hops 0))
    (when timeout-ms
      (setf (getf request :timeout-ms) timeout-ms))
    (loop
      for start-ms = (funcall now-fn)
      do
         (when (%budget-exhausted-p request-budget start-ms)
           (return (%deadline-exhausted-response request-id-value)))
         (let* ((response (funcall send-handoff-fn (%copy-plist request)))
                (end-ms (funcall now-fn))
                (elapsed-ms (max (- end-ms start-ms) 0)))
           (%consume-wall-time request-budget elapsed-ms)

           (when (getf response :accepted)
             (return response))
           (when (%budget-exhausted-p request-budget end-ms)
             (return (%deadline-exhausted-response request-id-value)))

           (let ((rejection-code (getf response :rejection-code)))
             (if (eql rejection-code +overloaded+)
                 (progn
                   (when (>= retry-index max-retries-on-overloaded)
                     (return response))
                   (let ((wait-ms (%next-retry-wait-ms
                                   response retry-index policy rand-fn)))
                     (incf retry-index)
                     (let ((remaining-deadline-ms
                             (- (getf request-budget :deadline-epoch-ms) end-ms))
                           (remaining-wall-time-ms
                             (getf request-budget :wall-time-remaining-ms)))
                       (when (or (<= wait-ms 0)
                                 (and (integerp remaining-wall-time-ms)
                                      (> wait-ms remaining-wall-time-ms))
                                 (> wait-ms remaining-deadline-ms))
                         (return response)))
                     (let ((before-sleep-ms (funcall now-fn)))
                       (funcall sleep-fn (/ wait-ms 1000.0d0))
                       (let ((after-sleep-ms (funcall now-fn)))
                         (%consume-wall-time request-budget
                                             (max (- after-sleep-ms before-sleep-ms) 0))))))
                 (if (not (eql rejection-code +redirect+))
                     (return response)
                     (if (not (getf policy :allow-spillover-routing))
                         (return response)
                         (let* ((raw-target (getf response :redirect-to-agent-id))
                                (target-agent
                                  (and (stringp raw-target)
                                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                                    raw-target))))
                           (when (or (null target-agent)
                                     (= (length target-agent) 0))
                             (return (%invalid-redirect-response
                                      request-id-value
                                      "Redirect response missing non-empty redirect_to_agent_id")))
                           (when (member target-agent visited-agents :test #'string=)
                             (return (%invalid-redirect-response
                                      request-id-value
                                      (format nil
                                              "Redirect loop detected for agent '~A'"
                                              target-agent))))
                           (when (>= redirect-hops redirect-bound)
                             (return response))
                           (setf (getf request :to-agent) target-agent)
                           (push target-agent visited-agents)
                           (incf redirect-hops))))))))))

(defun %normalize-handoff-request (request)
  "Validate and normalize a handoff REQUEST plist.

Returns two values: normalized-request and handoff-id."
  (%required-string request :from-agent)
  (%required-string request :to-agent)
  (%required-string request :reason)

  (let* ((normalized (%copy-plist request))
         (budget (getf normalized :budget))
         (policy (getf normalized :delegation-policy))
         (handoff-id (or (getf normalized :request-id)
                         (getf normalized :handoff-id)
                         (generate-uuid))))
    (when budget
      (let ((deadline (getf budget :deadline-epoch-ms)))
        (unless (and (integerp deadline) (> deadline 0))
          (error 'validation-error
                 :message "budget.deadline-epoch-ms is required for cross-swarm delegation"
                 :field "budget.deadline-epoch-ms"
                 :constraint "positive integer"))))

    (when (or budget policy)
      (setf (getf normalized :delegation-policy)
            (%normalize-delegation-policy policy)))

    (unless (getf normalized :created-at)
      (setf (getf normalized :created-at) (%now-ms)))

    (setf (getf normalized :request-id) handoff-id)
    (setf (getf normalized :handoff-id) handoff-id)

    (values normalized handoff-id)))

(defun %get-handoff-entry-or-signal (client handoff-id)
  "Fetch a handoff entry or signal RPC-ERROR if it does not exist."
  (or (gethash handoff-id (handoff-client-handoffs client))
      (error 'rpc-error
             :message (format nil "Handoff ~A not found" handoff-id)
             :status-code "NOT_FOUND"
             :details "handoff id does not exist")))

(defun %remove-pending-id (client agent-id handoff-id)
  "Remove HANDOFF-ID from AGENT-ID pending list."
  (let* ((pending-map (handoff-client-pending-by-agent client))
         (pending (gethash agent-id pending-map)))
    (when pending
      (setf (gethash agent-id pending-map)
            (remove handoff-id pending :test #'string=)))))

(defun %ensure-pending-status (response handoff-id)
  "Require RESPONSE status to be :PENDING for response mutation methods."
  (unless (eq (getf response :status) :pending)
    (error 'rpc-error
           :message (format nil "Handoff ~A is not in PENDING status" handoff-id)
           :status-code "FAILED_PRECONDITION"
           :details (format nil "current status: ~A" (getf response :status)))))

(defgeneric initiate-handoff (client request)
  (:documentation "Create a handoff request in local in-memory storage."))

(defmethod initiate-handoff ((client handoff-client) request)
  (ensure-connected client)
  (multiple-value-bind (normalized-request handoff-id)
      (%normalize-handoff-request request)
    (let ((handoffs (handoff-client-handoffs client))
          (pending-map (handoff-client-pending-by-agent client)))
      (when (gethash handoff-id handoffs)
        (error 'validation-error
               :message (format nil "Handoff request with ID '~A' already exists" handoff-id)
               :field "request-id"
               :constraint "must be unique"))

      (let ((response (list :accepted t
                            :handoff-id handoff-id
                            :request-id handoff-id
                            :status :pending
                            :accepting-agent nil
                            :rejection-reason nil
                            :rejection-code nil
                            :retry-after-ms nil
                            :redirect-to-agent-id nil
                            :metadata (list :created-at (%now-ms)))))
        (setf (gethash handoff-id handoffs)
              (list :request normalized-request
                    :response response))

        (let ((to-agent (getf normalized-request :to-agent)))
          (setf (gethash to-agent pending-map)
                (append (gethash to-agent pending-map) (list handoff-id))))

        (%copy-plist response)))))

(defgeneric accept-handoff (client handoff-id)
  (:documentation "Accept a pending handoff request."))

(defmethod accept-handoff ((client handoff-client) handoff-id)
  (ensure-connected client)
  (let* ((entry (%get-handoff-entry-or-signal client handoff-id))
         (request (getf entry :request))
         (response (getf entry :response))
         (to-agent (getf request :to-agent)))
    (%ensure-pending-status response handoff-id)
    (setf (getf response :accepted) t)
    (setf (getf response :status) :accepted)
    (setf (getf response :accepting-agent) to-agent)
    (setf (getf response :metadata)
          (append (getf response :metadata)
                  (list :accepted-at (%now-ms))))
    (%remove-pending-id client to-agent handoff-id)
    (%copy-plist response)))

(defgeneric reject-handoff (client handoff-id reason)
  (:documentation "Reject a pending handoff request with default metadata."))

(defgeneric reject-handoff-with-options
    (client handoff-id reason &key rejection-code retry-after-ms redirect-to-agent-id)
  (:documentation "Reject a pending handoff request with SW4-004/SW4-005 metadata."))

(defmethod reject-handoff ((client handoff-client) handoff-id reason)
  (reject-handoff-with-options client handoff-id reason))

(defmethod reject-handoff-with-options
    ((client handoff-client) handoff-id reason
     &key
       (rejection-code +error-code-unspecified+)
       retry-after-ms
       redirect-to-agent-id)
  (ensure-connected client)
  (let* ((entry (%get-handoff-entry-or-signal client handoff-id))
         (request (getf entry :request))
         (response (getf entry :response))
         (to-agent (getf request :to-agent)))
    (%ensure-pending-status response handoff-id)
    (setf (getf response :accepted) nil)
    (setf (getf response :status) :rejected)
    (setf (getf response :rejection-reason) reason)
    (setf (getf response :rejection-code) rejection-code)
    (setf (getf response :retry-after-ms)
          (and (integerp retry-after-ms) (> retry-after-ms 0) retry-after-ms))
    (setf (getf response :redirect-to-agent-id)
          (and (stringp redirect-to-agent-id)
               (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return)
                                           redirect-to-agent-id)))
                 (and (> (length trimmed) 0) trimmed))))
    (setf (getf response :metadata)
          (append (getf response :metadata)
                  (list :rejected-at (%now-ms))))
    (%remove-pending-id client to-agent handoff-id)
    (%copy-plist response)))

(defgeneric complete-handoff (client handoff-id)
  (:documentation "Mark an accepted handoff as completed."))

(defmethod complete-handoff ((client handoff-client) handoff-id)
  (ensure-connected client)
  (let* ((entry (%get-handoff-entry-or-signal client handoff-id))
         (response (getf entry :response)))
    (unless (eq (getf response :status) :accepted)
      (error 'rpc-error
             :message (format nil "Handoff ~A is not in ACCEPTED status" handoff-id)
             :status-code "FAILED_PRECONDITION"
             :details (format nil "current status: ~A" (getf response :status))))

    (setf (getf response :status) :completed)
    (setf (getf response :metadata)
          (append (getf response :metadata)
                  (list :completed-at (%now-ms))))
    (%copy-plist response)))

(defgeneric get-pending-handoffs (client agent-id)
  (:documentation "Return pending handoff requests for AGENT-ID."))

(defmethod get-pending-handoffs ((client handoff-client) agent-id)
  (ensure-connected client)
  (let* ((pending-ids (copy-list (gethash agent-id (handoff-client-pending-by-agent client))))
         (handoffs (handoff-client-handoffs client))
         (results '()))
    (dolist (handoff-id pending-ids (nreverse results))
      (let ((entry (gethash handoff-id handoffs)))
        (when (and entry
                   (eq (getf (getf entry :response) :status) :pending))
          (push (%copy-plist (getf entry :request)) results))))))

(defgeneric get-handoff-status (client handoff-id)
  (:documentation "Return handoff response plist for HANDOFF-ID, or NIL."))

(defmethod get-handoff-status ((client handoff-client) handoff-id)
  (ensure-connected client)
  (let ((entry (gethash handoff-id (handoff-client-handoffs client))))
    (when entry
      (%copy-plist (getf entry :response)))))

(defgeneric register-child-delegation (client parent-correlation-id child-correlation-id)
  (:documentation "Link parent/child delegation IDs for cancellation cascade."))

(defmethod register-child-delegation
    ((client handoff-client) parent-correlation-id child-correlation-id)
  (ensure-connected client)
  (%required-string (list :value parent-correlation-id) :value)
  (%required-string (list :value child-correlation-id) :value)
  (let* ((child-map (handoff-client-child-delegations client))
         (children (gethash parent-correlation-id child-map)))
    (unless (member child-correlation-id children :test #'string=)
      (setf (gethash parent-correlation-id child-map)
            (append children (list child-correlation-id)))))
  t)

(defgeneric cancel-delegation (client cancel-request)
  (:documentation "Set cancellation flags for a correlation and known children."))

(defmethod cancel-delegation ((client handoff-client) cancel-request)
  (ensure-connected client)
  (let* ((correlation-id (%required-string cancel-request :correlation-id))
         (requested-grace (or (getf cancel-request :grace-period-ms) 0))
         (grace-period-ms (max +min-cancel-grace-period-ms+
                               (if (and (integerp requested-grace)
                                        (> requested-grace 0))
                                   requested-grace
                                   0)))
         (reason (or (getf cancel-request :reason) ""))
         (cancel-time-ms (%now-ms))
         (flags (handoff-client-cancellation-flags client))
         (children (gethash correlation-id (handoff-client-child-delegations client)))
         (flag (list :cancelled t
                     :reason reason
                     :grace-period-ms grace-period-ms
                     :cancel-time-ms cancel-time-ms)))
    (setf (gethash correlation-id flags) (%copy-plist flag))
    (dolist (child-correlation-id children)
      (setf (gethash child-correlation-id flags) (%copy-plist flag)))
    (list :acknowledged t
          :correlation-id correlation-id
          :grace-period-ms grace-period-ms
          :message "Cancellation recorded")))

(defgeneric cancelled-delegation-p (client correlation-id)
  (:documentation "Return T when CORRELATION-ID has an active cancellation flag."))

(defmethod cancelled-delegation-p ((client handoff-client) correlation-id)
  (ensure-connected client)
  (let ((entry (gethash correlation-id (handoff-client-cancellation-flags client))))
    (and entry (not (null (getf entry :cancelled))))))

(defgeneric cancellation-grace-expired-p (client correlation-id &optional now-ms)
  (:documentation "Return T when cancellation grace period has elapsed."))

(defmethod cancellation-grace-expired-p
    ((client handoff-client) correlation-id &optional now-ms)
  (ensure-connected client)
  (let ((entry (gethash correlation-id (handoff-client-cancellation-flags client))))
    (if (and entry (getf entry :cancelled))
        (>= (- (or now-ms (%now-ms))
               (getf entry :cancel-time-ms))
            (getf entry :grace-period-ms))
        nil)))

(defgeneric forced-preemption-error-code (client correlation-id &optional now-ms)
  (:documentation "Return FORCED_PREEMPTION once cancellation grace expires."))

(defmethod forced-preemption-error-code
    ((client handoff-client) correlation-id &optional now-ms)
  (if (cancellation-grace-expired-p client correlation-id now-ms)
      +forced-preemption+
      +error-code-unspecified+))

(defgeneric collect-forced-preemptions (client correlation-ids &optional now-ms)
  (:documentation "Collect correlation IDs that have exceeded cancellation grace."))

(defmethod collect-forced-preemptions
    ((client handoff-client) correlation-ids &optional now-ms)
  (ensure-connected client)
  (let ((forced '())
        (check-now (or now-ms (%now-ms))))
    (dolist (correlation-id correlation-ids (nreverse forced))
      (when (cancellation-grace-expired-p client correlation-id check-now)
        (push correlation-id forced)))))
