# Agent Communication Fixes

**Date:** 2025-05-27
**Status:** Draft

## Problem

Five bugs in orc's agent communication pipeline:

1. `orc_notify` is a bash function, not a CLI command — agents running in opencode cannot call it
2. `opencode run --agent orc-engineer` doesn't pipe prompts correctly in latest opencode version
3. `orc send` takes too long (0.15s sleep per send)
4. Pipelining to opencode broke in latest version
5. Sleep-based waiting is inelegant — need a better signaling mechanism

## Fix 1: `orc notify --send` CLI Command

**Root cause:** `_orc_notify()` is defined in `_common.sh` as a bash function. Agents (opencode, claude) can only run executables, not bash functions.

**Solution:** Add `--send` flag to existing `orc notify` subcommand:

```
orc notify --send <level> <scope> <message>
```

- `level`: One of `PLAN_REVIEW`, `PLAN_INVALIDATED`, `QUESTION`, `BLOCKED`, `GOAL_REVIEW`, `DELIVERY`, `GOAL_COMPLETE`, `ESCALATION`, `CAPACITY`
- `scope`: String identifier (e.g., `project/goal/bead`)
- `message`: Description

The handler calls the same `_orc_notify()` function that already exists.

Update persona docs (`check.md`, `goal-orchestrator.md`, `engineer.md`) to reference `orc notify --send` instead of `_orc_notify`.

## Fix 2/4: `opencode run` Adapter Fix

**Root cause:** `opencode run --agent orc-engineer "$(cat $prompt_file)"` syntax changed in latest opencode. The `run` subcommand with `--agent` may now open a TUI session instead of running non-interactively.

**Solution:** Adapt the launch command based on actual `opencode run` behavior:
- For engineers: Use `opencode run --agent orc-engineer -- "$(cat $prompt_file)"` if positional args work
- For orchestrators/reviewers: Use `opencode --agent orc-agent-name` (TUI mode) + send Enter via tmux

**Investigation needed:** Test what `opencode run --agent NAME "message"` actually produces.

## Fix 3/5: Replace Sleep-Based Waiting

**Root cause:** `_tmux_send()` and `_tmux_send_pane()` use `sleep 0.15` for pacing. No notification mechanism exists for status file changes.

**Solution:**

### 3a. Reduce sleep in `_tmux_send` 
Change `sleep 0.15` to `sleep 0.05` and add a readiness check:

After `paste-buffer`, instead of blind sleep + Enter, capture pane output and wait for a shell prompt character (`$`, `#`, `%`) before sending Enter. Use `-- no-block` or timeout.

### 3b. Optional file-watcher for status changes
Add `_orc_watch_status()` function:
- On Linux: uses `inotifywait -m -e modify`
- On macOS: uses `fswatch`
- Falls back to polling (current behavior) if neither is available

### 3c. tmux hooks for dead pane detection
Add `set-hook pane-died` to auto-detect when an agent process exits, instead of polling with `sleep` loops.
