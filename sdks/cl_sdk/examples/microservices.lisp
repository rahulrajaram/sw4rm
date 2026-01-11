;;;; microservices.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Microservices Orchestration
;;;;
;;;; Purpose: Demonstrate microservices orchestration patterns with
;;;; health-aware routing, service discovery, and graceful degradation.
;;;;
;;;; This example covers:
;;;;   - Service registration and discovery
;;;;   - Health-aware routing
;;;;   - Load balancing strategies
;;;;   - Graceful degradation patterns
;;;;   - Circuit breaker concepts
;;;;
;;;; Architecture:
;;;;   +-----------------+
;;;;   |  Orchestrator   |
;;;;   +-------+---------+
;;;;           |
;;;;   +-------+-------+-------+
;;;;   |       |       |       |
;;;;   v       v       v       v
;;;; [Auth]  [API]  [Data] [Cache]
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/microservices.lisp")
;;;;   (microservices:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :microservices
  (:use :cl :sw4rm-orchestrator)
  (:import-from :sw4rm-orchestrator.tree
                #:leaf-host
                #:leaf-port
                #:node-status)
  (:export #:run-demo
           #:setup-microservices
           #:demonstrate-service-discovery
           #:demonstrate-health-routing
           #:demonstrate-graceful-degradation
           #:*orchestrator*
           #:*services*))

(in-package :microservices)

;;; ==========================================================================
;;; Service Configuration
;;; ==========================================================================

(defparameter *service-definitions*
  '((:id "auth-service"
     :host "localhost"
     :port 50051
     :capabilities (:authentication :authorization)
     :health :healthy)
    (:id "api-gateway"
     :host "localhost"
     :port 50052
     :capabilities (:routing :rate-limiting)
     :health :healthy)
    (:id "data-service"
     :host "localhost"
     :port 50053
     :capabilities (:storage :query)
     :health :healthy)
    (:id "cache-service"
     :host "localhost"
     :port 50054
     :capabilities (:caching :invalidation)
     :health :healthy))
  "Service definitions for the microservices cluster.")

;;; ==========================================================================
;;; Global State
;;; ==========================================================================

(defparameter *orchestrator* nil
  "The root orchestrator node.")

(defparameter *services* nil
  "Hash table of service-id -> swarm-leaf.")

(defparameter *service-health* nil
  "Hash table tracking service health status.")

;;; ==========================================================================
;;; Setup
;;; ==========================================================================

(defun setup-microservices ()
  "Set up the microservices cluster.

Creates:
  - Root orchestrator
  - Service leaves (auth, api, data, cache)
  - Health tracking registry"

  (format t "~&Setting up microservices cluster...~%~%")

  ;; Create orchestrator
  (setf *orchestrator* (make-instance 'swarm-node :id "orchestrator"))

  ;; Initialize registries
  (setf *services* (make-hash-table :test 'equal))
  (setf *service-health* (make-hash-table :test 'equal))

  ;; Register services
  (dolist (svc-def *service-definitions*)
    (let* ((id (getf svc-def :id))
           (host (getf svc-def :host))
           (port (getf svc-def :port))
           (capabilities (getf svc-def :capabilities))
           (health (getf svc-def :health))
           (leaf (make-instance 'swarm-leaf
                                 :id id
                                 :host host
                                 :port port)))

      ;; Register with orchestrator
      (register-child *orchestrator* leaf)

      ;; Track in services registry
      (setf (gethash id *services*) leaf)

      ;; Track health
      (setf (gethash id *service-health*) health)

      (format t "  Registered: ~A @ ~A:~D~%"
              id host port)
      (format t "    Capabilities: ~{~A~^, ~}~%"
              capabilities)))

  (format t "~%Cluster ready with ~D services.~%~%"
          (hash-table-count *services*)))

;;; ==========================================================================
;;; Service Discovery
;;; ==========================================================================

(defun discover-service (capability)
  "Discover services with a given capability.

Args:
  capability - Keyword capability to find

Returns:
  List of service IDs that provide the capability."
  (let ((matching nil))
    (dolist (svc-def *service-definitions*)
      (when (member capability (getf svc-def :capabilities))
        (push (getf svc-def :id) matching)))
    (nreverse matching)))

(defun demonstrate-service-discovery ()
  "Demonstrate service discovery patterns."

  (format t "~&=== Service Discovery ===~%~%")

  ;; List all services
  (format t "1. All registered services:~%")
  (maphash (lambda (id leaf)
             (format t "   ~A -> ~A:~D~%"
                     id (leaf-host leaf) (leaf-port leaf)))
           *services*)

  ;; Discover by capability
  (format t "~%2. Discovery by capability:~%")

  (let ((auth-services (discover-service :authentication)))
    (format t "   :authentication -> ~{~A~^, ~}~%"
            auth-services))

  (let ((storage-services (discover-service :storage)))
    (format t "   :storage -> ~{~A~^, ~}~%"
            storage-services))

  (let ((caching-services (discover-service :caching)))
    (format t "   :caching -> ~{~A~^, ~}~%"
            caching-services))

  ;; Service lookup
  (format t "~%3. Direct service lookup:~%")
  (let ((auth (gethash "auth-service" *services*)))
    (when auth
      (format t "   auth-service: ~A:~D~%"
              (leaf-host auth) (leaf-port auth)))))

;;; ==========================================================================
;;; Health-Aware Routing
;;; ==========================================================================

(defun get-service-health (service-id)
  "Get health status of a service."
  (gethash service-id *service-health* :unknown))

(defun set-service-health (service-id health)
  "Update health status of a service."
  (setf (gethash service-id *service-health*) health))

(defun healthy-services ()
  "Get list of healthy services."
  (let ((healthy nil))
    (maphash (lambda (id health)
               (when (eq health :healthy)
                 (push id healthy)))
             *service-health*)
    healthy))

(defun demonstrate-health-routing ()
  "Demonstrate health-aware routing."

  (format t "~&=== Health-Aware Routing ===~%~%")

  ;; Show initial health
  (format t "1. Initial health status:~%")
  (maphash (lambda (id health)
             (format t "   ~A: ~A~%" id health))
           *service-health*)

  ;; Simulate unhealthy service
  (format t "~%2. Simulating cache-service failure:~%")
  (set-service-health "cache-service" :unhealthy)
  (format t "   cache-service -> :unhealthy~%")

  ;; Show updated routing
  (format t "~%3. Healthy services for routing:~%")
  (dolist (id (healthy-services))
    (format t "   ~A~%" id))

  ;; Demonstrate routing decision
  (format t "~%4. Routing decision:~%")
  (let ((target "cache-service"))
    (if (eq (get-service-health target) :healthy)
        (format t "   Request to ~A: ROUTE~%" target)
        (format t "   Request to ~A: SKIP (unhealthy)~%" target)))

  ;; Restore health
  (format t "~%5. Restoring cache-service:~%")
  (set-service-health "cache-service" :healthy)
  (format t "   cache-service -> :healthy~%"))

;;; ==========================================================================
;;; Graceful Degradation
;;; ==========================================================================

(defun demonstrate-graceful-degradation ()
  "Demonstrate graceful degradation patterns."

  (format t "~&=== Graceful Degradation ===~%~%")

  ;; Pattern 1: Fallback to cache
  (format t "1. Cache Fallback Pattern:~%")
  (format t "   Normal flow: Client -> API -> Data~%")
  (format t "   Degraded:    Client -> API -> Cache (stale data OK)~%~%")

  (let ((data-health (get-service-health "data-service"))
        (cache-health (get-service-health "cache-service")))
    (cond
      ((eq data-health :healthy)
       (format t "   Status: Data service healthy, using fresh data~%"))
      ((eq cache-health :healthy)
       (format t "   Status: Data service down, using cached data~%"))
      (t
       (format t "   Status: Both down, returning error~%"))))

  ;; Pattern 2: Circuit breaker
  (format t "~%2. Circuit Breaker Pattern:~%")
  (format t "   States: CLOSED -> OPEN -> HALF-OPEN -> CLOSED~%~%")

  (let ((error-count 0)
        (threshold 5)
        (state :closed))
    (format t "   Initial state: ~A~%" state)
    (format t "   Error threshold: ~D~%~%" threshold)

    ;; Simulate errors
    (dotimes (i 6)
      (incf error-count)
      (when (>= error-count threshold)
        (setf state :open)))

    (format t "   After ~D errors: ~A~%" error-count state)
    (format t "   Requests now fail fast (no network call)~%"))

  ;; Pattern 3: Bulkhead
  (format t "~%3. Bulkhead Pattern:~%")
  (format t "   Isolate failures to prevent cascade~%~%")
  (format t "   Service pools:~%")
  (format t "   +----------------+  +----------------+~%")
  (format t "   | Auth Pool      |  | Data Pool      |~%")
  (format t "   | Max: 10 conns  |  | Max: 20 conns  |~%")
  (format t "   +----------------+  +----------------+~%~%")
  (format t "   Auth failure doesn't exhaust Data connections~%")

  ;; Pattern 4: Timeout
  (format t "~%4. Timeout Pattern:~%")
  (format t "   Configure per-service timeouts:~%")
  (format t "   - auth-service: 2s (fast auth required)~%")
  (format t "   - data-service: 10s (complex queries allowed)~%")
  (format t "   - cache-service: 0.5s (fast or skip)~%"))

;;; ==========================================================================
;;; Request Routing Demo
;;; ==========================================================================

(defun route-request (request-type)
  "Route a request based on type to appropriate service.

Args:
  request-type - Type of request (:auth, :data, :cache)

Returns:
  Service ID to route to, or :unavailable."

  (let ((target-service
          (case request-type
            (:auth "auth-service")
            (:data "data-service")
            (:cache "cache-service")
            (t "api-gateway"))))

    (if (eq (get-service-health target-service) :healthy)
        target-service
        ;; Try fallback
        (case request-type
          (:data
           (if (eq (get-service-health "cache-service") :healthy)
               "cache-service"
               :unavailable))
          (t :unavailable)))))

(defun demonstrate-request-routing ()
  "Demonstrate intelligent request routing."

  (format t "~&=== Request Routing ===~%~%")

  ;; Normal routing
  (format t "1. Normal routing (all healthy):~%")
  (dolist (req-type '(:auth :data :cache))
    (format t "   ~A -> ~A~%" req-type (route-request req-type)))

  ;; Simulate data service failure
  (format t "~%2. Data service failure:~%")
  (set-service-health "data-service" :unhealthy)
  (format t "   data-service -> :unhealthy~%~%")

  (format t "   Routing with fallback:~%")
  (dolist (req-type '(:auth :data :cache))
    (let ((result (route-request req-type)))
      (format t "   ~A -> ~A~A~%"
              req-type result
              (if (and (eq req-type :data) (string= result "cache-service"))
                  " (fallback to cache)"
                  ""))))

  ;; Restore
  (set-service-health "data-service" :healthy))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete microservices orchestration demonstration."

  (format t "~&==============================================~%")
  (format t "   Microservices Orchestration Patterns~%")
  (format t "==============================================~%~%")

  ;; Setup
  (setup-microservices)

  ;; Service discovery
  (demonstrate-service-discovery)
  (format t "~%")

  ;; Health-aware routing
  (demonstrate-health-routing)
  (format t "~%")

  ;; Request routing
  (demonstrate-request-routing)
  (format t "~%")

  ;; Graceful degradation
  (demonstrate-graceful-degradation)

  (format t "~%==============================================~%")
  (format t "   Demo Complete~%")
  (format t "==============================================~%~%")

  (format t "For REPL exploration:~%")
  (format t "  (in-package :microservices)~%")
  (format t "  (discover-service :authentication)~%")
  (format t "  (healthy-services)~%")
  (format t "  (route-request :data)~%"))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (microservices.py pattern):

    from typing import Dict, List, Optional
    from enum import Enum

    class HealthStatus(Enum):
        HEALTHY = "healthy"
        UNHEALTHY = "unhealthy"
        DEGRADED = "degraded"

    class ServiceRegistry:
        def __init__(self):
            self.services: Dict[str, ServiceInfo] = {}
            self.health: Dict[str, HealthStatus] = {}

        def register(self, service_id: str, info: ServiceInfo):
            self.services[service_id] = info
            self.health[service_id] = HealthStatus.HEALTHY

        def discover(self, capability: str) -> List[str]:
            return [
                sid for sid, info in self.services.items()
                if capability in info.capabilities
            ]

        def get_healthy(self) -> List[str]:
            return [
                sid for sid, health in self.health.items()
                if health == HealthStatus.HEALTHY
            ]

    class CircuitBreaker:
        def __init__(self, threshold: int = 5, timeout: int = 30):
            self.threshold = threshold
            self.timeout = timeout
            self.failures = 0
            self.state = "CLOSED"

        def call(self, func, *args, **kwargs):
            if self.state == "OPEN":
                raise CircuitOpenError()
            try:
                result = func(*args, **kwargs)
                self.failures = 0
                return result
            except Exception as e:
                self.failures += 1
                if self.failures >= self.threshold:
                    self.state = "OPEN"
                raise

CL Advantages Demonstrated:
1. CLOS allows natural modeling of service registry
2. Hash tables for O(1) service lookup
3. Conditions/restarts handle circuit breaker elegantly
4. Dynamic health updates without restart
|#

;;;; End of microservices.lisp
