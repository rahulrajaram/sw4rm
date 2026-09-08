# Verification of the 0.7.0 development repair

This page records **dated local verification** of the 0.7.0 development tree.
It is not a release announcement and not a remote CI result: every record here
was produced on the local working tree of the branch noted in the record, and
publication remains an explicit maintainer action. Where two dated records
coexist, the most recent one (top) supersedes the older one, which is retained
only as evidence.

## SDK parity qualification (2026-09-05 UTC)

The subsequent SDK parity loop verified the complete canonical wire interface
in all five SDKs: **15 services, 57 RPCs, 512 shared message cases**. Each SDK
exchanged every RPC with the localhost Python serialization fixture, including
both server streams and requests with full-range 64-bit values. The fixture is
not an implementation of the corresponding services.

| Final check | Result |
|---|---|
| Python SDK plus release/documentation/crash harness tests | 1,580 passed; two existing health-service deprecation warnings |
| JavaScript SDK | 1,121 passed across 38 files |
| Rust SDK | Full default-feature library/integration/doc suites passed; the opt-in live wire target also passed explicitly |
| Elixir SDK | 919 passed, including every canonical RPC and the actual Python router delivery test |
| Common Lisp SDK | 1,872 checks passed, including every canonical RPC over native gRPC |
| Python wheel and sdist | Built; isolated wheel imports and all 57 generated RPC bindings passed |
| JavaScript distribution | Isolated ESM/CommonJS imports and all 57 RPC bindings passed |
| Rust distribution | Crate built; the unpacked crate compiled offline using its packaged proto sources |
| Elixir and Lisp source layouts | Compiled/loaded outside the checkout using cached dependencies; all 57 RPC bindings exposed |
| Source/docs gates | Wire generation, release/schema checks, scoped Ruff, JS ESLint and strict MkDocs build passed |

The new [SDK parity contract](sdk-parity.md) describes the supported interfaces
and common helper behavior. Repairs include complete Python/JS/Lisp wire clients,
Lisp native ABI/deadline/stream lifecycle fixes, envelope lineage and timestamp
preservation, and one portable byte-oriented idempotency helper in every SDK.
Existing legacy hash outputs remain unchanged and are explicitly nonportable.

Lisp native transport is now qualified on Linux x86-64, SBCL 2.2.9 and gRPC
1.51.1. Tests cover remote status/details, deadlines, cancellation, concurrent
calls, large/empty native slices, and disconnecting before a stream worker runs.
Other native platforms and TLS handshakes were not qualified. The earlier
assessment that libgrpc was absent was a loader error: this host has
`libgrpc.so.29` but no unversioned development symlink.

Elixir used the existing cached container/dependency path. Isolated source
compilation passed; normal Hex package construction and dependency resolution
remain unverified. The Rust reference-services executable and optional SDK
feature combinations are outside this default SDK qualification.

Reproduction adds these checks to the commands below:

```bash
python scripts/generate_sdk_wire_contract.py
SW4RM_TEST_PYTHON=python cargo test --manifest-path sdks/rust_sdk/Cargo.toml --test wire_contract -- --include-ignored
python tests/sdk_parity/with_wire_server.py -- sh -c 'cd sdks/ex_sdk && mix test'
python tests/sdk_parity/with_wire_server.py -- sbcl --non-interactive --load ~/quicklisp/setup.lisp --eval '(push (truename "sdks/cl_sdk/") asdf:*central-registry*)' --eval '(asdf:test-system :sw4rm-sdk)'
python scripts/check_source_packages.py lisp
python scripts/check_source_packages.py elixir
```

The source-layout checks use already-present tools/dependencies and do not
install packages. All changes remain local and unpublished. CI configuration
was updated; no remote CI run or release is claimed. The earlier repair record
below is retained as dated evidence.

??? details "Earlier repair qualification (2026-09-04) — superseded by the 2026-09-05 parity record"

    Observed on 2026-09-04 in the local working tree on `campaign/credibility-first`,
    based on commit `39212b6` plus the uncommitted release repair. This is a dated
    local verification record, not a published release or a remote CI result.

    ## Results

    | Check | Observed result | Boundary |
    |---|---|---|
    | Python SDK, release/documentation gates, crash-harness tests | 941 passed | Python 3.11; two existing protobuf health-service deprecation warnings |
    | JavaScript SDK | 483 passed, 36 files | Includes JS client against the actual Python reference router |
    | Rust SDK | 368 passed, 1 ignored | Default-feature library, integration, and documentation tests with cached offline dependencies |
    | Elixir SDK | 396 passed | Cached Elixir 1.16 container, compiled source and full ExUnit suite; includes actual Python-router integration |
    | Common Lisp SDK | 665 checks passed | SBCL/ASDF suite including transport codecs; existing style warnings remain |
    | Python crash experiments | 6 pass, 0 fail, 0 error | Fresh scorecard at 23:47:55 UTC; boundaries below |
    | Python distribution | Wheel and sdist built; isolated wheel import passed | All generated protobuf modules import; delivery ACK API is present |
    | JavaScript distribution | ESM and CommonJS package checks passed | Copied distributable files outside the repo; both formats construct a Router client from packaged schemas |
    | npm package inventory | Dry run passed | 84 distributable files; no upload |
    | Version/schema contract | Passed | 11 version carriers across five SDKs; Rust proto copies; generated schema and RPC reference |
    | Documentation | Offline contract check and strict MkDocs build passed | Local links, selected prose claims, schema snippets, first-agent imports/keywords |
    | Lint | Scoped Python Ruff and JS ESLint passed | This is not a claim that every optional example passes every lint configuration |

    The JavaScript package check found failures that source tests did not expose:
    bundled CommonJS dependencies broke ESM import, and CommonJS client construction
    needed a valid module URL. The build now retains declared external dependencies
    and supplies that URL in the CommonJS bundle. CI and npm publication run the
    isolated package check.

    Python and JavaScript recovery checks also found duplicate ordering for repeated
    message IDs. Repeated recording now preserves one ordering entry, including at
    capacity. Python SQLite snapshots now round-trip byte payloads and audit proofs,
    failed writes preserve the prior snapshot, and malformed persisted envelopes
    raise a load error instead of becoming empty data.

    ## Crash experiment boundaries

    - Negotiation proposals and votes survive a service process kill.
    - An accepted message survives a router process kill and restart.
    - An unacknowledged delivery is redelivered on reconnect.
    - A previously confirmed activity snapshot survives an interrupted replacement.
    - Corrupt persistence blocks normal startup.
    - A restarted consumer suppresses a repeated effect after its completion record
      was already flushed, then acknowledges the redelivery.

    These are process-failure experiments. They do not prove power-loss behavior on
    every filesystem or an atomic transaction between external effects and records.
    The pytest harness permits measured failure verdicts, so the separate fresh
    scorecard was checked for actual passing invariants, not merely harness success.

    ## Reproduce

    Use an environment with the repository's declared dependencies already prepared.

    ```bash
    python scripts/smoke_protos.py
    python scripts/release_contract.py
    python scripts/check_documentation.py
    PYTHONPATH=sdks/py_sdk python -m pytest sdks/py_sdk/tests tests/release tests/documentation tests/crash_conformance -q
    PYTHONPATH=sdks/py_sdk python tests/crash_conformance/run_scenarios.py --scorecard /tmp/sw4rm-crash-check.json
    python -m mkdocs build --strict
    python -m build --no-isolation --outdir /tmp/sw4rm-release-check
    python scripts/check_python_artifact.py /tmp/sw4rm-release-check/sw4rm_sdk-0.7.0-py3-none-any.whl
    ```

    From `sdks/js_sdk`, run `npm test`, `npm run build`, `npm run check:artifact`,
    `npm run lint`, and `npm pack --dry-run`. Set `SW4RM_TEST_PYTHON` when the Python
    interpreter with gRPC is not the default interpreter.

    From `sdks/rust_sdk`, run `cargo test --offline`. From `sdks/ex_sdk`, run
    `SW4RM_RUN_REFERENCE_INTEGRATION=1 mix test` in a prepared Mix environment.
    `sdks/ex_sdk/scripts/offline_test.sh` supplies a local-cache alternative without
    installing Hex or dependencies; its ordinary run skips the opt-in wire test.
    The observed full wire run additionally mounted the existing Python site-packages
    into the cached container. Common Lisp's README gives the full ASDF invocation.

    ## Remaining qualification limits

    The separate Rust reference-services build has a stale lockfile and a dependency
    not available in the local offline cache. Its build remains unverified here;
    the main Rust SDK build passes. Broad Rust example clippy checks have existing
    warnings. Elixir's normal Mix dependency-resolution path was unavailable locally;
    the successful cached-source run does not certify that packaging path.

    At the time of the earlier repair, Common Lisp's loader could not find libgrpc;
    that limitation was resolved and qualified by the parity loop above. The Python
    router's durable pending/lease behavior is not implemented by the JS/Rust demo
    routers. Security, replicated operation, load limits, and optional feature
    combinations require their own qualification.

    No dependencies were added or installed, no owner extension drafts were changed,
    and no commits, release tags, branch pushes, or package uploads were made.
