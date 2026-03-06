;;;; groq-client.lisp - Groq LLM client for SW4RM agents
;;;;
;;;; Thin wrapper around the Groq REST API (OpenAI-compatible endpoint).
;;;; No tool-calling or diagnostic mode -- just prompt in, text out, with
;;;; rate limiting.
;;;;
;;;; Credentials (in order):
;;;;   1. :api-key constructor parameter
;;;;   2. GROQ_API_KEY environment variable
;;;;   3. ~/.groq file (plain text, first line)
;;;;
;;;; Ported from sdks/py_sdk/sw4rm/llm/groq.py

(in-package #:sw4rm-sdk)

;;;; ====================================================================
;;;; Constants
;;;; ====================================================================

(defparameter +groq-default-model+ "llama-3.3-70b-versatile"
  "Default Groq model used when no model is specified.")

(defparameter +groq-api-url+ "https://api.groq.com/openai/v1/chat/completions"
  "Groq chat completions API endpoint.")

;;;; ====================================================================
;;;; Groq Client Class
;;;; ====================================================================

(defclass groq-client (llm-client)
  ((timeout
    :initarg :timeout
    :accessor groq-client-timeout
    :initform 120
    :type integer
    :documentation "HTTP request timeout in seconds.")
   (rate-limiter
    :accessor groq-client-rate-limiter
    :documentation "Token-bucket rate limiter instance."))
  (:documentation "LLM client for the Groq API.

Credentials resolved from (in order):
  1. :api-key constructor argument
  2. GROQ_API_KEY environment variable
  3. ~/.groq file (plain text, first line)

Environment variables:
  GROQ_API_KEY:         API key override
  GROQ_DEFAULT_MODEL:   Default model override"))

(defun make-groq-client (&key api-key model timeout)
  "Create a Groq LLM client.

Args:
  api-key: String or NIL, explicit API key.
  model:   String or NIL, default model (falls back to GROQ_DEFAULT_MODEL
           env var, then to llama-3.3-70b-versatile).
  timeout: Integer or NIL, HTTP timeout in seconds (default: 120).

Returns:
  A groq-client instance.

Signals:
  llm-authentication-error: If no API key can be resolved."
  (let* ((resolved-model (or model
                             (uiop:getenv "GROQ_DEFAULT_MODEL")
                             +groq-default-model+))
         (env-key (let ((k (uiop:getenv "GROQ_API_KEY")))
                    (when (and k (plusp (length k)))
                      (string-trim '(#\Space #\Tab #\Newline #\Return) k))))
         (resolved-key (or api-key
                           env-key
                           (load-key-from-file ".groq")))
         (client (make-instance 'groq-client
                                :default-model resolved-model
                                :api-key resolved-key)))
    (unless resolved-key
      (error 'llm-authentication-error
             :message "No Groq API key. Set GROQ_API_KEY, pass :api-key, or create ~/.groq"))
    (when timeout
      (setf (groq-client-timeout client) timeout))
    (setf (groq-client-rate-limiter client) (get-global-rate-limiter))
    client))

;;;; ====================================================================
;;;; HTTP Request Helpers
;;;; ====================================================================

(defun %groq-build-request-body (model messages max-tokens temperature)
  "Build the JSON request body for a Groq chat completion.

Args:
  model:       String, model identifier.
  messages:    List of (:role \"...\" :content \"...\") plists.
  max-tokens:  Integer, maximum tokens to generate.
  temperature: Number, sampling temperature.

Returns:
  String, the JSON-encoded request body."
  (jojo:to-json
   (list :|model| model
         :|messages| (mapcar (lambda (msg)
                               (list :|role| (getf msg :role)
                                     :|content| (getf msg :content)))
                             messages)
         :|max_tokens| max-tokens
         :|temperature| (coerce temperature 'single-float))))

(defun %groq-parse-response (body)
  "Parse a Groq chat completion JSON response into an LLM response plist.

Args:
  body: String, the JSON response body.

Returns:
  A plist (:content ... :model ... :usage ...).

Signals:
  llm-error: If the response cannot be parsed or has no choices."
  (let* ((parsed (jojo:parse body))
         (choices (getf parsed :|choices|))
         (model (getf parsed :|model|)))
    (unless (and choices (listp choices) (plusp (length choices)))
      (error 'llm-error
             :message (format nil "Groq API returned no choices: ~A" body)))
    (let* ((choice (first choices))
           (message (getf choice :|message|))
           (content (or (getf message :|content|) ""))
           (usage-data (getf parsed :|usage|))
           (usage (when usage-data
                    (list :input-tokens (or (getf usage-data :|prompt_tokens|) 0)
                          :output-tokens (or (getf usage-data :|completion_tokens|) 0)))))
      (make-llm-response :content content
                         :model (or model "unknown")
                         :usage usage))))

(defun %groq-handle-http-error (status-code body)
  "Signal the appropriate condition for an HTTP error from Groq.

Args:
  status-code: Integer, the HTTP status code.
  body:        String, the response body.

Signals:
  llm-authentication-error:  On 401 or 403.
  llm-rate-limit-error:      On 429.
  llm-timeout-error:         On 408 or 504.
  llm-context-length-error:  When error code is context_length_exceeded.
  llm-error:                 On all other error codes."
  (cond
    ((or (= status-code 401) (= status-code 403))
     (error 'llm-authentication-error
            :message (format nil "Groq auth failed (HTTP ~D): ~A" status-code body)))
    ((= status-code 429)
     (error 'llm-rate-limit-error
            :message (format nil "Groq rate limit exceeded (HTTP 429): ~A" body)))
    ((or (= status-code 408) (= status-code 504))
     (error 'llm-timeout-error
            :message (format nil "Groq request timed out (HTTP ~D): ~A" status-code body)))
    ;; Groq uses OpenAI error codes -- check for context_length_exceeded
    ((search "context_length_exceeded" body)
     (error 'llm-context-length-error
            :message (format nil "Groq context length exceeded (HTTP ~D): ~A" status-code body)))
    (t
     (error 'llm-error
            :message (format nil "Groq API error (HTTP ~D): ~A" status-code body)))))

;;;; ====================================================================
;;;; LLM-QUERY Implementation
;;;; ====================================================================

(defmethod llm-query ((client groq-client) prompt
                      &key system-prompt (max-tokens 4096) (temperature 1.0) model)
  "Send a query to the Groq API and return a complete response.

Acquires tokens from the rate limiter before making the HTTP call.
On a 429 response, records the rate limit event before signaling.
On success, records the success for adaptive recovery.

Args:
  client:        A groq-client instance.
  prompt:        String, the user prompt.
  system-prompt: String or NIL, optional system prompt.
  max-tokens:    Integer, maximum tokens to generate (default: 4096).
  temperature:   Float, sampling temperature (default: 1.0).
  model:         String or NIL, override the default model.

Returns:
  A plist (:content ... :model ... :usage ...).

Signals:
  llm-authentication-error: On 401/403.
  llm-rate-limit-error:     On 429.
  llm-timeout-error:        On request timeout.
  llm-error:                On other API errors."
  (let* ((use-model (or model (llm-client-default-model client)))
         (estimated (estimate-tokens prompt system-prompt))
         (rate-limiter (groq-client-rate-limiter client))
         (messages (append
                    (when system-prompt
                      (list (list :role "system" :content system-prompt)))
                    (list (list :role "user" :content prompt))))
         (request-body (%groq-build-request-body use-model messages max-tokens temperature)))
    ;; Acquire rate-limit tokens
    (acquire rate-limiter estimated)
    ;; Make HTTP request -- catch network errors separately from HTTP errors
    (multiple-value-bind (body status-code)
        (handler-case
            (drakma:http-request +groq-api-url+
                                 :method :post
                                 :content-type "application/json"
                                 :additional-headers
                                 `(("Authorization" . ,(format nil "Bearer ~A"
                                                               (llm-client-api-key client))))
                                 :content request-body
                                 :connection-timeout (groq-client-timeout client)
                                 :want-stream nil)
          (error (e)
            ;; Network-level errors from drakma/usocket.
            ;; Heuristic: if the printed condition mentions "timeout", treat
            ;; it as a timeout; otherwise treat it as a generic LLM error.
            (let ((msg (format nil "~A" e)))
              (if (search "timeout" (string-downcase msg))
                  (error 'llm-timeout-error
                         :message (format nil "Groq request timed out: ~A" msg))
                  (error 'llm-error
                         :message (format nil "Groq network error: ~A" msg))))))
      ;; Ensure body is a string
      (let ((body-str (if (typep body '(simple-array (unsigned-byte 8) (*)))
                          (babel:octets-to-string body :encoding :utf-8)
                          (if (stringp body) body (format nil "~A" body)))))
        (unless (= status-code 200)
          ;; Record rate limit before signaling
          (when (= status-code 429)
            (record-rate-limit rate-limiter))
          (%groq-handle-http-error status-code body-str))
        ;; Success
        (record-success rate-limiter)
        (%groq-parse-response body-str)))))
