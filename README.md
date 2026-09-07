# SW4RM

A coordination protocol and SDK toolkit for independently implemented agents.

[![Python CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml)
[![Rust CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml)
[![JS CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml)

## What is this?

SW4RM gives agents a common vocabulary for messages, handoffs, proposals, review
votes, and decisions. Applications supply the agents and their work; SDKs expose
the protocol in Python, JavaScript/TypeScript, Rust, Elixir, and Common Lisp.

The repository includes Python reference services for Registry, Router,
Scheduler, and NegotiationRoom. Other protocol services have contracts and client
helpers but no reference backend. See [implementation coverage](documentation/protocol/implementation.md)
before choosing a deployment architecture. This is an experimental toolkit,
with a narrower implemented surface than the full specification.

**Published packages are 0.6.0. The next release target is 0.7.0, currently
unpublished.** The new router requires consumer delivery acknowledgements.
Read [release status and migration](documentation/release-status.md) before
mixing SDK/server versions.

## Features

- A typed protobuf contract for messages and coordination operations.
- A Python reference router with SQLite-backed pending deliveries, explicit
  consumer acknowledgements, and redelivery after disconnect or lease expiry.
- A negotiation-room service that persists proposals, votes, and decisions.
- Local score aggregation, quorum, handoff, cancellation, and workflow helpers,
  with language-specific APIs and per-SDK tests.
- Persistent activity buffers with explicit failure handling on supported
  backends. Applications remain responsible for idempotent external effects.
- An [A2A gateway](a2a_gateway/README.md) exposing a subset of task operations.

The [generated release reference](documentation/reference/release-contract.md)
lists the actual RPCs and every version carrier. Counts are generated from source;
passing test counts are reported by CI rather than copied into this README.

## Installation

These commands install the currently published **0.6.0** packages:

```bash
pip install sw4rm-sdk==0.6.0
npm install @sw4rm/js-sdk@0.6.0
```

```toml
# Cargo.toml
[dependencies]
sw4rm-sdk = "0.6.0"
```

```elixir
# mix.exs: deps/0
[{:sw4rm_sdk, "~> 0.6.0"}]
```

For the **0.7.0 development contract**, use this checkout consistently for
servers and clients. Python source setup:

```bash
python -m pip install -e ".[dev,test]"
python scripts/smoke_protos.py
```

| SDK | Setup, API, and tests |
|---|---|
| Python | [SDK README](sdks/py_sdk/README.md) |
| JavaScript/TypeScript | [SDK README](sdks/js_sdk/README.md) |
| Rust | [SDK README](sdks/rust_sdk/README.md) |
| Elixir | [SDK README](sdks/ex_sdk/README.md) |
| Common Lisp | [SDK README](sdks/cl_sdk/README.md) |

Common Lisp is loaded as an ASDF system from the checkout; the linked README
states its transport and persistence platform requirements. A package version
does not imply identical runtime implementations or interchangeable snapshot files.

## Quick start

Start the Python reference stack from a prepared source checkout:

```bash
cd sdks/py_sdk/reference-services
bash start_services.sh --local
```

Or build the container stack from the repository root:

```bash
docker compose up --build -d
```

The usual stack runs Registry on 50052, Router on 50051, Scheduler on 50053, and
the A2A gateway on 8080. NegotiationRoom is a separate service.
Follow [Your first agent](documentation/quickstart/first-agent.md) for a producer
and consumer that explicitly acknowledge deliveries. Registry registration alone
does not demonstrate completed work.

## Delivery and recovery

A consumer preserves `StreamItem.seq`, completes processing or durably transfers
responsibility, and calls `AckDelivery`. The router retains unacknowledged rows
for redelivery. Application ACK stages such as `READ` and `FULFILLED` report
progress separately; they do not release a delivery row.

This is at-least-once delivery. If an external side effect succeeds and the
consumer dies before persisting completion, the effect may happen again.
A deduplication token alone cannot close that transaction boundary. See
[the router contract](documentation/clients/router.md) and
[recovery limits](documentation/release-status.md).

## Protocol, architecture, and configuration

- [Overview](documentation/overview.md): concepts and operating boundaries.
- [Specification](documentation/protocol/spec.md): normative requirements.
- [Implementation coverage](documentation/protocol/implementation.md): service-backed and local features.
- [SDK clients](documentation/clients/index.md): language-specific APIs.
- [Examples](documentation/examples/index.md): runnable and illustrative examples.
- [A2A gateway](a2a_gateway/README.md): implemented HTTP/JSON-RPC endpoints.

The default reference deployment assumes a trusted environment. Identity fields
are not authentication, and the repository does not supply replicated consensus
or a general production authorization boundary. Configure storage, authentication,
TLS, and process supervision for the application being deployed.

## CLI reference

The Python package installs a local diagnostic command. It checks generated
bindings and reports configured addresses; it does not contact services.

```text
usage: sw4rm-doctor [-h] [--version]

Check local SDK bindings and configured service addresses; does not contact
servers.

options:
  -h, --help  show this help message and exit
  --version   show program's version number and exit
```

Run the command without arguments for its JSON diagnostic result.

## Development and documentation checks

With the existing development dependencies installed:

```bash
python scripts/release_contract.py
python scripts/check_documentation.py
python scripts/smoke_protos.py
python -m pytest -q sdks/py_sdk/tests
```

The release-contract check covers all five SDK versions, exported versions,
lockfiles, packaged proto copies, and generated reference pages. Behavioral
parity is exercised by SDK tests and shared conformance vectors. Documentation
CI runs on source changes too. See [documentation maintenance](documentation/documentation-contract.md)
for updating generated material and testing drift detection.

For the Python package, build and import the artifact before publishing:

```bash
python -m build
python scripts/check_python_artifact.py dist/*.whl
```

## Release

Use the version tool to prepare a local release candidate:

```bash
python scripts/bump_version.py 0.7.0
python scripts/release_contract.py
```

Publishing is tag-driven and requires explicit maintainer review. The release
workflows generate/check package contents before upload. No release is implied by
a manifest bump. See [CONTRIBUTING](CONTRIBUTING.md) and
[release migration](documentation/release-status.md).

## License

[Apache License 2.0](LICENSE).
