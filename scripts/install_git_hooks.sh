#!/usr/bin/env bash
set -euo pipefail

PRE_SRC="scripts/git-hooks/pre-commit"
CM_SRC="scripts/git-hooks/commit-msg"

HOOKS_DIR=$(git rev-parse --git-path hooks 2>/dev/null || true)
if [ -z "$HOOKS_DIR" ]; then
  echo "[install-git-hooks] Could not determine hooks directory; ensure this is a git repo." >&2
  exit 1
fi
mkdir -p "$HOOKS_DIR"
PRE_HOOK="$HOOKS_DIR/pre-commit"
CM_HOOK="$HOOKS_DIR/commit-msg"

if [ -e "$PRE_HOOK" ] && [ ! -L "$PRE_HOOK" ]; then
  echo "[install-git-hooks] A pre-commit hook already exists and is not a symlink. Aborting." >&2
  exit 1
fi

ln -sf "../../$PRE_SRC" "$PRE_HOOK"
chmod +x "$PRE_SRC"
echo "[install-git-hooks] Installed pre-commit hook -> $PRE_SRC"

# Install commit-msg hook
if [ -e "$CM_HOOK" ] && [ ! -L "$CM_HOOK" ]; then
  echo "[install-git-hooks] A commit-msg hook already exists and is not a symlink. Aborting." >&2
  exit 1
fi
ln -sf "../../$CM_SRC" "$CM_HOOK"
chmod +x "$CM_SRC"
echo "[install-git-hooks] Installed commit-msg hook -> $CM_SRC"

# Set local commit template
git config commit.template .gitmessage.txt
echo "[install-git-hooks] Set local commit.template to .gitmessage.txt"
