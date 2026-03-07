# SW4RM Common Lisp SDK

Reference Common Lisp SDK for the SW4RM Agentic Protocol. This is one of five SDKs in this repository (Python, Rust, JavaScript, Elixir, Common Lisp) and provides a full peer implementation with idiomatic CL condition/restart error handling patterns.

## Features

- **Full protocol coverage**: Clients for all SW4RM services (Registry, Router, Scheduler, HITL, Worktree, Tool, Connector, Negotiation, Reasoning, Logging)
- **Condition/restart error handling**: Idiomatic CL error recovery via `with-sw4rm-error-handling`
- **Envelope helpers**: Three-ID model envelope construction with HLC timestamps
- **Activity buffer**: Persistent message tracking with reconciliation
- **Worktree state**: Policy-driven binding management
- **Voting aggregation**: Confidence-weighted strategies for negotiation decisions
- **Secret management**: Encrypted credential storage with audit logging
- **State machine**: 12-state agent lifecycle matching the protocol spec
- **LLM client layer**: Provider-agnostic Groq/Anthropic/mock clients with adaptive rate limiting

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
   :version "0.6.0"
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

## LLM Client

The SDK includes a provider-agnostic LLM client layer with Groq, Anthropic, and mock backends.

### Class Hierarchy

```
llm-client              ;; abstract base (CLOS class)
  groq-client           ;; Groq API (OpenAI-compatible endpoint)
  anthropic-client      ;; Anthropic Claude Messages API
  mock-llm-client       ;; deterministic responses for testing
```

All concrete clients implement the `llm-query` generic function and return response plists of the form `(:content "..." :model "..." :usage (:input-tokens N :output-tokens N))`.

### Factory Usage

The `create-llm-client` factory resolves the backend from an explicit argument, the `LLM_CLIENT_TYPE` environment variable, or defaults to `"mock"`.

```lisp
;; Auto-detect from environment (defaults to Mock)
(defvar *llm* (create-llm-client))

;; Explicit Anthropic client with key
(defvar *llm* (create-llm-client :client-type "anthropic"
                                  :api-key "sk-ant-..."))

;; Mock client for tests -- no credentials needed
(defvar *llm* (create-llm-client :client-type "mock"))
```

### Credential Chain

Each real client resolves API keys in the same order:

1. `:api-key` constructor parameter
2. Environment variable (`GROQ_API_KEY` or `ANTHROPIC_API_KEY`)
3. Dotfile in home directory (`~/.groq` or `~/.anthropic`, first line)

If none are found, `llm-authentication-error` is signaled at construction time.

### Querying

```lisp
(let ((response (llm-query *llm* "Summarize the SW4RM protocol."
                           :system-prompt "You are a helpful assistant."
                           :max-tokens 1024
                           :temperature 0.7)))
  (format t "~A~%" (llm-response-content response))
  (format t "Model: ~A~%" (llm-response-model response))
  (format t "Tokens: ~A~%" (llm-response-usage response)))
```

The `:model` keyword overrides the client's default model for a single call.

### Mock Client for Testing

```lisp
;; Cycle through canned responses
(let ((client (make-mock-llm-client :responses '("alpha" "beta"))))
  (llm-query client "first")   ;; => :content "alpha"
  (llm-query client "second")  ;; => :content "beta"
  (llm-query client "third")   ;; => :content "alpha"  (cycles)
  (mock-client-call-count client)   ;; => 3
  (mock-client-call-history client) ;; list of recorded call plists
  (mock-client-reset client))       ;; reset counters

;; Dynamic responses via generator function
(let ((client (make-mock-llm-client
                :response-generator (lambda (prompt)
                                      (format nil "Echo: ~A" prompt)))))
  (llm-response-content (llm-query client "ping")))
  ;; => "Echo: ping"
```

### Rate Limiter

All real clients share a global token-bucket rate limiter (`*global-rate-limiter*`). It refills tokens at a steady rate and adaptively throttles on 429 responses.

```lisp
;; Access or create the global limiter (default: 250,000 TPM)
(get-global-rate-limiter)

;; Create a custom limiter
(make-rate-limiter :tokens-per-minute 100000
                   :reduction-factor 0.7d0
                   :recovery-factor 1.1d0
                   :cooldown-seconds 30.0d0
                   :successes-for-recovery 20
                   :max-wait-seconds 120.0d0)

;; Reset for test isolation
(reset-global-rate-limiter)
```

The limiter is thread-safe (bordeaux-threads lock) and automatically wired into Groq and Anthropic clients at construction.

### Condition Hierarchy

All LLM conditions inherit from `sw4rm-error` and integrate with `with-sw4rm-error-handling`.

| Condition | Signaled when |
|---|---|
| `llm-error` | Base condition for any LLM API failure |
| `llm-authentication-error` | Invalid/missing API key, billing issues (401, 403) |
| `llm-rate-limit-error` | Rate limit exceeded (HTTP 429) |
| `llm-timeout-error` | Request or rate-limiter wait timed out (408, 504) |

```lisp
(handler-case
    (llm-query *llm* "hello")
  (llm-rate-limit-error (c)
    (format t "Rate limited: ~A~%" (sw4rm-error-message c)))
  (llm-authentication-error (c)
    (format t "Auth failed: ~A~%" (sw4rm-error-message c)))
  (llm-error (c)
    (format t "LLM error: ~A~%" (sw4rm-error-message c))))
```

### Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `LLM_CLIENT_TYPE` | Factory backend (`"groq"`, `"anthropic"`, `"mock"`) | `"mock"` |
| `LLM_DEFAULT_MODEL` | Override default model for factory | per-client default |
| `GROQ_API_KEY` | Groq API key | none |
| `GROQ_DEFAULT_MODEL` | Groq model override | `llama-3.3-70b-versatile` |
| `ANTHROPIC_API_KEY` | Anthropic API key | none |
| `ANTHROPIC_DEFAULT_MODEL` | Anthropic model override | `claude-sonnet-4-20250514` |

### Running LLM Tests

```bash
cd sdks/cl_sdk
sbcl --load test/run-llm-tests.lisp
```

The test suite uses the mock client exclusively and does not require API keys.

## Architecture

The SDK follows the same layered pattern as the other SW4RM SDKs:

- **`src/`** - Core modules (constants, envelope, state machine, activity buffer, worktree, voting, persistence, errors)
- **`src/llm/`** - LLM client layer (base, factory, Groq, Anthropic, mock, rate limiter)
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
