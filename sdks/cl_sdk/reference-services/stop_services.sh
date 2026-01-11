#!/bin/bash
#
# stop_services.sh - Stop SW4RM Common Lisp Reference Services
#
# Usage:
#   ./stop_services.sh [--local|--docker]
#
# Modes:
#   --local   Stop local SBCL processes (default)
#   --docker  Stop docker-compose services
#
# Copyright 2025 SW4RM Team. Apache-2.0 License.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default mode
MODE="local"

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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--local|--docker]"
            exit 1
            ;;
    esac
done

# Kill process from PID file
kill_from_pidfile() {
    local pidfile=$1
    local name=$2
    if [[ -f "$pidfile" ]]; then
        local pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping $name (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            # Wait for process to exit
            for i in {1..10}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force killing $name..."
                kill -9 "$pid" 2>/dev/null || true
            fi
        else
            echo "$name not running (stale PID file)"
        fi
        rm -f "$pidfile"
    else
        echo "No PID file for $name"
    fi
}

# Kill by pattern matching
kill_by_pattern() {
    local pattern=$1
    local name=$2
    local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "Stopping $name by pattern..."
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
    fi
}

# Stop local mode
stop_local() {
    echo "Stopping SW4RM CL services (local mode)..."
    echo ""

    # Stop by PID files first
    kill_from_pidfile "$SCRIPT_DIR/.coordination.pid" "coordination"
    kill_from_pidfile "$SCRIPT_DIR/.scheduler.pid" "scheduler"
    kill_from_pidfile "$SCRIPT_DIR/.router.pid" "router"
    kill_from_pidfile "$SCRIPT_DIR/.registry.pid" "registry"

    # Fallback: kill by pattern
    kill_by_pattern "registry-service.lisp" "registry"
    kill_by_pattern "router-service.lisp" "router"
    kill_by_pattern "scheduler-service.lisp" "scheduler"
    kill_by_pattern "coordination/server.lisp" "coordination"

    echo ""
    echo "All services stopped."
}

# Stop Docker mode
stop_docker() {
    echo "Stopping SW4RM CL services (docker mode)..."
    echo ""

    if ! command -v docker &> /dev/null; then
        echo "Error: Docker not found."
        exit 1
    fi

    cd "$SCRIPT_DIR/docker"

    # Use docker compose or docker-compose based on availability
    if docker compose version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi

    $COMPOSE_CMD down

    echo ""
    echo "Docker services stopped."
}

# Main
case $MODE in
    local)
        stop_local
        ;;
    docker)
        stop_docker
        ;;
esac
