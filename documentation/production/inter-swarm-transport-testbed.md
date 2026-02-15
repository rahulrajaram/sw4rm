# Inter-Swarm Production Transport Testbed

This runbook documents the `I52` bootstrap scaffold, the `I54` repeatable smoke workflow promotion, and the `I55` CI smoke/evidence lockstep checks for production-transport integration work.
It provides a reproducible dual-swarm baseline and a canonical smoke command wrapper for follow-on native inter-swarm transport tranches.

## Scope

- Bootstrap two independent swarms (`swarm-a`, `swarm-b`) with isolated Router/Registry/Scheduler ports.
- Use gRPC transport and gRPC health checks as the baseline transport contract.
- Provide one local manifest and one multi-process compose scaffold that can run on one host now and be split across hosts later.

## Scaffold Artifacts

- Manifest: `tests/inter_swarm_testbed/bootstrap_manifest.json`
- Compose scaffold: `tests/inter_swarm_testbed/docker-compose.multi-swarm.yml`
- Bootstrap validation test: `sdks/py_sdk/tests/test_inter_swarm_testbed_bootstrap.py`
- Canonical smoke wrapper: `tests/inter_swarm_testbed/smoke_workflow.py`
- CI smoke target: `tests/inter_swarm_testbed/ci_smoke_target.py`

## Canonical Smoke Workflow

Run proto generation/import smoke before testbed checks:

```bash
make smoke
```

Run the canonical bounded smoke workflow (no container bring-up):

```bash
python tests/inter_swarm_testbed/smoke_workflow.py --mode bounded
```

This bounded workflow is the repeatable tranche entrypoint and executes:

- Manifest + compose layout validation test (`sdks/py_sdk/tests/test_inter_swarm_testbed_bootstrap.py`)
- Compose syntax validation (`docker compose config --quiet`) when docker is available
- Deterministic docker-step skips when docker is unavailable unless `--require-docker` is set

## CI Smoke Target and Evidence

Run the CI-equivalent smoke target locally:

```bash
python tests/inter_swarm_testbed/ci_smoke_target.py --summary-json artifacts/verification/i55-ci-smoke-summary.json --log-file artifacts/verification/i55-ci-smoke-workflow.log
```

The canonical CI workflow executes the same command and enforces docs lockstep checks in `.github/workflows/ci-inter-swarm-smoke-evidence.yml`.

Verification evidence artifacts are published under:

- `artifacts/verification/i55-ci-smoke-summary.json`
- `artifacts/verification/i55-ci-smoke-workflow.log`

## Full Compose Smoke (Docker Required)

Run full bring-up/status/teardown smoke workflow:

```bash
python tests/inter_swarm_testbed/smoke_workflow.py --mode compose --require-docker
```

Equivalent manual commands remain:

```bash
docker compose -f tests/inter_swarm_testbed/docker-compose.multi-swarm.yml up --build -d
docker compose -f tests/inter_swarm_testbed/docker-compose.multi-swarm.yml ps
docker compose -f tests/inter_swarm_testbed/docker-compose.multi-swarm.yml down -v
```

## Multi-Host Expansion Pattern

`bootstrap_manifest.json` already models per-swarm host identities and ports.
To split across hosts in follow-on tranches:

1. Pin each swarm entry to a real host/address.
2. Replace local `127.0.0.1` host mappings with routable hostnames or static IPs.
3. Switch transport profile from `local-insecure` to `production-mtls`.
4. Add cross-host smoke probes (`grpcurl` + SDK caller redirect helpers) against both gateway endpoints.

## Caveats

- This tranche provides bootstrap scaffolding and validation checks; it does not yet enable full native cross-host gateway orchestration.
- JS/TS, Rust, and Common Lisp transport helpers remain wired for local parity logic, while production inter-swarm transport orchestration is tracked in follow-on planning.
