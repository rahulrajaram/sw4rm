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

--local   Start Registry, Router, Scheduler as local Rust binaries
--docker  Start services via docker compose
--no-wait Do not wait in foreground (local mode only)
EOF
      exit 0
      ;;
  esac
done

if [[ "$MODE" == "docker" ]]; then
  echo "🚀 Starting Rust reference services (Docker)"
  # shellcheck disable=SC1091
  source ../scripts/lib.sh
  detect_compose || exit 1
  $COMPOSE_CMD -f docker/docker-compose.yml up --build -d
  echo "✅ Started. Registry: 50052, Router: 50051, Scheduler: 50053"
  exit 0
fi

echo "🚀 Starting Rust reference services (Local)"

# Configurable ports (for future support); defaults used by binaries
REGISTRY_PORT="${REGISTRY_PORT:-50052}"
ROUTER_PORT="${ROUTER_PORT:-50051}"
SCHEDULER_PORT="${SCHEDULER_PORT:-50053}"

# Preflight: ensure ports are available
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

# Build binaries
cargo build --bins

echo "🔧 Starting services in background... (REGISTRY_PORT=$REGISTRY_PORT, ROUTER_PORT=$ROUTER_PORT, SCHEDULER_PORT=$SCHEDULER_PORT)"

REGISTRY_PORT="$REGISTRY_PORT" ./target/debug/registry-service &
REGISTRY_PID=$!

sleep 2

ROUTER_PORT="$ROUTER_PORT" ./target/debug/router-service &
ROUTER_PID=$!

sleep 2

SCHEDULER_PORT="$SCHEDULER_PORT" ./target/debug/scheduler-service &
SCHEDULER_PID=$!

echo "$REGISTRY_PID" > .registry.pid
echo "$ROUTER_PID" > .router.pid
echo "$SCHEDULER_PID" > .scheduler.pid

echo "✅ Started. Registry PID: $REGISTRY_PID, Router PID: $ROUTER_PID, Scheduler PID: $SCHEDULER_PID"
echo "Press Ctrl+C to stop or run ./stop_services.sh --local"

if [[ $NO_WAIT -eq 0 ]]; then
  trap 'echo; echo "🛑 Stopping services..."; kill $REGISTRY_PID $ROUTER_PID $SCHEDULER_PID 2>/dev/null; rm -f .registry.pid .router.pid .scheduler.pid; echo "✅ Stopped"; exit 0' INT TERM
  wait
fi
