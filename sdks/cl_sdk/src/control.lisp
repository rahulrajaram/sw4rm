;;;; control.lisp - Control message types for scheduler orchestration
;;;;
;;;; This module provides structured data types for CONTROL-only orchestration
;;;; messages used between the scheduler and agents:
;;;;
;;;;   SCHEDULER-COMMAND-V1  -- issued by the scheduler to direct an agent
;;;;                            through stages (prompt, plan, run).
;;;;   AGENT-REPORT-V1       -- sent by an agent back to the scheduler to
;;;;                            report results, logs, file artifacts, and errors.
;;;;
;;;; Content type constants match the Rust and Python SDKs.
;;;; All structures support round-trip JSON serialisation via TO-JSON / FROM-JSON
;;;; generic functions.

(in-package #:sw4rm-sdk)

;;;; -----------------------------------------------------------------------
;;;; Content type constants
;;;; -----------------------------------------------------------------------

(defconstant +ct-scheduler-command-v1+
  "application/vnd.sw4rm.scheduler.command+json;v=1"
  "MIME content type for scheduler command messages (v1).")

(defconstant +ct-agent-report-v1+
  "application/vnd.sw4rm.agent.report+json;v=1"
  "MIME content type for agent report messages (v1).")

;;;; -----------------------------------------------------------------------
;;;; Scheduler stage type
;;;; -----------------------------------------------------------------------
;;;;
;;;; Stages are represented as keywords: :PROMPT, :PLAN, :RUN.
;;;; The type SCHEDULER-STAGE restricts values to the valid set.

(deftype scheduler-stage ()
  "Valid scheduler stage keywords.
Each stage corresponds to a phase in the agent execution lifecycle:
  :PROMPT -- Initial prompt delivery phase.
  :PLAN   -- Planning / decomposition phase.
  :RUN    -- Execution phase."
  '(member :prompt :plan :run))

(defun scheduler-stage-to-string (stage)
  "Convert a SCHEDULER-STAGE keyword to its lowercase JSON string.

Arguments:
  STAGE -- A keyword of type SCHEDULER-STAGE.

Returns:
  A lowercase string (\"prompt\", \"plan\", or \"run\").

Signals:
  TYPE-ERROR if STAGE is not a valid SCHEDULER-STAGE."
  (check-type stage scheduler-stage)
  (string-downcase (symbol-name stage)))

(defun string-to-scheduler-stage (s)
  "Parse a string into a SCHEDULER-STAGE keyword.

Arguments:
  S -- A string (\"prompt\", \"plan\", or \"run\"; case-insensitive).

Returns:
  The corresponding keyword (:PROMPT, :PLAN, or :RUN).

Signals:
  ERROR if S is not a recognised stage name."
  (let ((kw (intern (string-upcase s) :keyword)))
    (check-type kw scheduler-stage)
    kw))

;;;; -----------------------------------------------------------------------
;;;; Scheduler command (v1)
;;;; -----------------------------------------------------------------------

(defstruct (scheduler-command-v1
            (:constructor make-scheduler-command-v1
                (stage &key input)))
  "Scheduler CONTROL command (v1).

Represents a directive from the scheduler telling an agent which stage
to enter, with an optional JSON-serialisable input payload.

Slots:
  STAGE -- A SCHEDULER-STAGE keyword (:PROMPT, :PLAN, or :RUN).
  INPUT -- An optional association list or hash-table for arbitrary data.
           NIL means no input is provided."
  (stage (error "STAGE is required") :type keyword :read-only t)
  (input nil :read-only t))

(defun scheduler-command-v1-to-alist (cmd)
  "Convert a SCHEDULER-COMMAND-V1 to an association list suitable for JSON encoding.

Arguments:
  CMD -- A SCHEDULER-COMMAND-V1 instance.

Returns:
  An alist with :STAGE (string) and optionally :INPUT."
  (let ((result (list (cons :stage (scheduler-stage-to-string
                                    (scheduler-command-v1-stage cmd))))))
    (when (scheduler-command-v1-input cmd)
      (push (cons :input (scheduler-command-v1-input cmd)) result))
    (nreverse result)))

(defun alist-to-scheduler-command-v1 (alist)
  "Construct a SCHEDULER-COMMAND-V1 from an association list.

Arguments:
  ALIST -- An alist with at least a :STAGE entry (string value).

Returns:
  A new SCHEDULER-COMMAND-V1 instance.

Signals:
  ERROR if :STAGE is missing or invalid."
  (let ((stage-str (cdr (assoc :stage alist :test #'string-equal)))
        (input (cdr (assoc :input alist :test #'string-equal))))
    (make-scheduler-command-v1 (string-to-scheduler-stage stage-str)
                               :input input)))

;;;; -----------------------------------------------------------------------
;;;; Agent report file (v1)
;;;; -----------------------------------------------------------------------

(defstruct (agent-report-file-v1
            (:constructor make-agent-report-file-v1 (path b64)))
  "A single file artifact attached to an agent report.

Files are transported as base64-encoded blobs so they can be embedded
inside JSON payloads without binary-framing concerns.

Slots:
  PATH -- Relative POSIX-style file path (forward slashes).
  B64  -- Base64-encoded file content string."
  (path (error "PATH is required") :type string :read-only t)
  (b64  (error "B64 is required")  :type string :read-only t))

(defun agent-report-file-v1-to-alist (file)
  "Convert an AGENT-REPORT-FILE-V1 to an association list.

Arguments:
  FILE -- An AGENT-REPORT-FILE-V1 instance.

Returns:
  An alist with :PATH and :B64 keys."
  (list (cons :path (agent-report-file-v1-path file))
        (cons :b64  (agent-report-file-v1-b64 file))))

(defun alist-to-agent-report-file-v1 (alist)
  "Construct an AGENT-REPORT-FILE-V1 from an association list.

Arguments:
  ALIST -- An alist with :PATH and :B64 entries.

Returns:
  A new AGENT-REPORT-FILE-V1 instance."
  (make-agent-report-file-v1
   (cdr (assoc :path alist :test #'string-equal))
   (cdr (assoc :b64 alist :test #'string-equal))))

;;;; -----------------------------------------------------------------------
;;;; Agent report (v1)
;;;; -----------------------------------------------------------------------

(defstruct (agent-report-v1
            (:constructor make-agent-report-v1
                (&key agent-id stage success files logs error)))
  "Agent report with optional base64 file artifacts (v1).

Sent by an agent back to the scheduler to communicate execution results.
All fields are optional to support incremental / partial reports.

Slots:
  AGENT-ID -- Identifier of the reporting agent (string or NIL).
  STAGE    -- Free-form stage label, e.g. \"generate\", \"test\" (string or NIL).
  SUCCESS  -- Whether the reported operation succeeded (:TRUE, :FALSE, or NIL).
  FILES    -- List of AGENT-REPORT-FILE-V1 instances, or NIL.
  LOGS     -- List of log line strings, or NIL.
  ERROR    -- Human-readable error description (string or NIL)."
  (agent-id nil :type (or string null))
  (stage    nil :type (or string null))
  (success  nil :type (or keyword null))
  (files    nil :type list)
  (logs     nil :type list)
  (error    nil :type (or string null)))

(defun agent-report-v1-to-alist (report)
  "Convert an AGENT-REPORT-V1 to an association list, omitting NIL fields.

Arguments:
  REPORT -- An AGENT-REPORT-V1 instance.

Returns:
  An alist suitable for JSON encoding."
  (let ((result nil))
    (when (agent-report-v1-error report)
      (push (cons :error (agent-report-v1-error report)) result))
    (when (agent-report-v1-logs report)
      (push (cons :logs (agent-report-v1-logs report)) result))
    (when (agent-report-v1-files report)
      (push (cons :files (mapcar #'agent-report-file-v1-to-alist
                                 (agent-report-v1-files report)))
            result))
    (when (agent-report-v1-success report)
      (push (cons :success (ecase (agent-report-v1-success report)
                             (:true t)
                             (:false nil)))
            result))
    (when (agent-report-v1-stage report)
      (push (cons :stage (agent-report-v1-stage report)) result))
    (when (agent-report-v1-agent-id report)
      (push (cons :agent-id (agent-report-v1-agent-id report)) result))
    result))

(defun alist-to-agent-report-v1 (alist)
  "Construct an AGENT-REPORT-V1 from an association list.

Arguments:
  ALIST -- An alist with optional report fields.

Returns:
  A new AGENT-REPORT-V1 instance."
  (let ((files-raw (cdr (assoc :files alist :test #'string-equal))))
    (make-agent-report-v1
     :agent-id (cdr (assoc :agent-id alist :test #'string-equal))
     :stage    (cdr (assoc :stage alist :test #'string-equal))
     :success  (let ((val (assoc :success alist :test #'string-equal)))
                 (when val
                   (if (cdr val) :true :false)))
     :files    (when files-raw
                 (mapcar #'alist-to-agent-report-file-v1 files-raw))
     :logs     (cdr (assoc :logs alist :test #'string-equal))
     :error    (cdr (assoc :error alist :test #'string-equal)))))

;;;; -----------------------------------------------------------------------
;;;; Path normalisation
;;;; -----------------------------------------------------------------------

(defun normalize-posix-path (path)
  "Collapse a POSIX-style path, resolving \".\", \"..\", and duplicate slashes.

This is a pure string operation -- no filesystem access is performed.

Arguments:
  PATH -- A forward-slash-separated path string.

Returns:
  The collapsed path with no leading slash."
  (let ((parts (uiop:split-string (substitute #\/ #\\ path) :separator "/"))
        (out nil))
    (dolist (part parts)
      (cond
        ((or (string= part "") (string= part "."))
         nil)  ; skip empty and current-directory components
        ((string= part "..")
         (when out (pop out)))
        (t
         (push part out))))
    (format nil "~{~A~^/~}" (nreverse out))))

(defun normalize-agent-report-paths (report)
  "Normalize file paths in an AGENT-REPORT-V1 to POSIX style.

Replaces backslashes with forward slashes, collapses duplicate slashes,
and resolves \".\" and \"..\" components.

Arguments:
  REPORT -- An AGENT-REPORT-V1 instance.

Returns:
  A new AGENT-REPORT-V1 with normalised file paths.  The original
  instance is not mutated because the struct slots are read-only."
  (let ((files (agent-report-v1-files report)))
    (if (null files)
        report
        (make-agent-report-v1
         :agent-id (agent-report-v1-agent-id report)
         :stage    (agent-report-v1-stage report)
         :success  (agent-report-v1-success report)
         :files    (mapcar (lambda (f)
                             (make-agent-report-file-v1
                              (normalize-posix-path (agent-report-file-v1-path f))
                              (agent-report-file-v1-b64 f)))
                           files)
         :logs     (agent-report-v1-logs report)
         :error    (agent-report-v1-error report)))))
