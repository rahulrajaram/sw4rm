#!/bin/bash
set -e

cd "$(dirname "$0")"

MODE="docker"
for arg in "$@"; do
  case "$arg" in
    --local) MODE="local" ;;
    --docker) MODE="docker" ;;
    -h|--help)
      cat <<EOF
Usage: ./stop_services.sh [--local|--docker]
Default: --docker

--local   Stop local Node services
--docker  Stop docker-compose stack
EOF
      exit 0
      ;;
  esac
done

if [[ "$MODE" == "docker" ]]; then
  echo "🛑 Stopping JS reference services (Docker)"
  # shellcheck disable=SC1091
  source ../scripts/lib.sh
  detect_compose || exit 1
  $COMPOSE_CMD -f docker/docker-compose.yml down
  echo "✅ Stopped"
  exit 0
fi

echo "🛑 Stopping JS reference services (Local Node)"

source ../scripts/lib.sh
kill_from_pidfiles_then_patterns .registry.pid .router.pid .scheduler.pid -- \
  "src/registry-service" "src/router-service" "src/scheduler-service"

echo "✅ Stopped"
