;;;; sw4rm.asd - ASDF system definition for SW4RM SDK

(asdf:defsystem #:sw4rm-sdk
  :description "SW4RM Protocol SDK for Common Lisp - Full peer implementation"
  :version "0.6.0"
  :author "SW4RM Team"
  :license "Apache-2.0"
  :depends-on (#:cl-protobufs       ; Protocol buffer support
               #:alexandria         ; Common utilities
               #:bordeaux-threads   ; Thread portability
               #:local-time         ; Time handling
               #:ironclad           ; Cryptographic operations
               #:uuid               ; UUID generation
               #:jonathan           ; Fast JSON parsing/encoding
               #:cl-ppcre)          ; Regular expressions
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "constants")
                             (:file "errors")
                             (:file "config")
                             (:file "envelope")
                             (:file "state-machine")
                             (:file "activity-buffer")
                             (:file "idempotency")
                             (:file "worktree-state")
                             (:file "voting")
                             (:file "audit")
                             (:file "secrets")
                             (:file "persistence")
                             (:file "interceptors")
                             (:file "negotiation-events")
                             (:file "policy-store")))
               (:module "clients"
                :depends-on ("src")
                :serial t
                :components ((:file "base-client")
                             (:file "router-client")
                             (:file "registry-client")
                             (:file "scheduler-client")
                             (:file "hitl-client")
                             (:file "worktree-client")
                             (:file "tool-client")
                             (:file "connector-client")
                             (:file "negotiation-client")
                             (:file "reasoning-client")
                             (:file "logging-client"))))
  :in-order-to ((test-op (test-op #:sw4rm-sdk/tests))))

(asdf:defsystem #:sw4rm-sdk/tests
  :description "Test suite for SW4RM SDK"
  :depends-on (#:sw4rm-sdk
               #:fiveam)
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "constants-test")
                             (:file "envelope-test")
                             (:file "errors-test")
                             (:file "config-test")
                             (:file "idempotency-test"))))
  :perform (test-op (o c)
             (symbol-call :fiveam '#:run! :sw4rm-sdk-tests)))
