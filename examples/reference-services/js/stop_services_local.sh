#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🛑 Stopping JS reference services (Local Node)"

if [ -f .registry.pid ] && [ -f .router.pid ]; then
  kill $(cat .registry.pid) 2>/dev/null || true
  kill $(cat .router.pid) 2>/dev/null || true
  rm -f .registry.pid .router.pid
else
  pkill -f "src/registry-service.ts" 2>/dev/null || true
  pkill -f "src/router-service.ts" 2>/dev/null || true
fi

echo "✅ Stopped"

