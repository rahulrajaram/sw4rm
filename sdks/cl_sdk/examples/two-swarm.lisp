;;;; two-swarm.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Basic Two-Swarm Example
;;;;
;;;; Purpose: Entry point example demonstrating basic orchestrator setup
;;;; with two Python sw4rm leaves. This is the simplest complete example
;;;; showing the core patterns of the CL SDK.
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;   3. Two Python sw4rm instances running on ports 50051 and 50052
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/two-swarm.lisp")
;;;;   (two-swarm-example:run-demo)
;;;;
;;;; For REPL exploration:
;;;;   (in-package :two-swarm-example)
;;;;   (setup-orchestrator)
;;;;   (describe-orchestrator *root*)
;;;;   (route-test-message)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :two-swarm-example
  (:use :cl :sw4rm-orchestrator)
  (:import-from :sw4rm-orchestrator.tree
   #:leaf-host
   #:leaf-port
   #:node-status)
  (:export #:run-demo
           #:setup-orchestrator
           #:route-test-message
           #:describe-orchestrator
           #:*root*
           #:*frontend*
           #:*backend*))

(in-package :two-swarm-example)

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *frontend-port* 50051
  "Port where the frontend Python sw4rm instance is running.")

(defparameter *backend-port* 50052
  "Port where the backend Python sw4rm instance is running.")

(defparameter *host* "localhost"
  "Host where Python sw4rm instances are running.")

;;; ==========================================================================
;;; Global State (for REPL exploration)
;;; ==========================================================================

(defparameter *root* nil
  "The root orchestrator node. Set by SETUP-ORCHESTRATOR.")

(defparameter *frontend* nil
  "The frontend leaf. Set by SETUP-ORCHESTRATOR.")

(defparameter *backend* nil
  "The backend leaf. Set by SETUP-ORCHESTRATOR.")

;;; ==========================================================================
;;; Orchestrator Setup
;;; ==========================================================================

(defun setup-orchestrator ()
  "Create and configure the orchestrator with two leaves.

   This demonstrates:
   - Creating a swarm-node (orchestrator)
   - Creating swarm-leaf instances (Python sw4rm wrappers)
   - Registering leaves with the orchestrator

   Returns the root orchestrator node."

  ;; Create the root orchestrator node
  ;; The :id is used for routing and identification
  (setf *root* (make-instance 'swarm-node
                              :id "root"))

  ;; Create the frontend leaf
  ;; This wraps a Python sw4rm instance running on port 50051
  (setf *frontend* (make-instance 'swarm-leaf
                                  :id "frontend"
                                  :host *host*
                                  :port *frontend-port*))

  ;; Create the backend leaf
  ;; This wraps a Python sw4rm instance running on port 50052
  (setf *backend* (make-instance 'swarm-leaf
                                 :id "backend"
                                 :host *host*
                                 :port *backend-port*))

  ;; Register both leaves with the orchestrator
  ;; This adds them to the routing table
  (register-child *root* *frontend*)
  (register-child *root* *backend*)

  ;; Log the setup
  (format t "~&Orchestrator configured:~%")
  (format t "  Root: ~A~%" (swarm-id *root*))
  (format t "  Frontend: ~A @ ~A:~D~%"
          (swarm-id *frontend*) *host* *frontend-port*)
  (format t "  Backend: ~A @ ~A:~D~%"
          (swarm-id *backend*) *host* *backend-port*)

  *root*)

;;; ==========================================================================
;;; Envelope Creation with Reader Macros
;;; ==========================================================================

;; The #X{} reader macro creates cross-swarm envelopes.
;; This is a CL-specific DSL feature that makes envelope creation concise.
;;
;; Syntax: #X{:source-swarm "id" :target-swarm "id" ...}
;;
;; Compare to Python:
;;   envelope = CrossSwarmEnvelope(
;;       source_swarm="frontend",
;;       target_swarm="backend",
;;       ...
;;   )

(defun make-user-login-envelope (user-id)
  "Create a cross-swarm envelope for a user login event.

   Uses make-cross-swarm-envelope constructor."
  (sw4rm-orchestrator.envelope:make-cross-swarm-envelope
     :source-swarm "frontend"
     :target-swarm "backend"
     :sender "ui-agent"
     :recipient "auth-agent"
     :message-type :event
     :payload (list :event "user-login" :user-id user-id :timestamp (get-universal-time))))

(defun make-data-request-envelope (query)
  "Create a cross-swarm envelope for a data request.

   Shows how payloads can be arbitrary plists."
  (sw4rm-orchestrator.envelope:make-cross-swarm-envelope
     :source-swarm "frontend"
     :target-swarm "backend"
     :sender "dashboard-agent"
     :recipient "database-agent"
     :message-type :request
     :payload (list :query query :limit 100 :offset 0)))

;;; ==========================================================================
;;; Message Routing
;;; ==========================================================================

(defun route-test-message ()
  "Route a test message from frontend to backend.

   This demonstrates:
   - Creating an envelope with #X{}
   - Routing through the orchestrator
   - Basic error handling

   Returns the routing result or NIL on failure."

  (unless *root*
    (error "Orchestrator not set up. Call SETUP-ORCHESTRATOR first."))

  (let ((envelope (make-user-login-envelope 42)))
    (format t "~&Routing message:~%")
    (format t "  From: ~A/~A~%"
            (envelope-source-swarm envelope)
            (envelope-sender envelope))
    (format t "  To: ~A/~A~%"
            (envelope-target-swarm envelope)
            (envelope-recipient envelope))

    ;; Route the envelope through the orchestrator
    ;; In a real deployment, this would send via gRPC to the Python leaf
    (handler-case
        (let ((result (route-envelope *root* envelope)))
          (format t "  Result: ~A~%" result)
          result)
      (routing-error (e)
        (format t "  Routing failed: ~A~%" e)
        nil))))

;;; ==========================================================================
;;; REPL Helpers
;;; ==========================================================================

(defun show-routing-table ()
  "Display the current routing table.

   Useful for REPL exploration and debugging."
  (unless *root*
    (error "Orchestrator not set up. Call SETUP-ORCHESTRATOR first."))

  (format t "~&Routing Table:~%")
  (dolist (child (list-children *root*))
    (format t "  ~A -> ~A:~D (status: ~A)~%"
            (swarm-id child)
            (leaf-host child)
            (leaf-port child)
            (node-status child))))

(defun check-health ()
  "Check the health status of the orchestrator.

   Returns :READY, :DEGRADED, or :NOT-READY based on leaf connectivity."
  (unless *root*
    (error "Orchestrator not set up. Call SETUP-ORCHESTRATOR first."))

  (let ((status (get-health-status)))
    (format t "~&Health Status: ~A~%" status)
    status))

(defun describe-orchestrator (node)
  "Print a description of the orchestrator tree rooted at NODE.

   Shows the tree structure, registered leaves, and their status."
  (format t "~&Orchestrator: ~A~%" (swarm-id node))
  (format t "  Type: ~A~%" (type-of node))
  (format t "  Status: ~A~%" (node-status node))
  (let ((children (list-children node)))
    (format t "  Children (~D):~%" (length children))
    (dolist (child children)
      (format t "    - ~A: ~A:~D [~A]~%"
              (swarm-id child)
              (if (typep child 'sw4rm-orchestrator.tree:swarm-leaf)
                  (leaf-host child)
                  "orchestrator")
              (if (typep child 'sw4rm-orchestrator.tree:swarm-leaf)
                  (leaf-port child)
                  0)
              (node-status child)))))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete two-swarm demo.

   This demonstrates the full workflow:
   1. Set up the orchestrator
   2. Show the routing table
   3. Check health status
   4. Route a test message

   Note: In production, Python sw4rm instances would be running.
   This demo will show :DEGRADED status since gRPC is placeholder."

  (format t "~&=== SW4RM Two-Swarm Demo ===~%~%")

  ;; Step 1: Setup
  (format t "Step 1: Setting up orchestrator...~%")
  (setup-orchestrator)
  (format t "~%")

  ;; Step 2: Show routing table
  (format t "Step 2: Routing table...~%")
  (show-routing-table)
  (format t "~%")

  ;; Step 3: Check health
  (format t "Step 3: Health check...~%")
  (check-health)
  (format t "~%")

  ;; Step 4: Route a message
  (format t "Step 4: Routing test message...~%")
  (route-test-message)
  (format t "~%")

  ;; Step 5: Describe the orchestrator
  (format t "Step 5: Orchestrator description...~%")
  (describe-orchestrator *root*)

  (format t "~&=== Demo Complete ===~%")
  (format t "~%For interactive exploration:~%")
  (format t "  (in-package :two-swarm-example)~%")
  (format t "  (describe-orchestrator *root*)~%")
  (format t "  (route-test-message)~%"))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (echo_agent.py pattern):

    from sw4rm import SwarmAgent, SwarmRouter, Envelope

    # Setup
    router = SwarmRouter()
    frontend = SwarmAgent(id="frontend", host="localhost", port=50051)
    backend = SwarmAgent(id="backend", host="localhost", port=50052)
    router.register(frontend)
    router.register(backend)

    # Route message
    envelope = Envelope(
        source_swarm="frontend",
        target_swarm="backend",
        sender="ui-agent",
        recipient="auth-agent",
        message_type="DATA",
        payload={"event": "user-login", "user_id": 42}
    )
    result = router.route(envelope)

CL Advantages Demonstrated:
1. Reader macros (#X{}) provide concise envelope syntax
2. CLOS gives natural object-oriented structure
3. REPL allows interactive exploration
4. Conditions/restarts (shown in restarts-recovery.lisp) enable
   sophisticated error handling not possible in Python
|#

;;; End of two-swarm.lisp
