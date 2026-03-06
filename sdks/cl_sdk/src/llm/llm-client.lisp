;;;; llm-client.lisp - Base LLM client interface and condition hierarchy
;;;;
;;;; Provides the abstract interface for LLM clients used by SW4RM agents.
;;;; Implementations include Groq, Anthropic, and mock clients for testing.
;;;;
;;;; Ported from sdks/py_sdk/sw4rm/llm/client.py

(in-package #:sw4rm-sdk)

;;;; ====================================================================
;;;; LLM Condition Hierarchy
;;;; ====================================================================
;;;;
;;;; All LLM-specific conditions inherit from sw4rm-error to integrate
;;;; with the existing error handling infrastructure.

(define-condition llm-error (sw4rm-error)
  ()
  (:documentation "Base condition for all LLM client errors.

Signaled when an LLM API call fails for any reason not covered by a
more specific subcondition.  Inherits message and error-code from
sw4rm-error.")
  (:report (lambda (condition stream)
             (format stream "LLM Error: ~A"
                     (sw4rm-error-message condition)))))

(define-condition llm-authentication-error (llm-error)
  ()
  (:documentation "Signaled when LLM API authentication fails.

Common causes:
  - Invalid API key
  - Missing credentials (no env var, no dotfile, no explicit key)
  - Expired or revoked key
  - Billing / credit balance issues")
  (:report (lambda (condition stream)
             (format stream "LLM Authentication Error: ~A"
                     (sw4rm-error-message condition)))))

(define-condition llm-rate-limit-error (llm-error)
  ()
  (:documentation "Signaled when an LLM API rate limit is exceeded (HTTP 429).

The caller should implement exponential backoff or use the built-in
token-bucket rate limiter to avoid hitting this condition.")
  (:report (lambda (condition stream)
             (format stream "LLM Rate Limit Error: ~A"
                     (sw4rm-error-message condition)))))

(define-condition llm-timeout-error (llm-error)
  ()
  (:documentation "Signaled when an LLM API request times out.

Consider increasing the timeout or simplifying the prompt.")
  (:report (lambda (condition stream)
             (format stream "LLM Timeout Error: ~A"
                     (sw4rm-error-message condition)))))

(define-condition llm-context-length-error (llm-error)
  ()
  (:documentation "Signaled when the prompt exceeds the model's context length.

Common causes:
  - Prompt text is too long for the selected model's context window
  - System prompt plus user prompt combined exceed the limit

Consider truncating the prompt or using a model with a larger context window.")
  (:report (lambda (condition stream)
             (format stream "LLM Context Length Error: ~A"
                     (sw4rm-error-message condition)))))

;;;; ====================================================================
;;;; LLM Response
;;;; ====================================================================
;;;;
;;;; Responses are plists with the following keys:
;;;;   :content       -- string, the generated text
;;;;   :model         -- string, the model that generated the response
;;;;   :usage         -- plist (:input-tokens N :output-tokens N) or NIL
;;;;   :metadata      -- plist of additional metadata, or NIL
;;;;
;;;; This keeps things simple and idiomatic for Common Lisp without
;;;; requiring a dedicated struct or class.

(defun make-llm-response (&key content model usage metadata)
  "Construct an LLM response plist.

Args:
  content:  String, the generated text content.
  model:    String, the model that produced the response.
  usage:    Plist (:input-tokens N :output-tokens N) or NIL.
  metadata: Plist of additional response metadata, or NIL.

Returns:
  A plist representing the LLM response."
  (list :content (or content "")
        :model (or model "unknown")
        :usage usage
        :metadata metadata))

(defun llm-response-content (response)
  "Extract the content string from an LLM response plist.

Args:
  response: A plist returned by make-llm-response or llm-query.

Returns:
  The content string."
  (getf response :content))

(defun llm-response-model (response)
  "Extract the model name from an LLM response plist.

Args:
  response: A plist returned by make-llm-response or llm-query.

Returns:
  The model name string."
  (getf response :model))

(defun llm-response-usage (response)
  "Extract the usage plist from an LLM response plist.

Args:
  response: A plist returned by make-llm-response or llm-query.

Returns:
  A plist (:input-tokens N :output-tokens N) or NIL."
  (getf response :usage))

;;;; ====================================================================
;;;; Base LLM Client Class
;;;; ====================================================================

(defclass llm-client ()
  ((default-model
    :initarg :default-model
    :accessor llm-client-default-model
    :type string
    :documentation "Default model identifier for API calls.")
   (api-key
    :initarg :api-key
    :accessor llm-client-api-key
    :initform nil
    :type (or string null)
    :documentation "API key for authentication."))
  (:documentation "Abstract base class for LLM clients.

All LLM client implementations should inherit from this class and
implement the llm-query generic function.  This allows SW4RM agents
to be provider-agnostic.

Implementations:
  groq-client       -- Uses Groq API (OpenAI-compatible endpoint)
  anthropic-client  -- Uses Anthropic Claude API
  mock-llm-client   -- For testing without API calls"))

;;;; ====================================================================
;;;; Generic Functions
;;;; ====================================================================

(defgeneric llm-query (client prompt &key system-prompt max-tokens temperature model)
  (:documentation "Send a query to the LLM and get a complete response.

Args:
  client:        An llm-client instance.
  prompt:        String, the user prompt/query to send.
  system-prompt: String or NIL, optional system prompt for context.
  max-tokens:    Integer, maximum tokens to generate (default: 4096).
  temperature:   Float, sampling temperature 0.0-2.0 (default: 1.0).
  model:         String or NIL, override the default model.

Returns:
  A plist representing the LLM response:
    (:content \"...\" :model \"...\" :usage (:input-tokens N :output-tokens N))

Signals:
  llm-error:                On general API errors.
  llm-authentication-error: On authentication failures.
  llm-rate-limit-error:     When rate limits are exceeded.
  llm-timeout-error:        When the request times out."))

;;;; ====================================================================
;;;; Utility Functions
;;;; ====================================================================

(defun estimate-tokens (prompt &optional system-prompt)
  "Rough token estimate based on character count (~4 chars per token).

Args:
  prompt:        String, the user prompt.
  system-prompt: String or NIL, optional system prompt.

Returns:
  Integer, estimated token count (minimum 100)."
  (let ((total (length prompt)))
    (when system-prompt
      (incf total (length system-prompt)))
    (max (floor total 4) 100)))

(defun load-key-from-file (filename)
  "Load an API key from a dotfile in the user's home directory.

Reads the first line of ~/FILENAME, strips whitespace, and returns
the result.  Returns NIL if the file does not exist or cannot be read.

Args:
  filename: String, the dotfile name (e.g., \".groq\", \".anthropic\").

Returns:
  String containing the API key, or NIL."
  (let ((path (merge-pathnames filename (user-homedir-pathname))))
    (handler-case
        (when (probe-file path)
          (let ((text (uiop:read-file-string path)))
            (string-trim '(#\Space #\Tab #\Newline #\Return) text)))
      (error () nil))))
