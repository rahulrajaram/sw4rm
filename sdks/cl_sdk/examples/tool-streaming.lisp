;;;; tool-streaming.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Tool Streaming Example
;;;;
;;;; Purpose: Demonstrate streaming tool calls with progress updates,
;;;; cancellation handling, and frame-by-frame output processing.
;;;;
;;;; This example covers:
;;;;   - Streaming tool calls using simulated call-stream
;;;;   - Progress updates (percentage, status)
;;;;   - Incremental output frames
;;;;   - Cancellation handling
;;;;   - Frame types: PROGRESS, OUTPUT, RESULT, ERROR, CANCELLED
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/tool-streaming.lisp")
;;;;   (tool-streaming:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :tool-streaming
  (:use :cl :sw4rm-orchestrator)
  (:export #:run-demo
           #:setup-provider
           #:demonstrate-file-search
           #:demonstrate-code-analysis
           #:demonstrate-cancellation
           #:demonstrate-error-handling
           #:*provider*
           #:*active-calls*))

(in-package :tool-streaming)

;;; ==========================================================================
;;; Frame Types
;;; ==========================================================================

(deftype frame-type ()
  "Types of frames in a streaming tool response."
  '(member :progress :output :result :error :cancelled))

;;; ==========================================================================
;;; Data Structures
;;; ==========================================================================

(defstruct tool-frame
  "A single frame in a streaming tool response.

Slots:
  call-id - Unique identifier for the tool call
  frame-type - Type of this frame (:progress, :output, :result, :error, :cancelled)
  sequence - Sequence number for ordering
  data - Frame payload (plist)
  timestamp - When the frame was generated (universal-time)"
  (call-id "" :type string)
  (frame-type :progress :type frame-type)
  (sequence 0 :type integer)
  (data nil :type list)
  (timestamp (get-universal-time) :type integer))

(defstruct tool-call
  "Request to execute a tool.

Slots:
  call-id - Unique identifier for this call
  tool-name - Name of the tool to execute
  provider-id - ID of the provider offering this tool
  args - Arguments plist to pass to the tool
  worktree-id - Optional worktree context
  timeout-ms - Maximum execution time"
  (call-id "" :type string)
  (tool-name "" :type string)
  (provider-id "default" :type string)
  (args nil :type list)
  (worktree-id nil :type (or null string))
  (timeout-ms 30000 :type integer))

(defstruct cancel-result
  "Result of a cancellation request.

Slots:
  call-id - The call that was cancelled
  success - Whether cancellation succeeded
  message - Additional information"
  (call-id "" :type string)
  (success nil :type boolean)
  (message "" :type string))

;;; ==========================================================================
;;; Global State
;;; ==========================================================================

(defparameter *provider* nil
  "Mock tool provider for demonstration.")

(defparameter *active-calls* (make-hash-table :test 'equal)
  "Hash table tracking active calls: call-id -> running-p")

(defparameter *cancel-flags* (make-hash-table :test 'equal)
  "Hash table tracking cancellation requests: call-id -> cancelled-p")

;;; ==========================================================================
;;; Mock Tool Provider
;;; ==========================================================================

(defun generate-call-id ()
  "Generate a unique call ID."
  (format nil "call-~A-~D" (random 10000) (get-universal-time)))

(defun check-cancelled-p (call-id)
  "Check if a call has been cancelled."
  (gethash call-id *cancel-flags* nil))

(defun mark-active (call-id)
  "Mark a call as active."
  (setf (gethash call-id *active-calls*) t)
  (setf (gethash call-id *cancel-flags*) nil))

(defun mark-inactive (call-id)
  "Mark a call as inactive."
  (remhash call-id *active-calls*)
  (remhash call-id *cancel-flags*))

(defun request-cancel (call-id)
  "Request cancellation of a call."
  (if (gethash call-id *active-calls*)
      (progn
        (setf (gethash call-id *cancel-flags*) t)
        (make-cancel-result :call-id call-id
                            :success t
                            :message "Cancellation requested"))
      (make-cancel-result :call-id call-id
                          :success nil
                          :message "Call not found or already completed")))

;;; ==========================================================================
;;; Streaming Tool Implementations
;;; ==========================================================================

(defun stream-file-search (call)
  "Stream file search results.

Args:
  call - tool-call structure

Returns:
  List of tool-frame structures simulating streaming output."
  (let* ((call-id (tool-call-call-id call))
         (pattern (getf (tool-call-args call) :pattern "*"))
         (directory (getf (tool-call-args call) :directory "/"))
         (frames nil)
         (sequence 0))

    (mark-active call-id)

    ;; Simulate finding files
    (let ((files (list (format nil "~A/file1.py" directory)
                       (format nil "~A/file2.py" directory)
                       (format nil "~A/subdir/file3.py" directory)
                       (format nil "~A/subdir/file4.py" directory)
                       (format nil "~A/subdir/deep/file5.py" directory))))

      (loop for file in files
            for i from 1
            do
               ;; Check for cancellation
               (when (check-cancelled-p call-id)
                 (push (make-tool-frame
                        :call-id call-id
                        :frame-type :cancelled
                        :sequence sequence
                        :data (list :message "Search cancelled by user"
                                    :files-found (1- i)))
                       frames)
                 (mark-inactive call-id)
                 (return-from stream-file-search (nreverse frames)))

               ;; Progress frame
               (push (make-tool-frame
                      :call-id call-id
                      :frame-type :progress
                      :sequence (incf sequence)
                      :data (list :percentage (round (* 100 (/ i (length files))))
                                  :status (format nil "Searching... found ~D files" i)))
                     frames)

               ;; Output frame
               (push (make-tool-frame
                      :call-id call-id
                      :frame-type :output
                      :sequence (incf sequence)
                      :data (list :file file
                                  :matches-pattern (or (string= pattern "*")
                                                       (search pattern file))))
                     frames))

      ;; Result frame
      (push (make-tool-frame
             :call-id call-id
             :frame-type :result
             :sequence (incf sequence)
             :data (list :total-files (length files)
                         :pattern pattern
                         :directory directory))
            frames)

      (mark-inactive call-id)
      (nreverse frames))))

(defun stream-code-analysis (call)
  "Stream code analysis results.

Args:
  call - tool-call structure

Returns:
  List of tool-frame structures simulating streaming output."
  (let* ((call-id (tool-call-call-id call))
         (frames nil)
         (sequence 0)
         (results (make-hash-table :test 'equal)))

    (mark-active call-id)

    ;; Analysis steps
    (let ((analysis-steps '((:syntax "Checking syntax...")
                            (:imports "Analyzing imports...")
                            (:types "Checking type hints...")
                            (:complexity "Computing complexity...")
                            (:security "Scanning for vulnerabilities...")))
          (step-results '((:syntax (:valid t :errors nil))
                          (:imports (:count 3 :external ("json" "typing")))
                          (:types (:coverage 0.85 :missing ("return type on line 5")))
                          (:complexity (:cyclomatic 4 :cognitive 3))
                          (:security (:issues 0 :warnings 1)))))

      (loop for (step-name status) in analysis-steps
            for (step-result-name step-result) in step-results
            for i from 1
            do
               ;; Check for cancellation
               (when (check-cancelled-p call-id)
                 (push (make-tool-frame
                        :call-id call-id
                        :frame-type :cancelled
                        :sequence sequence
                        :data (list :message "Analysis cancelled"
                                    :completed-steps (hash-table-keys results)))
                       frames)
                 (mark-inactive call-id)
                 (return-from stream-code-analysis (nreverse frames)))

               ;; Progress frame
               (push (make-tool-frame
                      :call-id call-id
                      :frame-type :progress
                      :sequence (incf sequence)
                      :data (list :percentage (round (* 100 (/ i (length analysis-steps))))
                                  :status status
                                  :current-step step-name))
                     frames)

               ;; Store result
               (setf (gethash step-name results) step-result)

               ;; Output frame
               (push (make-tool-frame
                      :call-id call-id
                      :frame-type :output
                      :sequence (incf sequence)
                      :data (list :step step-name :result step-result))
                     frames))

      ;; Result frame
      (push (make-tool-frame
             :call-id call-id
             :frame-type :result
             :sequence (incf sequence)
             :data (list :summary "Analysis complete"
                         :overall-score 8.5
                         :results results))
            frames)

      (mark-inactive call-id)
      (nreverse frames))))

(defun stream-long-computation (call)
  "Stream a long-running computation.

Args:
  call - tool-call structure

Returns:
  List of tool-frame structures simulating streaming output."
  (let* ((call-id (tool-call-call-id call))
         (iterations (getf (tool-call-args call) :iterations 10))
         (frames nil)
         (sequence 0)
         (accumulated 0))

    (mark-active call-id)

    (loop for i from 0 below iterations
          do
             ;; Check for cancellation
             (when (check-cancelled-p call-id)
               (push (make-tool-frame
                      :call-id call-id
                      :frame-type :cancelled
                      :sequence sequence
                      :data (list :message "Computation cancelled"
                                  :completed-iterations i
                                  :partial-result accumulated))
                     frames)
               (mark-inactive call-id)
               (return-from stream-long-computation (nreverse frames)))

             ;; Simulate computation
             (incf accumulated (* i i))

             ;; Progress frame
             (push (make-tool-frame
                    :call-id call-id
                    :frame-type :progress
                    :sequence (incf sequence)
                    :data (list :percentage (round (* 100 (/ (1+ i) iterations)))
                                :status (format nil "Computing iteration ~D/~D" (1+ i) iterations)
                                :intermediate-result accumulated))
                   frames))

    ;; Result frame
    (push (make-tool-frame
           :call-id call-id
           :frame-type :result
           :sequence (incf sequence)
           :data (list :final-result accumulated
                       :iterations-completed iterations))
          frames)

    (mark-inactive call-id)
    (nreverse frames)))

(defun stream-unknown-tool (call)
  "Return error for unknown tool.

Args:
  call - tool-call structure

Returns:
  List containing single error frame."
  (list (make-tool-frame
         :call-id (tool-call-call-id call)
         :frame-type :error
         :sequence 0
         :data (list :error (format nil "Unknown tool: ~A"
                                    (tool-call-tool-name call))))))

;;; ==========================================================================
;;; Tool Provider Interface
;;; ==========================================================================

(defun call-stream (call)
  "Execute a streaming tool call.

Args:
  call - tool-call structure

Returns:
  List of tool-frame structures."
  (let ((tool-name (tool-call-tool-name call)))
    (cond
      ((string= tool-name "file_search")
       (stream-file-search call))
      ((string= tool-name "code_analysis")
       (stream-code-analysis call))
      ((string= tool-name "long_computation")
       (stream-long-computation call))
      (t
       (stream-unknown-tool call)))))

;;; ==========================================================================
;;; Streaming Handler
;;; ==========================================================================

(defstruct streaming-handler
  "Handler for processing streaming tool responses.

Slots:
  on-progress - Callback for progress frames (function of data)
  on-output - Callback for output frames (function of data)
  on-error - Callback for error frames (function of data)
  outputs - List of output data collected
  last-progress - Most recent progress data
  result - Final result data
  cancelled - Whether the stream was cancelled"
  (on-progress nil :type (or null function))
  (on-output nil :type (or null function))
  (on-error nil :type (or null function))
  (outputs nil :type list)
  (last-progress nil :type list)
  (result nil :type list)
  (cancelled nil :type boolean))

(defun process-stream (handler frames)
  "Process all frames from a stream.

Args:
  handler - streaming-handler structure
  frames - List of tool-frame structures

Returns:
  The final result data, or NIL if cancelled/error."
  (dolist (frame frames)
    (handle-frame handler frame)
    ;; Stop on terminal frames
    (when (member (tool-frame-frame-type frame)
                  '(:result :error :cancelled))
      (return)))
  (streaming-handler-result handler))

(defun handle-frame (handler frame)
  "Handle a single frame.

Args:
  handler - streaming-handler structure
  frame - tool-frame structure"
  (let ((frame-type (tool-frame-frame-type frame))
        (data (tool-frame-data frame)))

    (case frame-type
      (:progress
       (setf (streaming-handler-last-progress handler) data)
       (when (streaming-handler-on-progress handler)
         (funcall (streaming-handler-on-progress handler) data)))

      (:output
       (push data (streaming-handler-outputs handler))
       (when (streaming-handler-on-output handler)
         (funcall (streaming-handler-on-output handler) data)))

      (:result
       (setf (streaming-handler-result handler) data))

      (:error
       (when (streaming-handler-on-error handler)
         (funcall (streaming-handler-on-error handler) data)))

      (:cancelled
       (setf (streaming-handler-cancelled handler) t)
       (setf (streaming-handler-result handler) data)))))

;;; ==========================================================================
;;; Utility Functions
;;; ==========================================================================

(defun hash-table-keys (table)
  "Get all keys from a hash table."
  (loop for key being the hash-keys of table collect key))

;;; ==========================================================================
;;; Demonstrations
;;; ==========================================================================

(defun setup-provider ()
  "Set up the mock tool provider."
  (format t "~&Setting up mock tool provider...~%~%")
  (clrhash *active-calls*)
  (clrhash *cancel-flags*)
  (format t "Provider ready.~%~%"))

(defun demonstrate-file-search ()
  "Demonstrate streaming file search with progress updates."
  (format t "~&=== Streaming File Search ===~%~%")

  (let* ((call-id (generate-call-id))
         (call (make-tool-call :call-id call-id
                               :tool-name "file_search"
                               :provider-id "filesystem-provider"
                               :args (list :pattern "*.py"
                                           :directory "/project"))))

    (format t "Executing file search...~%~%")

    ;; Create handler with callbacks
    (let ((handler (make-streaming-handler
                    :on-progress (lambda (data)
                                   (format t "  Progress: ~D% - ~A~%"
                                           (getf data :percentage)
                                           (getf data :status)))
                    :on-output (lambda (data)
                                 (when (getf data :matches-pattern)
                                   (format t "  Found: ~A~%"
                                           (getf data :file)))))))

      (let* ((frames (call-stream call))
             (result (process-stream handler frames)))

        (format t "~%Search complete!~%")
        (format t "  Total files found: ~A~%"
                (getf result :total-files))
        (format t "  Pattern: ~A~%"
                (getf result :pattern))))))

(defun demonstrate-code-analysis ()
  "Demonstrate streaming code analysis with step-by-step output."
  (format t "~&=== Streaming Code Analysis ===~%~%")

  (let* ((call-id (generate-call-id))
         (call (make-tool-call :call-id call-id
                               :tool-name "code_analysis"
                               :provider-id "analyzer-provider"
                               :args (list :code "def calculate_total(items):\n    return sum(i.price for i in items)"))))

    (format t "Analyzing code...~%~%")

    (let ((handler (make-streaming-handler
                    :on-progress (lambda (data)
                                   (format t "  [~3D%] ~A~%"
                                           (getf data :percentage)
                                           (getf data :status)))
                    :on-output (lambda (data)
                                 (format t "        ~A: ~S~%"
                                         (getf data :step)
                                         (getf data :result))))))

      (let* ((frames (call-stream call))
             (result (process-stream handler frames)))

        (format t "~%Analysis complete!~%")
        (format t "  Overall score: ~A/10~%"
                (getf result :overall-score))))))

(defun demonstrate-cancellation ()
  "Demonstrate cancelling a long-running tool call."
  (format t "~&=== Cancellation Handling ===~%~%")

  (let* ((call-id (generate-call-id))
         (call (make-tool-call :call-id call-id
                               :tool-name "long_computation"
                               :provider-id "compute-provider"
                               :args (list :iterations 20))))

    (format t "Starting long computation (will cancel after 3 iterations)...~%~%")

    ;; Mark as active and schedule cancellation
    (mark-active call-id)

    (let ((handler (make-streaming-handler
                    :on-progress (lambda (data)
                                   (format t "  Progress: ~D% - ~A~%"
                                           (getf data :percentage)
                                           (getf data :status))))))

      ;; Get frames and cancel after 3
      (let ((frames nil)
            (frame-count 0))

        (dolist (frame (stream-long-computation call))
          (push frame frames)
          (incf frame-count)

          ;; Cancel after 3 progress frames
          (when (and (= frame-count 3)
                     (eq (tool-frame-frame-type frame) :progress))
            (format t "~%  Requesting cancellation...~%")
            (let ((cancel-result (request-cancel call-id)))
              (format t "  Cancel result: ~A~%~%"
                      (cancel-result-message cancel-result)))))

        (setf frames (nreverse frames))

        (let ((result (process-stream handler frames)))
          (if (streaming-handler-cancelled handler)
              (progn
                (format t "~%Computation was cancelled!~%")
                (format t "  Completed iterations: ~A~%"
                        (getf result :completed-iterations))
                (format t "  Partial result: ~A~%"
                        (getf result :partial-result)))
              (format t "~%Computation completed (cancellation failed).~%")))))))

(defun demonstrate-error-handling ()
  "Demonstrate error handling for unknown tools."
  (format t "~&=== Error Handling ===~%~%")

  (let* ((call-id (generate-call-id))
         (call (make-tool-call :call-id call-id
                               :tool-name "nonexistent_tool"
                               :provider-id "unknown-provider"
                               :args nil)))

    (format t "Calling unknown tool...~%~%")

    (let ((handler (make-streaming-handler
                    :on-error (lambda (data)
                                (format t "  ERROR: ~A~%"
                                        (getf data :error))))))

      (let ((frames (call-stream call)))
        (process-stream handler frames)
        (format t "  Result: Error handled gracefully~%")))))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete tool streaming demonstration."

  (format t "~&==============================================~%")
  (format t "   Tool Streaming Demonstration~%")
  (format t "==============================================~%~%")

  ;; Setup
  (setup-provider)

  ;; File search
  (demonstrate-file-search)
  (format t "~%")

  ;; Code analysis
  (demonstrate-code-analysis)
  (format t "~%")

  ;; Cancellation
  (demonstrate-cancellation)
  (format t "~%")

  ;; Error handling
  (demonstrate-error-handling)

  (format t "~%==============================================~%")
  (format t "   Demo Complete~%")
  (format t "==============================================~%~%")

  (format t "Key takeaways:~%")
  (format t "1. Use call-stream for tools that produce incremental output~%")
  (format t "2. Frame types: :progress, :output, :result, :error, :cancelled~%")
  (format t "3. Register callbacks for on-progress and on-output events~%")
  (format t "4. Use request-cancel to abort long-running operations~%")
  (format t "5. Check for :cancelled frame type in your stream handler~%~%")

  (format t "For REPL exploration:~%")
  (format t "  (in-package :tool-streaming)~%")
  (format t "  (call-stream (make-tool-call :call-id \"test\" :tool-name \"file_search\" :args '(:pattern \"*.lisp\")))~%"))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (tool_streaming_example.py pattern):

    from enum import Enum
    from dataclasses import dataclass, field
    from typing import Any, Generator, Optional, Callable
    import time
    import uuid
    import threading

    class FrameType(Enum):
        PROGRESS = 1
        OUTPUT = 2
        RESULT = 3
        ERROR = 4
        CANCELLED = 5

    @dataclass
    class ToolFrame:
        call_id: str
        frame_type: FrameType
        sequence: int
        data: dict[str, Any]
        timestamp_ms: int = field(default_factory=lambda: int(time.time() * 1000))

    @dataclass
    class ToolCall:
        call_id: str
        tool_name: str
        provider_id: str
        args: dict[str, Any]
        worktree_id: Optional[str] = None
        timeout_ms: int = 30000

    class MockToolClient:
        def call_stream(self, call: dict) -> Generator[ToolFrame, None, None]:
            # Returns generator of frames
            ...

        def cancel(self, call: dict) -> CancelResult:
            # Cancels active call
            ...

    class StreamingToolHandler:
        def __init__(self, on_progress=None, on_output=None, on_error=None):
            self.on_progress = on_progress
            self.on_output = on_output
            self.on_error = on_error
            self.outputs = []
            self.result = None
            self.cancelled = False

        def process_stream(self, frames):
            for frame in frames:
                self._handle_frame(frame)
                if frame.frame_type in (RESULT, ERROR, CANCELLED):
                    break
            return self.result

CL Advantages Demonstrated:
1. Structures provide clean data representation
2. CLOS generic functions could extend frame handling
3. Conditions/restarts for sophisticated error recovery
4. Hash tables for tracking active calls
5. Dynamic callbacks via function slots
|#

;;;; End of tool-streaming.lisp
