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

# Kill local service processes: first via the given PIDFILES (TERM, then KILL
# if still alive), then via pattern-matched process kills for stale or missing
# pidfiles. Arguments before `--` are pidfiles; arguments after are `pkill -f`
# patterns. Never fails the caller under `set -e` when no process matches.
kill_from_pidfiles_then_patterns() {
  local -a pidfiles=() patterns=()
  local arg seen_separator=0
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      seen_separator=1
    elif [[ "$seen_separator" == 0 ]]; then
      pidfiles+=("$arg")
    else
      patterns+=("$arg")
    fi
  done

  local pidfile pid
  for pidfile in "${pidfiles[@]}"; do
    if [[ -f "$pidfile" ]]; then
      pid="$(cat "$pidfile" 2>/dev/null)"
      if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        for _attempt in 1 2 3 4 5 6 7 8 9 10; do
          kill -0 "$pid" 2>/dev/null || break
          sleep 0.2
        done
        # Still alive after the TERM grace window: force kill.
        kill -9 "$pid" 2>/dev/null || true
      fi
      rm -f "$pidfile"
    fi
  done

  local pattern
  for pattern in "${patterns[@]}"; do
    pkill -f "$pattern" 2>/dev/null || true
  done
  sleep 0.2
  for pattern in "${patterns[@]}"; do
    pkill -9 -f "$pattern" 2>/dev/null || true
  done
  return 0
}
