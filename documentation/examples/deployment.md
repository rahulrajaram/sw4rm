# 4. Deployment Patterns

This guide is a pragmatic, step-by-step walkthrough for deploying SW4RM-based systems from local development to production. It includes actionable commands for macOS and Debian Linux, Python SDK usage snippets, and Infrastructure-as-Code examples with Docker Compose and Kubernetes. When a detail is ambiguous or environment-specific, we call it out explicitly and suggest a safe default. We also record outstanding ambiguities and assumptions in DEPLOYMENT_PATTERNS.md.

Important defaults used by the Python SDK (see `sdks/py_sdk/sw4rm/constants.py`):

- Router address env var: `SW4RM_ROUTER_ADDR` (default `localhost:50051`)
- Registry address env var: `SW4RM_REGISTRY_ADDR` (default `localhost:50052`)
- Optional: `AGENT_ID`, `AGENT_NAME` for client identity; sensible defaults apply.

Tip: After setup, validate SDK wiring:

```bash
sw4rm-doctor
```

## 4.1. Prerequisites

Choose your OS to prepare a baseline environment for local development and operator workflows.

**macOS (Apple Silicon or Intel)**:


1. Install Homebrew if needed:
    ```bash
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ```
2. Install core tools and Docker Desktop:
    ```bash
    brew install python@3.11 grpcurl kubectl
    brew install --cask docker
    ```
3. Enable Docker Desktop and ensure it’s running (for Compose/Kubernetes demos).
4. Optional docs/dev tooling (for make protos, docs, etc.):
    ```bash
    brew install make
    ```

**Debian/Ubuntu (root or sudo)**:


1. Install Python and build tools:
    ```bash
    sudo apt-get update && \
      sudo apt-get install -y python3 python3-venv python3-pip make
    ```
2. Install Docker Engine and Compose plugin:
    ```bash
    sudo apt-get install -y docker.io docker-compose-plugin
    ```
3. Install kubectl (vendor instructions may vary):
    ```bash
    sudo snap install kubectl --classic  # if Snap is available
    ```
4. Use Docker without sudo (new shell required):
    ```bash
    sudo usermod -aG docker $USER
    newgrp docker
    ```

**Notes and caveats**:


- `grpcurl` is optional but useful for quick gRPC health checks.
- If your environment uses a proxy or corporate CA, ensure Docker and Python trust your CA (see `DEPLOYMENT_PATTERNS.md` for notes on custom CAs and mTLS).

## 4.2. Local Development (Single Node)

Run the core control plane services (Router, Registry, Scheduler) on localhost for fast iteration. Use file-backed persistence and allow insecure transport locally unless you are explicitly testing mTLS.

Option A — Python SDK only (connect to an existing control plane):


1. Create a virtual environment:
    ```bash
    python3 -m venv venv && \
        . venv/bin/activate
    ```
2. Install SDK + dev dependencies:
    ```bash
    pip install -e .[dev]
    ```
3. Generate Python protobuf stubs:
    ```bash
    make protos
    ```
4. Sanity check SDK wiring:
    ```bash
    sw4rm-doctor
    ```

**Option B — Start local control plane via Docker Compose**:


1. Create `docker-compose.yml` with the example below (adjust tags/paths as needed).
2. Start the stack:
    ```bash
    docker compose up -d
    ```
3. Verify ports are open (router and registry):
    ```bash
    grpcurl -plaintext localhost:50051 list || true
    grpcurl -plaintext localhost:50052 list || true
    ```
4. Point SDK to local endpoints via environment variables (see the env block below).

### Python: connecting to Router and Registry

Ensure stubs are generated before running clients:

```bash
make protos
```

The example below demonstrates:


- Reading endpoints from env via `sw4rm.config.from_env()`.
- Creating gRPC channels with an optional correlation-id interceptor.
- Registering an agent, sending a message, and starting an incoming stream.

```python
import os
from sw4rm.config import from_env
from sw4rm.interceptors import channel_with_interceptors, CorrelationIdClientInterceptor
from sw4rm.clients.router import RouterClient
from sw4rm.clients.registry import RegistryClient

# Optionally set env vars before import or in your shell:
# export SW4RM_ROUTER_ADDR=localhost:50051
# export SW4RM_REGISTRY_ADDR=localhost:50052
# export AGENT_ID=agent-1
# export AGENT_NAME="Agent One"

cfg = from_env()

# Create channels (plaintext for local dev). Use secure=True with proper TLS creds in production.
router_ch = channel_with_interceptors(
    cfg.endpoints.router_addr,
    CorrelationIdClientInterceptor(correlation_id="local-dev-123"),
    secure=False,
)
registry_ch = channel_with_interceptors(cfg.endpoints.registry_addr, secure=False)

router = RouterClient(router_ch)
registry = RegistryClient(registry_ch)

# Register the agent (shape must match your .proto definition)
agent_desc = {
    "agent_id": cfg.agent_id,
    "name": cfg.name,
    "description": "Local dev agent",
}
try:
    registry.register(agent_desc)
    print("Registered agent:", agent_desc["agent_id"])
except Exception as e:
    print("Register failed; is Registry running?", e)

# Send a test message to the Router (shape must match Envelope in your .proto)
envelope = {
    "message_type": 1,  # CONTROL (see sw4rm.constants)
    "source": cfg.agent_id,
    "destination": "router",
    "payload": b"hello from local dev",
}
try:
    router.send_message(envelope)
    print("Message sent")
except Exception as e:
    print("Send failed; is Router running?", e)

# Stream incoming messages for this agent (runs until interrupted)
try:
    for msg in router.stream_incoming(cfg.agent_id):
        print("incoming:", msg)
except KeyboardInterrupt:
    pass
except Exception as e:
    print("Stream failed; is Router running?", e)
```

## 4.2.1. Build Your Own Images (Local Development)

If you don't have published container images yet, build local images and reference them in Compose. Below are templates; replace paths/names with your implementation.

Example Dockerfile for a service (Python-based):

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir -e .
EXPOSE 50051
CMD ["python", "-m", "your_service.entrypoint", "--addr", "0.0.0.0:50051"]
```

Compose referencing local builds:

```yaml
version: '3.9'
services:
  router:
    build: ./services/router        # path to your router source
    image: sw4rm-router:dev
    ports: ["50051:50051"]
    volumes: ["router-data:/var/lib/sw4rm"]
    restart: unless-stopped

  registry:
    build: ./services/registry
    image: sw4rm-registry:dev
    ports: ["50052:50052"]
    restart: unless-stopped

  scheduler:
    build: ./services/scheduler
    image: sw4rm-scheduler:dev
    ports: ["50053:50053"]
    restart: unless-stopped

volumes:
  router-data:
```

Build and start:

```bash
docker compose build
docker compose up -d
```

### Docker Compose: local dev stack (single-node)

The following Compose file builds Router, Registry, and Scheduler from your local sources, publishes standard ports, and persists Router state to a local volume.

```yaml
version: '3.9'
services:
  router:
    build: ./services/router
    image: sw4rm-router:dev
    container_name: sw4rm-router
    ports:
      - "50051:50051"  # Router
    volumes:
      - router-data:/var/lib/sw4rm
    restart: unless-stopped

  registry:
    build: ./services/registry
    image: sw4rm-registry:dev
    container_name: sw4rm-registry
    ports:
      - "50052:50052"  # Registry
    restart: unless-stopped

  scheduler:
    build: ./services/scheduler
    image: sw4rm-scheduler:dev
    container_name: sw4rm-scheduler
    ports:
      - "50053:50053"  # Scheduler
    restart: unless-stopped

volumes:
  router-data:
```

Environment variables for your Python clients:

```bash
export SW4RM_ROUTER_ADDR=localhost:50051
export SW4RM_REGISTRY_ADDR=localhost:50052
export AGENT_ID=my-agent
export AGENT_NAME="My Agent"
```

macOS specific notes:


- Use Docker Desktop; `docker compose` is available as part of it.
- For grpcurl installs via Homebrew, omit `sudo`. Use `grpcurl -plaintext` for local.

Debian specific notes:


- If `docker compose` subcommand is not present, use `docker-compose` or install the compose plugin (`docker-compose-plugin`).
- If `grpcurl` is not available via apt, use the binary release or `go install`.

## 4.3. Single-Node Production (VM/Bare metal)

Consolidate services on one host/VM for a small production footprint. Add supervision, persistence, and security hardening.

Recommended practices:


- Security: enable TLS/mTLS across service-to-service traffic. Store certs/keys in a secure location and mount read-only. Rotate credentials regularly.
- Persistence: configure volumes for Router state and any local WAL/logs. Set up periodic backups and verify restores.
- Resource isolation: set per-service CPU/memory limits. Use systemd (or Docker restart policies) for restarts.
- Observability: ship logs to your SIEM; export metrics/traces. Establish alerting on SLOs.

Example: systemd unit for Router (non-containerized)

```ini
[Unit]
Description=SW4RM Router
After=network.target

[Service]
User=sw4rm
Group=sw4rm
ExecStart=/usr/local/bin/sw4rm-router --addr 0.0.0.0:50051 --state-dir /var/lib/sw4rm
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

Note: Binary names and flags may differ depending on your distribution or packaging. If you rely on containers even on single-node hosts, prefer the Docker Compose approach with pinned image tags.

## 4.4. Multi-Node, Highly Available

Scale out the control plane horizontally behind L4/L7 load balancers; use HA backends for shared state where applicable.

Checklist:


- State: If Router/Scheduler depend on external stores (e.g., Postgres/Redis), deploy them in HA (primary/replica or cluster) with backups.
- Upgrades: perform rolling or canary deployments; validate with synthetic checks before 100% rollout.
- Networking: enforce mTLS for all east-west traffic; segment networks by environment/tenant. Use security groups and network policies.
- Capacity: set HPA or autoscaling policies and budget headroom for failover.

## 4.5. Kubernetes Reference Manifests

The snippet below targets a minimal, non-mTLS dev cluster. Replace image tags with your approved versions. For production, add PodSecurity, NetworkPolicy, Secrets for TLS, resource quotas, and PodDisruptionBudgets.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: sw4rm
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: router
  namespace: sw4rm
spec:
  replicas: 1
  selector: { matchLabels: { app: router } }
  template:
    metadata:
      labels: { app: router }
    spec:
      containers:
        - name: router
          image: localhost:5000/sw4rm-router:dev
          ports:
            - containerPort: 50051
          volumeMounts:
            - name: router-data
              mountPath: /var/lib/sw4rm
          readinessProbe:
            grpc:
              port: 50051
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            grpc:
              port: 50051
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits: { cpu: "500m", memory: "512Mi" }
      volumes:
        - name: router-data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: router
  namespace: sw4rm
spec:
  selector: { app: router }
  ports:
    - name: grpc
      port: 50051
      targetPort: 50051
      protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: sw4rm
spec:
  replicas: 1
  selector: { matchLabels: { app: registry } }
  template:
    metadata:
      labels: { app: registry }
    spec:
      containers:
        - name: registry
          image: localhost:5000/sw4rm-registry:dev
          ports:
            - containerPort: 50052
          readinessProbe:
            grpc:
              port: 50052
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            grpc:
              port: 50052
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits: { cpu: "250m", memory: "256Mi" }
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: sw4rm
spec:
  selector: { app: registry }
  ports:
    - name: grpc
      port: 50052
      targetPort: 50052
      protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: scheduler
  namespace: sw4rm
spec:
  replicas: 1
  selector: { matchLabels: { app: scheduler } }
  template:
    metadata:
      labels: { app: scheduler }
    spec:
      containers:
        - name: scheduler
          image: localhost:5000/sw4rm-scheduler:dev
          ports:
            - containerPort: 50053
          readinessProbe:
            grpc:
              port: 50053
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            grpc:
              port: 50053
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits: { cpu: "250m", memory: "256Mi" }
---
apiVersion: v1
kind: Service
metadata:
  name: scheduler
  namespace: sw4rm
spec:
  selector: { app: scheduler }
  ports:
    - name: grpc
      port: 50053
      targetPort: 50053
      protocol: TCP
```

Client configuration inside the cluster (Python SDK):

```bash
# If your app runs in the cluster, target the ClusterIP services
export SW4RM_ROUTER_ADDR=router.sw4rm.svc.cluster.local:50051
export SW4RM_REGISTRY_ADDR=registry.sw4rm.svc.cluster.local:50052
```

Health checks:


- If your images expose gRPC health, prefer gRPC health probes over tcpSocket.
- Otherwise, use tcpSocket or HTTP-based probes where available.

TLS/mTLS in Kubernetes (outline; non-normative — for example only):


- Create a `Secret` containing certs/keys; mount read-only into Pods.
- Configure services to use TLS flags/env. The protocol does not mandate specific env names; example below shows one possible convention.
- Distribute CA bundle to clients; set `secure=True` when creating channels and provide credentials if needed.

Example TLS/mTLS env convention:

```yaml
env:
  - name: SW4RM_TLS_ENABLED
    value: "true"
  - name: SW4RM_TLS_MODE
    value: "mtls"   # tls|mtls
  - name: SW4RM_TLS_CERT_FILE
    value: "/etc/sw4rm/tls/tls.crt"
  - name: SW4RM_TLS_KEY_FILE
    value: "/etc/sw4rm/tls/tls.key"
  - name: SW4RM_TLS_CA_FILE
    value: "/etc/sw4rm/tls/ca.crt"
volumeMounts:
  - name: tls
    mountPath: /etc/sw4rm/tls
    readOnly: true
volumes:
  - name: tls
    secret:
      secretName: router-tls
```

Client-side (Python SDK) would set `secure=True` when creating the channel and load CA/cert/key as needed.

## 4.5.1. Build Your Own Images (Kubernetes)

For dev clusters without published images, build and push images to a local registry, then reference them in the manifests:

```bash
# Example: build and tag
docker build -t localhost:5000/sw4rm-router:dev ./services/router
docker push localhost:5000/sw4rm-router:dev

# Update Deployment image: localhost:5000/sw4rm-router:dev
```

## 4.6. Environment Configuration Cheatsheet

Common environment variables used by the Python SDK and examples:

```bash
# Endpoints
export SW4RM_ROUTER_ADDR=localhost:50051
export SW4RM_REGISTRY_ADDR=localhost:50052

# Agent identity (used by sdks/py_sdk/sw4rm/config.py)
export AGENT_ID=agent-1
export AGENT_NAME="Agent"

# Example: set higher log verbosity for your app (if applicable)
export LOG_LEVEL=DEBUG
```

## 4.7. Rollout and Operations Checklist


- Identity and transport: TLS/mTLS configured, cert rotation scheduled, authorization policies validated.
- Persistence: backups tested end-to-end; retention and compaction policies defined.
- Capacity planning: concurrency limits, queue depths, and connection pools tuned for peak load with headroom.
- Observability: traces/metrics/logs wired; actionable alerts on SLOs and error budgets.
- Resilience: retry, DLQ, and backoff policies verified; chaos tests performed; runbooks documented and discoverable.
- Release hygiene: pinned image tags; reproducible environment; automated rollbacks and change audit.

## 4.8. Troubleshooting Quick Wins


- Python SDK errors about missing protobuf stubs:

  ```bash
  make protos
  ```
- Connection refused/timeouts: verify ports, container logs, and that `SW4RM_*` env vars point to reachable addresses.
- gRPC SSL/TLS failures: verify cert chain, hostname/SANs, and that clients trust your CA. For local dev, use plaintext.
- Kubernetes readiness flaps: relax initial delays, check CPU throttling, and ensure probes match actual listening ports.
- Compose + macOS: ensure Docker Desktop is running and file sharing is permitted for the volume mount path.

## 4.9. Storage Backends (Pluggable)

Implementers may choose storage backends per component using URI-style configuration. Examples (non-normative):

- Router store: `SW4RM_ROUTER_STORE_URL`
  - `file:///var/lib/sw4rm` (local dev; single-node)
  - `postgres://user:pass@host:5432/dbname`
  - `s3://bucket/prefix` (object store, large payloads)
  - `nfs:///mnt/share/sw4rm` (shared POSIX)

- Scheduler store/queue: `SW4RM_SCHEDULER_STORE_URL`
  - `redis://host:6379/0`
  - `postgres://...`

Document which backends each implementation supports; the protocol remains storage-agnostic.

## 4.10. Observability (Optional)

OpenTelemetry exporters (recommended neutral default):

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf  # or grpc
export OTEL_SERVICE_NAME=sw4rm-router
export OTEL_RESOURCE_ATTRIBUTES=env=dev,service.role=router
```

Prometheus metrics (optional; if your implementation exposes `/metrics`):

- Scrape target example (Kubernetes ServiceMonitor or Pod annotations).
- Keep disabled by default unless explicitly enabled.
