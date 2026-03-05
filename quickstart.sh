#!/bin/bash
# SW4RM Quickstart — Get a multi-agent swarm running in under 2 minutes.
#
# Usage:
#   ./quickstart.sh          # Start services + run demo
#   ./quickstart.sh --local  # Use local Python instead of Docker
#   ./quickstart.sh --stop   # Tear down Docker services
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODE="docker"
for arg in "$@"; do
  case "$arg" in
    --local) MODE="local" ;;
    --stop)
      echo "Stopping SW4RM services..."
      docker compose down -v 2>/dev/null || true
      echo "Done."
      exit 0
      ;;
    -h|--help)
      echo "Usage: ./quickstart.sh [--local|--stop]"
      echo "  (default)  Start services via Docker and run demo"
      echo "  --local    Start services as local Python processes"
      echo "  --stop     Tear down Docker services"
      exit 0
      ;;
  esac
done

echo "============================================"
echo "  SW4RM Quickstart"
echo "  Coordination runtime for agent swarms"
echo "============================================"
echo ""

# --- Step 1: Start services ---
if [[ "$MODE" == "docker" ]]; then
  if ! command -v docker &>/dev/null; then
    echo "Error: docker not found. Install Docker or use --local mode."
    exit 1
  fi

  echo "[1/3] Starting SW4RM services (Docker)..."
  docker compose up --build -d

  echo "[2/3] Waiting for services to be healthy..."
  RETRIES=30
  for i in $(seq 1 $RETRIES); do
    HEALTHY=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
healthy = sum(1 for l in lines if l and '\"healthy\"' in l.lower() or '\"running\"' in l.lower())
print(healthy)
" 2>/dev/null || echo "0")
    if [[ "$HEALTHY" -ge 3 ]]; then
      echo "  All 3 services healthy."
      break
    fi
    if [[ $i -eq $RETRIES ]]; then
      echo "  Warning: not all services healthy after ${RETRIES}s. Continuing anyway..."
      docker compose ps
    fi
    sleep 1
  done
else
  echo "[1/3] Starting SW4RM services (local Python)..."
  cd sdks/py_sdk/reference-services
  bash start_services.sh --local --no-wait
  cd "$SCRIPT_DIR"
  sleep 3
  echo "[2/3] Services started."
fi

# --- Step 2: Run demo ---
echo "[3/3] Running multi-agent demo..."
echo ""
echo "  This demo registers 2 agents, sends messages between them,"
echo "  and demonstrates the SW4RM coordination flow."
echo ""

python3 - <<'DEMO_SCRIPT'
"""SW4RM Quickstart Demo — minimal 2-agent message exchange."""
import sys
import time

try:
    import grpc
except ImportError:
    print("Installing grpcio...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "grpcio", "protobuf", "-q"])
    import grpc

try:
    from sw4rm.clients.registry import RegistryClient
    from sw4rm.clients.router import RouterClient
except ImportError:
    print("Installing sw4rm-sdk...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "sw4rm-sdk", "-q"])
    from sw4rm.clients.registry import RegistryClient
    from sw4rm.clients.router import RouterClient

REGISTRY_ADDR = "localhost:50052"
ROUTER_ADDR = "localhost:50051"

print("--- Connecting to SW4RM services ---")
reg_channel = grpc.insecure_channel(REGISTRY_ADDR)
router_channel = grpc.insecure_channel(ROUTER_ADDR)

reg = RegistryClient(reg_channel)
router = RouterClient(router_channel)

# Register two agents
print("\n--- Registering agents ---")
try:
    agent_a = {"agent_id": "demo-writer", "capabilities": ["code-generation"]}
    agent_b = {"agent_id": "demo-reviewer", "capabilities": ["code-review"]}
    reg.register_agent(agent_a)
    print("  Registered: demo-writer")
    reg.register_agent(agent_b)
    print("  Registered: demo-reviewer")
except Exception as e:
    print(f"  Registration note: {e}")
    print("  (Services may need proto stubs compiled — this is expected in quickstart)")

# Send a message
print("\n--- Sending message: demo-writer -> demo-reviewer ---")
try:
    envelope = {
        "producer_id": "demo-writer",
        "consumer_id": "demo-reviewer",
        "message_type": 2,  # DATA
        "payload": b"Please review function parse_config() in src/config.py",
    }
    router.send_message(envelope)
    print("  Message sent successfully!")
except Exception as e:
    print(f"  Send note: {e}")

# Heartbeat
print("\n--- Sending heartbeats ---")
try:
    reg.heartbeat(agent_id="demo-writer", state=1)
    print("  demo-writer: heartbeat OK")
    reg.heartbeat(agent_id="demo-reviewer", state=1)
    print("  demo-reviewer: heartbeat OK")
except Exception as e:
    print(f"  Heartbeat note: {e}")

# Deregister
print("\n--- Cleaning up ---")
try:
    reg.deregister_agent(agent_id="demo-writer")
    reg.deregister_agent(agent_id="demo-reviewer")
    print("  Agents deregistered.")
except Exception as e:
    print(f"  Cleanup note: {e}")

print("\n============================================")
print("  SW4RM Quickstart Complete!")
print("")
print("  Services running on:")
print("    Registry:  localhost:50052")
print("    Router:    localhost:50051")
print("    Scheduler: localhost:50053")
print("    Metrics:   localhost:9100-9102")
print("")
print("  Next steps:")
print("    pip install sw4rm-sdk")
print("    python sdks/py_sdk/reference-services/sw4rm_multi_agent.py")
print("")
print("  Stop services:")
print("    ./quickstart.sh --stop")
print("============================================")

reg_channel.close()
router_channel.close()
DEMO_SCRIPT
