#!/usr/bin/env bash
set -euo pipefail

interval_seconds="${1:-60}"

if ! [[ "$interval_seconds" =~ ^[0-9]+$ ]] || [ "$interval_seconds" -lt 1 ]; then
  echo "Usage: $0 [poll_interval_seconds]" >&2
  echo "Example: $0 60" >&2
  exit 2
fi

log_dir="logs"
mkdir -p "$log_dir"
start_ts="$(date +%Y%m%d_%H%M%S)"
log_file="$log_dir/yarli_run_stream_${start_ts}.log"
pid_file="$log_dir/yarli_run_stream_${start_ts}.pid"

printf '[%s] starting: yarli run --stream\n' "$(date -Iseconds)"
(
  exec yarli run --stream
) >"$log_file" 2>&1 &
pid=$!

printf '%s\n' "$pid" > "$pid_file"
printf '[%s] pid=%s log=%s\n' "$(date -Iseconds)" "$pid" "$log_file"

printed_lines=0

print_new_lines() {
  if [ ! -f "$log_file" ]; then
    return
  fi

  local total_lines
  total_lines=$(wc -l < "$log_file" | tr -d ' ')

  if [ "$total_lines" -gt "$printed_lines" ]; then
    local start_line=$((printed_lines + 1))
    printf '[%s] output lines %s-%s\n' "$(date -Iseconds)" "$start_line" "$total_lines"
    sed -n "${start_line},${total_lines}p" "$log_file"
    printed_lines="$total_lines"
  else
    printf '[%s] no new output\n' "$(date -Iseconds)"
  fi
}

while kill -0 "$pid" 2>/dev/null; do
  sleep "$interval_seconds"
  print_new_lines
done

if wait "$pid"; then
  exit_code=0
else
  exit_code=$?
fi

print_new_lines
printf '[%s] process exited with code %s\n' "$(date -Iseconds)" "$exit_code"

rm -f "$pid_file"
exit "$exit_code"
