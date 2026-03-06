;;;; anthropic-client.lisp - Anthropic Claude LLM client for SW4RM agents
;;;;
;;;; Thin wrapper around the Anthropic Messages API.  Handles the
;;;; system-message normalization (Anthropic uses a top-level "system"
;;;; param, not an in-band system message).
;;;;
;;;; Credentials (in order):
;;;;   1. :api-key constructor parameter
;;;;   2. ANTHROPIC_API_KEY environment variable
;;;;   3. ~/.anthropic file (plain text, first line)
;;;;
;;;; Ported from sdks/py_sdk/sw4rm/llm/anthropic.py

(in-package #:sw4rm-sdk)

;;;; ====================================================================
;;;; Constants
;;;; ====================================================================

(defparameter +anthropic-default-model+ "claude-sonnet-4-20250514"
  "Default Anthropic model used when no model is specified.")

(defparameter +anthropic-api-url+ "https://api.anthropic.com/v1/messages"
  "Anthropic Messages API endpoint.")

(defparameter +anthropic-api-version+ "2023-06-01"
  "Anthropic API version string sent via the anthropic-version header.")

;;;; ====================================================================
;;;; Anthropic Client Class
;;;; ====================================================================

(defclass anthropic-client (llm-client)
  ((timeout
    :initarg :timeout
    :accessor anthropic-client-timeout
    :initform 300
    :type integer
    :documentation "HTTP request timeout in seconds.")
   (rate-limiter
    :accessor anthropic-client-rate-limiter
    :documentation "Token-bucket rate limiter instance."))
  (:documentation "LLM client for the Anthropic Claude API.

Credentials resolved from (in order):
  1. :api-key constructor argument
  2. ANTHROPIC_API_KEY environment variable
  3. ~/.anthropic file (plain text, first line)

Environment variables:
  ANTHROPIC_API_KEY:         API key override
  ANTHROPIC_DEFAULT_MODEL:   Default model override"))

(defun make-anthropic-client (&key api-key model timeout)
  "Create an Anthropic Claude LLM client.

Args:
  api-key: String or NIL, explicit API key.
  model:   String or NIL, default model (falls back to ANTHROPIC_DEFAULT_MODEL
           env var, then to claude-sonnet-4-20250514).
  timeout: Integer or NIL, HTTP timeout in seconds (default: 300).

Returns:
  An anthropic-client instance.

Signals:
  llm-authentication-error: If no API key can be resolved."
  (let* ((resolved-model (or model
                             (uiop:getenv "ANTHROPIC_DEFAULT_MODEL")
                             +anthropic-default-model+))
         (env-key (let ((k (uiop:getenv "ANTHROPIC_API_KEY")))
                    (when (and k (plusp (length k)))
                      (string-trim '(#\Space #\Tab #\Newline #\Return) k))))
         (resolved-key (or api-key
                           env-key
                           (load-key-from-file ".anthropic")))
         (client (make-instance 'anthropic-client
                                :default-model resolved-model
                                :api-key resolved-key)))
    (unless resolved-key
      (error 'llm-authentication-error
             :message "No Anthropic API key. Set ANTHROPIC_API_KEY, pass :api-key, or create ~/.anthropic"))
    (when timeout
      (setf (anthropic-client-timeout client) timeout))
    (setf (anthropic-client-rate-limiter client) (get-global-rate-limiter))
    client))

;;;; ====================================================================
;;;; HTTP Request Helpers
;;;; ====================================================================

(defun %anthropic-build-request-body (model messages max-tokens temperature
                                      &optional system-prompt)
  "Build the JSON request body for an Anthropic messages call.

The Anthropic API takes system as a top-level field, not as a message
in the messages array.

Args:
  model:         String, model identifier.
  messages:      List of (:role \"...\" :content \"...\") plists.
  max-tokens:    Integer, maximum tokens to generate.
  temperature:   Number, sampling temperature.
  system-prompt: String or NIL, system prompt (sent as top-level field).

Returns:
  String, the JSON-encoded request body."
  (let ((body (list :|model| model
                    :|messages| (mapcar (lambda (msg)
                                         (list :|role| (getf msg :role)
                                               :|content| (getf msg :content)))
                                       messages)
                    :|max_tokens| max-tokens
                    :|temperature| (coerce temperature 'single-float))))
    (when system-prompt
      (setf body (append body (list :|system| system-prompt))))
    (jojo:to-json body)))

(defun %anthropic-parse-response (body)
  "Parse an Anthropic messages JSON response into an LLM response plist.

Extracts text from content blocks and collects usage statistics.

Args:
  body: String, the JSON response body.

Returns:
  A plist (:content ... :model ... :usage ...).

Signals:
  llm-error: If the response cannot be parsed."
  (let* ((parsed (jojo:parse body))
         (model (getf parsed :|model|))
         (content-blocks (getf parsed :|content|))
         (usage-data (getf parsed :|usage|)))
    ;; Extract text from content blocks
    (let* ((text-parts
             (loop for block in (or content-blocks '())
                   for block-type = (getf block :|type|)
                   for text = (getf block :|text|)
                   when (and (equal block-type "text") text)
                     collect text))
           (content (string-trim '(#\Space #\Tab #\Newline #\Return)
                                 (format nil "~{~A~}" text-parts)))
           ;; Extract usage
           (input-tokens (if usage-data
                             (or (getf usage-data :|input_tokens|) 0)
                             0))
           (output-tokens (if usage-data
                              (or (getf usage-data :|output_tokens|) 0)
                              0))
           (usage (list :input-tokens input-tokens
                        :output-tokens output-tokens)))
      (make-llm-response :content content
                         :model (or model "unknown")
                         :usage usage))))

(defun %anthropic-handle-http-error (status-code body)
  "Signal the appropriate condition for an HTTP error from Anthropic.

Args:
  status-code: Integer, the HTTP status code.
  body:        String, the response body.

Signals:
  llm-authentication-error:  On 401 or 403, or billing-related errors.
  llm-rate-limit-error:      On 429.
  llm-timeout-error:         On 408 or 504.
  llm-context-length-error:  On invalid_request_error mentioning context/token limits.
  llm-error:                 On all other error codes."
  (let ((lower-body (string-downcase body)))
    (cond
      ((or (= status-code 401) (= status-code 403))
       (error 'llm-authentication-error
              :message (format nil "Anthropic auth failed (HTTP ~D): ~A" status-code body)))
      ((= status-code 429)
       (error 'llm-rate-limit-error
              :message (format nil "Anthropic rate limit exceeded (HTTP 429): ~A" body)))
      ((or (= status-code 408) (= status-code 504))
       (error 'llm-timeout-error
              :message (format nil "Anthropic request timed out (HTTP ~D): ~A" status-code body)))
      ;; Anthropic context length: invalid_request_error with context/token mention
      ((and (search "invalid_request_error" lower-body)
            (or (search "context" lower-body)
                (search "token" lower-body)))
       (error 'llm-context-length-error
              :message (format nil "Anthropic context length exceeded (HTTP ~D): ~A" status-code body)))
      ;; Check for billing errors in the body
      ((or (search "credit balance" lower-body)
           (search "billing" lower-body))
       (error 'llm-authentication-error
              :message (format nil "Anthropic billing error (HTTP ~D): ~A" status-code body)))
      (t
       (error 'llm-error
              :message (format nil "Anthropic API error (HTTP ~D): ~A" status-code body))))))

;;;; ====================================================================
;;;; LLM-QUERY Implementation
;;;; ====================================================================

(defmethod llm-query ((client anthropic-client) prompt
                      &key system-prompt (max-tokens 4096) (temperature 1.0) model)
  "Send a query to the Anthropic API and return a complete response.

Acquires tokens from the rate limiter before making the HTTP call.
On a 429 response, records the rate limit event before signaling.
On success, records the success for adaptive recovery.

The Anthropic API requires:
  - x-api-key header for authentication
  - anthropic-version header for API versioning
  - system prompt as a top-level field (not in messages array)

Args:
  client:        An anthropic-client instance.
  prompt:        String, the user prompt.
  system-prompt: String or NIL, optional system prompt (top-level field).
  max-tokens:    Integer, maximum tokens to generate (default: 4096).
  temperature:   Float, sampling temperature (default: 1.0).
  model:         String or NIL, override the default model.

Returns:
  A plist (:content ... :model ... :usage ...).

Signals:
  llm-authentication-error: On 401/403 or billing errors.
  llm-rate-limit-error:     On 429.
  llm-timeout-error:        On request timeout.
  llm-error:                On other API errors."
  (let* ((use-model (or model (llm-client-default-model client)))
         (estimated (estimate-tokens prompt system-prompt))
         (rate-limiter (anthropic-client-rate-limiter client))
         (messages (list (list :role "user" :content prompt)))
         (request-body (%anthropic-build-request-body
                        use-model messages max-tokens temperature system-prompt)))
    ;; Acquire rate-limit tokens
    (acquire rate-limiter estimated)
    ;; Make HTTP request -- catch network errors separately from HTTP errors
    (multiple-value-bind (body status-code)
        (handler-case
            (drakma:http-request +anthropic-api-url+
                                 :method :post
                                 :content-type "application/json"
                                 :additional-headers
                                 `(("x-api-key" . ,(llm-client-api-key client))
                                   ("anthropic-version" . ,+anthropic-api-version+))
                                 :content request-body
                                 :connection-timeout (anthropic-client-timeout client)
                                 :want-stream nil)
          (error (e)
            ;; Network-level errors from drakma/usocket.
            ;; Heuristic: if the printed condition mentions "timeout", treat
            ;; it as a timeout; otherwise treat it as a generic LLM error.
            (let ((msg (format nil "~A" e)))
              (if (search "timeout" (string-downcase msg))
                  (error 'llm-timeout-error
                         :message (format nil "Anthropic request timed out: ~A" msg))
                  (error 'llm-error
                         :message (format nil "Anthropic network error: ~A" msg))))))
      ;; Ensure body is a string
      (let ((body-str (if (typep body '(simple-array (unsigned-byte 8) (*)))
                          (babel:octets-to-string body :encoding :utf-8)
                          (if (stringp body) body (format nil "~A" body)))))
        (unless (= status-code 200)
          ;; Record rate limit before signaling
          (when (= status-code 429)
            (record-rate-limit rate-limiter))
          (%anthropic-handle-http-error status-code body-str))
        ;; Success
        (record-success rate-limiter)
        (%anthropic-parse-response body-str)))))
