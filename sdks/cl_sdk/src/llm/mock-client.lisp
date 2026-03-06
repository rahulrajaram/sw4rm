;;;; mock-client.lisp - Mock LLM client for testing
;;;;
;;;; Provides deterministic responses without making actual API calls.
;;;; Tracks call count and history for test assertions.
;;;;
;;;; Ported from sdks/py_sdk/sw4rm/llm/mock.py

(in-package #:sw4rm-sdk)

;;;; ====================================================================
;;;; Mock LLM Client Class
;;;; ====================================================================

(defclass mock-llm-client (llm-client)
  ((responses
    :initarg :responses
    :accessor mock-client-responses
    :initform '("Mock response")
    :type list
    :documentation "List of response strings to return in order (cycles).")
   (response-generator
    :initarg :response-generator
    :accessor mock-client-response-generator
    :initform nil
    :type (or function null)
    :documentation "Optional function (prompt) -> string to generate responses.")
   (call-count
    :accessor mock-client-call-count
    :initform 0
    :type integer
    :documentation "Number of queries made to this client.")
   (call-history
    :accessor mock-client-call-history
    :initform nil
    :type list
    :documentation "List of plists recording each call's parameters.
Each entry is (:prompt ... :system-prompt ... :max-tokens ... :temperature ... :model ...).")
   (response-index
    :accessor mock-client-response-index
    :initform 0
    :type integer
    :documentation "Current index into the responses list (wraps around)."))
  (:documentation "Mock LLM client for testing without API calls.

Returns configurable responses for testing purposes.  Tracks all
calls made for assertion in tests.

Example:
  ;; Simple usage -- returns from the responses list
  (let ((client (make-mock-llm-client :responses '(\"Hello\" \"World\"))))
    (llm-query client \"test\")
    ;; => (:content \"Hello\" :model \"mock-model\" :usage ...)
    (llm-query client \"test2\")
    ;; => (:content \"World\" :model \"mock-model\" :usage ...)
    (mock-client-call-count client))
    ;; => 2

  ;; With a response generator
  (let ((client (make-mock-llm-client
                  :response-generator (lambda (prompt) (format nil \"Echo: ~A\" prompt)))))
    (llm-query client \"ping\"))
    ;; => (:content \"Echo: ping\" :model \"mock-model\" :usage ...)"))

(defun make-mock-llm-client (&key (model "mock-model")
                                   (responses '("Mock response"))
                                   response-generator)
  "Create a mock LLM client for testing.

Args:
  model:              String, model name to return in responses (default: \"mock-model\").
  responses:          List of strings to return in order, cycling (default: (\"Mock response\")).
  response-generator: Function (prompt-string) -> string, or NIL.
                      When provided, takes precedence over the responses list.

Returns:
  A mock-llm-client instance."
  (make-instance 'mock-llm-client
                 :default-model model
                 :api-key "mock-key"
                 :responses responses
                 :response-generator response-generator))

;;;; ====================================================================
;;;; Reset
;;;; ====================================================================

(defun mock-client-reset (client)
  "Reset call count, history, and response index of a mock client.

Args:
  client: A mock-llm-client instance."
  (setf (mock-client-call-count client) 0)
  (setf (mock-client-call-history client) nil)
  (setf (mock-client-response-index client) 0))

;;;; ====================================================================
;;;; LLM-QUERY Implementation
;;;; ====================================================================

(defmethod llm-query ((client mock-llm-client) prompt
                      &key system-prompt (max-tokens 4096) (temperature 1.0) model)
  "Return a mock response without making any API calls.

Records the call parameters in the client's call-history for later
inspection in tests.

Args:
  client:        A mock-llm-client instance.
  prompt:        String, the user prompt (recorded in history).
  system-prompt: String or NIL, optional system prompt (recorded in history).
  max-tokens:    Integer, max tokens (recorded in history).
  temperature:   Float, temperature (recorded in history).
  model:         String or NIL, model override.

Returns:
  A plist (:content ... :model ... :usage ... :metadata ...)."
  (let ((use-model (or model (llm-client-default-model client))))
    ;; Record the call
    (incf (mock-client-call-count client))
    (push (list :prompt prompt
                :system-prompt system-prompt
                :max-tokens max-tokens
                :temperature temperature
                :model use-model)
          (mock-client-call-history client))
    ;; Generate response
    (let ((content
            (cond
              ;; Response generator takes precedence
              ((mock-client-response-generator client)
               (funcall (mock-client-response-generator client) prompt))
              ;; Cycle through responses list
              ((mock-client-responses client)
               (let* ((responses (mock-client-responses client))
                      (idx (mod (mock-client-response-index client)
                                (length responses)))
                      (text (nth idx responses)))
                 (incf (mock-client-response-index client))
                 text))
              ;; Default fallback
              (t
               (format nil "Mock response to: ~A"
                       (subseq prompt 0 (min 100 (length prompt))))))))
      (make-llm-response
       :content content
       :model use-model
       :usage (list :input-tokens (max (floor (length prompt) 4) 1)
                    :output-tokens (max (floor (length content) 4) 1))
       :metadata (list :mock t
                       :call-count (mock-client-call-count client))))))
