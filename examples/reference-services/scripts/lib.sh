#!/usr/bin/env bash
# Shared helpers for reference-service scripts

# check_port_free PORT
# Returns 0 if free, 1 if busy
check_port_free() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk '{print $4}' | grep -q ":${port}$" && return 1 || return 0
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i :"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 1 || return 0
  else
    # Python fallback (present in all stacks here)
    python - "$port" <<'PY'
import socket, sys
p=int(sys.argv[1])
s=socket.socket()
try:
    s.bind(('0.0.0.0', p))
    s.close()
    raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
    return $?
  fi
}

# detect_compose
# Sets COMPOSE_CMD to either `docker-compose` or `docker compose`
detect_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    return 0
  fi
  echo "docker-compose/compose not found" >&2
  return 1
}

# kill_from_pidfiles_then_patterns PIDFILES... -- PATTERNS...
# Kills PIDs from the given files, then force-kills if needed, removes files,
# then pkill -f each pattern as a fallback.
kill_from_pidfiles_then_patterns() {
  local pid_files=()
  local patterns=()
  local parsing_pids=1
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then parsing_pids=0; continue; fi
    if [[ $parsing_pids -eq 1 ]]; then pid_files+=("$arg"); else patterns+=("$arg"); fi
  done

  # Graceful kill PIDs
  for f in "${pid_files[@]}"; do
    if [[ -f "$f" ]]; then
      local PID
      PID=$(cat "$f" 2>/dev/null || true)
      if [[ -n "$PID" ]]; then
        kill "$PID" 2>/dev/null || true
      fi
    fi
  done
  sleep 1
  # Force kill if still alive
  for f in "${pid_files[@]}"; do
    if [[ -f "$f" ]]; then
      local PID
      PID=$(cat "$f" 2>/dev/null || true)
      if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null || true
      fi
      rm -f "$f"
    fi
  done

  # Fallback by pattern
  for pat in "${patterns[@]}"; do
    pkill -f "$pat" 2>/dev/null || true
  done
}
