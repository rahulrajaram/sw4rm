# Centralized Git Worktrees for Milestones

This repository uses one branch and one dedicated worktree per milestone. Each worktree is checked out under a centralized directory to keep implementations isolated and easy to manage concurrently by different agents or processes.

## Location

All milestone worktrees live under `/home/rahul/Documents/sw4rm-worktrees` on this machine. Avoid creating additional worktrees inside the repo to prevent accidental cross-contamination.

## Current Branch → Worktree Mapping

- `llm-adapters-streaming-toolcalls` → `/home/rahul/Documents/sw4rm-worktrees/llm-adapters-streaming-toolcalls`
- `activity-buffer-sqlite-retention-cli` → `/home/rahul/Documents/sw4rm-worktrees/activity-buffer-sqlite-retention-cli`
- `scheduler-lanes-preemption-shell` → `/home/rahul/Documents/sw4rm-worktrees/scheduler-lanes-preemption-shell`
- `redis-streams-adapter-dlq-idempotency` → `/home/rahul/Documents/sw4rm-worktrees/redis-streams-adapter-dlq-idempotency`
- `tui-history-status-scheduler-commands` → `/home/rahul/Documents/sw4rm-worktrees/tui-history-status-scheduler-commands`
- `telemetry-spans-metrics-grafana` → `/home/rahul/Documents/sw4rm-worktrees/telemetry-spans-metrics-grafana`
- `secrets-cli-scoped-env` → `/home/rahul/Documents/sw4rm-worktrees/secrets-cli-scoped-env`
- `packaging-ci-examples` → `/home/rahul/Documents/sw4rm-worktrees/packaging-ci-examples`

## Conventions

Use exact, descriptive branch names without the `feature-` prefix. The worktree directory name should match the branch name. Each worktree is responsible only for its milestone’s scope. Keep commits atomic and include comprehensive tests for every change (unit, integration, property, CLI as applicable). Avoid cross-milestone changes in a single worktree.

## Common Operations

List all worktrees:

```bash
git worktree list
```

Create a new branch and worktree (when starting a new milestone):

```bash
branch="<milestone-branch>"
dir="/home/rahul/Documents/sw4rm-worktrees/$branch"
git worktree add -b "$branch" "$dir"
```

Rename an existing milestone branch and its directory:

```bash
old="<old-name>"; new="<new-name>"
oldp="/home/rahul/Documents/sw4rm-worktrees/$old"
newp="/home/rahul/Documents/sw4rm-worktrees/$new"
# Rename branch inside the worktree
git -C "$oldp" branch -m "$new"
# If supported by your Git version:
git worktree move "$oldp" "$newp"
# Otherwise remove and re-add:
# git worktree remove -f "$oldp" && git worktree add "$newp" "$new"
```

Remove a worktree (after merging or abandoning a milestone):

```bash
branch="<milestone-branch>"
dir="/home/rahul/Documents/sw4rm-worktrees/$branch"
git worktree remove -f "$dir"
# Optionally delete the branch reference if no longer needed:
git branch -D "$branch"  # only after verifying it is merged or safe to delete
```

Clean up stale administrative references:

```bash
git worktree prune
```

## Workflow Expectations

Each milestone proceeds in its own branch/worktree with exhaustive tests. Commits must be minimal and logically isolated. Prefer adding failing tests first, then implementing the smallest change to pass them. Use clear messages that reference the milestone and subsystem. Do not couple disparate areas across milestones in a single PR.

## Troubleshooting

- “A worktree is already checked out at …”: Choose a different directory or remove the existing worktree first (`git worktree remove -f <dir>`).
- “Branch is already checked out”: Use a distinct branch for each concurrent worktree, or remove the other worktree holding that branch.
- “Path already exists and is not empty”: Pick a new directory or clean the target path before adding the worktree.
