# SW4RM Common Lisp SDK

Reference Common Lisp SDK for the SW4RM Agentic Protocol. This is one of four SDKs in this repository (Python, Rust, JavaScript, Common Lisp) and provides a full peer implementation with idiomatic CL condition/restart error handling patterns.

## Features

- **Full protocol coverage**: Clients for all SW4RM services (Registry, Router, Scheduler, HITL, Worktree, Tool, Connector, Negotiation, Reasoning, Logging)
- **Condition/restart error handling**: Idiomatic CL error recovery via `with-sw4rm-error-handling`
- **Envelope helpers**: Three-ID model envelope construction with HLC timestamps
- **Activity buffer**: Persistent message tracking with reconciliation
- **Worktree state**: Policy-driven binding management
- **Voting aggregation**: Confidence-weighted strategies for negotiation decisions
- **Secret management**: Encrypted credential storage with audit logging
- **State machine**: 12-state agent lifecycle matching the protocol spec

## Install

Requires [SBCL](http://www.sbcl.org/) and [Quicklisp](https://www.quicklisp.org/).

```lisp
;; Add the SDK to your ASDF load path (one-time setup):
(push (truename "/path/to/sdks/cl_sdk/") asdf:*central-registry*)

;; Load the SDK
(ql:quickload :sw4rm-sdk)
```

Dependencies (resolved automatically via Quicklisp):
- `cl-protobufs` - Protocol buffer support
- `alexandria` - Common utilities
- `bordeaux-threads` - Thread portability
- `local-time` - Time handling
- `ironclad` - Cryptographic operations
- `uuid` - UUID generation
- `jonathan` - Fast JSON parsing/encoding
- `cl-ppcre` - Regular expressions

## Quick Start

```lisp
(ql:quickload :sw4rm-sdk)
(use-package :sw4rm-sdk)

;; Configure the agent
(defvar *config*
  (make-agent-config
   :agent-id "echo-1"
   :name "EchoAgent"
   :description "Echoes incoming DATA messages"
   :version "0.5.0"
   :capabilities '("echo" "application/json")
   :endpoints (make-default-endpoints)
   :timeout-ms 30000
   :retry-max-attempts 3))

;; Build a message envelope (Three-ID model)
(defvar *envelope*
  (make-envelope
   :producer-id (agent-config-agent-id *config*)
   :message-type +data+
   :content-type "application/json"
   :payload (map 'vector #'char-code "{\"echo\":\"hello\"}")
   :sequence-number 1))

;; Send with structured error handling
(with-sw4rm-error-handling ()
  (let ((client (make-instance 'router-client
                 :address (endpoints-router
                           (agent-config-endpoints *config*)))))
    (send-envelope client *envelope*)))
```

## Examples

- **Echo agent**: [`examples/echo-agent.lisp`](examples/echo-agent.lisp) - Core message loop pattern with Three-ID envelopes, state transitions, and retry semantics
- **Negotiation voting**: [`examples/negotiation-voting.lisp`](examples/negotiation-voting.lisp) - Multi-agent voting and aggregation strategies
- **Secret management**: [`examples/secret-management.lisp`](examples/secret-management.lisp) - Encrypted credential storage with audit trails

Run an example:

```bash
cd sdks/cl_sdk
sbcl --load ~/quicklisp/setup.lisp \
     --eval '(push (truename ".") asdf:*central-registry*)' \
     --eval '(load "examples/echo-agent.lisp")'
```

## Testing

Run the FiveAM test suite:

```bash
# Via Makefile (from repo root)
make test-lisp

# Directly with SBCL
cd sdks/cl_sdk
sbcl --load ~/quicklisp/setup.lisp \
     --eval '(push (truename ".") asdf:*central-registry*)' \
     --eval '(ql:quickload :sw4rm-sdk)' \
     --eval '(load "test/suite.lisp")' \
     --eval '(fiveam:run! (quote sw4rm-test::sw4rm-suite))'
```

## Architecture

The SDK follows the same layered pattern as the other SW4RM SDKs:

- **`src/`** - Core modules (constants, envelope, state machine, activity buffer, worktree, voting, persistence, errors)
- **`src/clients/`** - Service clients for all protocol RPCs
- **`test/`** - FiveAM test suite
- **`examples/`** - Runnable example scripts

## Operational Contracts

For production deployments, see the **[Operational Contracts](../docs/OPERATIONAL_CONTRACTS.md)** documentation, which defines:

- Connection timeouts and keep-alive settings
- Retry policies and error handling
- Data consistency guarantees
- Idempotency contracts
- State persistence guarantees

These are protocol-level contracts that all SW4RM SDKs honor.

## Links

- Top-level README (overview and API): [`../../README.md`](../../README.md)
- Quickstart for running local services: [`../../QUICKSTART.md`](../../QUICKSTART.md)
- Operational Contracts: [`../docs/OPERATIONAL_CONTRACTS.md`](../docs/OPERATIONAL_CONTRACTS.md)
- Python SDK: [`../py_sdk/README.md`](../py_sdk/README.md)
- Rust SDK: [`../rust_sdk/README.md`](../rust_sdk/README.md)
- JavaScript SDK: [`../js_sdk/README.md`](../js_sdk/README.md)
