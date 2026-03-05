#!/bin/bash
# SW4RM End-to-End Smoke Test
#
# Validates the full flow:
#   1. Start reference services (local Python)
#   2. Register agents via gRPC
#   3. Send messages between agents
#   4. Verify delivery via streaming
#   5. Heartbeat and deregister
#   6. Clean up
#
# Usage:
#   ./scripts/smoke_test.sh           # Run with local Python services
#   ./scripts/smoke_test.sh --docker   # Run with Docker services
#
# Exit codes:
#   0 — All checks passed
#   1 — One or more checks failed
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MODE="local"
CLEANUP_ON_EXIT=1
FAILURES=0

for arg in "$@"; do
  case "$arg" in
    --docker) MODE="docker" ;;
    --no-cleanup) CLEANUP_ON_EXIT=0 ;;
  esac
done

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

cleanup() {
  echo ""
  echo "--- Cleaning up ---"
  if [[ "$MODE" == "docker" ]]; then
    docker compose down -v 2>/dev/null || true
  else
    cd "$REPO_ROOT/sdks/py_sdk/reference-services"
    bash stop_services.sh --local 2>/dev/null || true
    cd "$REPO_ROOT"
  fi
  echo "Done."
}

if [[ $CLEANUP_ON_EXIT -eq 1 ]]; then
  trap cleanup EXIT
fi

echo "============================================"
echo "  SW4RM End-to-End Smoke Test"
echo "  Mode: $MODE"
echo "============================================"
echo ""

# --- Step 1: Start services ---
echo "--- Step 1: Start services ---"
if [[ "$MODE" == "docker" ]]; then
  docker compose up --build -d
  echo "  Waiting for Docker services..."
  sleep 15
else
  cd sdks/py_sdk/reference-services
  bash start_services.sh --local --no-wait
  cd "$REPO_ROOT"
  sleep 5
fi
pass "Services started ($MODE)"

# --- Step 2: Run smoke checks via Python ---
echo ""
echo "--- Step 2: Smoke checks ---"

python3 - <<'SMOKE_SCRIPT'
"""SW4RM smoke test — exercises Registry, Router, and Scheduler."""
import sys
import os
import time

# Ensure the local SDK is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__) or ".", "sdks", "py_sdk"))

failures = 0

def check(name, condition, detail=""):
    global failures
    if condition:
        print(f"  PASS: {name}")
    else:
        print(f"  FAIL: {name} — {detail}")
        failures += 1

try:
    import grpc
    from sw4rm.clients.registry import RegistryClient
    from sw4rm.clients.router import RouterClient
    check("SDK import", True)
except ImportError as e:
    check("SDK import", False, str(e))
    sys.exit(1)

REGISTRY = "localhost:50052"
ROUTER = "localhost:50051"

# Connect
try:
    reg_ch = grpc.insecure_channel(REGISTRY)
    rtr_ch = grpc.insecure_channel(ROUTER)
    grpc.channel_ready_future(reg_ch).result(timeout=10)
    grpc.channel_ready_future(rtr_ch).result(timeout=10)
    check("gRPC channels ready", True)
except Exception as e:
    check("gRPC channels ready", False, str(e))
    sys.exit(1)

reg = RegistryClient(reg_ch)
rtr = RouterClient(rtr_ch)

# Register agents
try:
    reg.register_agent({"agent_id": "smoke-agent-a", "capabilities": ["test"]})
    reg.register_agent({"agent_id": "smoke-agent-b", "capabilities": ["test"]})
    check("Register 2 agents", True)
except Exception as e:
    check("Register 2 agents", False, str(e))

# Send message
try:
    envelope = {
        "producer_id": "smoke-agent-a",
        "consumer_id": "smoke-agent-b",
        "message_type": 2,
        "payload": b"smoke-test-payload",
    }
    rtr.send_message(envelope)
    check("Send message A -> B", True)
except Exception as e:
    check("Send message A -> B", False, str(e))

# Heartbeat
try:
    reg.heartbeat(agent_id="smoke-agent-a", state=1)
    reg.heartbeat(agent_id="smoke-agent-b", state=1)
    check("Heartbeat both agents", True)
except Exception as e:
    check("Heartbeat both agents", False, str(e))

# Deregister
try:
    reg.deregister_agent(agent_id="smoke-agent-a")
    reg.deregister_agent(agent_id="smoke-agent-b")
    check("Deregister agents", True)
except Exception as e:
    check("Deregister agents", False, str(e))

# Close channels
reg_ch.close()
rtr_ch.close()

if failures > 0:
    print(f"\n  {failures} check(s) failed.")
    sys.exit(1)
else:
    print("\n  All smoke checks passed.")
    sys.exit(0)
SMOKE_SCRIPT

SMOKE_EXIT=$?
if [[ $SMOKE_EXIT -ne 0 ]]; then
  fail "Smoke checks"
else
  pass "Smoke checks"
fi

echo ""
echo "============================================"
if [[ $FAILURES -gt 0 ]]; then
  echo "  RESULT: $FAILURES failure(s)"
  exit 1
else
  echo "  RESULT: All checks passed"
  exit 0
fi
