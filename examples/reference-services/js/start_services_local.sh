#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🚀 Starting JS reference services (Local Node)"

# Install deps if needed
if [ ! -d node_modules ]; then
  npm ci
fi

echo "🔧 Starting services in background..."

npx tsx src/registry-service.ts &
REGISTRY_PID=$!

sleep 2

npx tsx src/router-service.ts &
ROUTER_PID=$!

echo "$REGISTRY_PID" > .registry.pid
echo "$ROUTER_PID" > .router.pid

echo "✅ Started. Registry PID: $REGISTRY_PID, Router PID: $ROUTER_PID"
echo "Press Ctrl+C to stop or run ./stop_services_local.sh"

trap 'echo; echo "🛑 Stopping services..."; kill $REGISTRY_PID $ROUTER_PID 2>/dev/null; rm -f .registry.pid .router.pid; echo "✅ Stopped"; exit 0' INT TERM

wait

