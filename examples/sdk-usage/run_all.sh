#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
sdk_dir="$repo_root/../sdks/js_sdk"
ref_js_dir="$repo_root/reference-services/js"
runner="npx tsx"

# Cleanup handler to stop anything we start
CLEANED=0
STARTED_SERVICES=0
ACK_PID=""
cleanup() {
  # Prevent double cleanup
  if [[ "$CLEANED" -eq 1 ]]; then return; fi
  CLEANED=1
  set +e
  if [[ -n "$ACK_PID" ]]; then
    kill "$ACK_PID" 2>/dev/null || true
  fi
  # Ensure any stray ack agent processes are gone
  pkill -f "agents/ack_agent.ts" 2>/dev/null || true
  if [[ "$STARTED_SERVICES" -eq 1 ]]; then
    ( cd "$ref_js_dir" && ./stop_services.sh --local ) || true
  fi
}
trap cleanup INT TERM EXIT

usage() {
  cat <<EOF
Usage: ./run_all.sh [ack-demo|all]

Modes:
  ack-demo  Start local JS services (non-blocking), run ACK agent in a separate
            process, then run router_send_receive.ts to demonstrate ACK flow.
  all       Run all SDK usage examples (requires more services running).

Environment:
  SW4RM_* address vars are respected (defaults: Router 50051, Registry 50052).
EOF
}

mode="ack-demo"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi
if [[ "${1:-}" == "all" ]]; then mode="all"; fi

if [[ "$mode" == "ack-demo" ]]; then
  echo "=== Ack demo: start services, run ack agent, run router_send_receive ==="
  pushd "$ref_js_dir" >/dev/null
  ./start_services.sh --local --no-wait
  popd >/dev/null
  STARTED_SERVICES=1

  # Give services a moment to bind
  sleep 2

  # Start ACK agent in its own process
  pushd "$sdk_dir" >/dev/null
  echo "=== Starting ACK agent ==="
  SW4RM_REGISTRY_ADDR="${SW4RM_REGISTRY_ADDR:-localhost:50052}" \
  SW4RM_ROUTER_ADDR="${SW4RM_ROUTER_ADDR:-localhost:50051}" \
  $runner "$repo_root/reference-services/js/agents/ack_agent.ts" &
  ACK_PID=$!
  popd >/dev/null

  # Give the ACK agent time to register/stream
  sleep 1

  # Run the router send/receive example (waits for ACK)
  pushd "$sdk_dir" >/dev/null
  echo "=== Running $here/router_send_receive.ts ==="
  SW4RM_ROUTER_ADDR="${SW4RM_ROUTER_ADDR:-localhost:50051}" \
  $runner "$here/router_send_receive.ts"
  popd >/dev/null

  echo "=== Cleaning up ACK agent and services ==="
  cleanup
  echo "✅ Ack demo completed"
  exit 0
fi

# Fallback: run all SDK examples (assumes services running for each)
pushd "$sdk_dir" >/dev/null
examples=(
  "$here/register_agent.ts"
  "$here/router_send_receive.ts"
  "$here/scheduler_tasks.ts"
  "$here/tool_call_unary.ts"
  "$here/tool_call_stream.ts"
  "$here/worktree_bind_switch.ts"
  "$here/hitl_decide.ts"
  "$here/negotiation_flow.ts"
  "$here/reasoning_checks.ts"
  "$here/logging_ingest.ts"
  "$here/persistence_autosave.ts"
  "$here/end_to_end_smoke.ts"
)
for ex in "${examples[@]}"; do
  echo "=== Running $ex ==="
  $runner "$ex"
done
popd >/dev/null
