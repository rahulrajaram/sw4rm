# Keeping documentation aligned with code

This is the process every reporter, SDK change, and documentation edit must
pass so that prose, published packages, and generated references stay aligned.
It exists because of a concrete failure mode:

The previous process reviewed prose, counted passing tests, and checked links.
It could still publish a stale RPC list, a mismatched SDK version, or an
unsupported delivery claim. More agent reviewers alone do not close those gaps.

## Four checks with different responsibilities

| Check | What it demonstrates | What it does not demonstrate |
|---|---|---|
| Source-derived reference | Versions, canonical schema, and RPC inventory match the checkout | Server implementation or runtime correctness |
| Shared behavioral cases | SDKs agree on named inputs, outputs, and failure cases | Every feature or platform is identical |
| Package import/wire checks | Users receive usable bindings and clients can communicate | Production readiness or arbitrary effect atomicity |
| Prose/link checks and review | Detect known stale claims, snippet fields, invalid examples, and broken local links | General truth or market demand |

The generated references replace copied schema tables and prose test counts.
The specification states normative requirements. Implementation coverage names
which ones have working backends. Release status separates development versions
from published packages. Extension drafts remain clearly outside release claims.

## Updating a contract

1. Change the canonical proto or SDK behavior and its meaningful failure tests.
2. Synchronize packaged/generated bindings in every affected SDK.
3. Add or update shared conformance cases where behavior is intended to match.
4. Update migration and implementation coverage when the user-visible contract changes.
5. Regenerate reference pages and run the offline checks:

```bash
python scripts/release_contract.py --write-docs
python scripts/release_contract.py
python scripts/check_documentation.py
python -m pytest -q tests/release tests/documentation
```

The release-contract tests deliberately introduce version drift, missing
carriers, and schema changes. The documentation tests introduce stale fields,
broken links, and known false claims. A gate that still passes these mutations
is itself defective; counting its normal successful run is insufficient.

## Review behavior rather than wording alone

Accuracy and usable depth are separate review requirements. Compare changed
pages against their previous version: inventory removed examples, field tables,
procedures, explanations, and diagrams. Correct obsolete APIs in place or
replace them with a current worked example that serves the same reader need.
When moving material, verify the destination retains its substance and link
directly to the relevant section. A pointer alone does not replace a tutorial.

Generated references own exact wire definitions; practical guides explain how
to use them, inspect responses, recover from failures, and choose integration
boundaries. A shorter page or a passing build is not evidence of improvement.
Before accepting a restoration, execute its self-contained examples where
feasible and identify the setup assumed by each fragment.

For each new reliability claim, identify the actor, operation, failure boundary,
implementation, and test. For example: after an accepted message and a router
process kill, a restarted consumer receives it; after a completion token is
flushed, a duplicate can be recognized. Neither test proves an arbitrary external
effect happens once.

Run the SDK's own code against the contract. Test package artifacts outside an
editable checkout. Keep at least one cross-language exchange against the actual
reference server. Store test results in CI with the source revision; do not turn
a passing old status report into a current certification.

## CI and scope

Docs CI responds to source/schema/SDK/test changes as well as Markdown changes.
Version checking covers all five SDKs, public version exports, and lockfile root
entries. Python release workflows generate bindings before building and import
the resulting wheel. JS and Elixir CI prepare the Python fixture for cross-language
testing. JS CI and publication also construct clients from both built module
formats in an isolated package directory. Lisp CI runs the complete ASDF suite
and fails when its checks fail.

The offline prose checker intentionally has a bounded scope. It catches explicit
known claim patterns and schema snippet mismatches; it cannot establish that any
arbitrary sentence is true. The three pre-existing owner extension drafts are
preserved and are not silently rewritten by the audit.

For contributor setup (docs dependencies, `mkdocs serve`, build and deploy
options), see the documentation handbook at `documentation/README.md` in the
repository — it is excluded from the published site on purpose and lives only
in the source tree.

## Additional techniques worth adopting next

- **Change-focused review:** present the changed contract, affected SDKs,
  associated examples, and failing behavioral cases together. Assign review of
  the remaining semantic claims to someone who did not write the implementation.
- **Claim expiry:** time-sensitive publication and operational evidence should
  carry the observation date and source revision. Expired observations remain
  historical evidence instead of continuing to appear as current certification.
- **Scenario-first docs:** derive the central tutorial from a runnable example
  tested against a disposable server, and explicitly label fragments that are
  illustrative rather than executable.

The first four gates are implemented in this release repair. The additional
techniques are proposals; no new external agent framework or capability bundle
is required or installed.
