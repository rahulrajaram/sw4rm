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

--local   Start Registry, Router, Scheduler as local Python processes
--docker  Start services via docker compose
--no-wait Do not wait in foreground (local mode only)
EOF
      exit 0
      ;;
  esac
done

if [[ "$MODE" == "docker" ]]; then
  echo "🚀 Starting Python reference services (Docker)"
  # shellcheck disable=SC1091
  source ../scripts/lib.sh
  detect_compose || exit 1
  $COMPOSE_CMD -f docker/docker-compose.yml up --build -d
  echo "✅ Started. Registry: 50052, Router: 50051"
  exit 0
fi

echo "🚀 Starting Python reference services (Local)"

# Configurable ports (override via env)
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

# Ensure SDK present
python -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1 || true
if ! python - <<'PY'
try:
    import sw4rm  # type: ignore
    print('sw4rm SDK present')
except Exception:
    raise SystemExit(1)
PY
then
  echo "📦 Installing local SDK (editable)"
  python -m pip install -e ../../sdks/py_sdk
fi

echo "📦 Installing service requirements"
python -m pip install -r requirements.txt

echo "🔧 Starting services in background... (REGISTRY_PORT=$REGISTRY_PORT, ROUTER_PORT=$ROUTER_PORT, SCHEDULER_PORT=$SCHEDULER_PORT)"

REGISTRY_PORT="$REGISTRY_PORT" python hive/registry_service.py &
REGISTRY_PID=$!

sleep 2

ROUTER_PORT="$ROUTER_PORT" python hive/router_service.py &
ROUTER_PID=$!

sleep 1

REGISTRY_PORT="$REGISTRY_PORT" ROUTER_PORT="$ROUTER_PORT" SCHEDULER_PORT="$SCHEDULER_PORT" python hive/scheduler_service.py &
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
