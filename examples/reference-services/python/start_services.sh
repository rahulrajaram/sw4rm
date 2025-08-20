#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🚀 Starting Python reference services (Docker)"

if command -v docker-compose &> /dev/null; then
  COMPOSE_CMD="docker-compose"
else
  COMPOSE_CMD="docker compose"
fi

$COMPOSE_CMD up --build -d

echo "✅ Started. Registry: 50052, Router: 50051"

