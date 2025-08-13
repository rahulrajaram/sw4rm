#!/usr/bin/env bash
# Append a UTC-stamped decision entry to logs/decisions.log
# Usage: scripts/log_decision.sh "Decision text here"

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 \"Decision text\"" >&2
  exit 1
fi

decision="$*"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$0")/../logs"
log_file="$(dirname "$0")/../logs/decisions.log"

echo "$ts $decision" >> "$log_file"
echo "Appended decision to ${log_file}"

