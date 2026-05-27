# Nested tmux Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate orc's tmux session in a dedicated server (`-L orc` socket), eliminating all config/keybinding/theme leaks to the user's tmux.

**Architecture:** Introduce `ORC_TMUX_SOCKET="orc"` constant and `_orc_tmux()` wrapper that injects `-L orc` before every tmux call. Extract static tmux config into `orc-tmux.conf`. Refactor `_tmux_ensure_session()` to load config via `-f` on server creation. Replace all 167 bare `tmux` calls with `_orc_tmux`. Update `_orc_goto()` for nested attach.

**Tech Stack:** Bash (pure shell — no runtime dependencies), tmux 2.0+, `tmux -L` socket isolation

---

## File Impact Map

| File | Action | Responsibility |
|------|--------|---------------|
| `packages/cli/lib/orc-tmux.conf` | **Create** | Static tmux config (theme, options, keybindings) |
| `packages/cli/lib/_common.sh` | Modify | Add `ORC_TMUX_SOCKET`, `_orc_tmux()`, refactor `_tmux_ensure_session()`, update `_orc_goto()` |
| `packages/cli/bin/orc` | Modify | Update `$TMUX` detection logic, propagate `ORC_TMUX_SOCKET` |
| `packages/cli/lib/start.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/spawn-goal.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/spawn.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/review.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/board.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/teardown.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/halt.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/leave.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/chooser.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/menu-action.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/help.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `packages/cli/lib/setup.sh` | Modify | Replace bare `tmux` → `_orc_tmux` |
| `CLAUDE.md` | Modify | Update tmux architecture documentation |
| `docs/configuration.md` | Modify | Document socket isolation |
| `docs/config.toml.example` | Modify | Add any new tmux config options |
| `migrations/CHANGELOG.md` | Modify | Add migration note |

---

## Task 1: Extract Static tmux Config File

**Files:**
- Create: `packages/cli/lib/orc-tmux.conf`

This task extracts the *static* tmux options from `_tmux_ensure_session()` (lines 322-330 in `_common.sh`) into a standalone config file. Dynamic options (theme colors, keybindings, status bars) are NOT static — they depend on config values read at runtime and must stay in shell.

- [ ] **Step 1: Create `orc-tmux.conf` with static options**

Create `packages/cli/lib/orc-tmux.conf`:

```tmux
# orc tmux configuration — loaded on server creation via:
#   tmux -L orc -f "$_ORC_ROOT/lib/orc-tmux.conf" new-session -d -s orc -n _orc_init
#
# This file contains ONLY static options that don't depend on runtime config.
# Dynamic options (theme colors, keybindings, status bars) are applied by
# _tmux_ensure_session() via _orc_tmux after the server is created.

# ── Terminal ──────────────────────────────────────────────────────────────────
set-option -g default-terminal "screen-256color"

# ── Functional settings ──────────────────────────────────────────────────────
set-option -g history-limit 50000
set-option -g alternate-screen off
set-option -g base-index 1
set-option -g renumber-windows on
set-option -g allow-rename off
set-option -g monitor-activity on
set-option -g visual-activity off
set-option -g pane-border-status top
set-option -g pane-border-format " #{pane_title} "
set-option -g status-interval 10

# ── Key bindings ─────────────────────────────────────────────────────────────
# Default prefix (Ctrl-b). This only affects the orc server, not the user's tmux.
# Prefix+Space, Prefix+m, Prefix+?, and Prefix+w are bound dynamically by
# _tmux_ensure_session() based on TUI config.
```

- [ ] **Step 2: Verify config loads without errors**

```bash
tmux -L orc-test -f packages/cli/lib/orc-tmux.conf new-session -d -s test
echo "Exit code: $?"
tmux -L orc-test list-sessions
tmux -L orc-test kill-server
echo "Config loads clean"
```

Expected: Exit code 0, session `test` listed, server cleaned up.

- [ ] **Step 3: Commit**

```bash
git add packages/cli/lib/orc-tmux.conf
git commit -m "feat: add orc-tmux.conf with static tmux options"
```

---

## Task 2: Add Socket Constants and Wrapper

**Files:**
- Modify: `packages/cli/lib/_common.sh`

- [ ] **Step 1: Add `ORC_TMUX_SOCKET` constant and `_orc_tmux()` wrapper**

In `_common.sh`, after `readonly ORC_TMUX_SESSION="orc"` (line 289), add:

```bash
readonly ORC_TMUX_SOCKET="orc"

# Wrap all tmux calls to target the isolated orc tmux server.
# This ensures no tmux commands leak to the user's default server.
_orc_tmux() {
    tmux -L "${ORC_TMUX_SOCKET}" "$@"
}

# Resolve the path to the static tmux config file.
_tmux_conf_path() {
    echo "${_ORC_ROOT}/lib/orc-tmux.conf"
}
```

- [ ] **Step 2: Update `_tmux_version_gte()` to use `_orc_tmux`**

The `_tmux_version_gte()` function (line 293) uses `tmux -V` which should NOT use `-L orc` because `tmux -V` returns the client version, not the server version. Keep this as bare `tmux -V` — it doesn't target any server.

No change needed for `_tmux_version_gte()`.

- [ ] **Step 3: Commit**

```bash
git add packages/cli/lib/_common.sh
git commit -m "feat: add ORC_TMUX_SOCKET, _orc_tmux wrapper, _tmux_conf_path"
```

---

## Task 3: Refactor `_tmux_ensure_session()`

**Files:**
- Modify: `packages/cli/lib/_common.sh`

This is the most complex task. The function currently: (1) creates/reuses the session, (2) sets ~200 lines of options/theme/bindings. We split it into: (1) session creation using the config file, (2) dynamic options that depend on runtime config (theme, keybindings, status bar).

- [ ] **Step 1: Rewrite session creation to use config file**

Replace the session creation block (lines 301-313) with:

```bash
_tmux_ensure_session() {
  if ! _orc_tmux has-session -t "$ORC_TMUX_SESSION" 2>/dev/null; then
    _orc_tmux -f "$(_tmux_conf_path)" new-session -d -s "$ORC_TMUX_SESSION" -n "_orc_init"
  else
    # Clean up stale _orc_init window from a prior session
    local _win_count
    _win_count="$(_orc_tmux list-windows -t "$ORC_TMUX_SESSION" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$_win_count" -gt 1 ]]; then
      _orc_tmux kill-window -t "${ORC_TMUX_SESSION}:_orc_init" 2>/dev/null || true
    fi
  fi
  # ... rest continues below
```

- [ ] **Step 2: Remove static option lines that are now in `orc-tmux.conf`**

Remove lines 322-330 (the `set-option` calls for `history-limit`, `alternate-screen`, `base-index`, `renumber-windows`, `allow-rename`, `monitor-activity`, `visual-activity`, `pane-border-format`, `pane-border-status`, `status-interval`). These are now in `orc-tmux.conf`.

- [ ] **Step 3: Keep dynamic options (theme, TUI, keybindings) but change `tmux` → `_orc_tmux`**

The remaining lines (315-510) contain dynamic logic that reads config values and generates theme. Replace all bare `tmux` calls in this section with `_orc_tmux`. This includes:
- `tmux set-environment` → `_orc_tmux set-environment`
- `tmux source-file` → `_orc_tmux source-file`
- `tmux set-option -t` → `_orc_tmux set-option -t`
- `tmux set-window-option -g` → `_orc_tmux set-window-option -g`
- `tmux bind-key` → `_orc_tmux bind-key`
- `tmux unbind-key` → `_orc_tmux unbind-key`
- `tmux show-option` → `_orc_tmux show-option`

Keep the `set-option -t "$ORC_TMUX_SESSION"` and `set-option -g` calls that are dynamic (they set status-left, status-right, per-window options like @orc_short). These must stay in shell because they depend on runtime config values and template strings.

- [ ] **Step 4: Remove `ORC_TMUX_NEEDS_CLEANUP` variable**

The `ORC_TMUX_NEEDS_CLEANUP` variable (set on line 304, used in `_tmux_cleanup_init`) was used to conditionally apply options only on first start. With the config file approach, static options are loaded via `-f` and don't need re-application. Remove the variable and its conditional usage in `_tmux_cleanup_init()`.

- [ ] **Step 5: Update `_tmux_cleanup_init()`**

Update `_tmux_cleanup_init()` to kill the `_orc_init` window using `_orc_tmux` instead of bare `tmux`. Also remove the `ORC_TMUX_NEEDS_CLEANUP` conditional.

- [ ] **Step 6: Smoke test**

```bash
# Kill any existing orc server
tmux -L orc kill-server 2>/dev/null || true

# Source the updated _common.sh and test session creation
source packages/cli/lib/_common.sh 2>/dev/null || true
_tmux_ensure_session

# Verify session exists on the orc server
tmux -L orc list-sessions
# Expected: "orc: 1 windows (created ...)"

# Verify session does NOT exist on default server
tmux list-sessions 2>&1 | grep -v "orc"
# Expected: no "orc" session on default server

# Cleanup
tmux -L orc kill-server
```

- [ ] **Step 7: Commit**

```bash
git add packages/cli/lib/_common.sh
git commit -m "feat: refactor _tmux_ensure_session to use orc-tmux.conf and _orc_tmux"
```

---

## Task 4: Replace All Bare `tmux` Calls (Batch Replace)

**Files:**
- Modify: all files in `packages/cli/lib/` and `packages/cli/bin/`

This is the largest mechanical change. Every bare `tmux` call that targets a session/window/pane must become `_orc_tmux`. The only exceptions are:
- `tmux -V` (version check, doesn't target a server)
- `tmux -L orc -f ...` in `_tmux_ensure_session()` (already handled)
- `fzf-tmux` in `chooser.sh` (separate binary, not a tmux command)

- [ ] **Step 4.1: Replace in `_common.sh` (excluding _tmux_ensure_session, already done)**

```bash
# Find remaining bare tmux calls in _common.sh
grep -n 'tmux ' packages/cli/lib/_common.sh | grep -v '_orc_tmux' | grep -v 'tmux -V' | grep -v '# '
```

Replace each with `_orc_tmux`. Pay special attention to:
- `_tmux_send()` (line ~543)
- `_tmux_new_window()` (line ~522)
- `_tmux_cleanup_goal_window()`
- `_tmux_set_pane_id()` / `_tmux_find_pane()`
- `_tmux_apply_goal_layout()`
- `_tmux_pane_target()` / `_tmux_overflow_windows()`
- `_tmux_split_with_agent()`
- `_launch_agent_in_window()` / `_launch_agent_in_review_pane()`
- `_tmux_tile_panes()`
- `_orc_goto()`
- `_tmux_is_pane_alive()` / `_tmux_is_dead_window()`
- `_last_project_window()`

- [ ] **Step 4.2: Replace in `start.sh`**
- [ ] **Step 4.3: Replace in `spawn-goal.sh`**
- [ ] **Step 4.4: Replace in `spawn.sh`**
- [ ] **Step 4.5: Replace in `review.sh`**
- [ ] **Step 4.6: Replace in `board.sh`**
- [ ] **Step 4.7: Replace in `teardown.sh`**
- [ ] **Step 4.8: Replace in `halt.sh`**
- [ ] **Step 4.9: Replace in `leave.sh`**
- [ ] **Step 4.10: Replace in `bin/orc`**
- [ ] **Step 4.11: Replace in `chooser.sh`**
- [ ] **Step 4.12: Replace in `menu-action.sh`**
- [ ] **Step 4.13: Replace in `setup.sh`**

- [ ] **Step 4.14: Verify no bare tmux calls remain for session management**

```bash
grep -rn 'tmux ' packages/cli/ --include='*.sh' \
  | grep -v '_orc_tmux' \
  | grep -v 'orc-tmux.conf' \
  | grep -v '# ' \
  | grep -v 'tmux -V' \
  | grep -v 'fzf-tmux' \
  | grep -v '_require tmux'
```

Expected: empty output (no remaining bare `tmux` calls for session management).

- [ ] **Step 4.15: Commit**

```bash
git add -A
git commit -m "refactor: replace all bare tmux calls with _orc_tmux wrapper"
```

---

## Task 5: Rewrite `_orc_goto()` for Nested Attach

**Files:**
- Modify: `packages/cli/lib/_common.sh`

- [ ] **Step 1: Rewrite `_orc_goto()`**

The current `_orc_goto()` (around line 575) uses `tmux switch-client` when inside tmux and `exec tmux attach-session` when outside. With socket isolation:

```bash
_orc_goto() {
  local target="$1"

  # If we're already inside the orc tmux, switch windows directly
  if [[ -n "${TMUX:-}" ]] && [[ "${TMUX##*/}" == "${ORC_TMUX_SOCKET}"* ]]; then
    _orc_tmux switch-client -t "${ORC_TMUX_SESSION}:${target}"
  else
    # Outside orc tmux (bare terminal or user's tmux) — attach
    _orc_tmux attach -t "${ORC_TMUX_SESSION}"
  fi
}
```

The key insight: `$TMUX` contains the socket path. Inside orc's tmux, it will contain the path to `/tmp/tmux-$UID/orc`. Inside the user's tmux, it will contain a different socket path. This allows us to detect which tmux we're in.

- [ ] **Step 2: Update `leave.sh`**

In `leave.sh`, replace `tmux detach-client` with `_orc_tmux detach-client`.

- [ ] **Step 3: Update `bin/orc` for `$TMUX` detection**

In `bin/orc`, update the `$TMUX` detection block (around lines 59-63) to check if we're inside the orc server specifically, and adjust YOLO propagation accordingly.

- [ ] **Step 4: Smoke test**

```bash
# Test from bare terminal
tmux -L orc kill-server 2>/dev/null || true
orc start myproject
# Should create orc server and attach

# Detach with Ctrl-b d
# Should return to bare terminal

# Test from user's tmux
tmux new -s user-session
orc start myproject
# Should nested-attach in current pane

# Ctrl-b d to detach from orc (prefix is orc's Ctrl-b)
# Should return to user's tmux

# Cleanup
tmux -L orc kill-server
tmux kill-session -t user-session
```

- [ ] **Step 5: Commit**

```bash
git add packages/cli/lib/_common.sh packages/cli/lib/leave.sh packages/cli/bin/orc
git commit -m "feat: rewrite _orc_goto for nested tmux attach with socket detection"
```

---

## Task 6: Update Teardown and Doctor

**Files:**
- Modify: `packages/cli/lib/teardown.sh`
- Modify: `packages/cli/lib/doctor.sh`

- [ ] **Step 1: Update `teardown.sh`**

The `teardown` command for "all" scope should kill the orc session, not the server:

```bash
# Replace: tmux kill-session -t "$ORC_TMUX_SESSION"
# With:     _orc_tmux kill-session -t "$ORC_TMUX_SESSION"
```

- [ ] **Step 2: Add orphan session check to `doctor.sh`**

Add a new doctor check that detects an `orc` session on the default tmux server (leftover from pre-migration):

```bash
# Check for orphaned orc session on default tmux server
if tmux has-session -t orc 2>/dev/null; then
  _warn "Found orphaned 'orc' session on default tmux server."
  _warn "This may be from a pre-v2 installation. Run: tmux kill-session -t orc"
  _warn "To clean up. The current orc uses a separate server (tmux -L orc)."
fi
```

- [ ] **Step 3: Commit**

```bash
git add packages/cli/lib/teardown.sh packages/cli/lib/doctor.sh
git commit -m "feat: update teardown for socket isolation, add orphan session doctor check"
```

---

## Task 7: Update Environment Propagation

**Files:**
- Modify: `packages/cli/lib/_common.sh`
- Modify: `packages/cli/bin/orc`

- [ ] **Step 1: Update environment propagation in `_tmux_ensure_session()`**

Replace:
```bash
tmux set-environment -t "$ORC_TMUX_SESSION" ORC_YOLO 1
```
With:
```bash
_orc_tmux set-environment -t "$ORC_TMUX_SESSION" ORC_YOLO 1
```

(already handled in Task 3 if done comprehensively, but verify)

- [ ] **Step 2: Update `bin/orc` YOLO detection**

In `bin/orc` (lines 60-63), the current code reads YOLO from the default tmux session environment. Update it to read from the orc server:

```bash
if [[ -n "${TMUX:-}" ]] && [[ "${ORC_YOLO:-}" != "1" ]]; then
  tmux_yolo="$(_orc_tmux show-environment -t "$ORC_TMUX_SESSION" ORC_YOLO 2>/dev/null | grep -v '^-' | cut -d= -f2 || true)"
  [[ "$tmux_yolo" == "1" ]] && export ORC_YOLO=1
fi
```

- [ ] **Step 3: Commit**

```bash
git add packages/cli/lib/_common.sh packages/cli/bin/orc
git commit -m "feat: update environment propagation for socket-isolated tmux"
```

---

## Task 8: Update Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/configuration.md`
- Modify: `docs/config.toml.example`
- Modify: `migrations/CHANGELOG.md`

- [ ] **Step 1: Update CLAUDE.md tmux architecture section**

Update the tmux architecture documentation to describe:
- Socket isolation (`-L orc` server)
- `_orc_tmux()` wrapper function
- `orc-tmux.conf` static config file
- Nested tmux attach behavior
- `ORC_TMUX_SOCKET` constant

- [ ] **Step 2: Update docs/configuration.md**

Add documentation for `ORC_TMUX_SOCKET` constant and socket isolation approach.

- [ ] **Step 3: Update docs/config.toml.example**

No new tmux-specific config options needed, but update any comments that reference "tmux session" to clarify "tmux server (socket-isolated)".

- [ ] **Step 4: Add migration note to migrations/CHANGELOG.md**

```markdown
## [next] - Breaking Change: Socket-Isolated tmux

### Migration

Orc now runs in its own tmux server (`-L orc`) instead of the default tmux server.
If you have an existing `orc` session on your default tmux server, remove it with:

    tmux kill-session -t orc

After upgrading, `orc start` will create a new isolated server automatically.
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/configuration.md docs/config.toml.example migrations/CHANGELOG.md
git commit -m "docs: update tmux architecture docs for socket isolation"
```

---

## Task 9: Integration Testing

- [ ] **Step 9.1: Test from bare terminal**

```bash
tmux -L orc kill-server 2>/dev/null || true
orc start <project>
# Expected: creates orc server, attaches in current terminal
# Ctrl-b d → detaches back to bare terminal
```

- [ ] **Step 9.2: Test from user's tmux**

```bash
tmux new -s user-test
orc start <project>
# Expected: nested attach in current pane
# Ctrl-b d → detaches from orc, returns to user's tmux
# User's tmux settings unchanged
```

- [ ] **Step 9.3: Test user's tmux is unaffected**

```bash
# Before starting orc, save user's tmux settings
tmux show-options -s > /tmp/before_settings

# Start orc
orc start <project>

# After starting orc, check user's tmux settings
tmux show-options -s > /tmp/after_settings

# Compare
diff /tmp/before_settings /tmp/after_settings
# Expected: no differences
```

- [ ] **Step 9.4: Test `orc spawn-goal` creates windows in orc server**

```bash
orc spawn-goal <project> <goal>
tmux -L orc list-windows
# Expected: shows the goal window

tmux list-windows 2>&1 | grep orc
# Expected: no "orc" session on default server
```

- [ ] **Step 9.5: Test `orc teardown all`**

```bash
orc teardown all
tmux -L orc list-sessions
# Expected: no sessions (or empty result)
tmux list-sessions
# Expected: user's sessions unchanged
```

- [ ] **Step 9.6: Test `orc doctor` orphan warning**

```bash
# Create a fake orphaned session on default server
tmux new-session -d -s orc
orc doctor
# Expected: warning about orphaned "orc" session on default server

# Clean up
tmux kill-session -t orc
```

- [ ] **Step 9.7: Commit passing tests**

```bash
git add -A
git commit -m "test: integration tests for socket-isolated tmux"
```

---

## Self-Review

### Spec Coverage

| Spec Requirement | Task |
|-----------------|------|
| Socket-Isolated tmux Server | Task 2 (constants), Task 3 (refactor) |
| Static tmux Config File | Task 1 |
| Nested tmux Attach | Task 5 |
| `_orc_tmux()` Wrapper | Task 2, Task 4 |
| Teardown Session Kill | Task 6 |
| Doctor Orphan Warning | Task 6 |
| Goal Orchestrator Worktree in orc server | Task 4 (slider calls) |
| Keybinding Scoping | Task 3 (dynamic bindings use `_orc_tmux`) |
| Environment Propagation | Task 7 |
| Command Categories (Attach/Operate/Query) | Task 4, Task 5 |

### Placeholder Scan

No TBD/TODO/placeholder entries found. All steps contain actual code or commands.

### Type Consistency

- `ORC_TMUX_SOCKET` = `"orc"` (string, used in `_orc_tmux` and `_tmux_ensure_session`)
- `_orc_tmux()` wraps all `tmux` calls consistently
- `_tmux_conf_path()` returns `${_ORC_ROOT}/lib/orc-tmux.conf` (path string)