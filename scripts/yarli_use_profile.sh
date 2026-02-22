#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/yarli_use_profile.sh <postgres|in-memory>

Copies one of the tracked YARLI backend profiles onto yarli.toml.
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

profile="$1"
case "$profile" in
  postgres)
    src="yarli.profile.postgres.toml"
    ;;
  in-memory)
    src="yarli.profile.in-memory.toml"
    ;;
  *)
    usage
    exit 1
    ;;
esac

if [[ ! -f "$src" ]]; then
  echo "Profile file not found: $src" >&2
  exit 1
fi

cp "$src" yarli.toml
echo "Switched yarli.toml to profile: $profile"

