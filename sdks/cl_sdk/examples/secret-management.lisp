;;;; secret-management.lisp -- Secret management example
;;;;
;;;; Demonstrates the SW4RM secrets module for managing API keys and credentials:
;;;;   1. Environment variable backend (read-only, uses SW4RM_SECRET_* prefix)
;;;;   2. File-based backend (read/write, persists to JSON)
;;;;   3. Secret resolver with multi-backend fallback chain
;;;;   4. Error handling for missing secrets and read-only backends
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed
;;;;   - SW4RM SDK on ASDF load path
;;;;
;;;; Run:
;;;;   sbcl --load examples/secret-management.lisp
;;;;
;;;; Optional environment variables for testing:
;;;;   SW4RM_SECRET_OPENAI_API_KEY=sk-test-12345
;;;;   SW4RM_SECRET_DATABASE_URL=postgres://localhost/mydb

;;; ---------------------------------------------------------------------------
;;; Step 0: Ensure Quicklisp is available, then load the SDK
;;; ---------------------------------------------------------------------------

;;; Ensure Quicklisp is available
#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload :sw4rm-sdk)

(defpackage #:secret-management-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:secret-management-example)

;;; ---------------------------------------------------------------------------
;;; Part A: File-Based Secret Backend
;;; ---------------------------------------------------------------------------
;;; The file backend stores secrets as JSON in a local file. It caches secrets
;;; in memory and persists changes to disk on every write. This is suitable
;;; for development and local testing.

(format t "~&;; === Part A: File-Based Secret Backend ===~%")

;; Create a file backend pointing to a temporary secrets file.
;; In production you would use the default path (~/.secrets.json) or a
;; deployment-specific location.
(defvar *secrets-file*
  (merge-pathnames "sw4rm-example-secrets.json" (uiop:temporary-directory))
  "Temporary file for storing secrets in this example.")

;; Clean up any leftover file from a previous run.
(when (probe-file *secrets-file*)
  (delete-file *secrets-file*))

(defvar *file-backend* (make-file-backend (namestring *secrets-file*)))

(format t ";;   Secrets file: ~A~%" *secrets-file*)

;; Store some secrets.
(set-secret *file-backend* "OPENAI_API_KEY" "sk-example-key-12345")
(set-secret *file-backend* "DATABASE_URL" "postgres://user:pass@localhost:5432/mydb")
(set-secret *file-backend* "GITHUB_TOKEN" "ghp_example_token_abcdef")

(format t ";;   Stored 3 secrets.~%")

;; Retrieve a secret.
(let ((api-key (get-secret *file-backend* "OPENAI_API_KEY")))
  (format t ";;   OPENAI_API_KEY: ~A~%"
          (if api-key
              (concatenate 'string (subseq api-key 0 8) "..." )
              "<not found>")))

;; List all secret keys (does not expose values).
(let ((keys (list-secrets *file-backend*)))
  (format t ";;   Secret keys stored: ~{~A~^, ~}~%" keys))

;; Delete a secret.
(let ((deleted (delete-secret *file-backend* "GITHUB_TOKEN")))
  (format t ";;   Deleted GITHUB_TOKEN: ~A~%" (if deleted "yes" "no")))

(let ((keys (list-secrets *file-backend*)))
  (format t ";;   Remaining keys: ~{~A~^, ~}~%" keys))

;;; ---------------------------------------------------------------------------
;;; Part B: Environment Variable Backend
;;; ---------------------------------------------------------------------------
;;; The env backend reads secrets from environment variables with a configurable
;;; prefix (default: "SW4RM_SECRET_"). It is read-only -- attempts to write
;;; will signal a secret-backend-error condition.

(format t "~&~%;; === Part B: Environment Variable Backend ===~%")

(defvar *env-backend* (make-env-backend "SW4RM_SECRET_"))

(format t ";;   Prefix: SW4RM_SECRET_~%")

;; Try to read a secret from the environment.
;; This will only find a value if you set SW4RM_SECRET_OPENAI_API_KEY before running.
(let ((env-key (get-secret *env-backend* "OPENAI_API_KEY")))
  (format t ";;   OPENAI_API_KEY from env: ~A~%"
          (if env-key
              (concatenate 'string (subseq env-key 0 (min 8 (length env-key))) "...")
              "<not set in environment>")))

;; Demonstrate the read-only constraint.
(format t ";;   Attempting to write to env backend...~%")
(handler-case
    (set-secret *env-backend* "TEST_KEY" "test-value")
  (secret-backend-error (e)
    (format t ";;   [expected] ~A~%" e)))

;;; ---------------------------------------------------------------------------
;;; Part C: Secret Resolver -- Multi-Backend Fallback Chain
;;; ---------------------------------------------------------------------------
;;; The secret-resolver queries backends in order and returns the first match.
;;; This allows layering: environment variables override file-based secrets,
;;; which override defaults.

(format t "~&~%;; === Part C: Secret Resolver (Fallback Chain) ===~%")

;; Create a resolver with env first, file second.
;; The env backend is checked first; if the secret is not found there,
;; the file backend is checked.
(defvar *resolver* (make-instance 'secret-resolver))

;; Backends are queried in the order they appear in the list.
;; add-backend pushes to front, so we add file first, then env.
(add-backend *resolver* *file-backend*)
(add-backend *resolver* *env-backend*)

(format t ";;   Resolver backends: env -> file~%")

;; Resolve OPENAI_API_KEY.
;; If SW4RM_SECRET_OPENAI_API_KEY is set in the environment, the env backend
;; returns it. Otherwise, the file backend returns the value we stored earlier.
(let ((resolved (resolve-secret *resolver* "OPENAI_API_KEY")))
  (format t ";;   Resolved OPENAI_API_KEY: ~A~%"
          (if resolved
              (concatenate 'string (subseq resolved 0 (min 8 (length resolved))) "...")
              "<not found>")))

;; Resolve DATABASE_URL (only in file backend).
(let ((resolved (resolve-secret *resolver* "DATABASE_URL")))
  (format t ";;   Resolved DATABASE_URL: ~A~%"
          (if resolved "found" "not found")))

;; Resolve a secret that does not exist anywhere -- returns fallback value (nil).
(let ((resolved (resolve-secret *resolver* "NONEXISTENT_KEY")))
  (format t ";;   Resolved NONEXISTENT_KEY: ~A~%" (or resolved "<nil / not found>")))

;;; ---------------------------------------------------------------------------
;;; Part D: Error Handling for Missing Secrets
;;; ---------------------------------------------------------------------------
;;; When signal-if-not-found is T, resolve-secret signals SECRET-NOT-FOUND
;;; instead of returning nil. This is useful when a secret is required.

(format t "~&~%;; === Part D: Error Handling ===~%")

;; Graceful handling with handler-case.
(format t ";;   Resolving required secret that does not exist...~%")
(handler-case
    (resolve-secret *resolver* "REQUIRED_BUT_MISSING"
                    :signal-if-not-found t)
  (secret-not-found (e)
    (format t ";;   [expected] ~A~%" e)
    (format t ";;   Missing key: ~A~%" (secret-key e))))

;; Store a secret through the resolver (targets a specific backend by index).
(format t "~&;;   Storing SECRET_X through resolver (backend-index 1 = file)...~%")
(store-secret *resolver* "SECRET_X" "value-x" :backend-index 1)

(let ((retrieved (resolve-secret *resolver* "SECRET_X")))
  (format t ";;   Retrieved SECRET_X: ~A~%" retrieved))

;;; ---------------------------------------------------------------------------
;;; Part E: Default Resolver Convenience
;;; ---------------------------------------------------------------------------
;;; make-default-resolver creates a pre-configured resolver with:
;;;   1. Environment variable backend (SW4RM_SECRET_* prefix)
;;;   2. File backend (~/.secrets.json)

(format t "~&~%;; === Part E: Default Resolver ===~%")

;; In production, you would typically just use the default resolver:
;;
;;   (defvar *secrets* (make-default-resolver))
;;   (resolve-secret *secrets* "OPENAI_API_KEY" :signal-if-not-found t)
;;
;; This checks SW4RM_SECRET_OPENAI_API_KEY in the environment first, then
;; falls back to the "OPENAI_API_KEY" entry in ~/.secrets.json.

(format t ";;   (make-default-resolver) creates a resolver with:~%")
(format t ";;     Backend 1: env-backend (SW4RM_SECRET_* prefix)~%")
(format t ";;     Backend 2: file-backend (~~/.secrets.json)~%")
(format t ";;   Usage:~%")
(format t ";;     (defvar *secrets* (make-default-resolver))~%")
(format t ";;     (resolve-secret *secrets* \"OPENAI_API_KEY\")~%")

;;; ---------------------------------------------------------------------------
;;; Cleanup
;;; ---------------------------------------------------------------------------

;; Remove the temporary secrets file.
(when (probe-file *secrets-file*)
  (delete-file *secrets-file*)
  (format t "~&;;   Cleaned up temporary secrets file.~%"))

;;; ---------------------------------------------------------------------------
;;; Summary
;;; ---------------------------------------------------------------------------

(format t "~&~%;; Secret management example complete.~%")
(format t ";; Key takeaways:~%")
(format t ";;   - make-file-backend for local JSON-based secret storage~%")
(format t ";;   - make-env-backend for environment variable secrets (read-only)~%")
(format t ";;   - secret-resolver with add-backend for multi-source fallback~%")
(format t ";;   - resolve-secret with :signal-if-not-found for required secrets~%")
(format t ";;   - store-secret / delete-secret for CRUD operations~%")
(format t ";;   - make-default-resolver for production-ready defaults~%")
(format t ";;   - handler-case for secret-not-found / secret-backend-error~%")
