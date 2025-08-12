#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../sdks/js_sdk"
runner="npx tsx"

examples=(
  "../../examples/js/register_agent.ts"
  "../../examples/js/router_send_receive.ts"
  "../../examples/js/scheduler_tasks.ts"
  "../../examples/js/tool_call_unary.ts"
  "../../examples/js/tool_call_stream.ts"
  "../../examples/js/worktree_bind_switch.ts"
  "../../examples/js/hitl_decide.ts"
  "../../examples/js/negotiation_flow.ts"
  "../../examples/js/reasoning_checks.ts"
  "../../examples/js/logging_ingest.ts"
  "../../examples/js/persistence_autosave.ts"
  "../../examples/js/end_to_end_smoke.ts"
)

for ex in "${examples[@]}"; do
  echo "=== Running $ex ==="
  $runner "$ex"
done

