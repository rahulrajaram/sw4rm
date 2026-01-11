;;;; envelope-semantics.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Envelope Semantics Deep Dive
;;;;
;;;; Purpose: Comprehensive demonstration of the cross-swarm envelope DSL
;;;; and three-ID semantics (message_id, correlation_id, idempotency_token).
;;;;
;;;; This example covers:
;;;;   - Envelope creation with all fields
;;;;   - Three-ID model for message tracking
;;;;   - Reader macros #E{} and #X{}
;;;;   - Serialization formats (JSON, Plist, Binary)
;;;;   - Message type handling (:request, :response, :event, :error)
;;;;   - Path tracking and hop counting
;;;;   - Deadline and TTL management
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/envelope-semantics.lisp")
;;;;   (envelope-semantics:run-demo)
;;;;
;;;; For REPL exploration:
;;;;   (in-package :envelope-semantics)
;;;;   (demonstrate-three-id-model)
;;;;   (demonstrate-serialization)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :envelope-semantics
  (:use :cl :sw4rm-orchestrator)
  (:import-from :sw4rm-orchestrator.envelope
                #:envelope-to-json
                #:json-to-envelope
                #:envelope-to-plist
                #:plist-to-envelope
                #:envelope-to-octets
                #:octets-to-envelope
                #:envelope-priority
                #:envelope-message-type)
  (:export #:run-demo
           #:demonstrate-three-id-model
           #:demonstrate-serialization
           #:demonstrate-message-types
           #:demonstrate-path-tracking
           #:demonstrate-deadlines
           #:*sample-envelope*))

(in-package :envelope-semantics)

;;; ==========================================================================
;;; Global State (for REPL exploration)
;;; ==========================================================================

(defparameter *sample-envelope* nil
  "A sample envelope for REPL exploration.")

;;; ==========================================================================
;;; Three-ID Model Demonstration
;;; ==========================================================================

(defun demonstrate-three-id-model ()
  "Demonstrate the three-ID model for message tracking.

The three-ID model provides comprehensive message tracking:

1. MESSAGE ID (envelope-id)
   - Unique per message instance
   - Auto-generated UUID
   - Used for logging and debugging

2. CORRELATION ID (envelope-correlation-id)
   - Groups related messages in a workflow
   - Same across request/response pairs
   - Optional - set by caller

3. IDEMPOTENCY TOKEN (envelope-idempotency-token)
   - Prevents duplicate processing
   - Client-generated for retries
   - Optional - used for at-most-once semantics"

  (format t "~&=== Three-ID Model ===~%~%")

  ;; 1. Basic message with auto-generated ID
  (format t "1. Basic message (auto-generated message ID):~%")
  (let ((env (make-cross-swarm-envelope
               :source-swarm "frontend"
               :target-swarm "backend"
               :sender "ui-agent"
               :recipient "api-agent"
               :payload '(:action "get-user" :user-id 42))))
    (format t "   Message ID: ~A~%" (envelope-id env))
    (format t "   Correlation ID: ~A~%" (envelope-correlation-id env))
    (format t "   Idempotency Token: ~A~%~%" (envelope-idempotency-token env)))

  ;; 2. Request/response pair with correlation
  (format t "2. Request/response pair (same correlation ID):~%")
  (let* ((correlation-id (format nil "workflow-~A" (get-universal-time)))
         (request (make-cross-swarm-envelope
                    :source-swarm "frontend"
                    :target-swarm "backend"
                    :correlation-id correlation-id
                    :message-type :request
                    :payload '(:action "create-order" :items (1 2 3))))
         (response (make-cross-swarm-envelope
                     :source-swarm "backend"
                     :target-swarm "frontend"
                     :correlation-id correlation-id
                     :message-type :response
                     :payload '(:order-id "ORD-123" :status "created"))))
    (format t "   Request:~%")
    (format t "     Message ID: ~A~%" (envelope-id request))
    (format t "     Correlation ID: ~A~%" (envelope-correlation-id request))
    (format t "   Response:~%")
    (format t "     Message ID: ~A~%" (envelope-id response))
    (format t "     Correlation ID: ~A~%~%" (envelope-correlation-id response)))

  ;; 3. Idempotent message with retry token
  (format t "3. Idempotent message (same token for retries):~%")
  (let ((idempotency-token "client-req-abc123"))
    (format t "   First attempt:~%")
    (let ((env1 (make-cross-swarm-envelope
                  :source-swarm "client"
                  :target-swarm "payment"
                  :idempotency-token idempotency-token
                  :payload '(:action "charge" :amount 100))))
      (format t "     Message ID: ~A~%" (envelope-id env1))
      (format t "     Idempotency Token: ~A~%" (envelope-idempotency-token env1)))

    (format t "   Retry with same token:~%")
    (let ((env2 (make-cross-swarm-envelope
                  :source-swarm "client"
                  :target-swarm "payment"
                  :idempotency-token idempotency-token
                  :payload '(:action "charge" :amount 100))))
      (format t "     Message ID: ~A (different!)~%" (envelope-id env2))
      (format t "     Idempotency Token: ~A (same!)~%~%"
              (envelope-idempotency-token env2))))

  (format t "The three-ID model enables:~%")
  (format t "  - Message tracing (message ID)~%")
  (format t "  - Workflow tracking (correlation ID)~%")
  (format t "  - Duplicate prevention (idempotency token)~%"))

;;; ==========================================================================
;;; Serialization Demonstration
;;; ==========================================================================

(defun demonstrate-serialization ()
  "Demonstrate envelope serialization to JSON, Plist, and Binary formats.

The SDK supports three serialization formats:

1. JSON - For wire transmission (Python interop)
2. Plist - For Lisp-to-Lisp communication
3. Binary - For persistence and WAL"

  (format t "~&=== Serialization Formats ===~%~%")

  (let ((env (make-cross-swarm-envelope
               :source-swarm "frontend"
               :target-swarm "backend"
               :sender "ui-agent"
               :recipient "api-agent"
               :payload '(:event "user-login"
                          :user-id 42
                          :timestamp 1704902400))))

    ;; Store for REPL exploration
    (setf *sample-envelope* env)

    ;; 1. JSON Serialization
    (format t "1. JSON Serialization (wire format):~%")
    (let ((json (envelope-to-json env)))
      (format t "   Length: ~D characters~%" (length json))
      (format t "   Preview: ~A...~%~%"
              (subseq json 0 (min 100 (length json)))))

    ;; 2. Plist Serialization
    (format t "2. Plist Serialization (Lisp-native):~%")
    (let ((plist (envelope-to-plist env)))
      (format t "   Keys: ~{~A~^, ~}~%"
              (loop for (k v) on plist by #'cddr collect k))
      (format t "   Source: ~A~%" (getf plist :source-swarm))
      (format t "   Target: ~A~%~%" (getf plist :target-swarm)))

    ;; 3. Binary Serialization
    (format t "3. Binary Serialization (persistence):~%")
    (let ((octets (envelope-to-octets env)))
      (format t "   Length: ~D bytes~%" (length octets))
      (format t "   Version byte: ~D~%" (aref octets 0))
      (format t "   First 16 bytes: ~{~2,'0X~^ ~}~%~%"
              (coerce (subseq octets 0 (min 16 (length octets))) 'list)))

    ;; 4. Round-trip verification
    (format t "4. Round-trip verification:~%")

    ;; JSON round-trip
    (let* ((json (envelope-to-json env))
           (restored (json-to-envelope json)))
      (format t "   JSON: ID match = ~A~%"
              (string= (envelope-id env) (envelope-id restored))))

    ;; Plist round-trip
    (let* ((plist (envelope-to-plist env))
           (restored (plist-to-envelope plist)))
      (format t "   Plist: ID match = ~A~%"
              (string= (envelope-id env) (envelope-id restored))))

    ;; Binary round-trip
    (let* ((octets (envelope-to-octets env))
           (restored (octets-to-envelope octets)))
      (format t "   Binary: ID match = ~A~%"
              (string= (envelope-id env) (envelope-id restored))))))

;;; ==========================================================================
;;; Message Types Demonstration
;;; ==========================================================================

(defun demonstrate-message-types ()
  "Demonstrate the four message types supported by envelopes.

Message types:
  :REQUEST - Initiates an operation, expects response
  :RESPONSE - Reply to a request
  :EVENT - One-way notification, no response expected
  :COMMAND - Command message (imperative action)"

  (format t "~&=== Message Types ===~%~%")

  ;; 1. Request message
  (format t "1. REQUEST - Initiates operation:~%")
  (let ((env (make-cross-swarm-envelope
               :source-swarm "client"
               :target-swarm "api"
               :message-type :request
               :payload '(:action "get-user" :id 42))))
    (format t "   Type: ~A~%" (envelope-message-type env))
    (format t "   Payload: ~S~%~%" (envelope-payload env)))

  ;; 2. Response message
  (format t "2. RESPONSE - Reply to request:~%")
  (let ((env (make-cross-swarm-envelope
               :source-swarm "api"
               :target-swarm "client"
               :message-type :response
               :payload '(:user (:id 42 :name "Alice")))))
    (format t "   Type: ~A~%" (envelope-message-type env))
    (format t "   Payload: ~S~%~%" (envelope-payload env)))

  ;; 3. Event message
  (format t "3. EVENT - One-way notification:~%")
  (let ((env (make-cross-swarm-envelope
               :source-swarm "monitor"
               :target-swarm "dashboard"
               :message-type :event
               :payload '(:event "user-logged-in" :user-id 42))))
    (format t "   Type: ~A~%" (envelope-message-type env))
    (format t "   Payload: ~S~%~%" (envelope-payload env)))

  ;; 4. Command message
  (format t "4. COMMAND - Imperative action:~%")
  (let ((env (make-cross-swarm-envelope
               :source-swarm "admin"
               :target-swarm "worker"
               :message-type :command
               :payload '(:command "shutdown" :reason "maintenance"))))
    (format t "   Type: ~A~%" (envelope-message-type env))
    (format t "   Payload: ~S~%" (envelope-payload env))))

;;; ==========================================================================
;;; Path Tracking Demonstration
;;; ==========================================================================

(defun demonstrate-path-tracking ()
  "Demonstrate path tracking and hop counting for message routing.

Path tracking records the route a message takes through the swarm hierarchy:
  - PATH: List of swarm IDs visited
  - HOP-COUNT: Current number of hops
  - MAX-HOPS: Maximum allowed hops (prevents infinite loops)"

  (format t "~&=== Path Tracking ===~%~%")

  ;; Create envelope
  (let ((env (make-cross-swarm-envelope
               :source-swarm "frontend"
               :target-swarm "database"
               :max-hops 5
               :payload '(:query "SELECT * FROM users"))))

    (format t "1. Initial state:~%")
    (format t "   Path: ~A~%" (envelope-path env))
    (format t "   Hop count: ~D~%" (envelope-hop-count env))
    (format t "   Max hops: ~D~%~%" (envelope-max-hops env))

    ;; Simulate routing through nodes
    (format t "2. Simulating route through nodes:~%")

    ;; First hop: root orchestrator
    (let ((env1 (envelope-add-to-path env "root")))
      (setf env1 (envelope-increment-hop-count env1))
      (format t "   After hop 1 (root):~%")
      (format t "     Path: ~A~%" (envelope-path env1))
      (format t "     Hop count: ~D~%~%" (envelope-hop-count env1))

      ;; Second hop: backend cluster
      (let ((env2 (envelope-add-to-path env1 "backend")))
        (setf env2 (envelope-increment-hop-count env2))
        (format t "   After hop 2 (backend):~%")
        (format t "     Path: ~A~%" (envelope-path env2))
        (format t "     Hop count: ~D~%~%" (envelope-hop-count env2))

        ;; Third hop: database
        (let ((env3 (envelope-add-to-path env2 "database")))
          (setf env3 (envelope-increment-hop-count env3))
          (format t "   After hop 3 (database):~%")
          (format t "     Path: ~A~%" (envelope-path env3))
          (format t "     Hop count: ~D~%~%" (envelope-hop-count env3))

          ;; Check hop limit
          (format t "3. Hop limit check:~%")
          (format t "   Exceeded? ~A~%"
                  (envelope-hop-limit-exceeded-p env3)))))))

;;; ==========================================================================
;;; Deadline Management Demonstration
;;; ==========================================================================

(defun demonstrate-deadlines ()
  "Demonstrate deadline and TTL management for time-sensitive messages.

Deadlines ensure messages don't live forever:
  - DEADLINE: Absolute universal-time when message expires
  - CREATED-AT: When message was created
  - TTL: Time-to-live calculated from deadline"

  (format t "~&=== Deadline Management ===~%~%")

  ;; 1. Message without deadline
  (format t "1. Message without deadline:~%")
  (let ((env (make-cross-swarm-envelope
               :source-swarm "frontend"
               :target-swarm "backend"
               :payload '(:data "no rush"))))
    (format t "   Created at: ~A~%" (envelope-created-at env))
    (format t "   Deadline: ~A~%" (envelope-deadline env))
    (format t "   Expired? ~A~%~%" (envelope-expired-p env)))

  ;; 2. Message with deadline (10 seconds from now)
  (format t "2. Message with 10-second deadline:~%")
  (let* ((now (get-universal-time))
         (deadline (+ now 10))
         (env (envelope-set-deadline
               (make-cross-swarm-envelope
                 :source-swarm "frontend"
                 :target-swarm "backend"
                 :payload '(:data "time-sensitive"))
               deadline)))
    (format t "   Created at: ~A~%" (envelope-created-at env))
    (format t "   Deadline: ~A~%" (envelope-deadline env))
    (format t "   TTL remaining: ~D seconds~%" (envelope-remaining-ttl env))
    (format t "   Expired? ~A~%~%" (envelope-expired-p env)))

  ;; 3. Expired message (deadline in the past)
  (format t "3. Expired message (deadline in past):~%")
  (let* ((now (get-universal-time))
         (past-deadline (- now 60)) ; 1 minute ago
         (env (envelope-set-deadline
               (make-cross-swarm-envelope
                 :source-swarm "frontend"
                 :target-swarm "backend"
                 :payload '(:data "too late"))
               past-deadline)))
    (format t "   Created at: ~A~%" (envelope-created-at env))
    (format t "   Deadline: ~A~%" (envelope-deadline env))
    (format t "   TTL remaining: ~D seconds~%" (envelope-remaining-ttl env))
    (format t "   Expired? ~A~%" (envelope-expired-p env))))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete envelope semantics demonstration."

  (format t "~&==============================================~%")
  (format t "   SW4RM Envelope Semantics Deep Dive~%")
  (format t "==============================================~%~%")

  ;; Section 1: Three-ID Model
  (demonstrate-three-id-model)
  (format t "~%")

  ;; Section 2: Serialization
  (demonstrate-serialization)
  (format t "~%")

  ;; Section 3: Message Types
  (demonstrate-message-types)
  (format t "~%")

  ;; Section 4: Path Tracking
  (demonstrate-path-tracking)
  (format t "~%")

  ;; Section 5: Deadlines
  (demonstrate-deadlines)

  (format t "~%==============================================~%")
  (format t "   Demo Complete~%")
  (format t "==============================================~%~%")

  (format t "For REPL exploration:~%")
  (format t "  (in-package :envelope-semantics)~%")
  (format t "  *sample-envelope*~%")
  (format t "  (demonstrate-three-id-model)~%")
  (format t "  (demonstrate-serialization)~%"))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (cross_swarm_envelope.py pattern):

    from dataclasses import dataclass
    from typing import Optional, List, Any
    import json
    import uuid

    @dataclass
    class CrossSwarmEnvelope:
        id: str = field(default_factory=lambda: str(uuid.uuid4()))
        correlation_id: Optional[str] = None
        idempotency_token: Optional[str] = None
        source_swarm: Optional[str] = None
        target_swarm: Optional[str] = None
        sender: Optional[str] = None
        recipient: Optional[str] = None
        payload: Any = None
        path: List[str] = field(default_factory=list)
        hop_count: int = 0
        max_hops: int = 10
        created_at: float = field(default_factory=time.time)
        deadline: Optional[float] = None
        message_type: str = "request"

        def to_json(self) -> str:
            return json.dumps(asdict(self))

        @classmethod
        def from_json(cls, json_str: str) -> "CrossSwarmEnvelope":
            return cls(**json.loads(json_str))

CL Advantages Demonstrated:
1. Reader macros (#E{}, #X{}) enable concise envelope syntax
2. CLOS provides extensible type system with generic functions
3. Multiple serialization formats with consistent interface
4. Built-in validation via validate-envelope
5. Conditions/restarts for error handling (see restarts-recovery.lisp)
|#

;;;; End of envelope-semantics.lisp
