;;;; negotiation-room-service.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Negotiation Room Service
;;;;
;;;; Purpose: Multi-agent approval workflows and consensus building.
;;;; This is the equivalent of the Python negotiation_room_service.py.
;;;;
;;;; Features:
;;;;   - Multi-party negotiation rooms
;;;;   - Voting and approval workflows
;;;;   - Consensus detection
;;;;   - Timeout-based resolution
;;;;   - Quorum support
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :negotiation-room-service
  (:use :cl)
  (:export #:make-negotiation-room-service
           #:create-room
           #:join-room
           #:leave-room
           #:submit-vote
           #:submit-proposal
           #:get-room
           #:list-rooms
           #:get-consensus
           #:clear-all
           #:negotiation-room-service))

(in-package :negotiation-room-service)

;;; ==========================================================================
;;; Dependencies
;;; ==========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:bordeaux-threads :alexandria) :silent t))

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *room-timeout* 600
  "Default room timeout in seconds (10 minutes).")

(defparameter *default-quorum* 0.5
  "Default quorum ratio (50%).")

;;; ==========================================================================
;;; Vote Record
;;; ==========================================================================

(deftype vote-value ()
  '(member :approve :reject :abstain))

(defclass vote-record ()
  ((voter-id :initarg :voter-id :accessor vote-voter-id :type string)
   (value :initarg :value :accessor vote-value)
   (reason :initarg :reason :accessor vote-reason :initform nil)
   (timestamp :initarg :timestamp :accessor vote-timestamp))
  (:documentation "A vote cast by a participant."))

(defun make-vote (voter-id value &key reason)
  "Create a new vote record."
  (make-instance 'vote-record
                 :voter-id voter-id
                 :value value
                 :reason reason
                 :timestamp (get-universal-time)))

(defmethod vote-to-plist ((v vote-record))
  "Convert vote to plist for JSON serialization."
  (list :voter-id (vote-voter-id v)
        :value (string-downcase (symbol-name (vote-value v)))
        :reason (vote-reason v)
        :timestamp (vote-timestamp v)))

;;; ==========================================================================
;;; Proposal Record
;;; ==========================================================================

(defclass proposal ()
  ((proposal-id :initarg :proposal-id :accessor proposal-id :type string)
   (proposer-id :initarg :proposer-id :accessor proposal-proposer-id :type string)
   (title :initarg :title :accessor proposal-title)
   (description :initarg :description :accessor proposal-description :initform nil)
   (options :initarg :options :accessor proposal-options :initform nil)
   (created-at :initarg :created-at :accessor proposal-created-at))
  (:documentation "A proposal for negotiation."))

(defun make-proposal (proposal-id proposer-id title &key description options)
  "Create a new proposal."
  (make-instance 'proposal
                 :proposal-id proposal-id
                 :proposer-id proposer-id
                 :title title
                 :description description
                 :options options
                 :created-at (get-universal-time)))

(defmethod proposal-to-plist ((p proposal))
  "Convert proposal to plist for JSON serialization."
  (list :proposal-id (proposal-id p)
        :proposer-id (proposal-proposer-id p)
        :title (proposal-title p)
        :description (proposal-description p)
        :options (proposal-options p)
        :created-at (proposal-created-at p)))

;;; ==========================================================================
;;; Negotiation Room
;;; ==========================================================================

(deftype room-status ()
  '(member :open :voting :resolved :timeout :cancelled))

(defclass negotiation-room ()
  ((room-id :initarg :room-id :accessor room-id :type string)
   (name :initarg :name :accessor room-name :initform nil)
   (participants :initform nil :accessor room-participants)
   (proposals :initform (make-hash-table :test 'equal) :accessor room-proposals)
   (votes :initform (make-hash-table :test 'equal) :accessor room-votes)
   (status :initarg :status :accessor room-status :initform :open)
   (quorum :initarg :quorum :accessor room-quorum)
   (consensus :initform nil :accessor room-consensus)
   (created-at :initarg :created-at :accessor room-created-at)
   (timeout :initarg :timeout :accessor room-timeout)
   (resolved-at :initform nil :accessor room-resolved-at)
   (metadata :initarg :metadata :accessor room-metadata :initform nil))
  (:documentation "A negotiation room for multi-party decision making."))

(defun make-room (room-id &key name quorum timeout metadata)
  "Create a new negotiation room."
  (make-instance 'negotiation-room
                 :room-id room-id
                 :name name
                 :quorum (or quorum *default-quorum*)
                 :timeout (or timeout *room-timeout*)
                 :metadata metadata
                 :created-at (get-universal-time)))

(defmethod room-to-plist ((r negotiation-room))
  "Convert room to plist for JSON serialization."
  (let ((proposals nil)
        (votes nil))
    (maphash (lambda (id p)
               (declare (ignore id))
               (push (proposal-to-plist p) proposals))
             (room-proposals r))
    (maphash (lambda (voter-id v)
               (declare (ignore voter-id))
               (push (vote-to-plist v) votes))
             (room-votes r))
    (list :room-id (room-id r)
          :name (room-name r)
          :participants (room-participants r)
          :proposals (nreverse proposals)
          :votes (nreverse votes)
          :status (string-downcase (symbol-name (room-status r)))
          :quorum (room-quorum r)
          :consensus (room-consensus r)
          :created-at (room-created-at r)
          :timeout (room-timeout r)
          :resolved-at (room-resolved-at r)
          :metadata (room-metadata r))))

;;; ==========================================================================
;;; Negotiation Room Service Class
;;; ==========================================================================

(defclass negotiation-room-service ()
  ((rooms :initform (make-hash-table :test 'equal)
          :accessor service-rooms)
   (lock :initform (bt:make-lock "negotiation-lock")
         :accessor service-lock)
   (cleanup-thread :initform nil :accessor service-cleanup-thread)
   (running :initform nil :accessor service-running))
  (:documentation "Service for managing negotiation rooms."))

(defun make-negotiation-room-service ()
  "Create a new negotiation room service instance."
  (let ((service (make-instance 'negotiation-room-service)))
    (setf (service-running service) t)
    (start-cleanup-thread service)
    service))

;;; ==========================================================================
;;; Cleanup
;;; ==========================================================================

(defun cleanup-expired-rooms (service)
  "Timeout rooms that have exceeded their timeout."
  (let ((now (get-universal-time)))
    (bt:with-lock-held ((service-lock service))
      (maphash (lambda (id room)
                 (declare (ignore id))
                 (when (and (member (room-status room) '(:open :voting))
                            (> (- now (room-created-at room))
                               (room-timeout room)))
                   (setf (room-status room) :timeout)
                   (setf (room-resolved-at room) now)
                   (format t "[NegotiationRoom] Timeout: ~A~%" (room-id room))))
               (service-rooms service)))))

(defun start-cleanup-thread (service)
  "Start the background cleanup thread."
  (setf (service-cleanup-thread service)
        (bt:make-thread
         (lambda ()
           (loop while (service-running service)
                 do (sleep 60)
                    (when (service-running service)
                      (handler-case
                          (cleanup-expired-rooms service)
                        (error (e)
                          (format t "[NegotiationRoom] Cleanup error: ~A~%" e))))))
         :name "negotiation-cleanup")))

;;; ==========================================================================
;;; Core Operations
;;; ==========================================================================

(defun create-room (service room-id &key name quorum timeout metadata)
  "Create a new negotiation room."
  (bt:with-lock-held ((service-lock service))
    (let ((room (make-room room-id
                           :name name
                           :quorum quorum
                           :timeout timeout
                           :metadata metadata)))
      (setf (gethash room-id (service-rooms service)) room)
      (format t "[NegotiationRoom] Created: ~A~%" room-id)
      room)))

(defun join-room (service room-id participant-id)
  "Add a participant to a room."
  (bt:with-lock-held ((service-lock service))
    (let ((room (gethash room-id (service-rooms service))))
      (when (and room (eq (room-status room) :open))
        (unless (member participant-id (room-participants room) :test #'equal)
          (push participant-id (room-participants room))
          (format t "[NegotiationRoom] ~A joined ~A~%" participant-id room-id))
        room))))

(defun leave-room (service room-id participant-id)
  "Remove a participant from a room."
  (bt:with-lock-held ((service-lock service))
    (let ((room (gethash room-id (service-rooms service))))
      (when room
        (setf (room-participants room)
              (remove participant-id (room-participants room) :test #'equal))
        (format t "[NegotiationRoom] ~A left ~A~%" participant-id room-id)
        room))))

(defun submit-proposal (service room-id proposer-id title &key description options)
  "Submit a proposal to a room."
  (bt:with-lock-held ((service-lock service))
    (let ((room (gethash room-id (service-rooms service))))
      (when (and room (eq (room-status room) :open))
        (let* ((proposal-id (format nil "prop-~A-~A"
                                    proposer-id (get-universal-time)))
               (proposal (make-proposal proposal-id proposer-id title
                                        :description description
                                        :options options)))
          (setf (gethash proposal-id (room-proposals room)) proposal)
          ;; Move room to voting status
          (setf (room-status room) :voting)
          (format t "[NegotiationRoom] Proposal ~A submitted to ~A~%"
                  proposal-id room-id)
          proposal)))))

(defun submit-vote (service room-id voter-id value &key reason)
  "Submit a vote in a room."
  (bt:with-lock-held ((service-lock service))
    (let ((room (gethash room-id (service-rooms service))))
      (when (and room (eq (room-status room) :voting))
        ;; Must be a participant
        (when (member voter-id (room-participants room) :test #'equal)
          (let ((vote (make-vote voter-id value :reason reason)))
            (setf (gethash voter-id (room-votes room)) vote)
            (format t "[NegotiationRoom] ~A voted ~A in ~A~%"
                    voter-id value room-id)
            ;; Check for consensus
            (check-consensus service room)
            vote))))))

(defun check-consensus (service room)
  "Check if consensus has been reached."
  (declare (ignore service))
  (let* ((participant-count (length (room-participants room)))
         (vote-count (hash-table-count (room-votes room)))
         (approvals 0)
         (rejections 0))
    ;; Count votes
    (maphash (lambda (id vote)
               (declare (ignore id))
               (case (vote-value vote)
                 (:approve (incf approvals))
                 (:reject (incf rejections))))
             (room-votes room))

    ;; Check if quorum met
    (when (>= (/ vote-count participant-count) (room-quorum room))
      ;; Determine outcome
      (let ((approval-ratio (if (> vote-count 0)
                                (/ approvals vote-count)
                                0)))
        (cond
          ((> approval-ratio 0.5)
           (setf (room-status room) :resolved)
           (setf (room-consensus room) :approved)
           (setf (room-resolved-at room) (get-universal-time))
           (format t "[NegotiationRoom] ~A: APPROVED~%" (room-id room)))
          ((>= (/ rejections vote-count) 0.5)
           (setf (room-status room) :resolved)
           (setf (room-consensus room) :rejected)
           (setf (room-resolved-at room) (get-universal-time))
           (format t "[NegotiationRoom] ~A: REJECTED~%" (room-id room))))))))

(defun get-room (service room-id)
  "Get a room by ID."
  (bt:with-lock-held ((service-lock service))
    (let ((room (gethash room-id (service-rooms service))))
      (when room
        (room-to-plist room)))))

(defun list-rooms (service &key status)
  "List rooms with optional status filter."
  (bt:with-lock-held ((service-lock service))
    (let ((results nil))
      (maphash (lambda (id room)
                 (declare (ignore id))
                 (when (or (null status)
                           (eq (room-status room) status))
                   (push (room-to-plist room) results)))
               (service-rooms service))
      (nreverse results))))

(defun get-consensus (service room-id)
  "Get the consensus status of a room."
  (bt:with-lock-held ((service-lock service))
    (let ((room (gethash room-id (service-rooms service))))
      (when room
        (list :room-id room-id
              :status (string-downcase (symbol-name (room-status room)))
              :consensus (when (room-consensus room)
                           (string-downcase (symbol-name (room-consensus room))))
              :participant-count (length (room-participants room))
              :vote-count (hash-table-count (room-votes room)))))))

(defun clear-all (service)
  "Clear all rooms (for testing)."
  (bt:with-lock-held ((service-lock service))
    (clrhash (service-rooms service))))

;;; ==========================================================================
;;; Request Handling
;;; ==========================================================================

(defun handle-request (service request)
  "Process a negotiation room service request."
  (let ((method (cdr (assoc :method request)))
        (params (cdr (assoc :params request))))
    (handler-case
        (cond
          ;; CreateRoom
          ((string-equal method "create")
           (let* ((room-id (cdr (assoc :room-id params)))
                  (name (cdr (assoc :name params)))
                  (quorum (cdr (assoc :quorum params)))
                  (timeout (cdr (assoc :timeout params)))
                  (metadata (cdr (assoc :metadata params)))
                  (room (create-room service room-id
                                     :name name
                                     :quorum quorum
                                     :timeout timeout
                                     :metadata metadata)))
             (list (cons :success t)
                   (cons :result (room-to-plist room)))))

          ;; JoinRoom
          ((string-equal method "join")
           (let* ((room-id (cdr (assoc :room-id params)))
                  (participant-id (cdr (assoc :participant-id params)))
                  (room (join-room service room-id participant-id)))
             (if room
                 (list (cons :success t)
                       (cons :result (room-to-plist room)))
                 (list (cons :success nil)
                       (cons :error "room not found or not open")))))

          ;; LeaveRoom
          ((string-equal method "leave")
           (let* ((room-id (cdr (assoc :room-id params)))
                  (participant-id (cdr (assoc :participant-id params)))
                  (room (leave-room service room-id participant-id)))
             (if room
                 (list (cons :success t)
                       (cons :result (room-to-plist room)))
                 (list (cons :success nil)
                       (cons :error "room not found")))))

          ;; SubmitProposal
          ((string-equal method "propose")
           (let* ((room-id (cdr (assoc :room-id params)))
                  (proposer-id (cdr (assoc :proposer-id params)))
                  (title (cdr (assoc :title params)))
                  (description (cdr (assoc :description params)))
                  (options (cdr (assoc :options params)))
                  (proposal (submit-proposal service room-id proposer-id title
                                             :description description
                                             :options options)))
             (if proposal
                 (list (cons :success t)
                       (cons :result (proposal-to-plist proposal)))
                 (list (cons :success nil)
                       (cons :error "room not found or not open")))))

          ;; SubmitVote
          ((string-equal method "vote")
           (let* ((room-id (cdr (assoc :room-id params)))
                  (voter-id (cdr (assoc :voter-id params)))
                  (value-str (cdr (assoc :value params)))
                  (value (intern (string-upcase value-str) :keyword))
                  (reason (cdr (assoc :reason params)))
                  (vote (submit-vote service room-id voter-id value :reason reason)))
             (if vote
                 (list (cons :success t)
                       (cons :result (vote-to-plist vote)))
                 (list (cons :success nil)
                       (cons :error "room not found, not voting, or not participant")))))

          ;; GetRoom
          ((string-equal method "get")
           (let* ((room-id (cdr (assoc :room-id params)))
                  (room (get-room service room-id)))
             (if room
                 (list (cons :success t)
                       (cons :result room))
                 (list (cons :success nil)
                       (cons :error "room not found")))))

          ;; ListRooms
          ((string-equal method "list")
           (let* ((status-str (cdr (assoc :status params)))
                  (status (when status-str
                            (intern (string-upcase status-str) :keyword)))
                  (rooms (list-rooms service :status status)))
             (list (cons :success t)
                   (cons :result rooms))))

          ;; GetConsensus
          ((string-equal method "consensus")
           (let* ((room-id (cdr (assoc :room-id params)))
                  (consensus (get-consensus service room-id)))
             (if consensus
                 (list (cons :success t)
                       (cons :result consensus))
                 (list (cons :success nil)
                       (cons :error "room not found")))))

          ;; Unknown method
          (t
           (list (cons :success nil)
                 (cons :error (format nil "unknown method: ~A" method)))))

      (error (e)
        (list (cons :success nil)
              (cons :error (format nil "~A" e)))))))

;;;; End of negotiation-room-service.lisp
