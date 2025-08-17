# Bee TUI and Shell Architecture

This document describes the interactive Shell and TUI architecture for Bee, focusing on persistent history, status line, scheduler-oriented slash commands, and configurable keybindings.

## Overview
- Goal: Improve operator efficiency and situational awareness during interactive sessions.
- Scope: Persistent command history, incremental search, status line widget (model/lane/events/cost), scheduler slash commands, and parity for `/events on|off` in non-TUI shell.
- Non-goals: Multi-window tiling and plugin systems.

## Root Inference and Events
- Root Inference: When run inside a folder containing `bee.json`, the shell infers the default agent identity and service endpoints from that file, avoiding repeated flags. The TUI variant honors the same inference.
- Event Tailing: After a `/from` is established, the TUI tails live events in a top events pane. In the non-TUI shell, event streaming is controlled via `/events on|off`.

## Negotiation UX
- Seed Intent: Negotiations are typically seeded by the operator via the Scheduler through CLI/shell commands or a file-based input. This keeps initiation explicit and auditable.
- Agent-Initiated Rooms: Agents may optionally initiate rooms; when enabled, the shell/TUI must clearly label such sessions as agent-initiated.

## Components
- History Store: JSON Lines file under Bee home with rotation and user-only permissions.
- TUI Layer: Crossterm + Ratatui for rendering, with an input area and a status line.
- Composer: Inline Markdown composer with live preview; initial sample is pre-filled on first open for demo friendliness (clear or overwrite as desired).
- Slash Commands: Call into existing CLI clients (Scheduler/Negotiation/Router) and render results inline.
- Keybindings: Dotfile-driven chords to toggle features and switch lanes.
- Telemetry Hook: Optional source for usage/cost estimates; TUI degrades gracefully when unavailable.

## Data Flow
1. Input events are read via Crossterm and translated into editor actions or commands.
2. Commands prefixed with `/` are parsed; arguments follow shell-style `key=value` pairs.
3. Scheduler/Negotiation actions execute asynchronously via SDK clients; outputs stream to the console pane.
4. The status line subscribes to in-memory session state (from agent, lane, events toggle) and telemetry (optional) to render dynamic fields.
5. Commands are appended to the history store with a timestamp and basic result flag.
6. When a session source is bound via `/from`, the TUI attaches an event tail subscription; the non-TUI shell exposes `/events on|off` to mirror this behavior.

## History Persistence
- Format: NDJSON, each line is `{ ts, input, ok }`.
- Path: `$BEE_HOME/history.jsonl` (default to `~/.config/bee/history.jsonl` on Unix).
- Rotation: Size-based; preserves atomicity by rename-then-recreate with `0600` where supported.
- Search: Incremental “Ctrl+R”-style search over persisted history, preserving multiline entries.

## Status Line
- Fields: `model`, `lane`, `events`, `from`, and `cost`.
- Behavior: Updates on state changes; if telemetry is unavailable, shows cost as `—`.
- Styling: Low-contrast dimmed normal state; high-contrast when exit is armed (double Ctrl+C confirmation).

## Scheduler Slash Commands
- `/submit <task_id> agent=<id> [priority=N] [scope=lane] [content_type=...] [params_json=...]`
- `/preempt <task_id> [reason=txt] [agent=<id>]`
- `/bind <lane>` (switch current lane for commands)
- `/switch <agent_id>` (change default “from” agent)
- Non-TUI parity: `/events on|off` supported in non-TUI shell.

## Negotiation Commands
- `/open <id> participants=a,b topic=... [intensity=low|high] [timeout_ms=N]`
- `/propose json <payload>` | `/propose <text>`
- `/counter json <payload>` | `/counter <text>`
- `/eval <score:0..1> <notes>`
- `/decide json <result>` | `/decide <text>`
- `/abort [reason]`
## Keybindings and Config
- Source: `$BEE_HOME/keybindings.json` (defaults to `~/.config/bee/keybindings.json`).
- Defaults:
  - Search toggle: `Ctrl+R`
  - Status toggle: `Ctrl+S`
  - Lane next/prev: `Ctrl+L` / `Alt+L`
- Behavior:
  - Search toggle enters/leaves incremental history search mode.
  - Status toggle shows/hides dynamic status details.
  - Lane cycling updates the active lane used by scheduler commands.

### Config File Format
Location:
- Unix-like default: `~/.config/bee/keybindings.json`
- Override: `$BEE_HOME/keybindings.json`

Example:
```
{
  "search_toggle": "Ctrl+R",
  "status_toggle": "Ctrl+S",
  "lane_next": "Ctrl+L",
  "lane_prev": "Alt+L"
}
```

Supported key chord forms:
- Modifiers: `Ctrl`, `Shift`, `Alt` (case-insensitive), combined with `+`.
- Keys: single letters (e.g., `J`), `Esc`, `Enter`, `Backspace`, `Delete`, or `F1`..`F12`.

Notes:
- If the config file is missing or invalid, built-in defaults are used.
- Some combinations may conflict with terminal emulators; adjust as needed.

## Edge Cases and Resilience
- Debug overlay: set `BEE_TUI_DEBUG=1` to show an extra debug line with cursor/markdown diagnostics.
- History rotation avoids corruption; reads tolerate malformed lines.
- Terminal resizes recalculate layout without truncating content.
- Telemetry missing: status line falls back to static fields; cost remains `—`.
- Exit handling: first Ctrl+C arms exit and displays a prompt; second Ctrl+C within a timeout exits.

## Testing
- Unit tests: history read/write/rotation; cursor movement helpers; keybinding parsing and defaults.
- Snapshots: status line rendering under various widths (planned expansion).
- Integration: slash command execution against mocked clients; non-TUI `/events` parity.

## Migration and Rollout
- Enabled by default; configuration via Bee home dotfiles.
- Backwards compatible with existing shell usage; additional features are opt-in via keybindings.

## Observability
- Debug overlay: set `BEE_TUI_DEBUG=1` to enable an extra debug line with cursor/markdown diagnostics at the bottom of the TUI.
- Metrics emitter for scheduler outcomes, lane depths, and preemption rates is planned.
- Tracing: configured via `BEE_OTEL_EXPORTER`, `OTEL_EXPORTER_OTLP_ENDPOINT`, and `BEE_OTEL_SAMPLING`.

## Files and Modules
- TUI entry: `bee/src/tui/mod.rs`
- Keybindings: `bee/src/tui/keybindings.rs`
- History store: `bee/src/history.rs`
- Telemetry: `bee/src/telemetry/*`
 
