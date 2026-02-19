;;;; sw4rm-sdk.asd - ASDF system definition for SW4RM SDK

(asdf:defsystem #:sw4rm-sdk
  :description "SW4RM Protocol SDK for Common Lisp - Full peer implementation"
  :version "0.5.0"
  :author "SW4RM Team"
  :license "Apache-2.0"
  :depends-on (#:cl-protobufs.asdf   ; Protocol buffer support (Quicklisp system name)
               #:alexandria         ; Common utilities
               #:bordeaux-threads   ; Thread portability
               #:local-time         ; Time handling
               #:ironclad           ; Cryptographic operations
               #:uuid               ; UUID generation
               #:jonathan           ; Fast JSON parsing/encoding
               #:cl-ppcre           ; Regular expressions
               #:split-sequence     ; String/sequence splitting
               #:cl-json            ; JSON encoding/decoding
               #:cffi               ; Foreign function interface (libgrpc)
               #:cffi-libffi        ; Struct-by-value support for CFFI
               #:babel)             ; String/octets encoding
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
                             (:file "worktree-state")
                             (:file "voting")
                             (:file "audit")
                             (:file "secrets")
                             (:file "persistence")
                             (:file "ack-manager")
                             (:file "control")
                             (:file "interceptors")
                             (:file "negotiation-events")
                             (:file "policy-store")))
               (:module "transport"
                :pathname "src/transport"
                :depends-on ("src")
                :serial t
                :components ((:file "grpc-ffi")
                             (:file "protobuf-codec")
                             (:file "grpc-transport")))
               (:module "clients"
                :pathname "src/clients"
                :depends-on ("src" "transport")
                :serial t
                :components ((:file "base")
                             (:file "router")
                             (:file "registry")
                             (:file "scheduler")
                             (:file "scheduler-policy")
                             (:file "hitl")
                             (:file "worktree")
                             (:file "tool")
                             (:file "connector")
                             (:file "negotiation")
                             (:file "negotiation-room")
                             (:file "negotiation-room-store")
                             (:file "reasoning")
                             (:file "logging")
                             (:file "activity")
                             (:file "gateway")
                             (:file "handoff")
                             (:file "workflow"))))
  :in-order-to ((test-op (test-op #:sw4rm-sdk/tests))))

(asdf:defsystem #:sw4rm-sdk/tests
  :description "Test suite for SW4RM SDK"
  :depends-on (#:sw4rm-sdk
               #:fiveam)
  :components ((:module "test"
                :serial t
                :components ((:file "suite")
                             (:file "transport-test"))))
  :perform (test-op (o c)
             (let* ((suite-package (or (find-package :sw4rm-test)
                                       (error "SW4RM test package missing")))
                    (suite-symbol (or (find-symbol "SW4RM-SUITE" suite-package)
                                      (error "SW4RM suite symbol missing"))))
               (symbol-call :fiveam '#:run! suite-symbol))))
