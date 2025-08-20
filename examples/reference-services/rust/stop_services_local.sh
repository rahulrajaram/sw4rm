#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🛑 Stopping Rust reference services (Local)"

if [ -f .registry.pid ] && [ -f .router.pid ]; then
  kill $(cat .registry.pid) 2>/dev/null || true
  kill $(cat .router.pid) 2>/dev/null || true
  rm -f .registry.pid .router.pid
else
  pkill -f "/target/.*/registry-service" 2>/dev/null || true
  pkill -f "/target/.*/router-service" 2>/dev/null || true
fi

echo "✅ Stopped"

