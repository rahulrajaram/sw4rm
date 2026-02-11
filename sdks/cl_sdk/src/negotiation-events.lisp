;;;; negotiation-events.lisp
;;;; Event system for negotiation room activities

(in-package :sw4rm-sdk)

;;; Event Type Definitions

(deftype negotiation-event-type ()
  "Valid negotiation event types."
  '(member :proposal-submitted
           :critique-added
           :vote-cast
           :round-complete
           :approved
           :rejected
           :participant-joined
           :participant-left
           :room-created
           :room-closed))

;;; Negotiation Event Structure

(defstruct negotiation-event
  "Event representing an occurrence in a negotiation room."
  (event-type nil :type (or null negotiation-event-type))
  (room-id nil :type (or null string))
  (agent-id nil :type (or null string))
  (timestamp (get-universal-time) :type integer)
  (data nil :type t)
  (event-id nil :type (or null string)))

(defun make-negotiation-event-with-id (&key event-type room-id agent-id data)
  "Create a negotiation event with auto-generated ID.

   Args:
     event-type: Event type keyword
     room-id: Negotiation room identifier
     agent-id: Agent identifier (may be nil for system events)
     data: Event-specific data

   Returns:
     negotiation-event struct"
  (make-negotiation-event
   :event-type event-type
   :room-id room-id
   :agent-id agent-id
   :timestamp (get-universal-time)
   :data data
   :event-id (format nil "event-~A-~A" (get-universal-time) (random 1000000))))

;;; Event Listener Protocol

(deftype event-listener ()
  "A function called when an event is emitted.
   Signature: (lambda (event) ...)"
  'function)

;;; Negotiation Event Emitter

(defclass negotiation-event-emitter ()
  ((listeners
    :accessor emitter-listeners
    :type hash-table
    :initform (make-hash-table :test 'eq)
    :documentation "Hash table mapping event-type to list of listener functions.")

   (global-listeners
    :accessor global-listeners
    :type list
    :initform nil
    :documentation "List of listeners that receive all events.")

   (event-history
    :accessor event-history
    :type list
    :initform nil
    :documentation "History of emitted events, newest first.")

   (max-history
    :initarg :max-history
    :accessor max-history
    :type (integer 0 *)
    :initform 1000
    :documentation "Maximum number of events to keep in history.")

   (lock
    :accessor emitter-lock
    :initform (bt:make-lock "event-emitter-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "Event emitter for negotiation room events.
                   Supports type-specific and global event listeners."))

(defmethod on ((emitter negotiation-event-emitter) event-type listener)
  "Register a listener for a specific event type.

   Args:
     emitter: negotiation-event-emitter instance
     event-type: Event type keyword, or :all for all events
     listener: Listener function (event -> void)"
  (check-type listener function)
  (bt:with-lock-held ((emitter-lock emitter))
    (if (eq event-type :all)
        (pushnew listener (global-listeners emitter) :test #'eq)
        (progn
          (check-type event-type negotiation-event-type)
          (let ((listeners (gethash event-type (emitter-listeners emitter))))
            (pushnew listener listeners :test #'eq)
            (setf (gethash event-type (emitter-listeners emitter)) listeners))))))

(defmethod off ((emitter negotiation-event-emitter) event-type listener)
  "Unregister a listener for a specific event type.

   Args:
     emitter: negotiation-event-emitter instance
     event-type: Event type keyword, or :all for global listeners
     listener: Listener function to remove"
  (bt:with-lock-held ((emitter-lock emitter))
    (if (eq event-type :all)
        (setf (global-listeners emitter)
              (remove listener (global-listeners emitter) :test #'eq))
        (let ((listeners (gethash event-type (emitter-listeners emitter))))
          (setf (gethash event-type (emitter-listeners emitter))
                (remove listener listeners :test #'eq))))))

(defmethod emit ((emitter negotiation-event-emitter) event)
  "Emit an event to all registered listeners.

   Args:
     emitter: negotiation-event-emitter instance
     event: negotiation-event struct

   Returns:
     The event"
  (check-type event negotiation-event)
  (bt:with-lock-held ((emitter-lock emitter))
    (let ((event-type (negotiation-event-event-type event)))

      ;; Add to history
      (push event (event-history emitter))
      (when (> (length (event-history emitter)) (max-history emitter))
        (setf (event-history emitter)
              (subseq (event-history emitter) 0 (max-history emitter))))

      ;; Notify type-specific listeners
      (let ((listeners (gethash event-type (emitter-listeners emitter))))
        (dolist (listener listeners)
          (handler-case
              (funcall listener event)
            (error (e)
              (warn "Error in event listener for ~A: ~A" event-type e)))))

      ;; Notify global listeners
      (dolist (listener (global-listeners emitter))
        (handler-case
            (funcall listener event)
          (error (e)
            (warn "Error in global event listener: ~A" e)))))

    event))

(defmethod emit-event ((emitter negotiation-event-emitter)
                      event-type room-id agent-id data)
  "Create and emit a negotiation event.

   Args:
     emitter: negotiation-event-emitter instance
     event-type: Event type keyword
     room-id: Negotiation room identifier
     agent-id: Agent identifier
     data: Event-specific data

   Returns:
     The emitted event"
  (let ((event (make-negotiation-event-with-id
                :event-type event-type
                :room-id room-id
                :agent-id agent-id
                :data data)))
    (emit emitter event)))

(defmethod get-history ((emitter negotiation-event-emitter)
                       &key event-type room-id limit)
  "Get event history with optional filtering.

   Args:
     emitter: negotiation-event-emitter instance
     event-type: Optional event type filter
     room-id: Optional room ID filter
     limit: Optional maximum number of events to return

   Returns:
     List of negotiation-event structs, newest first"
  (let ((events (event-history emitter)))

    ;; Apply filters
    (when event-type
      (setf events (remove-if-not
                    (lambda (e) (eq (negotiation-event-event-type e) event-type))
                    events)))

    (when room-id
      (setf events (remove-if-not
                    (lambda (e) (equal (negotiation-event-room-id e) room-id))
                    events)))

    ;; Apply limit
    (if limit
        (subseq events 0 (min limit (length events)))
        events)))

(defmethod clear-history ((emitter negotiation-event-emitter))
  "Clear all event history.

   Args:
     emitter: negotiation-event-emitter instance"
  (bt:with-lock-held ((emitter-lock emitter))
    (setf (event-history emitter) nil)))

(defmethod clear-listeners ((emitter negotiation-event-emitter))
  "Remove all event listeners.

   Args:
     emitter: negotiation-event-emitter instance"
  (bt:with-lock-held ((emitter-lock emitter))
    (clrhash (emitter-listeners emitter))
    (setf (global-listeners emitter) nil)))

(defmethod listener-count ((emitter negotiation-event-emitter) &optional event-type)
  "Get the number of registered listeners.

   Args:
     emitter: negotiation-event-emitter instance
     event-type: Optional event type to count (nil for all)

   Returns:
     Number of listeners"
  (if event-type
      (if (eq event-type :all)
          (length (global-listeners emitter))
          (length (gethash event-type (emitter-listeners emitter))))
      (+ (length (global-listeners emitter))
         (let ((count 0))
           (maphash (lambda (type listeners)
                      (declare (ignore type))
                      (incf count (length listeners)))
                    (emitter-listeners emitter))
           count))))

;;; Helper Functions for Event Creation

(defun make-proposal-submitted-event (room-id agent-id proposal)
  "Create a PROPOSAL-SUBMITTED event.

   Args:
     room-id: Negotiation room ID
     agent-id: Agent who submitted the proposal
     proposal: Proposal data

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :proposal-submitted
   :room-id room-id
   :agent-id agent-id
   :data (list :proposal proposal)))

(defun make-critique-added-event (room-id agent-id critique)
  "Create a CRITIQUE-ADDED event.

   Args:
     room-id: Negotiation room ID
     agent-id: Agent who added the critique
     critique: Critique data

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :critique-added
   :room-id room-id
   :agent-id agent-id
   :data (list :critique critique)))

(defun make-vote-cast-event (room-id agent-id vote)
  "Create a VOTE-CAST event.

   Args:
     room-id: Negotiation room ID
     agent-id: Agent who cast the vote
     vote: Vote data

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :vote-cast
   :room-id room-id
   :agent-id agent-id
   :data (list :vote vote)))

(defun make-round-complete-event (room-id round-number result)
  "Create a ROUND-COMPLETE event.

   Args:
     room-id: Negotiation room ID
     round-number: Round number that completed
     result: Round result data

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :round-complete
   :room-id room-id
   :agent-id nil
   :data (list :round-number round-number :result result)))

(defun make-approved-event (room-id proposal)
  "Create an APPROVED event.

   Args:
     room-id: Negotiation room ID
     proposal: Approved proposal

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :approved
   :room-id room-id
   :agent-id nil
   :data (list :proposal proposal)))

(defun make-rejected-event (room-id reason)
  "Create a REJECTED event.

   Args:
     room-id: Negotiation room ID
     reason: Rejection reason

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :rejected
   :room-id room-id
   :agent-id nil
   :data (list :reason reason)))

(defun make-participant-joined-event (room-id agent-id)
  "Create a PARTICIPANT-JOINED event.

   Args:
     room-id: Negotiation room ID
     agent-id: Agent who joined

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :participant-joined
   :room-id room-id
   :agent-id agent-id
   :data nil))

(defun make-participant-left-event (room-id agent-id reason)
  "Create a PARTICIPANT-LEFT event.

   Args:
     room-id: Negotiation room ID
     agent-id: Agent who left
     reason: Reason for leaving (optional)

   Returns:
     negotiation-event struct"
  (make-negotiation-event-with-id
   :event-type :participant-left
   :room-id room-id
   :agent-id agent-id
   :data (list :reason reason)))

;;; Utility Functions

(defun event-to-plist (event)
  "Convert a negotiation event to a property list.

   Args:
     event: negotiation-event struct

   Returns:
     Property list"
  (list :event-id (negotiation-event-event-id event)
        :event-type (negotiation-event-event-type event)
        :room-id (negotiation-event-room-id event)
        :agent-id (negotiation-event-agent-id event)
        :timestamp (negotiation-event-timestamp event)
        :data (negotiation-event-data event)))

(defun make-event-emitter (&key (max-history 1000))
  "Create a negotiation event emitter.

   Args:
     max-history: Maximum number of events to keep in history (default 1000)

   Returns:
     negotiation-event-emitter instance"
  (make-instance 'negotiation-event-emitter :max-history max-history))
