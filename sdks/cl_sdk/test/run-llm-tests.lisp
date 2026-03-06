;;;; run-llm-tests.lisp -- Standalone LLM module tests
;;;;
;;;; Runs without Quicklisp/FiveAM.  Loads only the error hierarchy and the
;;;; LLM module, then exercises mock client, rate limiter, factory, condition
;;;; hierarchy, and response helpers.
;;;;
;;;; Usage:  sbcl --load test/run-llm-tests.lisp
;;;;
;;;; Exit code 0 = all pass, 1 = failure.

;;; =====================================================================
;;;  Dependency shims (no Quicklisp on this system)
;;; =====================================================================

;;; UIOP is bundled with SBCL but must be required
(require :uiop)

;;; bordeaux-threads shim -- tests are single-threaded
(defpackage #:bt
  (:use #:cl)
  (:export #:make-lock #:with-lock-held))

(in-package #:bt)

(defun make-lock (name)
  "No-op lock for single-threaded test use."
  (declare (ignore name))
  nil)

(defmacro with-lock-held ((lock) &body body)
  "No-op lock-held for single-threaded test use."
  (declare (ignore lock))
  `(progn ,@body))

;;; jonathan (jojo) shim -- mock client does not use JSON, but groq/anthropic
;;; client files reference jojo at load time.  Provide stub definitions.
(defpackage #:jojo
  (:use #:cl)
  (:export #:to-json #:parse))

(in-package #:jojo)

(defun to-json (object)
  "Stub -- not called during mock-only tests."
  (declare (ignore object))
  (error "jojo:to-json stub called -- should not happen in mock tests"))

(defun parse (string)
  "Stub -- not called during mock-only tests."
  (declare (ignore string))
  (error "jojo:parse stub called -- should not happen in mock tests"))

;;; babel shim (string <-> octets)
(defpackage #:babel
  (:use #:cl)
  (:export #:string-to-octets #:octets-to-string))

(in-package #:babel)

(defun string-to-octets (string &key (encoding :utf-8))
  (declare (ignore encoding))
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun octets-to-string (octets &key (encoding :utf-8))
  (declare (ignore encoding))
  (sb-ext:octets-to-string octets :external-format :utf-8))

;;; drakma shim -- HTTP client not needed for mock tests
(defpackage #:drakma
  (:use #:cl)
  (:export #:http-request))

(in-package #:drakma)

(defun http-request (&rest args)
  "Stub -- not called during mock-only tests."
  (declare (ignore args))
  (error "drakma:http-request stub called -- should not happen in mock tests"))

;;; alexandria shim -- empty package, the LLM module doesn't use its symbols
(defpackage #:alexandria
  (:use #:cl))

;;; =====================================================================
;;;  Minimal sw4rm-sdk package and required source files
;;; =====================================================================

(defpackage #:sw4rm-sdk
  (:use #:cl #:alexandria))

(in-package #:sw4rm-sdk)

;;; Load source files relative to this test file's directory
(let* ((test-dir (make-pathname :directory (pathname-directory *load-truename*)))
       (sdk-dir  (merge-pathnames (make-pathname :directory '(:relative :up)) test-dir)))
  ;; Constants required by errors.lisp
  ;; (only the ones referenced by :default-initargs in error conditions)
  (defconstant +internal-error+ 99)
  (defconstant +no-route+ 2)
  (defconstant +validation-error+ 6)
  (defconstant +ack-timeout+ 3)
  (defconstant +buffer-full+ 1)
  (defconstant +duplicate-detected+ 14)

  ;; Load error hierarchy
  (load (merge-pathnames "src/errors.lisp" sdk-dir))
  ;; Load LLM module (serial order matches ASDF definition)
  (load (merge-pathnames "src/llm/llm-client.lisp" sdk-dir))
  (load (merge-pathnames "src/llm/rate-limiter.lisp" sdk-dir))
  (load (merge-pathnames "src/llm/groq-client.lisp" sdk-dir))
  (load (merge-pathnames "src/llm/anthropic-client.lisp" sdk-dir))
  (load (merge-pathnames "src/llm/mock-client.lisp" sdk-dir))
  (load (merge-pathnames "src/llm/factory.lisp" sdk-dir)))


;;; =====================================================================
;;;  Simple test framework (same pattern as run-codec-tests.lisp)
;;; =====================================================================
;;;
;;; Tests run inside the sw4rm-sdk package so all internal symbols are
;;; directly accessible without exports.

(defvar *test-count* 0)
(defvar *pass-count* 0)
(defvar *fail-count* 0)
(defvar *failures* nil)

(defmacro deftest (name &body body)
  `(progn
     (incf *test-count*)
     (handler-case
         (progn ,@body
                (incf *pass-count*)
                (format t "  PASS  ~A~%" ',name))
       (error (c)
         (incf *fail-count*)
         (push (cons ',name c) *failures*)
         (format t "  FAIL  ~A: ~A~%" ',name c)))))

(defmacro check (expr &optional msg)
  `(unless ,expr
     (error "Assertion failed~@[: ~A~]~%  Form: ~S" ,msg ',expr)))

(defmacro check= (a b &optional msg)
  `(let ((va ,a) (vb ,b))
     (unless (equal va vb)
       (error "~@[~A: ~]Expected ~S, got ~S" ,msg vb va))))

(defmacro check-signals (condition-type &body body)
  "Assert that BODY signals CONDITION-TYPE."
  (let ((signaled (gensym "SIGNALED")))
    `(let ((,signaled nil))
       (handler-case (progn ,@body)
         (,condition-type () (setf ,signaled t))
         (error (c) (error "Expected ~A but got ~A: ~A"
                           ',condition-type (type-of c) c)))
       (unless ,signaled
         (error "Expected ~A to be signaled but no condition was raised."
                ',condition-type)))))


;;; =====================================================================
;;;  Tests
;;; =====================================================================

(format t "~%=== SW4RM LLM Module Tests ===~%~%")

;;; --- 1. Response Helpers ------------------------------------------------
(format t "-- Response Helpers --~%")

(deftest response-defaults
  (let ((resp (make-llm-response)))
    (check= (llm-response-content resp) "")
    (check= (llm-response-model resp) "unknown")
    (check (null (llm-response-usage resp)))))

(deftest response-with-values
  (let ((resp (make-llm-response
               :content "Hello" :model "m1"
               :usage '(:input-tokens 5 :output-tokens 10))))
    (check= (llm-response-content resp) "Hello")
    (check= (llm-response-model resp) "m1")
    (check= (getf (llm-response-usage resp) :input-tokens) 5)
    (check= (getf (llm-response-usage resp) :output-tokens) 10)))

;;; --- 2. Utilities -------------------------------------------------------
(format t "~%-- Utilities --~%")

(deftest estimate-tokens-minimum
  (check= (estimate-tokens "hi") 100
          "Short prompt should return minimum 100"))

(deftest estimate-tokens-long
  (let ((prompt (make-string 1000 :initial-element #\x)))
    (check= (estimate-tokens prompt) 250)))

(deftest estimate-tokens-with-system
  (let ((prompt (make-string 400 :initial-element #\x))
        (system (make-string 400 :initial-element #\y)))
    (check= (estimate-tokens prompt system) 200)))

;;; --- 3. Condition Hierarchy ---------------------------------------------
(format t "~%-- Condition Hierarchy --~%")

(deftest llm-error-inherits-sw4rm-error
  (check-signals sw4rm-error
    (error 'llm-error :message "test")))

(deftest llm-auth-error-inherits-llm-error
  (check-signals llm-error
    (error 'llm-authentication-error :message "bad key")))

(deftest llm-rate-limit-error-inherits-llm-error
  (check-signals llm-error
    (error 'llm-rate-limit-error :message "429")))

(deftest llm-timeout-error-inherits-llm-error
  (check-signals llm-error
    (error 'llm-timeout-error :message "timed out")))

(deftest llm-error-message-accessor
  (handler-case
      (error 'llm-error :message "the message")
    (llm-error (c)
      (check= (sw4rm-error-message c) "the message"))))

(deftest llm-error-report-format
  (handler-case
      (error 'llm-error :message "something failed")
    (llm-error (c)
      (let ((report (format nil "~A" c)))
        (check (search "something failed" report)
               "Report should contain the error message")))))

;;; --- 4. Mock Client -----------------------------------------------------
(format t "~%-- Mock Client --~%")

(deftest mock-client-creation
  (let ((client (make-mock-llm-client)))
    (check= (llm-client-default-model client) "mock-model")
    (check= (llm-client-api-key client) "mock-key")
    (check= (mock-client-call-count client) 0)
    (check (null (mock-client-call-history client)))))

(deftest mock-client-custom-model
  (let ((client (make-mock-llm-client :model "custom")))
    (check= (llm-client-default-model client) "custom")))

(deftest mock-client-is-llm-client
  (let ((client (make-mock-llm-client)))
    (check (typep client 'llm-client)
           "mock-llm-client should be a subtype of llm-client")))

(deftest mock-client-single-query
  (let* ((client (make-mock-llm-client :responses '("Hello")))
         (resp (llm-query client "test")))
    (check= (llm-response-content resp) "Hello")
    (check= (llm-response-model resp) "mock-model")
    (check= (mock-client-call-count client) 1)))

(deftest mock-client-response-cycling
  (let* ((client (make-mock-llm-client :responses '("a" "b" "c")))
         (r1 (llm-query client "q1"))
         (r2 (llm-query client "q2"))
         (r3 (llm-query client "q3"))
         (r4 (llm-query client "q4")))
    (check= (llm-response-content r1) "a")
    (check= (llm-response-content r2) "b")
    (check= (llm-response-content r3) "c")
    ;; Cycles back
    (check= (llm-response-content r4) "a")
    (check= (mock-client-call-count client) 4)))

(deftest mock-client-response-generator
  (let* ((client (make-mock-llm-client
                  :response-generator (lambda (p) (format nil "Echo: ~A" p))))
         (resp (llm-query client "ping")))
    (check= (llm-response-content resp) "Echo: ping")))

(deftest mock-client-call-history
  (let ((client (make-mock-llm-client)))
    (llm-query client "prompt-1"
               :system-prompt "sys"
               :max-tokens 100
               :temperature 0.5)
    (let* ((history (mock-client-call-history client))
           (call (first history)))
      (check= (length history) 1)
      (check= (getf call :prompt) "prompt-1")
      (check= (getf call :system-prompt) "sys")
      (check= (getf call :max-tokens) 100)
      (check= (getf call :temperature) 0.5))))

(deftest mock-client-usage-tokens
  (let* ((client (make-mock-llm-client :responses '("short")))
         (resp (llm-query client "a longer test prompt")))
    (let ((usage (llm-response-usage resp)))
      (check (not (null usage)) "Usage should not be nil")
      (check (integerp (getf usage :input-tokens)))
      (check (integerp (getf usage :output-tokens)))
      (check (plusp (getf usage :input-tokens)))
      (check (plusp (getf usage :output-tokens))))))

(deftest mock-client-reset
  (let ((client (make-mock-llm-client :responses '("a" "b"))))
    (llm-query client "q1")
    (llm-query client "q2")
    (check= (mock-client-call-count client) 2)
    ;; Reset
    (mock-client-reset client)
    (check= (mock-client-call-count client) 0)
    (check (null (mock-client-call-history client)))
    ;; Cycles from beginning again
    (let ((resp (llm-query client "q3")))
      (check= (llm-response-content resp) "a"))))

(deftest mock-client-model-override
  (let* ((client (make-mock-llm-client))
         (resp (llm-query client "test" :model "override")))
    (check= (llm-response-model resp) "override")))

(deftest mock-client-metadata-mock-flag
  (let* ((client (make-mock-llm-client))
         (resp (llm-query client "test")))
    (let ((metadata (getf resp :metadata)))
      (check (not (null metadata)) "Metadata should not be nil")
      (check (eq t (getf metadata :mock)) "Metadata should contain :mock T"))))

;;; --- 5. Rate Limiter ----------------------------------------------------
(format t "~%-- Rate Limiter --~%")

(deftest rate-limiter-creation
  (let ((rl (make-rate-limiter :tokens-per-minute 100000)))
    (check (typep rl 'token-bucket))
    (check= (bucket-base-tpm rl) 100000.0d0)
    (check= (bucket-current-tpm rl) 100000.0d0)
    (check= (bucket-tokens rl) 100000.0d0)
    (check (eq t (bucket-enabled-p rl)))
    (check (eq t (bucket-adaptive-p rl)))))

(deftest rate-limiter-disabled-acquire
  (let ((rl (make-rate-limiter :enabled nil)))
    (let ((waited (acquire rl 999999)))
      (check= waited 0.0d0 "Disabled limiter should return 0.0"))))

(deftest rate-limiter-acquire-immediate
  (let ((rl (make-rate-limiter :tokens-per-minute 500000)))
    (let ((waited (acquire rl 100)))
      (check (< waited 1.0) "Should acquire immediately with plenty of tokens"))))

(deftest rate-limiter-acquire-decrements
  (let ((rl (make-rate-limiter :tokens-per-minute 10000)))
    (let ((before (bucket-tokens rl)))
      (acquire rl 1000)
      (check (< (bucket-tokens rl) before)
             "Tokens should decrease after acquire"))))

(deftest rate-limiter-acquire-minimum-100
  (let ((rl (make-rate-limiter :tokens-per-minute 10000)))
    (let ((before (bucket-tokens rl)))
      (acquire rl 1)
      ;; Should have consumed at least 100 tokens (the minimum)
      (check (<= (bucket-tokens rl) (- before 99))
             "Minimum acquire should be 100 tokens"))))

(deftest rate-limiter-record-success
  (let ((rl (make-rate-limiter)))
    (record-success rl)
    (record-success rl)
    (record-success rl)
    (check= (bucket-successes-since-limit rl) 3)))

(deftest rate-limiter-record-rate-limit-reduces
  (let ((rl (make-rate-limiter :tokens-per-minute 100000
                                :reduction-factor 0.5d0)))
    (record-rate-limit rl)
    (check= (bucket-current-tpm rl) 50000.0d0
            "TPM should be halved by 0.5 reduction factor")))

(deftest rate-limiter-record-rate-limit-floor
  (let ((rl (make-rate-limiter :tokens-per-minute 10000
                                :reduction-factor 0.1d0)))
    ;; min-tpm = max(1000, 0.25 * 10000) = 2500
    (record-rate-limit rl)
    (check (>= (bucket-current-tpm rl) 2500.0d0)
           "TPM should not go below min-tpm floor")))

(deftest rate-limiter-record-rate-limit-resets-successes
  (let ((rl (make-rate-limiter)))
    (dotimes (_ 10) (record-success rl))
    (check= (bucket-successes-since-limit rl) 10)
    (record-rate-limit rl)
    (check= (bucket-successes-since-limit rl) 0)))

(deftest rate-limiter-non-adaptive-ignores-rate-limit
  (let ((rl (make-rate-limiter :tokens-per-minute 100000 :adaptive nil)))
    (let ((before (bucket-current-tpm rl)))
      (record-rate-limit rl)
      (check= (bucket-current-tpm rl) before
              "Non-adaptive limiter should not change TPM"))))

(deftest rate-limiter-non-adaptive-ignores-success
  (let ((rl (make-rate-limiter :adaptive nil)))
    (record-success rl)
    (check= (bucket-successes-since-limit rl) 0
            "Non-adaptive limiter should not count successes")))

(deftest rate-limiter-disabled-ignores-rate-limit
  (let ((rl (make-rate-limiter :tokens-per-minute 100000 :enabled nil)))
    (let ((before (bucket-current-tpm rl)))
      (record-rate-limit rl)
      (check= (bucket-current-tpm rl) before
              "Disabled limiter should not change TPM"))))

;;; --- 6. Global Rate Limiter ---------------------------------------------
(format t "~%-- Global Rate Limiter --~%")

(deftest global-rate-limiter-reset
  (reset-global-rate-limiter)
  (check (null *global-rate-limiter*)
         "After reset, global limiter should be nil"))

(deftest global-rate-limiter-creation
  (reset-global-rate-limiter)
  (let ((rl (get-global-rate-limiter :tokens-per-minute 50000)))
    (check (typep rl 'token-bucket))
    (check= (bucket-base-tpm rl) 50000.0d0)))

(deftest global-rate-limiter-singleton
  (reset-global-rate-limiter)
  (let ((rl1 (get-global-rate-limiter))
        (rl2 (get-global-rate-limiter)))
    (check (eq rl1 rl2) "Should return the same instance")))

(deftest global-rate-limiter-ignores-tpm-on-second-call
  (reset-global-rate-limiter)
  (let ((rl1 (get-global-rate-limiter :tokens-per-minute 50000)))
    (let ((rl2 (get-global-rate-limiter :tokens-per-minute 999999)))
      (check (eq rl1 rl2))
      (check= (bucket-base-tpm rl2) 50000.0d0
              "Should keep original TPM"))))

;;; --- 7. Factory ---------------------------------------------------------
(format t "~%-- Factory --~%")

(deftest factory-mock-client
  (let ((client (create-llm-client :client-type "mock")))
    (check (typep client 'mock-llm-client)
           "Factory should create a mock-llm-client")
    (check= (llm-client-default-model client) "mock-model")))

(deftest factory-mock-with-model
  (let ((client (create-llm-client :client-type "mock" :model "custom-mock")))
    (check (typep client 'mock-llm-client))
    (check= (llm-client-default-model client) "custom-mock")))

(deftest factory-mock-is-functional
  (let* ((client (create-llm-client :client-type "mock"))
         (resp (llm-query client "hello")))
    (check (stringp (llm-response-content resp)))
    (check (plusp (length (llm-response-content resp))))))

(deftest factory-invalid-type-signals-error
  (check-signals sw4rm-error
    (create-llm-client :client-type "nonexistent")))

(deftest factory-case-insensitive
  (let ((c1 (create-llm-client :client-type "MOCK"))
        (c2 (create-llm-client :client-type "Mock")))
    (check (typep c1 'mock-llm-client))
    (check (typep c2 'mock-llm-client))))

(deftest factory-groq-no-key-signals-auth-error
  ;; Only test if no key is available via env var or dotfile
  (let ((saved (uiop:getenv "GROQ_API_KEY")))
    (unwind-protect
         (progn
           (setf (uiop:getenv "GROQ_API_KEY") "")
           (let ((dotfile (merge-pathnames ".groq" (user-homedir-pathname))))
             (unless (probe-file dotfile)
               (check-signals llm-authentication-error
                 (create-llm-client :client-type "groq")))))
      (when saved
        (setf (uiop:getenv "GROQ_API_KEY") saved)))))

(deftest factory-anthropic-no-key-signals-auth-error
  ;; Only test if no key is available via env var or dotfile
  (let ((saved (uiop:getenv "ANTHROPIC_API_KEY")))
    (unwind-protect
         (progn
           (setf (uiop:getenv "ANTHROPIC_API_KEY") "")
           (let ((dotfile (merge-pathnames ".anthropic" (user-homedir-pathname))))
             (unless (probe-file dotfile)
               (check-signals llm-authentication-error
                 (create-llm-client :client-type "anthropic")))))
      (when saved
        (setf (uiop:getenv "ANTHROPIC_API_KEY") saved)))))

;;; --- 8. Provider Client Construction ------------------------------------
(format t "~%-- Provider Client Construction --~%")

(deftest groq-client-with-explicit-key
  (reset-global-rate-limiter)
  (let ((client (make-groq-client :api-key "test-key-123")))
    (check (typep client 'groq-client))
    (check= (llm-client-api-key client) "test-key-123")
    (check= (llm-client-default-model client) +groq-default-model+)))

(deftest groq-client-custom-model
  (reset-global-rate-limiter)
  (let ((client (make-groq-client :api-key "key" :model "llama-3.1-8b")))
    (check= (llm-client-default-model client) "llama-3.1-8b")))

(deftest groq-client-is-llm-client
  (reset-global-rate-limiter)
  (let ((client (make-groq-client :api-key "key")))
    (check (typep client 'llm-client))))

(deftest anthropic-client-with-explicit-key
  (reset-global-rate-limiter)
  (let ((client (make-anthropic-client :api-key "sk-ant-test")))
    (check (typep client 'anthropic-client))
    (check= (llm-client-api-key client) "sk-ant-test")
    (check= (llm-client-default-model client) +anthropic-default-model+)))

(deftest anthropic-client-custom-model
  (reset-global-rate-limiter)
  (let ((client (make-anthropic-client :api-key "key" :model "claude-3-haiku")))
    (check= (llm-client-default-model client) "claude-3-haiku")))

(deftest anthropic-client-is-llm-client
  (reset-global-rate-limiter)
  (let ((client (make-anthropic-client :api-key "key")))
    (check (typep client 'llm-client))))


;;; =====================================================================
;;;  Summary
;;; =====================================================================

(format t "~%=== Results: ~D/~D passed, ~D failed ===~%"
        *pass-count* *test-count* *fail-count*)

(when *failures*
  (format t "~%Failures:~%")
  (dolist (f (reverse *failures*))
    (format t "  ~A: ~A~%" (car f) (cdr f))))

(sb-ext:exit :code (if (zerop *fail-count*) 0 1))
