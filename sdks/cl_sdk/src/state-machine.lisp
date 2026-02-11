;;;; state-machine.lisp
;;;; Agent state machine implementation per SW4RM spec §8

(in-package :sw4rm-sdk)

;;; Condition Types

(define-condition state-transition-error (error)
  ((from-state :initarg :from-state :reader from-state)
   (to-state :initarg :to-state :reader to-state)
   (reason :initarg :reason :reader reason :initform nil))
  (:report (lambda (condition stream)
             (format stream "Invalid state transition from ~A to ~A~@[: ~A~]"
                     (from-state condition)
                     (to-state condition)
                     (reason condition))))
  (:documentation "Signaled when an invalid state transition is attempted."))

;;; State Definitions

(deftype agent-state ()
  "Valid agent states per SW4RM spec §8."
  '(member :initializing :runnable :scheduled :running :waiting
           :waiting-resources :suspended :resumed :completed :failed
           :shutting-down :recovering))

;;; Transition Matrix

(defparameter *state-transition-matrix*
  '((:initializing . (:runnable :failed))
    (:runnable . (:scheduled))
    (:scheduled . (:running))
    (:running . (:waiting :waiting-resources :suspended :completed :failed :shutting-down))
    (:waiting . (:running))
    (:waiting-resources . (:running :failed))
    (:suspended . (:resumed :failed))
    (:resumed . (:running))
    (:completed . (:runnable))
    (:failed . (:recovering))
    (:shutting-down . (:failed))
    (:recovering . (:runnable :shutting-down :failed)))
  "Transition matrix mapping each state to its valid target states.
   This implements the complete state transition rules from spec §8.")

;;; Transition Validation Functions

(defun valid-transitions (from-state)
  "Return a list of valid target states from FROM-STATE.

   Args:
     from-state: Current agent state (keyword)

   Returns:
     List of valid target states, or NIL if no transitions allowed."
  (check-type from-state agent-state)
  (cdr (assoc from-state *state-transition-matrix*)))

(defun valid-transition-p (from-state to-state)
  "Return T if transitioning from FROM-STATE to TO-STATE is valid.

   Args:
     from-state: Current agent state (keyword)
     to-state: Target agent state (keyword)

   Returns:
     T if transition is valid, NIL otherwise."
  (check-type from-state agent-state)
  (check-type to-state agent-state)
  (member to-state (valid-transitions from-state)))

;;; Transition Hook Types

(deftype transition-hook ()
  "A function called during state transitions.
   Signature: (lambda (from-state to-state timestamp metadata) ...)"
  'function)

;;; State Transition History Entry

(defstruct transition-history-entry
  "Records a single state transition event."
  (from-state nil :type (or null agent-state))
  (to-state nil :type agent-state)
  (timestamp (get-universal-time) :type integer)
  (metadata nil :type list))

;;; Agent State Machine Class

(defclass agent-state-machine ()
  ((current-state
    :initarg :current-state
    :accessor current-state
    :type agent-state
    :initform :initializing
    :documentation "Current state of the agent.")

   (before-transition-hooks
    :initarg :before-transition-hooks
    :accessor before-transition-hooks
    :type list
    :initform nil
    :documentation "List of functions called before state transitions.")

   (after-transition-hooks
    :initarg :after-transition-hooks
    :accessor after-transition-hooks
    :type list
    :initform nil
    :documentation "List of functions called after state transitions.")

   (transition-history
    :initarg :transition-history
    :accessor transition-history
    :type list
    :initform nil
    :documentation "History of state transitions, newest first.")

   (max-history
    :initarg :max-history
    :accessor max-history
    :type (integer 0 *)
    :initform 100
    :documentation "Maximum number of history entries to retain."))
  (:documentation "Agent state machine managing state transitions and lifecycle.
                   Implements the complete state transition matrix from spec §8."))

;;; State Machine Methods

(defmethod initialize-instance :after ((sm agent-state-machine) &key)
  "Initialize state machine with initial transition history entry."
  (with-slots (current-state transition-history) sm
    (push (make-transition-history-entry
           :from-state nil
           :to-state current-state
           :timestamp (get-universal-time))
          transition-history)))

(defmethod add-before-hook ((sm agent-state-machine) hook)
  "Add a before-transition hook to the state machine.

   Args:
     sm: Agent state machine instance
     hook: Function with signature (from-state to-state timestamp metadata)"
  (check-type hook function)
  (pushnew hook (before-transition-hooks sm) :test #'eq))

(defmethod add-after-hook ((sm agent-state-machine) hook)
  "Add an after-transition hook to the state machine.

   Args:
     sm: Agent state machine instance
     hook: Function with signature (from-state to-state timestamp metadata)"
  (check-type hook function)
  (pushnew hook (after-transition-hooks sm) :test #'eq))

(defmethod remove-before-hook ((sm agent-state-machine) hook)
  "Remove a before-transition hook from the state machine.

   Args:
     sm: Agent state machine instance
     hook: Hook function to remove"
  (setf (before-transition-hooks sm)
        (remove hook (before-transition-hooks sm) :test #'eq)))

(defmethod remove-after-hook ((sm agent-state-machine) hook)
  "Remove an after-transition hook from the state machine.

   Args:
     sm: Agent state machine instance
     hook: Hook function to remove"
  (setf (after-transition-hooks sm)
        (remove hook (after-transition-hooks sm) :test #'eq)))

(defmethod transition-to ((sm agent-state-machine) to-state &key metadata)
  "Transition the state machine to TO-STATE.

   Validates the transition, calls hooks, records history, and updates state.
   Signals STATE-TRANSITION-ERROR if the transition is invalid.

   Args:
     sm: Agent state machine instance
     to-state: Target state (keyword)
     metadata: Optional plist of metadata to record with transition

   Returns:
     The new current state

   Signals:
     STATE-TRANSITION-ERROR: If transition is invalid"
  (check-type to-state agent-state)
  (with-slots (current-state transition-history max-history) sm
    (let ((from-state current-state)
          (timestamp (get-universal-time)))

      ;; Validate transition
      (unless (valid-transition-p from-state to-state)
        (error 'state-transition-error
               :from-state from-state
               :to-state to-state
               :reason (format nil "No valid transition from ~A to ~A"
                              from-state to-state)))

      ;; Call before-transition hooks
      (dolist (hook (before-transition-hooks sm))
        (funcall hook from-state to-state timestamp metadata))

      ;; Perform transition
      (setf current-state to-state)

      ;; Record history
      (push (make-transition-history-entry
             :from-state from-state
             :to-state to-state
             :timestamp timestamp
             :metadata metadata)
            transition-history)

      ;; Trim history if needed
      (when (> (length transition-history) max-history)
        (setf transition-history (subseq transition-history 0 max-history)))

      ;; Call after-transition hooks
      (dolist (hook (after-transition-hooks sm))
        (funcall hook from-state to-state timestamp metadata))

      ;; Return new state
      to-state)))

(defmethod get-history ((sm agent-state-machine) &key (limit nil))
  "Get transition history entries.

   Args:
     sm: Agent state machine instance
     limit: Optional maximum number of entries to return (newest first)

   Returns:
     List of transition-history-entry structs"
  (if limit
      (subseq (transition-history sm) 0 (min limit (length (transition-history sm))))
      (transition-history sm)))

(defmethod clear-history ((sm agent-state-machine))
  "Clear all transition history except the current state entry.

   Args:
     sm: Agent state machine instance"
  (with-slots (current-state transition-history) sm
    (setf transition-history
          (list (make-transition-history-entry
                 :from-state nil
                 :to-state current-state
                 :timestamp (get-universal-time))))))

(defmethod can-transition-to-p ((sm agent-state-machine) to-state)
  "Check if the state machine can transition to TO-STATE.

   Args:
     sm: Agent state machine instance
     to-state: Target state to check

   Returns:
     T if transition is valid, NIL otherwise"
  (check-type to-state agent-state)
  (valid-transition-p (current-state sm) to-state))

(defmethod get-valid-transitions ((sm agent-state-machine))
  "Get list of valid target states from the current state.

   Args:
     sm: Agent state machine instance

   Returns:
     List of valid target states"
  (valid-transitions (current-state sm)))
