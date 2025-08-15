5. Shell and TUI Enhancements Milestone Context

5.1. Scope
This milestone adds persistent command history and search, a richer status line displaying active model, lane, and estimated cost, parity for `/events on|off` in non-TUI shell, and scheduler-oriented slash commands. It does not introduce new negotiation flows or deep UI redesign.

5.2. Objectives
The objective is to improve operator efficiency and situational awareness during interactive sessions. A secondary objective is to standardize UX affordances between TUI and non-TUI modes.

5.3. Deliverables
Deliverables include a history store on disk with configurable retention, incremental search, a status line widget with dynamic fields, slash commands `/submit`, `/preempt`, `/bind`, and `/switch`, and documentation for new shortcuts.

5.4. Architecture and Interfaces
The shell persists commands in a newline-delimited file under the Bee home with file locks to prevent corruption. The TUI renders a status bar that subscribes to session state changes and telemetry. The slash commands call existing CLI subcommands and render results inline with structured formatting. Keybindings are configurable via a dotfile.

5.5. Data Model
The history file stores timestamped entries with raw input and an execution result code. The status line reads the active context (hive, agent, model, lane) and aggregates recent token usage for cost estimates.

5.6. Edge Cases and Failure Modes
History file rotation must preserve atomicity. Terminal resizing updates the layout without truncation. When telemetry is unavailable, the status line degrades to static fields.

5.7. Testing Strategy
Unit tests validate history read/write/rotation and keybindings mapping. Snapshot tests assert status line rendering under various widths. Integration tests exercise slash commands against mocked backends and ensure error messages are actionable. Non-TUI shell tests verify `/events` parity.

5.8. Non-Goals
This milestone does not implement multi-window tiling or plugin systems.

5.9. Dependencies
Depends on scheduler CLI endpoints for slash commands and telemetry hooks for status data.

5.10. Migration and Rollout
The features are enabled by default with configuration knobs. Backwards compatibility for existing shell usage is preserved.

5.11. Operational Considerations
History files may include sensitive commands; permissions are set to user-only. Status line emits minimal overhead by sampling metrics at a controlled cadence.


5.12. Prioritized Checklist

- [x] Persistent history store: File-backed command history under Bee home with file locks, rotation by size/date, and `0600` perms; config for retention path/limits.
- [x] Scheduler slash commands (MVP): Implement `/submit`, `/preempt`, `/bind`, `/switch` in shell/TUI wired to CLI; idempotency key per request; clear, actionable errors.
- [x] Status line (minimal): Display active model, lane, and events state; subscribe to session state; degrade to static fields without telemetry.
- [x] Non-TUI `/events` parity: Support `/events on|off` in the non-TUI shell with confirmation and persisted preference.
- [x] Incremental history search: Ctrl-R fuzzy/incremental search across persisted history; navigate next/prev match; preserve multiline entries.
- [ ] Cost estimate integration: Aggregate recent token usage to show rolling cost in status line; fallback to `—` when telemetry unavailable.
- [ ] Arguments, help, and autocomplete: Contextual help for slash commands; tab-complete lanes, task ids, and flags; inline usage hints on errors.
- [ ] Keybindings + config: Dotfile-driven bindings for history search, status toggle, lane switch; documented defaults and overrides.
- [ ] Robust preemption UX: Preempt by id or lane/priority; show checkpoint progress and resume hints; warn on risky mass-preempt.
- [ ] Testing coverage: Unit tests for history read/write/rotation and keybinding map; snapshots for status line widths; integration tests for slash commands and `/events`.
- [ ] Observability and metrics: Emit scheduler command outcomes, lane depths, and preemption rates; basic alerts on repeated failed resumes.
- [x] Docs and examples: Update QUICKSTART, add slash command reference, status line legend, config samples, and troubleshooting for history/telemetry.
