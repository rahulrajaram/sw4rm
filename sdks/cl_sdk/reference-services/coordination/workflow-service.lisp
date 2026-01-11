;;;; workflow-service.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Workflow Service
;;;;
;;;; Purpose: DAG-based workflow orchestration for multi-agent tasks.
;;;; This is the equivalent of the Python workflow_service.py.
;;;;
;;;; Features:
;;;;   - DAG workflow definition
;;;;   - Step dependency tracking
;;;;   - Parallel step execution
;;;;   - Workflow state management
;;;;   - Progress monitoring
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :workflow-service
  (:use :cl)
  (:export #:make-workflow-service
           #:create-workflow
           #:add-step
           #:start-workflow
           #:complete-step
           #:fail-step
           #:get-workflow
           #:list-workflows
           #:get-ready-steps
           #:clear-all
           #:workflow-service))

(in-package :workflow-service)

;;; ==========================================================================
;;; Dependencies
;;; ==========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :alexandria) :silent t))

;;; ==========================================================================
;;; Step Definition
;;; ==========================================================================

(deftype step-status ()
  '(member :pending :ready :running :completed :failed :skipped))

(defclass workflow-step ()
  ((step-id :initarg :step-id :accessor step-id :type string)
   (agent-id :initarg :agent-id :accessor step-agent-id :type string)
   (task :initarg :task :accessor step-task)
   (dependencies :initarg :dependencies :accessor step-dependencies :initform nil)
   (status :initarg :status :accessor step-status :initform :pending)
   (input :initarg :input :accessor step-input :initform nil)
   (output :initform nil :accessor step-output)
   (error-message :initform nil :accessor step-error-message)
   (started-at :initform nil :accessor step-started-at)
   (completed-at :initform nil :accessor step-completed-at))
  (:documentation "A single step in a workflow."))

(defun make-step (step-id agent-id task &key dependencies input)
  "Create a new workflow step."
  (make-instance 'workflow-step
                 :step-id step-id
                 :agent-id agent-id
                 :task task
                 :dependencies (or dependencies nil)
                 :input input))

(defmethod step-to-plist ((s workflow-step))
  "Convert step to plist for JSON serialization."
  (list :step-id (step-id s)
        :agent-id (step-agent-id s)
        :task (step-task s)
        :dependencies (step-dependencies s)
        :status (string-downcase (symbol-name (step-status s)))
        :input (step-input s)
        :output (step-output s)
        :error-message (step-error-message s)
        :started-at (step-started-at s)
        :completed-at (step-completed-at s)))

;;; ==========================================================================
;;; Workflow Definition
;;; ==========================================================================

(deftype workflow-status ()
  '(member :created :running :completed :failed :cancelled))

(defclass workflow ()
  ((workflow-id :initarg :workflow-id :accessor workflow-id :type string)
   (name :initarg :name :accessor workflow-name :initform nil)
   (steps :initform (make-hash-table :test 'equal) :accessor workflow-steps)
   (status :initarg :status :accessor workflow-status :initform :created)
   (created-at :initarg :created-at :accessor workflow-created-at)
   (started-at :initform nil :accessor workflow-started-at)
   (completed-at :initform nil :accessor workflow-completed-at)
   (metadata :initarg :metadata :accessor workflow-metadata :initform nil))
  (:documentation "A workflow containing ordered steps."))

(defun make-workflow (workflow-id &key name metadata)
  "Create a new workflow."
  (make-instance 'workflow
                 :workflow-id workflow-id
                 :name name
                 :metadata metadata
                 :created-at (get-universal-time)))

(defmethod workflow-to-plist ((w workflow))
  "Convert workflow to plist for JSON serialization."
  (let ((steps nil))
    (maphash (lambda (id step)
               (declare (ignore id))
               (push (step-to-plist step) steps))
             (workflow-steps w))
    (list :workflow-id (workflow-id w)
          :name (workflow-name w)
          :status (string-downcase (symbol-name (workflow-status w)))
          :steps (nreverse steps)
          :created-at (workflow-created-at w)
          :started-at (workflow-started-at w)
          :completed-at (workflow-completed-at w)
          :metadata (workflow-metadata w))))

;;; ==========================================================================
;;; Workflow Service Class
;;; ==========================================================================

(defclass workflow-service ()
  ((workflows :initform (make-hash-table :test 'equal)
              :accessor service-workflows)
   (lock :initform (bt:make-lock "workflow-lock")
         :accessor service-lock))
  (:documentation "Service for managing workflows."))

(defun make-workflow-service ()
  "Create a new workflow service instance."
  (make-instance 'workflow-service))

;;; ==========================================================================
;;; Core Operations
;;; ==========================================================================

(defun create-workflow (service workflow-id &key name metadata)
  "Create a new workflow."
  (bt:with-lock-held ((service-lock service))
    (let ((workflow (make-workflow workflow-id :name name :metadata metadata)))
      (setf (gethash workflow-id (service-workflows service)) workflow)
      (format t "[Workflow] Created: ~A~%" workflow-id)
      workflow)))

(defun add-step (service workflow-id step-id agent-id task &key dependencies input)
  "Add a step to a workflow."
  (bt:with-lock-held ((service-lock service))
    (let ((workflow (gethash workflow-id (service-workflows service))))
      (when workflow
        (let ((step (make-step step-id agent-id task
                               :dependencies dependencies
                               :input input)))
          (setf (gethash step-id (workflow-steps workflow)) step)
          (format t "[Workflow] Added step ~A to ~A~%" step-id workflow-id)
          step)))))

(defun start-workflow (service workflow-id)
  "Start a workflow, marking it as running."
  (bt:with-lock-held ((service-lock service))
    (let ((workflow (gethash workflow-id (service-workflows service))))
      (when (and workflow (eq (workflow-status workflow) :created))
        (setf (workflow-status workflow) :running)
        (setf (workflow-started-at workflow) (get-universal-time))
        ;; Mark steps with no dependencies as ready
        (maphash (lambda (id step)
                   (declare (ignore id))
                   (when (null (step-dependencies step))
                     (setf (step-status step) :ready)))
                 (workflow-steps workflow))
        (format t "[Workflow] Started: ~A~%" workflow-id)
        workflow))))

(defun complete-step (service workflow-id step-id &key output)
  "Mark a step as completed and update dependent steps."
  (bt:with-lock-held ((service-lock service))
    (let ((workflow (gethash workflow-id (service-workflows service))))
      (when workflow
        (let ((step (gethash step-id (workflow-steps workflow))))
          (when step
            (setf (step-status step) :completed)
            (setf (step-output step) output)
            (setf (step-completed-at step) (get-universal-time))
            (format t "[Workflow] Step completed: ~A/~A~%" workflow-id step-id)

            ;; Check and update dependent steps
            (maphash (lambda (id other-step)
                       (declare (ignore id))
                       (when (and (eq (step-status other-step) :pending)
                                  (member step-id (step-dependencies other-step)
                                          :test #'equal))
                         ;; Check if all dependencies are now complete
                         (when (every (lambda (dep-id)
                                        (let ((dep (gethash dep-id (workflow-steps workflow))))
                                          (and dep (eq (step-status dep) :completed))))
                                      (step-dependencies other-step))
                           (setf (step-status other-step) :ready))))
                     (workflow-steps workflow))

            ;; Check if workflow is complete
            (check-workflow-completion service workflow)
            step))))))

(defun fail-step (service workflow-id step-id &key error-message)
  "Mark a step as failed."
  (bt:with-lock-held ((service-lock service))
    (let ((workflow (gethash workflow-id (service-workflows service))))
      (when workflow
        (let ((step (gethash step-id (workflow-steps workflow))))
          (when step
            (setf (step-status step) :failed)
            (setf (step-error-message step) error-message)
            (setf (step-completed-at step) (get-universal-time))
            (format t "[Workflow] Step failed: ~A/~A - ~A~%"
                    workflow-id step-id error-message)

            ;; Mark dependent steps as skipped
            (maphash (lambda (id other-step)
                       (declare (ignore id))
                       (when (member step-id (step-dependencies other-step) :test #'equal)
                         (setf (step-status other-step) :skipped)))
                     (workflow-steps workflow))

            ;; Check if workflow is complete (even if failed)
            (check-workflow-completion service workflow)
            step))))))

(defun check-workflow-completion (service workflow)
  "Check if a workflow is complete and update its status."
  (declare (ignore service))
  (let ((all-done t)
        (any-failed nil))
    (maphash (lambda (id step)
               (declare (ignore id))
               (let ((status (step-status step)))
                 (when (eq status :failed)
                   (setf any-failed t))
                 (when (member status '(:pending :ready :running))
                   (setf all-done nil))))
             (workflow-steps workflow))
    (when all-done
      (setf (workflow-status workflow) (if any-failed :failed :completed))
      (setf (workflow-completed-at workflow) (get-universal-time))
      (format t "[Workflow] ~A: ~A~%"
              (workflow-id workflow) (workflow-status workflow)))))

(defun get-workflow (service workflow-id)
  "Get a workflow by ID."
  (bt:with-lock-held ((service-lock service))
    (let ((workflow (gethash workflow-id (service-workflows service))))
      (when workflow
        (workflow-to-plist workflow)))))

(defun list-workflows (service &key status)
  "List workflows with optional status filter."
  (bt:with-lock-held ((service-lock service))
    (let ((results nil))
      (maphash (lambda (id workflow)
                 (declare (ignore id))
                 (when (or (null status)
                           (eq (workflow-status workflow) status))
                   (push (workflow-to-plist workflow) results)))
               (service-workflows service))
      (nreverse results))))

(defun get-ready-steps (service workflow-id)
  "Get all steps that are ready to execute."
  (bt:with-lock-held ((service-lock service))
    (let ((workflow (gethash workflow-id (service-workflows service))))
      (when workflow
        (let ((ready nil))
          (maphash (lambda (id step)
                     (declare (ignore id))
                     (when (eq (step-status step) :ready)
                       (push (step-to-plist step) ready)))
                   (workflow-steps workflow))
          (nreverse ready))))))

(defun clear-all (service)
  "Clear all workflows (for testing)."
  (bt:with-lock-held ((service-lock service))
    (clrhash (service-workflows service))))

;;; ==========================================================================
;;; Request Handling
;;; ==========================================================================

(defun handle-request (service request)
  "Process a workflow service request."
  (let ((method (cdr (assoc :method request)))
        (params (cdr (assoc :params request))))
    (handler-case
        (cond
          ;; CreateWorkflow
          ((string-equal method "create")
           (let* ((workflow-id (cdr (assoc :workflow-id params)))
                  (name (cdr (assoc :name params)))
                  (metadata (cdr (assoc :metadata params)))
                  (workflow (create-workflow service workflow-id
                                             :name name :metadata metadata)))
             (list (cons :success t)
                   (cons :result (workflow-to-plist workflow)))))

          ;; AddStep
          ((string-equal method "add-step")
           (let* ((workflow-id (cdr (assoc :workflow-id params)))
                  (step-id (cdr (assoc :step-id params)))
                  (agent-id (cdr (assoc :agent-id params)))
                  (task (cdr (assoc :task params)))
                  (dependencies (cdr (assoc :dependencies params)))
                  (input (cdr (assoc :input params)))
                  (step (add-step service workflow-id step-id agent-id task
                                  :dependencies dependencies :input input)))
             (if step
                 (list (cons :success t)
                       (cons :result (step-to-plist step)))
                 (list (cons :success nil)
                       (cons :error "workflow not found")))))

          ;; StartWorkflow
          ((string-equal method "start")
           (let* ((workflow-id (cdr (assoc :workflow-id params)))
                  (workflow (start-workflow service workflow-id)))
             (if workflow
                 (list (cons :success t)
                       (cons :result (workflow-to-plist workflow)))
                 (list (cons :success nil)
                       (cons :error "workflow not found or not ready")))))

          ;; CompleteStep
          ((string-equal method "complete-step")
           (let* ((workflow-id (cdr (assoc :workflow-id params)))
                  (step-id (cdr (assoc :step-id params)))
                  (output (cdr (assoc :output params)))
                  (step (complete-step service workflow-id step-id :output output)))
             (if step
                 (list (cons :success t)
                       (cons :result (step-to-plist step)))
                 (list (cons :success nil)
                       (cons :error "step not found")))))

          ;; FailStep
          ((string-equal method "fail-step")
           (let* ((workflow-id (cdr (assoc :workflow-id params)))
                  (step-id (cdr (assoc :step-id params)))
                  (error-msg (cdr (assoc :error-message params)))
                  (step (fail-step service workflow-id step-id
                                   :error-message error-msg)))
             (if step
                 (list (cons :success t)
                       (cons :result (step-to-plist step)))
                 (list (cons :success nil)
                       (cons :error "step not found")))))

          ;; GetWorkflow
          ((string-equal method "get")
           (let* ((workflow-id (cdr (assoc :workflow-id params)))
                  (workflow (get-workflow service workflow-id)))
             (if workflow
                 (list (cons :success t)
                       (cons :result workflow))
                 (list (cons :success nil)
                       (cons :error "workflow not found")))))

          ;; ListWorkflows
          ((string-equal method "list")
           (let* ((status-str (cdr (assoc :status params)))
                  (status (when status-str
                            (intern (string-upcase status-str) :keyword)))
                  (workflows (list-workflows service :status status)))
             (list (cons :success t)
                   (cons :result workflows))))

          ;; GetReadySteps
          ((string-equal method "ready-steps")
           (let* ((workflow-id (cdr (assoc :workflow-id params)))
                  (steps (get-ready-steps service workflow-id)))
             (list (cons :success t)
                   (cons :result steps))))

          ;; Unknown method
          (t
           (list (cons :success nil)
                 (cons :error (format nil "unknown method: ~A" method)))))

      (error (e)
        (list (cons :success nil)
              (cons :error (format nil "~A" e)))))))

;;;; End of workflow-service.lisp
