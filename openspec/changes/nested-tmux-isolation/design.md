## Context

Orc currently runs in the user's tmux server. It creates a session named `orc` and applies server-level options (theme, keybindings, `base-index`, `renumber-windows`, `history-limit`, etc.) directly via `set-option -s` and `bind-key` calls in `_common.sh:_tmux_ensure_session()`. This works when orc is the only tmux session on the machine, but causes problems when the user already has their own tmux session with different preferences — orc overwrites their settings.

The current architecture:
- Single hardcoded session: `ORC_TMUX_SESSION="orc"` in `_common.sh:289`
- ~200 lines of inline tmux configuration in `_tmux_ensure_session()` (lines 301-511)
- All `tmux` commands are bare calls (no `-L` flag), targeting the default server
- `_orc_goto()` uses `switch-client` for in-tmux navigation, `attach-session` for outside-tmux
- Window hierarchy: `root → project → goal → bead` all in one session

## Goals / Non-Goals

**Goals:**
- Run orc in a fully isolated tmux server (socket `-L orc`), separate from the user's tmux
- Eliminate all leaks: config, keybindings, theme, session names must not affect the user's tmux
- Support nested tmux: user inside their tmux can attach to orc's tmux, detach returns to their tmux
- Support non-nested: user outside tmux can attach to orc's tmux directly
- Extract static tmux configuration into a dedicated `orc-tmux.conf` file
- Keep the existing window/pane/pane hierarchy unchanged within the isolated server
- All existing orc commands work from any environment (bare terminal, user tmux, inner orc tmux)

**Non-Goals:**
- Multiple orc server instances (one per project) — all projects share one `orc` server
- Configurable socket name — `orc` is the only socket, matching the session name
- Custom prefix key — `Ctrl-b` remains the inner tmux prefix
- Changing the window/pane layout system — goal windows, overflow, pane registry all stay the same
- Auto-detecting or integrating with the user's tmux prefix key
- Providing a way to run orc without tmux (tmux is a hard requirement)

## Decisions

### D1: Sock-style isolation via `-L orc`

**Decision**: Use `tmux -L orc` to create a separate tmux server process with its own socket file (`/tmp/tmux-$UID/orc`).

**Rationale**: This is the only approach that provides true isolation. The `-L` flag creates a completely separate server with its own config, session list, and options. No server-level options leak between orc and the user's tmux.

**Alternatives considered:**
- **Separate config file only (`-f`)**: Still uses the same server. `set-option -s` calls would still affect all sessions on that server, including the user's.
- **Session name namespacing**: Same server, different session names. Doesn't prevent option/keybinding leaks.
- **Namespace isolation within the same server**: tmux doesn't support namespaces. Every session on a server shares server-level options.

### D2: `_orc_tmux()` wrapper function

**Decision**: Introduce a single wrapper function in `_common.sh` that all tmux calls go through:

```bash
readonly ORC_TMUX_SOCKET="orc"
readonly ORC_TMUX_SESSION="orc"

_orc_tmux() {
    tmux -L "${ORC_TMUX_SOCKET}" "$@"
}
```

**Rationale**: Single point of control. Cannot forget `-L orc` on any call. If the socket naming ever needs to change, one line to edit.

**Alternatives considered:**
- **Global search-replace** of `tmux` → `tmux -L orc`: Fragile — one miss creates a leak.
- **Environment variable `TMUX_SOCKET`**: Requires every call to remember `$TMUX_SOCKET`; easy to forget.
- **Shell alias**: Aliases don't propagate to subshells or scripts sourced in different contexts.

### D3: Static config in `orc-tmux.conf`, dynamic logic stays in shell

**Decision**: Extract all static tmux configuration (theme, colors, options, keybindings) from `_tmux_ensure_session()` into `packages/cli/lib/orc-tmux.conf`. Dynamic logic (session creation, window checks, cleanup) stays in shell.

**Rationale**: ~200 lines of bash-quoting-heavy tmux config is hard to maintain and error-prone. A dedicated tmux config file is the idiomatic way to configure tmux. The file is loaded once on server creation via `tmux -L orc -f "$_ORC_ROOT/lib/orc-tmux.conf"` and never again.

**Alternatives considered:**
- **Keep everything in shell**: Works but harder to read, harder to modify theme without bash quoting issues.
- **`~/.config/orc/tmux.conf` user override**: Adds complexity. Users can already set tmux options in their own `~/.tmux.conf` — but since orc has its own server, this doesn't conflict. Can be added later if needed.

### D4: Path resolution via `_ORC_ROOT`

**Decision**: `orc-tmux.conf` lives at `${_ORC_ROOT}/lib/orc-tmux.conf`, resolved the same way as all other orc shell scripts.

**Rationale**: Follows the existing pattern. `_ORC_ROOT` is resolved in `bin/orc` and exported. No new path resolution mechanism needed. The file travels with the installation.

### D5: Nested attach as default, pane-level entry

**Decision**: When the user runs `orc start` or `orc goto`, they attach to the orc tmux server in their current pane. If they're inside their own tmux, this creates a nested tmux. If they're in a bare terminal, they attach directly. Both cases use the same command: `_orc_tmux attach`.

**Rationale**: Simplest behavior. The user's prefix key (their tmux) controls navigation in the outer tmux. `Ctrl-b` (orc's prefix) controls navigation in the inner tmux. Detaching from inner (`Ctrl-b d`) returns to the outer. This is the standard nested tmux workflow.

**Alternatives considered:**
- **New window in outer tmux**: `tmux new-window 'tmux -L orc attach'` — adds orc as a window in the user's tmux. Loses isolation of the tmux experience (user can accidentally navigate away).
- **Popup/float**: `tmux popup` — not persistent, disappears on close. Not suitable for long-running agent sessions.

### D6: `default-terminal "screen-256color"`

**Decision**: Set `default-terminal "screen-256color"` in `orc-tmux.conf`.

**Rationale**: Standard for tmux inner sessions. Ensures colors and terminal features work correctly inside nested tmux. Modern tmux handles TERM nesting correctly.

### D7: Teardown kills session, not server

**Decision**: `orc teardown all` kills the `orc` session in the `-L orc` server, but leaves the server running. If the user wants to kill the server entirely, they can run `tmux -L orc kill-server` manually.

**Rationale**: Matches the current `teardown all` behavior (kill-session). The server is lightweight and can be reused. No unnecessary process management.

### D8: Single server, single session, multiple projects

**Decision**: All projects share one `orc` session in the `-L orc` server. Window hierarchy (`root → project → goal → bead`) remains unchanged.

**Rationale**: The current architecture already handles multiple projects in one session via window naming. No change needed. If per-project isolation is needed in the future, `ORC_TMUX_SOCKET` could become configurable, but that's out of scope.

## Risks / Trade-offs

**[Nested tmux keybinding confusion]** → Users new to nested tmux may accidentally send `Ctrl-b` commands to the wrong tmux layer. **Mitigation**: Document the nested prefix workflow clearly. The user's current keybindings don't conflict because they're on different prefix keys. The inner tmux uses `Ctrl-b` (default), and the user's tmux uses their own prefix.

**[TERM variable in nested sessions]** → Some terminal emulators may not handle `TERM=screen-256color` correctly inside another tmux. **Mitigation**: `default-terminal "screen-256color"` in `orc-tmux.conf` handles this. Modern tmux (2.x+) handles nested TERM correctly.

**[Migration: orphaned session on default server]** → After upgrading, existing users will have an `orc` session on their default tmux server (the old architecture) that won't be cleaned up automatically. **Mitigation**: Document the migration step: `tmux kill-session -t orc` on the default server, or `orc teardown all` before upgrading.

**[Socket file permissions]** → The `-L orc` socket file at `/tmp/tmux-$UID/orc` follows standard tmux permissions (0600). No additional risk beyond normal tmux usage.

**[iac configuration file cat-herding]** → Moving 200 lines from shell to `orc-tmux.conf` requires careful extraction. Missing an option means it won't be applied. **Mitigation**: Extract systematically, test each option group, and validate that the new config produces the same visual and behavioral result.

**[Command accessibility from all environments]** → Some commands (like `orc spawn-goal`) are designed to run from within the orc tmux session, while others (like `orc start`) are designed to run from outside. With socket isolation, all commands need `_orc_tmux` to target the correct server regardless of where they're invoked. **Mitigation**: The `_orc_tmux` wrapper ensures every command targets the right server. No environment-specific behavior needed.

## Migration Plan

1. **Pre-upgrade**: Users should run `orc teardown all` to cleanly shut down their existing `orc` session on the default tmux server.
2. **Upgrade**: Install the new version. The `orc` session on the default server is now orphaned — users can `tmux kill-session -t orc` to remove it.
3. **Post-upgrade**: Running `orc start` will create a new server via `-L orc` and a session named `orc` inside it. All existing commands work identically, just targeting the isolated server.
4. **Rollback**: If needed, revert to the old version. The `-L orc` server can be killed with `tmux -L orc kill-server`. The old version will recreate the session on the default server.

## Open Questions

- Should `orc doctor` check for orphaned `orc` sessions on the default tmux server and warn the user? (Recommended: yes, low cost, high value.)
- Should `orc-tmux.conf` support user overrides via `~/.config/orc/tmux.conf`? (Deferred to a future change — not needed for initial isolation.)