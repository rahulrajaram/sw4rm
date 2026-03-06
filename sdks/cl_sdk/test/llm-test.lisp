;;;; llm-test.lisp - FiveAM tests for the LLM module
;;;;
;;;; Covers: mock client, rate limiter, factory, condition hierarchy,
;;;;         response helpers, and utility functions.
;;;;
;;;; Run with:
;;;;   (ql:quickload '(:sw4rm-sdk :fiveam))
;;;;   (load "test/llm-test.lisp")
;;;;   (fiveam:run! 'sw4rm-test::llm-suite)

(in-package :sw4rm-test)

(def-suite llm-suite :description "LLM client module tests"
  :in sw4rm-suite)
(in-suite llm-suite)


;;; =======================================================================
;;;  1. LLM Response Helpers
;;; =======================================================================

(def-suite llm-response-suite :description "LLM response plist helpers"
  :in llm-suite)
(in-suite llm-response-suite)

(test make-llm-response-defaults
  "make-llm-response with no args returns sensible defaults."
  (let ((resp (sw4rm-sdk:make-llm-response)))
    (is (string= "" (sw4rm-sdk:llm-response-content resp)))
    (is (string= "unknown" (sw4rm-sdk:llm-response-model resp)))
    (is (null (sw4rm-sdk:llm-response-usage resp)))))

(test make-llm-response-with-values
  "make-llm-response stores all provided values."
  (let* ((usage '(:input-tokens 10 :output-tokens 20))
         (resp (sw4rm-sdk:make-llm-response
                :content "Hello"
                :model "test-model"
                :usage usage
                :metadata '(:foo "bar"))))
    (is (string= "Hello" (sw4rm-sdk:llm-response-content resp)))
    (is (string= "test-model" (sw4rm-sdk:llm-response-model resp)))
    (is (equal usage (sw4rm-sdk:llm-response-usage resp)))))

(test llm-response-content-extraction
  "llm-response-content extracts content from a response plist."
  (let ((resp (sw4rm-sdk:make-llm-response :content "test content")))
    (is (string= "test content" (sw4rm-sdk:llm-response-content resp)))))

(test llm-response-model-extraction
  "llm-response-model extracts model name from a response plist."
  (let ((resp (sw4rm-sdk:make-llm-response :model "my-model")))
    (is (string= "my-model" (sw4rm-sdk:llm-response-model resp)))))


;;; =======================================================================
;;;  2. Utility Functions
;;; =======================================================================

(def-suite llm-util-suite :description "LLM utility functions"
  :in llm-suite)
(in-suite llm-util-suite)

(test estimate-tokens-minimum
  "estimate-tokens returns at least 100 even for short prompts."
  (is (= 100 (sw4rm-sdk:estimate-tokens "hi"))))

(test estimate-tokens-long-prompt
  "estimate-tokens returns roughly (length / 4) for long prompts."
  (let* ((prompt (make-string 1000 :initial-element #\x))
         (est (sw4rm-sdk:estimate-tokens prompt)))
    (is (= 250 est))))

(test estimate-tokens-with-system-prompt
  "estimate-tokens includes system prompt length in its estimate."
  (let* ((prompt (make-string 400 :initial-element #\x))
         (system (make-string 400 :initial-element #\y))
         (est (sw4rm-sdk:estimate-tokens prompt system)))
    (is (= 200 est))))


;;; =======================================================================
;;;  3. Condition Hierarchy
;;; =======================================================================

(def-suite llm-condition-suite :description "LLM condition hierarchy"
  :in llm-suite)
(in-suite llm-condition-suite)

(test llm-error-is-sw4rm-error
  "llm-error inherits from sw4rm-error."
  (handler-case
      (error 'sw4rm-sdk:llm-error :message "test")
    (sw4rm-sdk:sw4rm-error (c)
      (is (string= "test" (sw4rm-sdk:sw4rm-error-message c))))
    (:no-error (&rest args)
      (declare (ignore args))
      (fail "Expected llm-error to be signaled."))))

(test llm-authentication-error-is-llm-error
  "llm-authentication-error inherits from llm-error."
  (handler-case
      (error 'sw4rm-sdk:llm-authentication-error :message "bad key")
    (sw4rm-sdk:llm-error (c)
      (is (string= "bad key" (sw4rm-sdk:sw4rm-error-message c))))
    (:no-error (&rest args)
      (declare (ignore args))
      (fail "Expected llm-authentication-error to be signaled."))))

(test llm-rate-limit-error-is-llm-error
  "llm-rate-limit-error inherits from llm-error."
  (handler-case
      (error 'sw4rm-sdk:llm-rate-limit-error :message "429")
    (sw4rm-sdk:llm-error (c)
      (is (string= "429" (sw4rm-sdk:sw4rm-error-message c))))
    (:no-error (&rest args)
      (declare (ignore args))
      (fail "Expected llm-rate-limit-error to be signaled."))))

(test llm-timeout-error-is-llm-error
  "llm-timeout-error inherits from llm-error."
  (handler-case
      (error 'sw4rm-sdk:llm-timeout-error :message "timed out")
    (sw4rm-sdk:llm-error (c)
      (is (string= "timed out" (sw4rm-sdk:sw4rm-error-message c))))
    (:no-error (&rest args)
      (declare (ignore args))
      (fail "Expected llm-timeout-error to be signaled."))))

(test llm-error-report-includes-message
  "llm-error report format includes the error message."
  (handler-case
      (error 'sw4rm-sdk:llm-error :message "something failed")
    (sw4rm-sdk:llm-error (c)
      (let ((report (format nil "~A" c)))
        (is (search "something failed" report)
            "Report should contain the error message.")))))


;;; =======================================================================
;;;  4. Mock Client
;;; =======================================================================

(def-suite mock-client-suite :description "Mock LLM client tests"
  :in llm-suite)
(in-suite mock-client-suite)

(test mock-client-creation
  "make-mock-llm-client creates a client with the correct defaults."
  (let ((client (sw4rm-sdk:make-mock-llm-client)))
    (is (string= "mock-model" (sw4rm-sdk:llm-client-default-model client)))
    (is (string= "mock-key" (sw4rm-sdk:llm-client-api-key client)))
    (is (= 0 (sw4rm-sdk:mock-client-call-count client)))
    (is (null (sw4rm-sdk:mock-client-call-history client)))))

(test mock-client-custom-model
  "make-mock-llm-client with :model sets the default model."
  (let ((client (sw4rm-sdk:make-mock-llm-client :model "custom-model")))
    (is (string= "custom-model" (sw4rm-sdk:llm-client-default-model client)))))

(test mock-client-custom-responses
  "make-mock-llm-client with :responses stores the response list."
  (let ((client (sw4rm-sdk:make-mock-llm-client
                 :responses '("alpha" "beta"))))
    (is (equal '("alpha" "beta") (sw4rm-sdk:mock-client-responses client)))))

(test mock-client-single-query
  "llm-query on a mock client returns the first response."
  (let* ((client (sw4rm-sdk:make-mock-llm-client :responses '("Hello world")))
         (resp (sw4rm-sdk:llm-query client "test prompt")))
    (is (string= "Hello world" (sw4rm-sdk:llm-response-content resp)))
    (is (string= "mock-model" (sw4rm-sdk:llm-response-model resp)))
    (is (= 1 (sw4rm-sdk:mock-client-call-count client)))))

(test mock-client-response-cycling
  "llm-query cycles through the responses list."
  (let* ((client (sw4rm-sdk:make-mock-llm-client
                  :responses '("first" "second" "third")))
         (r1 (sw4rm-sdk:llm-query client "q1"))
         (r2 (sw4rm-sdk:llm-query client "q2"))
         (r3 (sw4rm-sdk:llm-query client "q3"))
         (r4 (sw4rm-sdk:llm-query client "q4")))
    (is (string= "first" (sw4rm-sdk:llm-response-content r1)))
    (is (string= "second" (sw4rm-sdk:llm-response-content r2)))
    (is (string= "third" (sw4rm-sdk:llm-response-content r3)))
    ;; Should cycle back to first
    (is (string= "first" (sw4rm-sdk:llm-response-content r4)))
    (is (= 4 (sw4rm-sdk:mock-client-call-count client)))))

(test mock-client-response-generator
  "llm-query uses response-generator when provided."
  (let* ((client (sw4rm-sdk:make-mock-llm-client
                  :response-generator (lambda (prompt)
                                        (format nil "Echo: ~A" prompt))))
         (resp (sw4rm-sdk:llm-query client "ping")))
    (is (string= "Echo: ping" (sw4rm-sdk:llm-response-content resp)))))

(test mock-client-call-history
  "llm-query records calls in the call-history."
  (let* ((client (sw4rm-sdk:make-mock-llm-client))
         (_ (sw4rm-sdk:llm-query client "prompt-1"
                                  :system-prompt "sys"
                                  :max-tokens 100
                                  :temperature 0.5)))
    (declare (ignore _))
    (let ((history (sw4rm-sdk:mock-client-call-history client)))
      (is (= 1 (length history)))
      (let ((call (first history)))
        (is (string= "prompt-1" (getf call :prompt)))
        (is (string= "sys" (getf call :system-prompt)))
        (is (= 100 (getf call :max-tokens)))
        (is (= 0.5 (getf call :temperature)))))))

(test mock-client-usage-tokens
  "llm-query returns usage with estimated input and output tokens."
  (let* ((client (sw4rm-sdk:make-mock-llm-client :responses '("short")))
         (resp (sw4rm-sdk:llm-query client "test prompt text")))
    (let ((usage (sw4rm-sdk:llm-response-usage resp)))
      (is (not (null usage)))
      (is (integerp (getf usage :input-tokens)))
      (is (integerp (getf usage :output-tokens)))
      (is (plusp (getf usage :input-tokens)))
      (is (plusp (getf usage :output-tokens))))))

(test mock-client-reset
  "mock-client-reset clears call count, history, and response index."
  (let ((client (sw4rm-sdk:make-mock-llm-client
                 :responses '("a" "b"))))
    ;; Make some calls
    (sw4rm-sdk:llm-query client "q1")
    (sw4rm-sdk:llm-query client "q2")
    (is (= 2 (sw4rm-sdk:mock-client-call-count client)))
    ;; Reset
    (sw4rm-sdk:mock-client-reset client)
    (is (= 0 (sw4rm-sdk:mock-client-call-count client)))
    (is (null (sw4rm-sdk:mock-client-call-history client)))
    ;; Should start from first response again
    (let ((resp (sw4rm-sdk:llm-query client "q3")))
      (is (string= "a" (sw4rm-sdk:llm-response-content resp))))))

(test mock-client-model-override
  "llm-query with :model overrides the default model in the response."
  (let* ((client (sw4rm-sdk:make-mock-llm-client))
         (resp (sw4rm-sdk:llm-query client "test" :model "override-model")))
    (is (string= "override-model" (sw4rm-sdk:llm-response-model resp)))))

(test mock-client-metadata-includes-mock-flag
  "Mock responses include :mock T in metadata."
  (let* ((client (sw4rm-sdk:make-mock-llm-client))
         (resp (sw4rm-sdk:llm-query client "test")))
    (let ((metadata (getf resp :metadata)))
      (is (not (null metadata)))
      (is (eq t (getf metadata :mock))))))

(test mock-client-is-llm-client
  "mock-llm-client is a subclass of llm-client."
  (let ((client (sw4rm-sdk:make-mock-llm-client)))
    (is (typep client 'sw4rm-sdk:llm-client))))


;;; =======================================================================
;;;  5. Rate Limiter
;;; =======================================================================

(def-suite rate-limiter-suite :description "Token bucket rate limiter tests"
  :in llm-suite)
(in-suite rate-limiter-suite)

(test rate-limiter-creation
  "make-rate-limiter creates a bucket with correct initial values."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 100000)))
    (is (typep rl 'sw4rm-sdk:token-bucket))
    (is (= 100000.0d0 (sw4rm-sdk:bucket-base-tpm rl)))
    (is (= 100000.0d0 (sw4rm-sdk:bucket-current-tpm rl)))
    ;; Starts full
    (is (= 100000.0d0 (sw4rm-sdk:bucket-tokens rl)))
    (is (eq t (sw4rm-sdk:bucket-enabled-p rl)))
    (is (eq t (sw4rm-sdk:bucket-adaptive-p rl)))))

(test rate-limiter-disabled
  "Disabled rate limiter returns 0.0 from acquire without blocking."
  (let ((rl (sw4rm-sdk:make-rate-limiter :enabled nil)))
    (let ((waited (sw4rm-sdk:acquire rl 999999)))
      (is (= 0.0d0 waited)))))

(test rate-limiter-acquire-immediate
  "acquire returns immediately when enough tokens are available."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 500000)))
    (let ((waited (sw4rm-sdk:acquire rl 100)))
      ;; Should be nearly instant
      (is (< waited 1.0)))))

(test rate-limiter-acquire-decrements-tokens
  "acquire decrements the token count by the requested amount."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 10000)))
    (let ((before (sw4rm-sdk:bucket-tokens rl)))
      (sw4rm-sdk:acquire rl 1000)
      ;; Tokens should have decreased (some refill may have occurred,
      ;; but net result should be lower than before minus 1000... loosely)
      (is (< (sw4rm-sdk:bucket-tokens rl) before)))))

(test rate-limiter-acquire-minimum-100
  "acquire treats requests below 100 as 100 tokens."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 10000)))
    ;; Request 1 token; the implementation uses (max tokens 100)
    (let ((before (sw4rm-sdk:bucket-tokens rl)))
      (sw4rm-sdk:acquire rl 1)
      ;; Should have consumed at least 100 tokens
      (is (<= (sw4rm-sdk:bucket-tokens rl) (- before 99))))))

(test rate-limiter-record-success
  "record-success increments successes-since-limit counter."
  (let ((rl (sw4rm-sdk:make-rate-limiter)))
    ;; successes-since-limit starts at 0
    (sw4rm-sdk:record-success rl)
    (sw4rm-sdk:record-success rl)
    (sw4rm-sdk:record-success rl)
    ;; We check via the internal accessor (uses package-internal symbol)
    (is (= 3 (sw4rm-sdk::bucket-successes-since-limit rl)))))

(test rate-limiter-record-rate-limit-reduces-tpm
  "record-rate-limit reduces current-tpm by the reduction factor."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 100000
                                          :reduction-factor 0.5d0)))
    (let ((before (sw4rm-sdk:bucket-current-tpm rl)))
      (sw4rm-sdk:record-rate-limit rl)
      (is (< (sw4rm-sdk:bucket-current-tpm rl) before))
      ;; Should be roughly 50000 (0.5 * 100000)
      (is (= 50000.0d0 (sw4rm-sdk:bucket-current-tpm rl))))))

(test rate-limiter-record-rate-limit-respects-floor
  "record-rate-limit does not reduce below min-tpm (25% of base)."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 10000
                                          :reduction-factor 0.1d0)))
    ;; min-tpm = max(1000, 0.25 * 10000) = 2500
    ;; First reduction: 10000 * 0.1 = 1000, but floor is 2500
    (sw4rm-sdk:record-rate-limit rl)
    (is (>= (sw4rm-sdk:bucket-current-tpm rl) 2500.0d0))))

(test rate-limiter-record-rate-limit-resets-success-counter
  "record-rate-limit resets successes-since-limit to 0."
  (let ((rl (sw4rm-sdk:make-rate-limiter)))
    ;; Build up some successes
    (dotimes (_ 10)
      (sw4rm-sdk:record-success rl))
    (is (= 10 (sw4rm-sdk::bucket-successes-since-limit rl)))
    ;; Record rate limit
    (sw4rm-sdk:record-rate-limit rl)
    (is (= 0 (sw4rm-sdk::bucket-successes-since-limit rl)))))

(test rate-limiter-non-adaptive-ignores-rate-limit
  "record-rate-limit is a no-op when adaptive is disabled."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 100000
                                          :adaptive nil)))
    (let ((before (sw4rm-sdk:bucket-current-tpm rl)))
      (sw4rm-sdk:record-rate-limit rl)
      (is (= before (sw4rm-sdk:bucket-current-tpm rl))))))

(test rate-limiter-non-adaptive-ignores-success
  "record-success is a no-op when adaptive is disabled."
  (let ((rl (sw4rm-sdk:make-rate-limiter :adaptive nil)))
    (sw4rm-sdk:record-success rl)
    ;; successes counter should remain 0
    (is (= 0 (sw4rm-sdk::bucket-successes-since-limit rl)))))

(test rate-limiter-disabled-ignores-rate-limit
  "record-rate-limit is a no-op when limiter is disabled."
  (let ((rl (sw4rm-sdk:make-rate-limiter :tokens-per-minute 100000
                                          :enabled nil)))
    (let ((before (sw4rm-sdk:bucket-current-tpm rl)))
      (sw4rm-sdk:record-rate-limit rl)
      (is (= before (sw4rm-sdk:bucket-current-tpm rl))))))


;;; =======================================================================
;;;  6. Global Rate Limiter
;;; =======================================================================

(def-suite global-rate-limiter-suite
  :description "Global rate limiter singleton"
  :in llm-suite)
(in-suite global-rate-limiter-suite)

(test global-rate-limiter-reset
  "reset-global-rate-limiter clears the global limiter."
  (sw4rm-sdk:reset-global-rate-limiter)
  (is (null sw4rm-sdk:*global-rate-limiter*)))

(test global-rate-limiter-creation
  "get-global-rate-limiter creates a new limiter when none exists."
  (sw4rm-sdk:reset-global-rate-limiter)
  (let ((rl (sw4rm-sdk:get-global-rate-limiter :tokens-per-minute 50000)))
    (is (typep rl 'sw4rm-sdk:token-bucket))
    (is (= 50000.0d0 (sw4rm-sdk:bucket-base-tpm rl)))))

(test global-rate-limiter-singleton
  "get-global-rate-limiter returns the same instance on subsequent calls."
  (sw4rm-sdk:reset-global-rate-limiter)
  (let ((rl1 (sw4rm-sdk:get-global-rate-limiter))
        (rl2 (sw4rm-sdk:get-global-rate-limiter)))
    (is (eq rl1 rl2))))

(test global-rate-limiter-ignores-tpm-after-creation
  "get-global-rate-limiter ignores tokens-per-minute on subsequent calls."
  (sw4rm-sdk:reset-global-rate-limiter)
  (let ((rl1 (sw4rm-sdk:get-global-rate-limiter :tokens-per-minute 50000)))
    ;; Second call with different TPM should return same instance
    (let ((rl2 (sw4rm-sdk:get-global-rate-limiter :tokens-per-minute 999999)))
      (is (eq rl1 rl2))
      (is (= 50000.0d0 (sw4rm-sdk:bucket-base-tpm rl2))))))


;;; =======================================================================
;;;  7. Factory Function
;;; =======================================================================

(def-suite factory-suite :description "LLM client factory" :in llm-suite)
(in-suite factory-suite)

(test factory-mock-client
  "create-llm-client with :client-type \"mock\" returns a mock client."
  (let ((client (sw4rm-sdk:create-llm-client :client-type "mock")))
    (is (typep client 'sw4rm-sdk:mock-llm-client))
    (is (string= "mock-model" (sw4rm-sdk:llm-client-default-model client)))))

(test factory-mock-with-model
  "create-llm-client with :client-type \"mock\" and :model overrides model."
  (let ((client (sw4rm-sdk:create-llm-client :client-type "mock"
                                              :model "custom-mock")))
    (is (typep client 'sw4rm-sdk:mock-llm-client))
    (is (string= "custom-mock" (sw4rm-sdk:llm-client-default-model client)))))

(test factory-mock-is-functional
  "Mock client created via factory can answer queries."
  (let* ((client (sw4rm-sdk:create-llm-client :client-type "mock"))
         (resp (sw4rm-sdk:llm-query client "hello")))
    (is (stringp (sw4rm-sdk:llm-response-content resp)))
    (is (plusp (length (sw4rm-sdk:llm-response-content resp))))))

(test factory-invalid-type-signals-error
  "create-llm-client with an invalid type signals sw4rm-error."
  (signals sw4rm-sdk:sw4rm-error
    (sw4rm-sdk:create-llm-client :client-type "nonexistent")))

(test factory-groq-without-key-signals-auth-error
  "create-llm-client with :client-type \"groq\" and no key signals auth error."
  ;; Temporarily clear the env var to ensure no key is found
  (let ((saved-env (uiop:getenv "GROQ_API_KEY")))
    (unwind-protect
         (progn
           (setf (uiop:getenv "GROQ_API_KEY") "")
           ;; Only test if there is also no ~/.groq file
           (let ((dotfile (merge-pathnames ".groq" (user-homedir-pathname))))
             (unless (probe-file dotfile)
               (signals sw4rm-sdk:llm-authentication-error
                 (sw4rm-sdk:create-llm-client :client-type "groq")))))
      (when saved-env
        (setf (uiop:getenv "GROQ_API_KEY") saved-env)))))

(test factory-anthropic-without-key-signals-auth-error
  "create-llm-client with :client-type \"anthropic\" and no key signals auth error."
  ;; Temporarily clear the env var to ensure no key is found
  (let ((saved-env (uiop:getenv "ANTHROPIC_API_KEY")))
    (unwind-protect
         (progn
           (setf (uiop:getenv "ANTHROPIC_API_KEY") "")
           ;; Only test if there is also no ~/.anthropic file
           (let ((dotfile (merge-pathnames ".anthropic" (user-homedir-pathname))))
             (unless (probe-file dotfile)
               (signals sw4rm-sdk:llm-authentication-error
                 (sw4rm-sdk:create-llm-client :client-type "anthropic")))))
      (when saved-env
        (setf (uiop:getenv "ANTHROPIC_API_KEY") saved-env)))))

(test factory-case-insensitive
  "create-llm-client accepts client-type in any case."
  (let ((client (sw4rm-sdk:create-llm-client :client-type "MOCK")))
    (is (typep client 'sw4rm-sdk:mock-llm-client)))
  (let ((client (sw4rm-sdk:create-llm-client :client-type "Mock")))
    (is (typep client 'sw4rm-sdk:mock-llm-client))))


;;; =======================================================================
;;;  8. Groq and Anthropic Client Construction
;;; =======================================================================
;;;
;;; These tests verify that make-groq-client and make-anthropic-client
;;; work correctly with an explicit API key (no env var or dotfile needed).

(def-suite provider-construction-suite
  :description "Provider client construction"
  :in llm-suite)
(in-suite provider-construction-suite)

(test groq-client-with-explicit-key
  "make-groq-client with :api-key succeeds."
  (let ((client (sw4rm-sdk:make-groq-client :api-key "test-key-123")))
    (is (typep client 'sw4rm-sdk:groq-client))
    (is (string= "test-key-123" (sw4rm-sdk:llm-client-api-key client)))
    (is (string= sw4rm-sdk:+groq-default-model+
                 (sw4rm-sdk:llm-client-default-model client)))))

(test groq-client-with-custom-model
  "make-groq-client with :model overrides the default model."
  (let ((client (sw4rm-sdk:make-groq-client :api-key "key"
                                             :model "llama-3.1-8b")))
    (is (string= "llama-3.1-8b" (sw4rm-sdk:llm-client-default-model client)))))

(test groq-client-is-llm-client
  "groq-client is a subclass of llm-client."
  (let ((client (sw4rm-sdk:make-groq-client :api-key "key")))
    (is (typep client 'sw4rm-sdk:llm-client))))

(test anthropic-client-with-explicit-key
  "make-anthropic-client with :api-key succeeds."
  (let ((client (sw4rm-sdk:make-anthropic-client :api-key "sk-ant-test")))
    (is (typep client 'sw4rm-sdk:anthropic-client))
    (is (string= "sk-ant-test" (sw4rm-sdk:llm-client-api-key client)))
    (is (string= sw4rm-sdk:+anthropic-default-model+
                 (sw4rm-sdk:llm-client-default-model client)))))

(test anthropic-client-with-custom-model
  "make-anthropic-client with :model overrides the default model."
  (let ((client (sw4rm-sdk:make-anthropic-client :api-key "key"
                                                  :model "claude-3-haiku")))
    (is (string= "claude-3-haiku" (sw4rm-sdk:llm-client-default-model client)))))

(test anthropic-client-is-llm-client
  "anthropic-client is a subclass of llm-client."
  (let ((client (sw4rm-sdk:make-anthropic-client :api-key "key")))
    (is (typep client 'sw4rm-sdk:llm-client))))
