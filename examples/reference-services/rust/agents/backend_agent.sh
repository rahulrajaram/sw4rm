#!/usr/bin/env bash
# moved to agents/
set -euo pipefail
cd "$(dirname "$0")/.."
cargo run --bin backend-agent "$@"
