## Why

Orc currently uses the user's tmux server directly — it sets server-level options, keybindings, and theme that leak into the user's existing tmux session. Users who already have tmux running with their own keybindings and theme experience conflicts: orc overwrites their `status-style`, `base-index`, `renumber-windows`, and keybindings like `C-b n`, `C-b p`, `C-b c`, `C-b x`, `C-b D`. There is no isolation boundary between orc's tmux and the user's tmux.

## What Changes

- **BREAKING**: All `tmux` calls in the CLI are replaced with `_orc_tmux()`, a wrapper that targets the orc-specific tmux socket (`-L orc`). This moves orc into its own tmux server, completely isolated from the user's tmux.
- **BREAKING**: `_tmux_ensure_session()` is refactored to use `tmux -L orc -f orc-tmux.conf new-session` for first-time server initialization, applying config via a dedicated tmux config file instead of inline `set-option` calls.
- **NEW**: Static tmux configuration (theme, keybindings, options) is extracted from `_common.sh` into `packages/cli/lib/orc-tmux.conf`.
- **NEW**: `_orc_tmux()` wrapper function in `_common.sh` that injects `-L "${ORC_TMUX_SOCKET}"` before every tmux command.
- **NEW**: `ORC_TMUX_SOCKET="orc"` constant added alongside the existing `ORC_TMUX_SESSION="orc"`.
- **MODIFIED**: `_orc_goto()` changes from `tmux switch-client` / `tmux attach-session` to `tmux -L orc attach` (nested attach in current pane).
- **MODIFIED**: `leave.sh` changes from `tmux detach-client` to `_orc_tmux detach-client`.
- **MODIFIED**: `_tmux_ensure_session()` no longer applies 200 lines of inline `set-option` / `bind-key` — these move to `orc-tmux.conf`.
- **MODIFIED**: All tmux commands in `start.sh`, `spawn-goal.sh`, `spawn.sh`, `review.sh`, `board.sh`, `teardown.sh`, `halt.sh`, `leave.sh`, and `_common.sh` are replaced with `_orc_tmux` calls.

## Capabilities

### New Capabilities
- `tmux-isolation`: Orc runs in its own tmux server via `-L orc` socket, fully isolated from the user's tmux. Config, keybindings, theme, and session are contained. Nested attach for users inside tmux, direct attach for users outside tmux.

### Modified Capabilities
- `tui-keybinding-layer`: Keybindings now only apply within the orc tmux server. The `[keybindings]` config section controls bindings in the isolated server, not the user's tmux.
- `goal-workspace-isolation`: Goal orchestrator worktree tmux windows are created inside the orc server (via `_orc_tmux`), not the user's tmux server.

## Impact

- **packages/cli/lib/_common.sh**: Major refactor — `ORC_TMUX_SOCKET` constant, `_orc_tmux()` wrapper, `_tmux_ensure_session()` simplified, `_orc_goto()` rewritten, all bare `tmux` calls replaced.
- **packages/cli/lib/orc-tmux.conf**: New file — static tmux config (theme, options, keybindings) extracted from `_common.sh`.
- **packages/cli/lib/start.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/lib/spawn-goal.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/lib/spawn.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/lib/review.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/lib/board.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/lib/teardown.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/lib/halt.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/lib/leave.sh**: All `tmux` calls → `_orc_tmux`.
- **packages/cli/bin/orc**: Entry point needs to propagate `ORC_TMUX_SOCKET`.
- **CLAUDE.md / docs/**: Update tmux architecture documentation to reflect socket isolation.
- **Migration**: Existing `orc` tmux session on default server will be orphaned. Users need `tmux kill-session -t orc` on their default server after upgrade, or `orc teardown all` before upgrading.