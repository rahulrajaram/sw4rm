;;;; echo-agent.lisp -- Basic SW4RM echo agent example
;;;;
;;;; Demonstrates the core message loop pattern using the SW4RM Common Lisp SDK:
;;;;   1. Load and configure an agent via make-agent-config / load-config-from-env
;;;;   2. Build message envelopes with Three-ID model (message_id, correlation_id, idempotency_token)
;;;;   3. Send envelopes through the router client
;;;;   4. Track envelope state transitions (SENT -> RECEIVED -> FULFILLED)
;;;;   5. Use a sequence tracker for monotonic message ordering
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed (https://www.quicklisp.org/)
;;;;   - SW4RM SDK on ASDF load path (e.g., symlink sdks/cl_sdk/ into ~/quicklisp/local-projects/)
;;;;
;;;; Run:
;;;;   sbcl --load examples/echo-agent.lisp
;;;;
;;;; Environment variables (all optional):
;;;;   AGENT_ID                  - Agent identifier (default: "echo-1")
;;;;   AGENT_NAME                - Agent display name (default: "EchoAgent")
;;;;   AGENT_DESCRIPTION         - Agent description
;;;;   SW4RM_ROUTER_ADDR         - Router service address (default: "localhost:50051")
;;;;   SW4RM_REGISTRY_ADDR       - Registry service address (default: "localhost:50052")
;;;;   SW4RM_TIMEOUT_MS          - Default operation timeout (default: 30000)
;;;;   SW4RM_RETRY_MAX_ATTEMPTS  - Retry attempts on transient failure (default: 3)

;;; ---------------------------------------------------------------------------
;;; Step 0: Load the SDK
;;; ---------------------------------------------------------------------------

(ql:quickload :sw4rm-sdk)

;;; We USE the :sw4rm-sdk package so that exported symbols are directly accessible.
;;; In library code you would typically use the package-qualified form (sw4rm-sdk:make-envelope)
;;; but for a standalone script this is more readable.

(defpackage #:echo-agent-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:echo-agent-example)

;;; ---------------------------------------------------------------------------
;;; Step 1: Configure the agent
;;; ---------------------------------------------------------------------------
;;; load-config-from-env reads AGENT_ID, AGENT_NAME, SW4RM_*_ADDR, etc. from
;;; environment variables, falling back to sensible defaults.  You can also
;;; build a config manually with make-agent-config + make-default-endpoints.

(defvar *config*
  (load-config-from-env)
  "Agent configuration loaded from environment variables.")

;; For demonstration, override the agent-id and name when env vars are absent.
;; make-agent-config is a struct constructor, so we can build one explicitly:
(defvar *echo-config*
  (make-agent-config
   :agent-id "echo-1"
   :name "EchoAgent"
   :description "Echoes incoming DATA messages back through the router."
   :version "0.5.0"
   :capabilities '("echo" "text/plain" "application/json")
   :endpoints (make-default-endpoints)   ; honours SW4RM_*_ADDR env vars
   :timeout-ms 30000
   :retry-max-attempts 3
   :heartbeat-interval-ms 30000))

(format t "~&;; Agent configured: ~A (~A)~%"
        (agent-config-agent-id *echo-config*)
        (agent-config-name *echo-config*))

(format t ";;   Router endpoint : ~A~%"
        (endpoints-router (agent-config-endpoints *echo-config*)))

(format t ";;   Registry endpoint: ~A~%"
        (endpoints-registry (agent-config-endpoints *echo-config*)))

;;; ---------------------------------------------------------------------------
;;; Step 2: Create a sequence tracker
;;; ---------------------------------------------------------------------------
;;; The sequence tracker provides monotonically increasing, thread-safe sequence
;;; numbers used to order messages within a correlation scope.

(defvar *seq* (make-sequence-tracker :start 1)
  "Thread-safe sequence number generator for this agent.")

(format t ";;   First sequence number: ~D~%" (next-sequence *seq*))  ; => 1
(format t ";;   Second sequence number: ~D~%" (next-sequence *seq*)) ; => 2

;;; ---------------------------------------------------------------------------
;;; Step 3: Build a message envelope
;;; ---------------------------------------------------------------------------
;;; make-envelope implements the Three-ID model from spec section 11.3:
;;;   - message_id:       auto-generated UUIDv4, unique per delivery attempt
;;;   - correlation_id:   stable across a workflow/session (auto-generated if nil)
;;;   - idempotency_token: stable across retries of the same logical operation
;;;
;;; The envelope is returned as a property list compatible with the
;;; sw4rm.common.Envelope protobuf message.

(defvar *correlation-id* "workflow-echo-demo-001"
  "A stable correlation ID for grouping related messages in this demo.")

;; Build an idempotency token to enable exactly-once semantics.
;; Format: {producer_id}:{operation_type}:{deterministic_hash}
(defvar *idem-hash*
  (compute-deterministic-hash
   '(:task "echo" :input "hello world" :attempt 1))
  "Deterministic hash of the operation parameters.")

(defvar *idem-token*
  (make-idempotency-token "echo-1" "echo-reply" *idem-hash*)
  "Idempotency token for deduplication.")

(format t ";;   Idempotency token: ~A~%" *idem-token*)

;; Construct the envelope.
(defvar *envelope*
  (make-envelope
   :producer-id (agent-config-agent-id *echo-config*)
   :message-type +data+                           ; DATA message (constant = 2)
   :content-type "application/json"
   :payload (map 'vector #'char-code "{\"echo\":\"hello world\"}")
   :correlation-id *correlation-id*
   :idempotency-token *idem-token*
   :sequence-number (next-sequence *seq*)          ; => 3
   :retry-count 0
   :ttl-ms 60000                                   ; 60-second TTL
   :state +sent+))                                  ; initial state

(format t "~&;; Envelope built:~%")
(format t ";;   message_id       : ~A~%" (getf *envelope* :message-id))
(format t ";;   correlation_id   : ~A~%" (getf *envelope* :correlation-id))
(format t ";;   idempotency_token: ~A~%" (getf *envelope* :idempotency-token))
(format t ";;   sequence_number  : ~D~%" (getf *envelope* :sequence-number))
(format t ";;   message_type     : ~D (+DATA+)~%" (getf *envelope* :message-type))
(format t ";;   state            : ~D (+SENT+)~%" (getf *envelope* :state))
(format t ";;   hlc_timestamp    : ~A~%" (getf *envelope* :hlc-timestamp))

;;; ---------------------------------------------------------------------------
;;; Step 4: Simulate sending via router and receiving ACK
;;; ---------------------------------------------------------------------------
;;; In production, you would create a router-client and call send-envelope.
;;; The gRPC transport layer is currently stubbed, so we demonstrate the
;;; error-handling pattern using with-sw4rm-error-handling and simulate the
;;; ACK cycle by updating envelope state manually.

(format t "~&;; Attempting to send envelope via router...~%")

;; Demonstrate the error handling macro with restarts.
;; In a real deployment the router-client would be connected to a live service.
(with-sw4rm-error-handling ()
  (handler-case
      (let ((client (make-instance 'router-client
                                   :address (endpoints-router
                                             (agent-config-endpoints *echo-config*)))))
        ;; send-envelope is a stub that signals rpc-error (UNIMPLEMENTED).
        ;; We catch it here to show the error handling pattern.
        (send-envelope client *envelope*))
    (error (e)
      (format t ";;   [expected] Router call failed: ~A~%" e)
      (format t ";;   (In production, this connects to a live gRPC router service.)~%"))))

;;; ---------------------------------------------------------------------------
;;; Step 5: Simulate ACK lifecycle -- state transitions
;;; ---------------------------------------------------------------------------
;;; Per spec section 11, an envelope moves through these states:
;;;   SENT -> RECEIVED -> READ -> FULFILLED   (happy path)
;;;   SENT -> RECEIVED -> REJECTED            (recipient rejects)
;;;   SENT -> RECEIVED -> FAILED              (processing error)
;;;   SENT -> TIMED_OUT                       (no ACK within deadline)

(format t "~&;; Simulating envelope state transitions (happy path):~%")

;; Transition: SENT -> RECEIVED
(update-envelope-state *envelope* +received-envelope+)
(format t ";;   State after RECEIVED: ~D~%" (getf *envelope* :state))

;; Transition: RECEIVED -> READ
(update-envelope-state *envelope* +read-envelope+)
(format t ";;   State after READ    : ~D~%" (getf *envelope* :state))

;; Transition: READ -> FULFILLED (terminal)
(update-envelope-state *envelope* +fulfilled-envelope+)
(format t ";;   State after FULFILLED: ~D~%" (getf *envelope* :state))

;; Check if we have reached a terminal state.
(format t ";;   Terminal state?     : ~A~%"
        (if (terminal-state-p (getf *envelope* :state)) "yes" "no"))

;;; ---------------------------------------------------------------------------
;;; Step 6: Demonstrate retry with new message_id but same idempotency_token
;;; ---------------------------------------------------------------------------
;;; On retry, a new message_id is generated (since it is unique per delivery
;;; attempt), but the correlation_id and idempotency_token remain stable so
;;; that the recipient can detect duplicates.

(format t "~&;; Building retry envelope (same idempotency_token, new message_id):~%")

(defvar *retry-envelope*
  (make-envelope
   :producer-id (agent-config-agent-id *echo-config*)
   :message-type +data+
   :content-type "application/json"
   :payload (map 'vector #'char-code "{\"echo\":\"hello world\"}")
   :correlation-id *correlation-id*              ; same correlation scope
   :idempotency-token *idem-token*               ; same token for dedup
   :sequence-number (next-sequence *seq*)         ; new sequence number
   :retry-count 1                                 ; incremented retry count
   :ttl-ms 60000
   :state +sent+))

(format t ";;   Original message_id: ~A~%" (getf *envelope* :message-id))
(format t ";;   Retry    message_id: ~A~%" (getf *retry-envelope* :message-id))
(format t ";;   Same idempotency?  : ~A~%"
        (string= (getf *envelope* :idempotency-token)
                 (getf *retry-envelope* :idempotency-token)))

;;; ---------------------------------------------------------------------------
;;; Summary
;;; ---------------------------------------------------------------------------

(format t "~&;; Echo agent example complete.~%")
(format t ";; Key takeaways:~%")
(format t ";;   - make-agent-config / load-config-from-env for configuration~%")
(format t ";;   - make-envelope for Three-ID envelope construction~%")
(format t ";;   - update-envelope-state / terminal-state-p for lifecycle tracking~%")
(format t ";;   - make-sequence-tracker / next-sequence for ordering~%")
(format t ";;   - compute-deterministic-hash / make-idempotency-token for dedup~%")
(format t ";;   - with-sw4rm-error-handling for structured error recovery~%")
