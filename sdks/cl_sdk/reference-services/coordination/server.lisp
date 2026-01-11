;;;; server.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Coordination Server
;;;;
;;;; Purpose: Unified server for all coordination services (Handoff, Workflow,
;;;; NegotiationRoom). This is the equivalent of the Python coordination/server.py.
;;;;
;;;; Protocol: JSON-over-TCP with 4-byte big-endian length prefix
;;;; Default Port: 50060
;;;;
;;;; Services:
;;;;   - handoff: Agent-to-agent context handoff
;;;;   - workflow: DAG-based workflow orchestration
;;;;   - negotiation: Multi-party approval workflows
;;;;
;;;; Usage:
;;;;   sbcl --load server.lisp --eval '(coordination-server:start-server)'
;;;;
;;;; Environment:
;;;;   COORDINATION_PORT - Server port (default: 50060)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :coordination-server
  (:use :cl)
  (:export #:start-server
           #:stop-server
           #:*server*
           #:*handoff-service*
           #:*workflow-service*
           #:*negotiation-service*))

(in-package :coordination-server)

;;; ==========================================================================
;;; Dependencies
;;; ==========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:usocket :bordeaux-threads :cl-json :alexandria)
                :silent t))

;; Load coordination services
(load (merge-pathnames "handoff-service.lisp" *load-pathname*))
(load (merge-pathnames "workflow-service.lisp" *load-pathname*))
(load (merge-pathnames "negotiation-room-service.lisp" *load-pathname*))

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *default-port* 50060
  "Default coordination server port.")

;;; ==========================================================================
;;; State Management
;;; ==========================================================================

(defparameter *server* nil
  "The running server socket.")

(defparameter *running* nil
  "Flag to control server loop.")

(defparameter *handoff-service* nil
  "Handoff service instance.")

(defparameter *workflow-service* nil
  "Workflow service instance.")

(defparameter *negotiation-service* nil
  "Negotiation room service instance.")

;;; ==========================================================================
;;; JSON-over-TCP Protocol
;;; ==========================================================================

(defun read-message (stream)
  "Read a length-prefixed JSON message from stream."
  (handler-case
      (let ((length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
        (when (= 4 (read-sequence length-bytes stream))
          (let ((length (+ (ash (aref length-bytes 0) 24)
                           (ash (aref length-bytes 1) 16)
                           (ash (aref length-bytes 2) 8)
                           (aref length-bytes 3))))
            (when (and (> length 0) (< length (* 16 1024 1024)))
              (let ((payload (make-array length :element-type '(unsigned-byte 8))))
                (when (= length (read-sequence payload stream))
                  (let ((json-string (babel:octets-to-string payload :encoding :utf-8)))
                    (cl-json:decode-json-from-string json-string))))))))
    (end-of-file () nil)
    (error () nil)))

(defun write-message (stream response)
  "Write a length-prefixed JSON message to stream."
  (let* ((json-string (cl-json:encode-json-to-string response))
         (payload (babel:string-to-octets json-string :encoding :utf-8))
         (length (length payload))
         (length-bytes (make-array 4 :element-type '(unsigned-byte 8))))
    (setf (aref length-bytes 0) (ldb (byte 8 24) length))
    (setf (aref length-bytes 1) (ldb (byte 8 16) length))
    (setf (aref length-bytes 2) (ldb (byte 8 8) length))
    (setf (aref length-bytes 3) (ldb (byte 8 0) length))
    (write-sequence length-bytes stream)
    (write-sequence payload stream)
    (force-output stream)))

;;; ==========================================================================
;;; Request Routing
;;; ==========================================================================

(defun handle-request (request)
  "Route a request to the appropriate service.
Request format: {:service \"handoff|workflow|negotiation\" :method ... :params {...}}"
  (let ((service-name (cdr (assoc :service request))))
    (handler-case
        (cond
          ;; Handoff service
          ((string-equal service-name "handoff")
           (handoff-service::handle-request *handoff-service* request))

          ;; Workflow service
          ((string-equal service-name "workflow")
           (workflow-service::handle-request *workflow-service* request))

          ;; Negotiation service
          ((string-equal service-name "negotiation")
           (negotiation-room-service::handle-request *negotiation-service* request))

          ;; Health check (no service specified)
          ((string-equal (cdr (assoc :method request)) "health")
           (list (cons :success t)
                 (cons :result "healthy")
                 (cons :services '("handoff" "workflow" "negotiation"))))

          ;; Unknown service
          (t
           (list (cons :success nil)
                 (cons :error (format nil "unknown service: ~A" service-name)))))

      (error (e)
        (list (cons :success nil)
              (cons :error (format nil "~A" e)))))))

;;; ==========================================================================
;;; Client Connection Handler
;;; ==========================================================================

(defun handle-client (client-socket)
  "Handle a single client connection."
  (let ((stream (usocket:socket-stream client-socket)))
    (unwind-protect
         (loop for request = (read-message stream)
               while request
               do (let ((response (handle-request request)))
                    (write-message stream response)))
      (usocket:socket-close client-socket))))

;;; ==========================================================================
;;; Server Lifecycle
;;; ==========================================================================

(defun get-port ()
  "Get port from environment or use default."
  (let ((env-port (uiop:getenv "COORDINATION_PORT")))
    (if env-port
        (parse-integer env-port :junk-allowed t)
        *default-port*)))

(defun initialize-services ()
  "Initialize all coordination services."
  (setf *handoff-service* (handoff-service::make-handoff-service))
  (setf *workflow-service* (workflow-service::make-workflow-service))
  (setf *negotiation-service* (negotiation-room-service::make-negotiation-room-service))
  (format t "[Coordination] Services initialized~%"))

(defun start-server (&key (port nil))
  "Start the coordination server."
  (let ((actual-port (or port (get-port))))
    (format t "[Coordination] Starting on port ~D~%" actual-port)

    ;; Initialize services
    (initialize-services)

    ;; Create server socket
    (setf *server* (usocket:socket-listen "0.0.0.0" actual-port
                                           :reuse-address t
                                           :element-type '(unsigned-byte 8)))
    (setf *running* t)

    (format t "[Coordination] Ready to accept connections~%")
    (format t "[Coordination] Services: handoff, workflow, negotiation~%")

    (unwind-protect
         (loop while *running*
               do (handler-case
                      (let ((client (usocket:socket-accept *server*
                                                           :element-type '(unsigned-byte 8))))
                        (bt:make-thread
                         (lambda () (handle-client client))
                         :name "coordination-client"))
                    (usocket:connection-aborted-error () nil)
                    (error (e)
                      (when *running*
                        (format t "[Coordination] Accept error: ~A~%" e)))))
      (stop-server))

    *server*))

(defun stop-server ()
  "Stop the coordination server."
  (setf *running* nil)
  (when *server*
    (handler-case
        (usocket:socket-close *server*)
      (error () nil))
    (setf *server* nil))
  ;; Cleanup services
  (when *handoff-service*
    (setf (handoff-service::service-running *handoff-service*) nil))
  (when *negotiation-service*
    (setf (negotiation-room-service::service-running *negotiation-service*) nil))
  (format t "[Coordination] Server stopped~%"))

;;; ==========================================================================
;;; Signal Handling
;;; ==========================================================================

#+sbcl
(defun install-signal-handlers ()
  "Install signal handlers for graceful shutdown."
  (sb-sys:enable-interrupt
   sb-unix:sigint
   (lambda (sig code scp)
     (declare (ignore sig code scp))
     (format t "~%[Coordination] Received SIGINT, shutting down...~%")
     (stop-server)))
  (sb-sys:enable-interrupt
   sb-unix:sigterm
   (lambda (sig code scp)
     (declare (ignore sig code scp))
     (format t "[Coordination] Received SIGTERM, shutting down...~%")
     (stop-server))))

;;; ==========================================================================
;;; Entry Point
;;; ==========================================================================

(defun main ()
  "Entry point for standalone execution."
  #+sbcl (install-signal-handlers)
  (start-server))

;;;; End of server.lisp
