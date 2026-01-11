;;;; sw4rm-orchestrator.asd
;;;;
;;;; ASDF system definition for SW4RM Recursive Tree Orchestration Layer
;;;;
;;;; This system provides Common Lisp-based orchestration for hierarchical
;;;; SW4RM deployments, enabling recursive composition of sw4rm instances
;;;; into trees where nodes coordinate child sw4rms via gRPC.

(defsystem "sw4rm-orchestrator"
  :description "SW4RM Recursive Tree Orchestration Layer"
  :version "0.6.0"
  :author "SW4RM Team"
  :license "Apache-2.0"
  :homepage "https://github.com/ruvnet/sigagent"

  ;; Dependencies
  :depends-on (
               ;; Core utilities
               "alexandria"           ; General utilities
               "bordeaux-threads"     ; Portable threading
               "lparallel"           ; Parallel execution
               "split-sequence"      ; String/sequence splitting

               ;; Data serialization
               "cl-json"             ; JSON encoding/decoding
               "cl-store"            ; Object persistence
               "babel"               ; Portable string/octets encoding

               ;; Networking
               "usocket"             ; Portable TCP sockets

               ;; Logging
               "log4cl"              ; Logging framework

               ;; gRPC and networking (note: may need to build/adapt)
               ;; "grpc"              ; gRPC client/server (to be integrated)
               ;; "cl-protobuf"       ; Protocol buffers (to be integrated)

               ;; Testing
               "fiveam")             ; Testing framework

  ;; Source file components in dependency order
  :serial t
  :components (
               ;; Package definitions must come first
               (:file "src/package")

               ;; Configuration management (early, used by everything)
               (:file "src/config")

               ;; Error handling with conditions/restarts (before tree, routing, etc.)
               (:module "errors"
                :pathname "src/errors"
                :serial t
                :components ((:file "conditions")   ; Condition definitions
                            (:file "restarts")))   ; Standard restarts

               ;; Envelope handling (before tree, used by routing)
               (:module "envelope"
                :pathname "src/envelope"
                :serial t
                :components ((:file "types")         ; Envelope data types
                            (:file "reader")        ; Reader macros (#E{}, #X{})
                            (:file "serialization"))) ; Proto conversion

               ;; Core tree data types and protocols
               (:module "tree"
                :pathname "src/tree"
                :serial t
                :components ((:file "types")      ; Base types and protocols
                            (:file "leaf")       ; Leaf node (Python wrapper)
                            (:file "node")       ; Inner node (orchestrator)
                            (:file "traversal"))) ; Tree operations

               ;; Cross-swarm routing (depends on tree and envelope)
               (:module "routing"
                :pathname "src/routing"
                :serial t
                :components ((:file "table")       ; Routing table management
                            (:file "strategies")  ; Routing strategies
                            (:file "router")))     ; Core routing logic

               ;; Cross-swarm coordination primitives
               (:module "coordination"
                :pathname "src/coordination"
                :serial t
                :components ((:file "sync")         ; Barrier synchronization
                            (:file "artifacts")    ; Shared artifact registry
                            (:file "negotiation"))) ; Cross-swarm negotiation

               ;; gRPC bridge to Python sw4rm instances
               (:module "grpc"
                :pathname "src/grpc"
                :serial t
                :components ((:file "proto-compat") ; Proto compatibility layer
                            (:file "client")       ; gRPC client
                            (:file "server")       ; gRPC server (for Python callbacks)
                            (:file "transport")))  ; JSON-over-TCP transport

               ;; State persistence and recovery
               (:module "persistence"
                :pathname "src/persistence"
                :serial t
                :components ((:file "checkpoint")   ; Image checkpointing
                            (:file "wal")))        ; Write-ahead logging

               ;; Main entry point
               (:file "src/main"))

  ;; Test system
  :in-order-to ((test-op (test-op "sw4rm-orchestrator/test"))))


;;;; Test system definition
(defsystem "sw4rm-orchestrator/test"
  :description "Test suite for SW4RM orchestrator"
  :author "SW4RM Team"
  :license "Apache-2.0"
  :depends-on ("sw4rm-orchestrator"
               "fiveam")
  :serial t
  :components ((:module "test"
                :serial t
                :components ((:file "package")
                            (:file "tree-tests")
                            (:file "routing-tests")
                            (:file "wal-tests")
                            (:file "lifecycle-tests")
                            (:file "fuzz-tests")
                            (:file "integration-tests"))))
  :perform (test-op (op c)
                    (symbol-call :fiveam :run!
                                (find-symbol* :sw4rm-orchestrator-tests
                                             :sw4rm-orchestrator.test))))
