;;;; handoff-service.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Handoff Service
;;;;
;;;; Purpose: Agent-to-agent context handoff coordination.
;;;; This is the equivalent of the Python handoff_service.py.
;;;;
;;;; Features:
;;;;   - Context handoff between agents
;;;;   - Handoff state tracking
;;;;   - Timeout-based cleanup
;;;;   - Thread-safe operations
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :handoff-service
  (:use :cl)
  (:export #:make-handoff-service
           #:initiate-handoff
           #:complete-handoff
           #:cancel-handoff
           #:get-handoff
           #:list-handoffs
           #:clear-all
           #:handoff-service))

(in-package :handoff-service)

;;; ==========================================================================
;;; Dependencies
;;; ==========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :alexandria) :silent t))

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *handoff-timeout* 300
  "Default handoff timeout in seconds (5 minutes).")

;;; ==========================================================================
;;; Handoff Record
;;; ==========================================================================

(deftype handoff-status ()
  '(member :initiated :pending :completed :failed :cancelled :timeout))

(defclass handoff-record ()
  ((handoff-id :initarg :handoff-id :accessor handoff-id :type string)
   (source-agent :initarg :source-agent :accessor handoff-source-agent :type string)
   (target-agent :initarg :target-agent :accessor handoff-target-agent :type string)
   (context :initarg :context :accessor handoff-context :initform nil)
   (status :initarg :status :accessor handoff-status :initform :initiated)
   (created-at :initarg :created-at :accessor handoff-created-at)
   (updated-at :initarg :updated-at :accessor handoff-updated-at)
   (timeout :initarg :timeout :accessor handoff-timeout)
   (result :initform nil :accessor handoff-result)
   (error-message :initform nil :accessor handoff-error-message))
  (:documentation "A handoff record tracking context transfer between agents."))

(defun make-handoff-record (handoff-id source-agent target-agent &key context timeout)
  "Create a new handoff record."
  (let ((now (get-universal-time)))
    (make-instance 'handoff-record
                   :handoff-id handoff-id
                   :source-agent source-agent
                   :target-agent target-agent
                   :context context
                   :created-at now
                   :updated-at now
                   :timeout (or timeout *handoff-timeout*))))

(defmethod handoff-to-plist ((h handoff-record))
  "Convert handoff record to plist for JSON serialization."
  (list :handoff-id (handoff-id h)
        :source-agent (handoff-source-agent h)
        :target-agent (handoff-target-agent h)
        :context (handoff-context h)
        :status (string-downcase (symbol-name (handoff-status h)))
        :created-at (handoff-created-at h)
        :updated-at (handoff-updated-at h)
        :timeout (handoff-timeout h)
        :result (handoff-result h)
        :error-message (handoff-error-message h)))

;;; ==========================================================================
;;; Handoff Service Class
;;; ==========================================================================

(defclass handoff-service ()
  ((handoffs :initform (make-hash-table :test 'equal)
             :accessor service-handoffs)
   (lock :initform (bt:make-lock "handoff-lock")
         :accessor service-lock)
   (cleanup-thread :initform nil :accessor service-cleanup-thread)
   (running :initform nil :accessor service-running))
  (:documentation "Service for managing agent handoffs."))

(defun make-handoff-service ()
  "Create a new handoff service instance."
  (let ((service (make-instance 'handoff-service)))
    (setf (service-running service) t)
    (start-cleanup-thread service)
    service))

;;; ==========================================================================
;;; Cleanup
;;; ==========================================================================

(defun cleanup-expired-handoffs (service)
  "Remove handoffs that have exceeded their timeout."
  (let ((now (get-universal-time))
        (expired nil))
    (bt:with-lock-held ((service-lock service))
      (maphash (lambda (id handoff)
                 (when (and (member (handoff-status handoff) '(:initiated :pending))
                            (> (- now (handoff-created-at handoff))
                               (handoff-timeout handoff)))
                   (push id expired)
                   (setf (handoff-status handoff) :timeout)
                   (setf (handoff-updated-at handoff) now)))
               (service-handoffs service))
      (dolist (id expired)
        (format t "[Handoff] Expired: ~A~%" id)))))

(defun start-cleanup-thread (service)
  "Start the background cleanup thread."
  (setf (service-cleanup-thread service)
        (bt:make-thread
         (lambda ()
           (loop while (service-running service)
                 do (sleep 60)
                    (when (service-running service)
                      (handler-case
                          (cleanup-expired-handoffs service)
                        (error (e)
                          (format t "[Handoff] Cleanup error: ~A~%" e))))))
         :name "handoff-cleanup")))

;;; ==========================================================================
;;; Core Operations
;;; ==========================================================================

(defun initiate-handoff (service source-agent target-agent &key context timeout)
  "Initiate a handoff from source to target agent.
Returns the handoff record."
  (let* ((handoff-id (format nil "handoff-~A-~A-~A"
                             source-agent target-agent (get-universal-time)))
         (handoff (make-handoff-record handoff-id source-agent target-agent
                                       :context context :timeout timeout)))
    (bt:with-lock-held ((service-lock service))
      (setf (gethash handoff-id (service-handoffs service)) handoff)
      (format t "[Handoff] Initiated: ~A -> ~A (~A)~%"
              source-agent target-agent handoff-id))
    handoff))

(defun complete-handoff (service handoff-id &key result)
  "Complete a handoff with optional result.
Returns the updated handoff or NIL if not found."
  (bt:with-lock-held ((service-lock service))
    (let ((handoff (gethash handoff-id (service-handoffs service))))
      (when handoff
        (setf (handoff-status handoff) :completed)
        (setf (handoff-result handoff) result)
        (setf (handoff-updated-at handoff) (get-universal-time))
        (format t "[Handoff] Completed: ~A~%" handoff-id)
        handoff))))

(defun cancel-handoff (service handoff-id &key reason)
  "Cancel a handoff.
Returns the updated handoff or NIL if not found."
  (bt:with-lock-held ((service-lock service))
    (let ((handoff (gethash handoff-id (service-handoffs service))))
      (when handoff
        (setf (handoff-status handoff) :cancelled)
        (setf (handoff-error-message handoff) reason)
        (setf (handoff-updated-at handoff) (get-universal-time))
        (format t "[Handoff] Cancelled: ~A~%" handoff-id)
        handoff))))

(defun get-handoff (service handoff-id)
  "Get a handoff by ID."
  (bt:with-lock-held ((service-lock service))
    (let ((handoff (gethash handoff-id (service-handoffs service))))
      (when handoff
        (handoff-to-plist handoff)))))

(defun list-handoffs (service &key status source-agent target-agent)
  "List handoffs with optional filters."
  (bt:with-lock-held ((service-lock service))
    (let ((results nil))
      (maphash (lambda (id handoff)
                 (declare (ignore id))
                 (when (and (or (null status)
                                (eq (handoff-status handoff) status))
                            (or (null source-agent)
                                (string-equal (handoff-source-agent handoff)
                                              source-agent))
                            (or (null target-agent)
                                (string-equal (handoff-target-agent handoff)
                                              target-agent)))
                   (push (handoff-to-plist handoff) results)))
               (service-handoffs service))
      (nreverse results))))

(defun clear-all (service)
  "Clear all handoffs (for testing)."
  (bt:with-lock-held ((service-lock service))
    (clrhash (service-handoffs service))))

;;; ==========================================================================
;;; Request Handling
;;; ==========================================================================

(defun handle-request (service request)
  "Process a handoff service request."
  (let ((method (cdr (assoc :method request)))
        (params (cdr (assoc :params request))))
    (handler-case
        (cond
          ;; InitiateHandoff
          ((string-equal method "initiate")
           (let* ((source-agent (cdr (assoc :source-agent params)))
                  (target-agent (cdr (assoc :target-agent params)))
                  (context (cdr (assoc :context params)))
                  (timeout (cdr (assoc :timeout params)))
                  (handoff (initiate-handoff service source-agent target-agent
                                             :context context :timeout timeout)))
             (list (cons :success t)
                   (cons :result (handoff-to-plist handoff)))))

          ;; CompleteHandoff
          ((string-equal method "complete")
           (let* ((handoff-id (cdr (assoc :handoff-id params)))
                  (result (cdr (assoc :result params)))
                  (handoff (complete-handoff service handoff-id :result result)))
             (if handoff
                 (list (cons :success t)
                       (cons :result (handoff-to-plist handoff)))
                 (list (cons :success nil)
                       (cons :error "handoff not found")))))

          ;; CancelHandoff
          ((string-equal method "cancel")
           (let* ((handoff-id (cdr (assoc :handoff-id params)))
                  (reason (cdr (assoc :reason params)))
                  (handoff (cancel-handoff service handoff-id :reason reason)))
             (if handoff
                 (list (cons :success t)
                       (cons :result (handoff-to-plist handoff)))
                 (list (cons :success nil)
                       (cons :error "handoff not found")))))

          ;; GetHandoff
          ((string-equal method "get")
           (let* ((handoff-id (cdr (assoc :handoff-id params)))
                  (handoff (get-handoff service handoff-id)))
             (if handoff
                 (list (cons :success t)
                       (cons :result handoff))
                 (list (cons :success nil)
                       (cons :error "handoff not found")))))

          ;; ListHandoffs
          ((string-equal method "list")
           (let* ((status-str (cdr (assoc :status params)))
                  (status (when status-str
                            (intern (string-upcase status-str) :keyword)))
                  (source (cdr (assoc :source-agent params)))
                  (target (cdr (assoc :target-agent params)))
                  (handoffs (list-handoffs service
                                           :status status
                                           :source-agent source
                                           :target-agent target)))
             (list (cons :success t)
                   (cons :result handoffs))))

          ;; Unknown method
          (t
           (list (cons :success nil)
                 (cons :error (format nil "unknown method: ~A" method)))))

      (error (e)
        (list (cons :success nil)
              (cons :error (format nil "~A" e)))))))

;;;; End of handoff-service.lisp
