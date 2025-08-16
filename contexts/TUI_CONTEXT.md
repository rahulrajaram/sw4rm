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
- [x] Keybindings + config: Dotfile-driven bindings for history search, status toggle, lane switch; documented defaults and overrides.
- [ ] Robust preemption UX: Preempt by id or lane/priority; show checkpoint progress and resume hints; warn on risky mass-preempt.
- [ ] Testing coverage: Unit tests for history read/write/rotation and keybinding map; snapshots for status line widths; integration tests for slash commands and `/events`.
- [ ] Observability and metrics: Emit scheduler command outcomes, lane depths, and preemption rates; basic alerts on repeated failed resumes.
- [x] Docs and examples: Update QUICKSTART, add slash command reference, status line legend, config samples, and troubleshooting for history/telemetry.

5.13. Current State (TUI Shell) — Inline Markdown + Testing

- Summary: The TUI now renders the composer (input) and transcript in a single combined area with inline Markdown styling. Headings, bold/italic, inline code, blockquotes (left gray bar), links (blue + underline), and hierarchical bullets (•, ◦, ▪) are supported. History search (Ctrl+R) remains; Enter appends a harmless stub response (no blocking) and keeps the composer text. Newlines are inserted with Ctrl+J. A debug overlay is available via `BEE_TUI_DEBUG=1` and shows the wrap-aware cursor row/col, editor area, scroll, and input cursor indices.

- Keybindings: Configurable; defaults retained for search (Ctrl+R), status toggle (Ctrl+S), lane cycling (Ctrl+L / Alt+L). The previous preview toggle (Ctrl+M) was removed to avoid conflicts with Enter.

- Persistence + History: File-backed history (JSONL) with rotation; incremental search reads persisted history; tests added for rotation and malformed lines tolerance.

- Tests: Added pure helpers for editing and composing, buffer-level Markdown rendering tests (ratatui TestBackend), and step-function interaction tests (typing, newline, Enter, slash clearing, search mode). This reduces flakiness and catches regressions without raw terminal IO.

Known Issue — Cursor “two-line” misalignment (pending)

- Symptom: In some cases the visible caret appears ~1–2 lines below the position where the text is being entered.

- Root cause: Cursor math originally used the composed string (input + transcript) and didn’t compensate for Markdown transformations and two-line spacing between composer and transcript. Even after switching to a wrap-aware composer-only calculation, certain Markdown transformations can still alter visible width on the current line:
  - Headings: Stripping `#` markers reduces visual width vs. raw input.
  - Blockquotes: Raw `> ` becomes a visual `│  ` (adds columns).
  - Lists: `- ` / `* ` / `10. ` become `• `; nesting/indentation changes width.
  - Inline markers: `**`, `*`, `_`, backticks, `[text](url)` affect measured vs. visible width.

- Current mitigation: Implemented a Markdown-aware cursor function that (a) adjusts line-start prefixes (headings, quotes, bullets/indentation), (b) ignores inline emphasis/backticks, and (c) counts only link text for `[text](url)`. Cursor position is computed at the editor’s wrap width with a fixed prompt width of 2. A debug overlay (`BEE_TUI_DEBUG=1`) prints `cur=row,col` so operators can compare expected vs. actual placement.

- Status: Improved, but there may still be edge cases (e.g., mixed markers, very long words, multi-byte symbols) where visual wrap differs. These are being tracked and reproduced with targeted tests.

- Next steps:
  - Add focused tests for the exact inputs that misalign (from operator screenshots and debug overlay lines) and refine the visual mapping logic accordingly.
  - Add a thin dim separator between composer and transcript to visually anchor the composer height while tuning cursor math.
 - Optional: introduce a “safe mode” flag for the TUI to stub all network calls and guarantee zero stalls during interactive sessions.

5.14. Known Issue — Backspace Hang Near Code Fences (triple backticks)

- Summary: Operators can observe the editor appear to “hang” or fail to backspace at specific positions around Markdown code fences and inline backticks. This tends to happen at the opening fence line (e.g., "```rust") after removing the trailing newline, or when two backticks remain at end-of-line ("``"). The symptom is: pressing Backspace does nothing, while the debug overlay shows the cursor at the start of the fence or on a double-backtick.

- Reproduction (using current mock input):
  1) Launch with `BEE_TUI_DEBUG=1` so the debug overlay is visible.
  2) Use the prefilled sample that includes a fenced Rust block.
  3) Move the cursor to the end of the line immediately after the opening fence ` ```rust` and press Backspace to remove the newline.
  4) Keep pressing Backspace toward the backticks. In some runs, when the line reads exactly ` `` ` (two backticks) or when the fence line has no trailing newline, Backspace appears to stall.

- Debug overlay reference (fields):
  - `cur=r,c`: Markdown-aware cursor row/col (what UI aims to show).
  - `raw=r,c`: Plain wrapped cursor row/col (no Markdown transforms).
  - `b=idx/len`: Byte index/length (UTF‑8 bytes).
  - `ch=idx/len`: Character index/length (Unicode scalar values).
  - `vis_w`: Visible wrap width used for cursor math.
  - `scroll`, `area=WxH`: Editor scroll and dimensions.
  - `head="…"`: Post-edit line head near the cursor (first ~40 visible chars).
  - `last=… line_head="…"`: Pre-edit action summary and the pre-edit line head.
  - `md_code=on|off`: Whether the current line is considered inside a fenced code block by the cursor logic.
  - `fence=yes|no`: Whether the current line starts with a triple-backtick fence.

- What’s been implemented so far to mitigate:
  - Headings and bullet markers render literally (e.g., `# `, `- `) and are counted literally in cursor math to prevent hidden-offset confusion.
  - Code fences are rendered as literal lines (styled maroon on a dim background) and are counted in cursor math; we also toggle “in code block” state even if the fence line temporarily has no trailing newline (after a Backspace).
  - Backspace/Delete/Left/Right operate on Unicode character boundaries to avoid getting stuck mid‑UTF‑8.
  - Inline markers (``, `**`, `*`, `_`, links) are only treated as formatting when a proper closing delimiter exists before the cursor; otherwise, they count as visible characters. Empty inline-code spans `` render as two visible backticks to match navigation.
  - Extra debug logs show pre/post line heads, removed rune, and whether the cursor logic thinks we are inside a code fence (`md_code`, `fence`).

- Current hypothesis (remaining edge):
  - There are still rare states where the inline-backtick logic and the fence-state toggle become inconsistent at end-of-line, especially right after the third backtick is deleted or when the fence newline has been removed. In those states, cursor math and rendering can briefly disagree on whether a backtick is a marker or a literal character, leading to an apparent “no‑progress” Backspace.
  - Another possibility is a no‑progress loop in the cursor-width walk for specific sequences (e.g., two ticks at EOL with mixed state), where neither the index nor the column changes for that frame.

- Short-term workarounds:
  - Insert a space after the backticks (e.g., change `` to ``␣) and then backspace; this forces literal treatment and breaks the stalemate.
  - Add a newline after the fence (`Enter` or `Ctrl+J`) before editing back toward the fence; this re-establishes a clear fence boundary.
  - Use `Delete` (forward delete) from just before the backticks to remove them left‑to‑right.

- Planned fixes (near-term):
  - Unify parsing for cursor math and rendering: build a tiny, line-scoped tokenizer (heading, blockquote, fence, inline markers) used by both the renderer and the cursor calculator to eliminate divergence.
  - Strengthen inline backtick rules: treat backticks as markers only when a matching closer exists on the same line ahead of the cursor; otherwise, always literal.
  - Add explicit progress guards in the cursor walk (detect and break if neither `i` nor `(row,col)` advances for a character) and surface a warning in debug overlay.
  - Expand tests to cover: fence without newline, removing the third backtick, ` `` ` at EOL, mixed markers on the same line, and multibyte characters adjacent to backticks.

- Status: Partially mitigated. The majority of cases are fixed (e.g., headings/bullets literal, fences rendered/counting, Unicode-safe edits), but there is still an intermittent hang specifically when backspacing into/through the opening fence after newline removal or when two backticks remain at EOL. This is tracked for the next iteration with the parser unification and additional guardrails described above.
