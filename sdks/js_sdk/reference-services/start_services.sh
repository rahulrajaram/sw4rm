#!/bin/bash
set -e

cd "$(dirname "$0")"

MODE="docker"
NO_WAIT=0
for arg in "$@"; do
  case "$arg" in
    --local) MODE="local" ;;
    --docker) MODE="docker" ;;
    --no-wait|--detach) NO_WAIT=1 ;;
    -h|--help)
      cat <<EOF
Usage: ./start_services.sh [--local|--docker] [--no-wait]
Default: --docker

--local   Start Registry, Router, Scheduler as local Node processes
--docker  Start services via docker compose
--no-wait Do not wait in foreground (local mode only)
EOF
      exit 0
      ;;
  esac
done

if [[ "$MODE" == "docker" ]]; then
  echo "🚀 Starting JS reference services (Docker)"
  # shellcheck disable=SC1091
  source ../scripts/lib.sh
  detect_compose || exit 1
  $COMPOSE_CMD -f docker/docker-compose.yml up --build -d
  echo "✅ Started. Registry: 50052, Router: 50051, Scheduler: 50053"
  exit 0
fi

echo "🚀 Starting JS reference services (Local Node)"

# Configurable ports (for future support); defaults used by code
REGISTRY_PORT="${REGISTRY_PORT:-50052}"
ROUTER_PORT="${ROUTER_PORT:-50051}"
SCHEDULER_PORT="${SCHEDULER_PORT:-50053}"

# Preflight: ensure ports are available (shared helper)
# shellcheck disable=SC1091
source ../scripts/lib.sh

if ! check_port_free "$REGISTRY_PORT"; then
  echo "❌ Port $REGISTRY_PORT busy. Set REGISTRY_PORT to override or stop the process using it."
  exit 1
fi
if ! check_port_free "$ROUTER_PORT"; then
  echo "❌ Port $ROUTER_PORT busy. Set ROUTER_PORT to override or stop the process using it."
  exit 1
fi
if ! check_port_free "$SCHEDULER_PORT"; then
  echo "❌ Port $SCHEDULER_PORT busy. Set SCHEDULER_PORT to override or stop the process using it."
  exit 1
fi

# Install deps if needed
if [ ! -d node_modules ]; then
  npm ci
fi

echo "🔧 Starting services in background... (REGISTRY_PORT=$REGISTRY_PORT, ROUTER_PORT=$ROUTER_PORT, SCHEDULER_PORT=$SCHEDULER_PORT)"

REGISTRY_PORT="$REGISTRY_PORT" npx tsx src/registry-service-proper.ts &
# Resolve actual Node/tsx PID for the service
sleep 0.5
REGISTRY_PID=$(pgrep -f -n "src/registry-service-proper.ts" || true)
if [[ -z "$REGISTRY_PID" ]]; then REGISTRY_PID=$!; fi

sleep 2

ROUTER_PORT="$ROUTER_PORT" npx tsx src/router-service-proper.ts &
sleep 0.5
ROUTER_PID=$(pgrep -f -n "src/router-service-proper.ts" || true)
if [[ -z "$ROUTER_PID" ]]; then ROUTER_PID=$!; fi

sleep 2

SCHEDULER_PORT="$SCHEDULER_PORT" npx tsx src/scheduler-service.ts &
sleep 0.5
SCHEDULER_PID=$(pgrep -f -n "src/scheduler-service.ts" || true)
if [[ -z "$SCHEDULER_PID" ]]; then SCHEDULER_PID=$!; fi

echo "$REGISTRY_PID" > .registry.pid
echo "$ROUTER_PID" > .router.pid
echo "$SCHEDULER_PID" > .scheduler.pid

echo "✅ Started. Registry PID: $REGISTRY_PID, Router PID: $ROUTER_PID, Scheduler PID: $SCHEDULER_PID"
echo "Press Ctrl+C to stop or run ./stop_services.sh --local"
echo "Agents: npx tsx agents/backend_agent.ts | npx tsx agents/frontend_agent.ts"

if [[ $NO_WAIT -eq 0 ]]; then
  trap 'echo; echo "🛑 Stopping services..."; kill $REGISTRY_PID $ROUTER_PID $SCHEDULER_PID 2>/dev/null; rm -f .registry.pid .router.pid .scheduler.pid; echo "✅ Stopped"; exit 0' INT TERM
  wait
fi
