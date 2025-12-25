#!/bin/bash
# Shared utility functions for service scripts

# Detect docker compose command
detect_compose() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
  else
    echo "Error: Neither 'docker-compose' nor 'docker compose' found"
    return 1
  fi
  export COMPOSE_CMD
}

# Check if a port is free
check_port_free() {
  local port="$1"
  if command -v lsof &>/dev/null; then
    ! lsof -i :"$port" &>/dev/null
  elif command -v ss &>/dev/null; then
    ! ss -tuln | grep -q ":$port "
  elif command -v netstat &>/dev/null; then
    ! netstat -tuln | grep -q ":$port "
  else
    # Assume free if we can't check
    return 0
  fi
}
