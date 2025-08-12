#!/usr/bin/env bash
set -euo pipefail

HOOK=".git/hooks/pre-commit"
SRC="scripts/git-hooks/pre-commit"

if [ ! -d .git ]; then
  echo "[install-git-hooks] .git directory not found. Run from the repo root." >&2
  exit 1
fi

mkdir -p .git/hooks
if [ -e "$HOOK" ] && [ ! -L "$HOOK" ]; then
  echo "[install-git-hooks] A pre-commit hook already exists and is not a symlink. Aborting." >&2
  exit 1
fi

ln -sf "../../$SRC" "$HOOK"
chmod +x "$SRC"
echo "[install-git-hooks] Installed pre-commit hook -> $SRC"

