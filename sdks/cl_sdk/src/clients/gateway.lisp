;;;; gateway.lisp - Gateway redirect-emitter helpers for SW4-005
;;;;
;;;; Provides local gateway-side redirect emission and health-aware peer
;;;; selection semantics for spillover routing parity.

(in-package :sw4rm-sdk)

(defconstant +registration-type-standard-agent+ 1
  "Registry registration type for standard non-gateway agents.")

(defconstant +registration-type-swarm-gateway+ 2
  "Registry registration type for SWARM_GATEWAY agents.")

(defconstant +default-peer-liveness-threshold-ms+ 30000
  "Default staleness bound for gateway peer heartbeats.")

(defparameter +non-serving-agent-states+
  (list +initializing+ +agent-failed+ +shutting-down+)
  "Agent states that cannot receive spillover traffic.")

(defstruct gateway-peer-descriptor
  "Gateway peer metadata used for redirect eligibility checks."
  (agent-id ""
   :type string)
  (registration-type +registration-type-swarm-gateway+
   :type integer)
  (capabilities '()
   :type list))

(defstruct peer-runtime-state
  "Mutable health state tracked for each known peer."
  (state +running+
   :type integer)
  (last-heartbeat-ms 0
   :type integer)
  (cooldown-until-ms 0
   :type integer))

(defclass peer-selector ()
  ((local-agent-id
    :initarg :local-agent-id
    :accessor peer-selector-local-agent-id)
   (local-capabilities
    :initarg :local-capabilities
    :accessor peer-selector-local-capabilities)
   (now-ms-fn
    :initarg :now-ms-fn
    :accessor peer-selector-now-ms-fn)
   (peer-health-fn
    :initarg :peer-health-fn
    :accessor peer-selector-peer-health-fn)
   (liveness-threshold-ms
    :initarg :liveness-threshold-ms
    :accessor peer-selector-liveness-threshold-ms)
   (peers
    :initform '()
    :accessor peer-selector-peers)
   (runtime
    :initform (make-hash-table :test 'equal)
    :accessor peer-selector-runtime)
   (rr-cursor
    :initform 0
    :accessor peer-selector-rr-cursor))
  (:documentation "Health-aware spillover redirect peer selector."))

(defclass gateway-redirect-emitter ()
  ((agent-id
    :initarg :agent-id
    :accessor gateway-redirect-emitter-agent-id)
   (capabilities
    :initarg :capabilities
    :initform '()
    :accessor gateway-redirect-emitter-capabilities)
   (retry-after-ms
    :initarg :retry-after-ms
    :initform 1000
    :accessor gateway-redirect-emitter-retry-after-ms)
   (peer-descriptors
    :initarg :peer-descriptors
    :initform '()
    :accessor gateway-redirect-emitter-peer-descriptors)
   (peer-health-fn
    :initarg :peer-health-fn
    :initform nil
    :accessor gateway-redirect-emitter-peer-health-fn)
   (now-ms-fn
    :initarg :now-ms-fn
    :initform nil
    :accessor gateway-redirect-emitter-now-ms-fn)
   (peer-liveness-threshold-ms
    :initarg :peer-liveness-threshold-ms
    :initform +default-peer-liveness-threshold-ms+
    :accessor gateway-redirect-emitter-peer-liveness-threshold-ms)
   (peer-selector
    :initform nil
    :accessor gateway-redirect-emitter-peer-selector))
  (:documentation "SW4-005 gateway helper for redirect emission + peer health filtering."))

(defun %default-now-ms ()
  "Current wall clock in milliseconds."
  (current-time-ms))

(defun %normalize-non-negative-integer (value fallback)
  "Normalize VALUE to a non-negative integer or return FALLBACK."
  (if (and (integerp value) (>= value 0))
      value
      fallback))

(defun %require-non-empty-string (value field-name)
  "Require VALUE to be a non-empty string for FIELD-NAME."
  (unless (and (stringp value) (> (length value) 0))
    (error 'validation-error
           :message (format nil "~A must be a non-empty string" field-name)
           :field field-name
           :constraint "non-empty string"))
  value)

(defun %normalize-capabilities (capabilities)
  "Normalize CAPABILITIES into a unique string list."
  (remove-duplicates
   (loop for capability in capabilities
         when (and (stringp capability) (> (length capability) 0))
         collect capability)
   :test #'string=))

(defun %same-capabilities-p (peer-capabilities local-capabilities)
  "Return T when PEER-CAPABILITIES and LOCAL-CAPABILITIES match as sets."
  (let* ((peer (%normalize-capabilities peer-capabilities))
         (local (%normalize-capabilities local-capabilities)))
    (and (= (length peer) (length local))
         (every (lambda (capability)
                  (member capability peer :test #'string=))
                local))))

(defun %coerce-peer-descriptor (peer)
  "Coerce PEER into a gateway-peer-descriptor."
  (cond
    ((typep peer 'gateway-peer-descriptor)
     (let ((normalized (%normalize-capabilities
                        (gateway-peer-descriptor-capabilities peer))))
       (setf (gateway-peer-descriptor-capabilities peer) normalized)
       (%require-non-empty-string
        (gateway-peer-descriptor-agent-id peer)
        "peer.agent-id")
       peer))
    ((listp peer)
     (let ((agent-id (%require-non-empty-string
                      (or (getf peer :agent-id) "")
                      "peer.agent-id")))
       (make-gateway-peer-descriptor
        :agent-id agent-id
        :registration-type (%normalize-non-negative-integer
                            (getf peer :registration-type)
                            +registration-type-swarm-gateway+)
        :capabilities (%normalize-capabilities (getf peer :capabilities)))))
    (t
     (error 'validation-error
            :message "peer descriptor must be a plist or gateway-peer-descriptor"
            :field "peer"
            :constraint "supported type"))))

(defun %make-peer-selector (&key
                              local-agent-id
                              (local-capabilities '())
                              now-ms-fn
                              peer-health-fn
                              (liveness-threshold-ms +default-peer-liveness-threshold-ms+))
  "Create a peer-selector with normalized options."
  (%require-non-empty-string local-agent-id "local-agent-id")
  (unless (and (integerp liveness-threshold-ms) (>= liveness-threshold-ms 0))
    (error 'validation-error
           :message "peer-liveness-threshold-ms must be >= 0"
           :field "peer-liveness-threshold-ms"
           :constraint "non-negative integer"))
  (make-instance 'peer-selector
                 :local-agent-id local-agent-id
                 :local-capabilities (%normalize-capabilities local-capabilities)
                 :now-ms-fn (or now-ms-fn #'%default-now-ms)
                 :peer-health-fn (or peer-health-fn (lambda (_peer) (declare (ignore _peer)) t))
                 :liveness-threshold-ms liveness-threshold-ms))

(defun %ensure-peer-runtime (selector agent-id)
  "Ensure runtime state exists for AGENT-ID in SELECTOR."
  (let* ((runtime-table (peer-selector-runtime selector))
         (existing (gethash agent-id runtime-table)))
    (or existing
        (let ((created (make-peer-runtime-state
                        :last-heartbeat-ms (funcall (peer-selector-now-ms-fn selector)))))
          (setf (gethash agent-id runtime-table) created)
          created))))

(defun %peer-selector-set-peers (selector peers)
  "Replace tracked peers on SELECTOR."
  (let* ((normalized-peers (mapcar #'%coerce-peer-descriptor peers))
         (runtime-table (peer-selector-runtime selector))
         (active-ids (mapcar #'gateway-peer-descriptor-agent-id normalized-peers))
         (now-ms (funcall (peer-selector-now-ms-fn selector))))
    (setf (peer-selector-peers selector) normalized-peers)
    (maphash
     (lambda (agent-id _state)
       (declare (ignore _state))
       (unless (member agent-id active-ids :test #'string=)
         (remhash agent-id runtime-table)))
     runtime-table)
    (dolist (peer normalized-peers)
      (unless (gethash (gateway-peer-descriptor-agent-id peer) runtime-table)
        (setf (gethash (gateway-peer-descriptor-agent-id peer) runtime-table)
              (make-peer-runtime-state :last-heartbeat-ms now-ms)))))
  selector)

(defun %peer-selector-update-peer-runtime-state
    (selector
     agent-id
     state
     state-supplied-p
     last-heartbeat-ms
     last-heartbeat-supplied-p
     cooldown-until-ms
     cooldown-until-supplied-p)
  "Update runtime health fields for AGENT-ID in SELECTOR."
  (%require-non-empty-string agent-id "agent-id")
  (let ((runtime (%ensure-peer-runtime selector agent-id)))
    (when state-supplied-p
      (setf (peer-runtime-state-state runtime)
            (%normalize-non-negative-integer state +running+)))
    (when last-heartbeat-supplied-p
      (setf (peer-runtime-state-last-heartbeat-ms runtime)
            (%normalize-non-negative-integer last-heartbeat-ms 0)))
    (when cooldown-until-supplied-p
      (setf (peer-runtime-state-cooldown-until-ms runtime)
            (%normalize-non-negative-integer cooldown-until-ms 0))))
  selector)

(defun %peer-selector-touch-peer-heartbeat (selector agent-id state state-supplied-p now-ms)
  "Record a heartbeat update for AGENT-ID."
  (%peer-selector-update-peer-runtime-state
   selector
   agent-id
   state
   state-supplied-p
   (or now-ms (funcall (peer-selector-now-ms-fn selector)))
   t
   nil
   nil)
  selector)

(defun %peer-selector-record-peer-overloaded
    (selector agent-id retry-after-ms retry-after-supplied-p local-cooldown-ms local-cooldown-supplied-p)
  "Apply cooldown tracking for AGENT-ID after overload."
  (%require-non-empty-string agent-id "agent-id")
  (let* ((runtime (%ensure-peer-runtime selector agent-id))
         (now-ms (funcall (peer-selector-now-ms-fn selector)))
         (retry-after (if retry-after-supplied-p
                          (%normalize-non-negative-integer retry-after-ms 0)
                          0))
         (local-cooldown (if local-cooldown-supplied-p
                             (%normalize-non-negative-integer local-cooldown-ms 0)
                             0))
         (cooldown-ms (max retry-after local-cooldown)))
    (setf (peer-runtime-state-cooldown-until-ms runtime)
          (max (peer-runtime-state-cooldown-until-ms runtime)
               (+ now-ms cooldown-ms))))
  selector)

(defun %peer-selector-eligible-p (selector peer)
  "Return T when PEER is redirect-eligible for SELECTOR."
  (and (= (gateway-peer-descriptor-registration-type peer)
          +registration-type-swarm-gateway+)
       (not (string= (gateway-peer-descriptor-agent-id peer)
                     (peer-selector-local-agent-id selector)))
       (%same-capabilities-p (gateway-peer-descriptor-capabilities peer)
                             (peer-selector-local-capabilities selector))))

(defun %peer-selector-healthy-p (selector peer)
  "Return T when PEER passes eligibility + health filters for SELECTOR."
  (when (and (%peer-selector-eligible-p selector peer)
             (funcall (peer-selector-peer-health-fn selector) peer))
    (let* ((runtime (gethash (gateway-peer-descriptor-agent-id peer)
                             (peer-selector-runtime selector)))
           (now-ms (funcall (peer-selector-now-ms-fn selector))))
      (when runtime
        (let ((age-ms (max 0 (- now-ms (peer-runtime-state-last-heartbeat-ms runtime)))))
          (and (<= (peer-runtime-state-cooldown-until-ms runtime) now-ms)
               (<= age-ms (peer-selector-liveness-threshold-ms selector))
               (not (member (peer-runtime-state-state runtime)
                            +non-serving-agent-states+
                            :test #'=))))))))

(defun %peer-selector-select-peer (selector)
  "Select a healthy redirect target from SELECTOR using round-robin."
  (let ((healthy
          (remove-if-not
           (lambda (peer) (%peer-selector-healthy-p selector peer))
           (peer-selector-peers selector))))
    (when healthy
      (let* ((idx (mod (peer-selector-rr-cursor selector) (length healthy)))
             (selected (nth idx healthy)))
        (incf (peer-selector-rr-cursor selector))
        (gateway-peer-descriptor-agent-id selected)))))

(defmethod initialize-instance :after ((emitter gateway-redirect-emitter) &key)
  "Validate constructor options and initialize internal peer selector state."
  (%require-non-empty-string
   (gateway-redirect-emitter-agent-id emitter)
   "agent-id")
  (unless (and (integerp (gateway-redirect-emitter-retry-after-ms emitter))
               (>= (gateway-redirect-emitter-retry-after-ms emitter) 0))
    (error 'validation-error
           :message "retry-after-ms must be >= 0"
           :field "retry-after-ms"
           :constraint "non-negative integer"))
  (setf (gateway-redirect-emitter-capabilities emitter)
        (%normalize-capabilities (gateway-redirect-emitter-capabilities emitter)))
  (setf (gateway-redirect-emitter-peer-selector emitter)
        (%make-peer-selector
         :local-agent-id (gateway-redirect-emitter-agent-id emitter)
         :local-capabilities (gateway-redirect-emitter-capabilities emitter)
         :now-ms-fn (gateway-redirect-emitter-now-ms-fn emitter)
         :peer-health-fn (gateway-redirect-emitter-peer-health-fn emitter)
         :liveness-threshold-ms (gateway-redirect-emitter-peer-liveness-threshold-ms emitter)))
  (%peer-selector-set-peers
   (gateway-redirect-emitter-peer-selector emitter)
   (gateway-redirect-emitter-peer-descriptors emitter)))

(defgeneric set-peer-descriptors (emitter peers)
  (:documentation "Replace peer descriptors used for redirect selection."))

(defmethod set-peer-descriptors ((emitter gateway-redirect-emitter) peers)
  (%peer-selector-set-peers (gateway-redirect-emitter-peer-selector emitter) peers)
  (setf (gateway-redirect-emitter-peer-descriptors emitter)
        (peer-selector-peers (gateway-redirect-emitter-peer-selector emitter)))
  emitter)

(defgeneric update-peer-runtime-state
    (emitter agent-id &key state last-heartbeat-ms cooldown-until-ms)
  (:documentation "Update runtime health state for a peer gateway."))

(defmethod update-peer-runtime-state
    ((emitter gateway-redirect-emitter)
     agent-id
     &key
       (state nil state-supplied-p)
       (last-heartbeat-ms nil last-heartbeat-supplied-p)
       (cooldown-until-ms nil cooldown-until-supplied-p))
  (%peer-selector-update-peer-runtime-state
   (gateway-redirect-emitter-peer-selector emitter)
   agent-id
   state
   state-supplied-p
   last-heartbeat-ms
   last-heartbeat-supplied-p
   cooldown-until-ms
   cooldown-until-supplied-p)
  emitter)

(defgeneric touch-peer-heartbeat (emitter agent-id &key state now-ms)
  (:documentation "Record a heartbeat update for a peer gateway."))

(defmethod touch-peer-heartbeat
    ((emitter gateway-redirect-emitter)
     agent-id
     &key
       (state nil state-supplied-p)
       now-ms)
  (%peer-selector-touch-peer-heartbeat
   (gateway-redirect-emitter-peer-selector emitter)
   agent-id
   state
   state-supplied-p
   now-ms)
  emitter)

(defgeneric record-peer-overloaded
    (emitter agent-id &key retry-after-ms local-cooldown-ms)
  (:documentation "Apply a temporary cooldown to a peer after overload."))

(defmethod record-peer-overloaded
    ((emitter gateway-redirect-emitter)
     agent-id
     &key
       (retry-after-ms nil retry-after-supplied-p)
       (local-cooldown-ms nil local-cooldown-supplied-p))
  (%peer-selector-record-peer-overloaded
   (gateway-redirect-emitter-peer-selector emitter)
   agent-id
   retry-after-ms
   retry-after-supplied-p
   local-cooldown-ms
   local-cooldown-supplied-p)
  emitter)

(defgeneric emit-overloaded-response (emitter request)
  (:documentation "Emit SW4-005 gateway overload/redirect response for REQUEST."))

(defmethod emit-overloaded-response ((emitter gateway-redirect-emitter) request)
  (%require-non-empty-string (or (getf request :request-id)
                                 (getf request :handoff-id)
                                 "")
                            "request-id")
  (let* ((request-id (or (getf request :request-id)
                         (getf request :handoff-id)))
         (policy (and (listp request) (getf request :delegation-policy)))
         (allow-spillover
           (and (listp policy)
                (not (null (getf policy :allow-spillover-routing)))))
         (selector (gateway-redirect-emitter-peer-selector emitter)))
    (when allow-spillover
      (let ((target-agent (%peer-selector-select-peer selector)))
        (when target-agent
          (return-from emit-overloaded-response
            (list :request-id request-id
                  :handoff-id request-id
                  :accepted nil
                  :status :rejected
                  :rejection-reason "Gateway at capacity; redirect to peer gateway"
                  :rejection-code +redirect+
                  :retry-after-ms 0
                  :redirect-to-agent-id target-agent)))))
    (list :request-id request-id
          :handoff-id request-id
          :accepted nil
          :status :rejected
          :rejection-reason "Gateway at capacity"
          :rejection-code +overloaded+
          :retry-after-ms (gateway-redirect-emitter-retry-after-ms emitter)
          :redirect-to-agent-id nil)))
