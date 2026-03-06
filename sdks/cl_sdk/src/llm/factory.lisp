;;;; factory.lisp - Factory function for creating LLM clients
;;;;
;;;; Provides a simple way to create the appropriate LLM client based on
;;;; environment configuration or explicit parameters.
;;;;
;;;; Ported from sdks/py_sdk/sw4rm/llm/factory.py

(in-package #:sw4rm-sdk)

;;;; ====================================================================
;;;; Factory Function
;;;; ====================================================================

(defun create-llm-client (&key client-type model api-key)
  "Create an LLM client based on environment or explicit type.

This factory function creates the appropriate LLM client based on:
  1. Explicit CLIENT-TYPE parameter
  2. LLM_CLIENT_TYPE environment variable
  3. Default to \"mock\"

Environment variables:
  LLM_CLIENT_TYPE:    \"groq\", \"anthropic\", or \"mock\" (default: \"mock\")
  LLM_DEFAULT_MODEL:  Default model to use

Args:
  client-type: String or NIL, override client type.
               Valid values: \"groq\", \"anthropic\", \"mock\".
  model:       String or NIL, default model to use.
  api-key:     String or NIL, API key for the client.

Returns:
  An llm-client instance.

Signals:
  sw4rm-error: If an invalid client-type is specified.
  llm-authentication-error: If client initialization fails due to
                            missing credentials.

Example:
  ;; Auto-detect from environment
  (create-llm-client)

  ;; Explicit Groq client
  (create-llm-client :client-type \"groq\" :api-key \"gsk_...\")

  ;; Mock client for testing
  (create-llm-client :client-type \"mock\")

  ;; Via environment variables
  ;; (setf (uiop:getenv \"LLM_CLIENT_TYPE\") \"anthropic\")
  (create-llm-client)"
  (let* ((resolved-type (or client-type
                            (uiop:getenv "LLM_CLIENT_TYPE")
                            "mock"))
         (type-lower (string-downcase resolved-type))
         (resolved-model (or model
                             (uiop:getenv "LLM_DEFAULT_MODEL"))))
    (cond
      ((string= type-lower "mock")
       (make-mock-llm-client :model (or resolved-model "mock-model")))

      ((string= type-lower "groq")
       (apply #'make-groq-client
              (append
               (when resolved-model (list :model resolved-model))
               (when api-key (list :api-key api-key)))))

      ((string= type-lower "anthropic")
       (apply #'make-anthropic-client
              (append
               (when resolved-model (list :model resolved-model))
               (when api-key (list :api-key api-key)))))

      (t
       (error 'sw4rm-error
              :message (format nil "Unknown LLM client type: ~A. ~
                                    Valid types: \"groq\", \"anthropic\", \"mock\""
                               resolved-type))))))
