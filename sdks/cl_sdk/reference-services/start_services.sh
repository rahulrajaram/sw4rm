#!/bin/bash
#
# start_services.sh - Start SW4RM Common Lisp Reference Services
#
# Usage:
#   ./start_services.sh [--local|--docker] [--no-wait]
#
# Modes:
#   --local   Start services as SBCL processes (default)
#   --docker  Start services via docker-compose
#   --no-wait Don't wait in foreground (local mode only)
#
# Environment Variables:
#   REGISTRY_PORT     - Registry service port (default: 50052)
#   ROUTER_PORT       - Router service port (default: 50051)
#   SCHEDULER_PORT    - Scheduler service port (default: 50053)
#   COORDINATION_PORT - Coordination server port (default: 50060)
#
# Copyright 2025 SW4RM Team. Apache-2.0 License.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default mode
MODE="local"
WAIT=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            MODE="local"
            shift
            ;;
        --docker)
            MODE="docker"
            shift
            ;;
        --no-wait)
            WAIT=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--local|--docker] [--no-wait]"
            exit 1
            ;;
    esac
done

# Default ports
REGISTRY_PORT="${REGISTRY_PORT:-50052}"
ROUTER_PORT="${ROUTER_PORT:-50051}"
SCHEDULER_PORT="${SCHEDULER_PORT:-50053}"
COORDINATION_PORT="${COORDINATION_PORT:-50060}"

# Check if a port is available
check_port() {
    local port=$1
    local name=$2
    if nc -z localhost "$port" 2>/dev/null; then
        echo "Error: Port $port ($name) is already in use"
        exit 1
    fi
}

# Start in local mode
start_local() {
    echo "Starting SW4RM CL services in local mode..."
    echo ""

    # Check ports
    check_port "$REGISTRY_PORT" "registry"
    check_port "$ROUTER_PORT" "router"
    check_port "$SCHEDULER_PORT" "scheduler"
    check_port "$COORDINATION_PORT" "coordination"

    # Check SBCL
    if ! command -v sbcl &> /dev/null; then
        echo "Error: SBCL not found. Please install SBCL first."
        exit 1
    fi

    # Check Quicklisp
    if [[ ! -f ~/quicklisp/setup.lisp ]]; then
        echo "Error: Quicklisp not found at ~/quicklisp/setup.lisp"
        exit 1
    fi

    echo "Starting Registry Service on port $REGISTRY_PORT..."
    REGISTRY_PORT="$REGISTRY_PORT" sbcl --non-interactive \
        --load ~/quicklisp/setup.lisp \
        --load "$SCRIPT_DIR/hive/registry-service.lisp" \
        --eval '(registry-service:main)' &
    echo $! > "$SCRIPT_DIR/.registry.pid"
    sleep 2

    echo "Starting Router Service on port $ROUTER_PORT..."
    ROUTER_PORT="$ROUTER_PORT" sbcl --non-interactive \
        --load ~/quicklisp/setup.lisp \
        --load "$SCRIPT_DIR/hive/router-service.lisp" \
        --eval '(router-service:main)' &
    echo $! > "$SCRIPT_DIR/.router.pid"
    sleep 2

    echo "Starting Scheduler Service on port $SCHEDULER_PORT..."
    SCHEDULER_PORT="$SCHEDULER_PORT" \
    REGISTRY_HOST="localhost" REGISTRY_PORT="$REGISTRY_PORT" \
    ROUTER_HOST="localhost" ROUTER_PORT="$ROUTER_PORT" \
    sbcl --non-interactive \
        --load ~/quicklisp/setup.lisp \
        --load "$SCRIPT_DIR/hive/scheduler-service.lisp" \
        --eval '(scheduler-service:main)' &
    echo $! > "$SCRIPT_DIR/.scheduler.pid"
    sleep 2

    echo "Starting Coordination Server on port $COORDINATION_PORT..."
    COORDINATION_PORT="$COORDINATION_PORT" sbcl --non-interactive \
        --load ~/quicklisp/setup.lisp \
        --load "$SCRIPT_DIR/coordination/server.lisp" \
        --eval '(coordination-server:main)' &
    echo $! > "$SCRIPT_DIR/.coordination.pid"
    sleep 1

    echo ""
    echo "All services started:"
    echo "  Registry:     http://localhost:$REGISTRY_PORT (JSON-TCP)"
    echo "  Router:       http://localhost:$ROUTER_PORT (JSON-TCP)"
    echo "  Scheduler:    http://localhost:$SCHEDULER_PORT (JSON-TCP)"
    echo "  Coordination: http://localhost:$COORDINATION_PORT (JSON-TCP)"
    echo ""
    echo "PID files:"
    echo "  .registry.pid: $(cat "$SCRIPT_DIR/.registry.pid")"
    echo "  .router.pid: $(cat "$SCRIPT_DIR/.router.pid")"
    echo "  .scheduler.pid: $(cat "$SCRIPT_DIR/.scheduler.pid")"
    echo "  .coordination.pid: $(cat "$SCRIPT_DIR/.coordination.pid")"
    echo ""

    if $WAIT; then
        echo "Press Ctrl+C to stop all services..."
        trap 'echo ""; ./stop_services.sh --local' INT TERM
        wait
    else
        echo "Services running in background. Use ./stop_services.sh to stop."
    fi
}

# Start in Docker mode
start_docker() {
    echo "Starting SW4RM CL services in Docker mode..."
    echo ""

    if ! command -v docker &> /dev/null; then
        echo "Error: Docker not found. Please install Docker first."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo "Error: docker-compose not found. Please install docker-compose."
        exit 1
    fi

    cd "$SCRIPT_DIR/docker"

    # Use docker compose or docker-compose based on availability
    if docker compose version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi

    REGISTRY_PORT="$REGISTRY_PORT" \
    ROUTER_PORT="$ROUTER_PORT" \
    SCHEDULER_PORT="$SCHEDULER_PORT" \
    COORDINATION_PORT="$COORDINATION_PORT" \
    $COMPOSE_CMD up --build

    echo ""
    echo "Docker services started."
}

# Main
case $MODE in
    local)
        start_local
        ;;
    docker)
        start_docker
        ;;
esac
