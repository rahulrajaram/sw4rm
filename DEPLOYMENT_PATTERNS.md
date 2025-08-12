Deployment Patterns — Open Questions and Assumptions
====================================================

This file tracks ambiguities discovered while expanding documentation for deployments. It is intentionally not staged or committed unless requested, and serves as a working log for follow-up.

Images and Versioning
---------------------
- Assumption: Container images exist under `ghcr.io/rahulrajaram/sw4rm/{router,registry,scheduler}`.
  - Action bias: Used these image names with `:latest` in examples.
  - Open question: What are the officially supported tags and upgrade policy? Should examples pin to a specific minor (e.g., `:0.1.x`) instead of `:latest`?

Ports and Endpoints
-------------------
- Observed defaults from Python SDK constants: router `localhost:50051`, registry `localhost:50052`.
  - Action bias: Corrected Compose example so Router publishes `50051` and Registry `50052`.
  - Open question: Are these ports authoritative for the server implementations as well, or do images use different defaults via flags/env?

TLS/mTLS Configuration
----------------------
- Ambiguity: Exact flags/environment variables the Router/Registry/Scheduler images accept for enabling TLS/mTLS, and expected file paths for certs/keys/CA bundles.
  - Action bias: Documented patterns (mount `Secret`, use `secure=True` for clients) without specific flags.
  - Open question: Provide canonical env names (e.g., `SW4RM_TLS_CERT_FILE`, `SW4RM_TLS_KEY_FILE`, `SW4RM_TLS_CA_FILE`) and example cert generation steps.

Persistence and Data Paths
--------------------------
- Assumption: Router persists state at `/var/lib/sw4rm` inside the container.
  - Action bias: Mounted a volume at that path in Compose and Kubernetes examples.
  - Open question: Which components are stateful and what are the precise data directories? Are there compaction/retention knobs to expose in docs?

Health Probes
-------------
- Ambiguity: Whether images expose gRPC health (`grpc.health.v1.Health/Check`) or HTTP health endpoints.
  - Action bias: Used `tcpSocket` probes in Kubernetes for simplicity.
  - Open question: If gRPC health is available, document the service names and example probes; otherwise, define a reliable TCP or HTTP check.

Resource Guidance
-----------------
- Assumption: Light defaults suffice for examples (requests/limits in the hundreds of MiB and <1 CPU).
  - Action bias: Provided conservative placeholders in Kubernetes manifests.
  - Open question: Provide profiling-derived guidance per service for common workloads (messages/sec, concurrent agents, etc.).

Observability
-------------
- Ambiguity: Specific metrics/traces/logs endpoints and configuration (Prometheus ports, OTLP, etc.).
  - Action bias: Mentioned exporting to your APM/SIEM without concrete flags.
  - Open question: List supported exporters and sample configuration for Router/Registry/Scheduler.

Scheduler and External Stores
-----------------------------
- Ambiguity: Whether Scheduler and Router depend on external data stores (e.g., Postgres/Redis) and recommended topologies.
  - Action bias: Suggested HA backends as a general pattern.
  - Open question: Provide a reference architecture with explicit dependencies and minimal versions.

Client SDK Assumptions
----------------------
- Observed: Python SDK expects protobuf stubs to be generated (`make protos`).
  - Action bias: Emphasized this in the guide; used `sw4rm-doctor` for validation.
  - Open question: Should the SDK auto-generate stubs at import time if missing, or ship prebuilt stubs for common use?

Networking and Security
-----------------------
- Ambiguity: Recommended network policies (Kubernetes) and service account/RBAC requirements for each component.
  - Action bias: Left minimal manifests; suggested adding NetworkPolicy and PodSecurity in production.
  - Open question: Provide canonical policies and example least-privilege RBAC for cluster installs.

Migration Paths
---------------
- Ambiguity: Supported migration path from single-node → HA → Kubernetes, including state migrations and zero-downtime steps.
  - Action bias: Included general upgrade and canary guidance.
  - Open question: Publish a step-by-step playbook for each migration path with validation checkpoints.

Next Steps for Resolution
-------------------------
1) Confirm official image names, default ports, and flags for TLS, logging, and persistence.
2) Provide a minimal cert management example (mkcert, step-ca, or openssl) for local mTLS parity.
3) Add gRPC health probe examples (if supported) and Prometheus scrape annotations (if metrics exposed).
4) Publish resource sizing guidance based on internal benchmarks.
5) Add Helm charts or Kustomize overlays as supported deployment options.

