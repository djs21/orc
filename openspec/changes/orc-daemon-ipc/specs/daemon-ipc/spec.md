# Spec: Orc Daemon & IPC

## Functional Requirements

### FR1 — Daemon Auto-Spawn
- `_orc_daemon_ensure()` checks `/tmp/orc-state/daemon.lock` for a live PID.
- If dead or missing: create FIFO `/tmp/orc-state/ipc.fifo`, spawn `daemon.sh` in background via `_orc_tmux run-shell -b`, write new PID.
- Must complete in <200ms total.

### FR2 — Non-blocking FIFO Write
- `orc notify --send` calls `_orc_daemon_ensure`, then tries FIFO write with `timeout 0.1`.
- On success: message delivered instantly to daemon.
- On failure (FIFO full / no reader yet): fallback to `/tmp/orc-state/queue/<N>.msg`.

### FR3 — Disk Queue Fallback
- Queue files: `/tmp/orc-state/queue/<epoch-ns>.msg`.
- Daemon, on startup and every idle cycle, reads and processes all `.msg` files in order.
- After processing, deletes each `.msg` file.

### FR4 — Signal-Based Orchestrator Wake-Up
- Before waiting, orchestrator writes its PID to `<state_dir>/.worker-pid`.
- Registers trap: `trap "_worker_wake_handler" SIGUSR1`.
- Enters passive wait: `sleep 3600 & wait $!`.
- On `SIGUSR1`: trap fires, orchestrator re-reads `.worker-status` and proceeds.

### FR5 — Queue Purge
- Daemon reads all backlogged `.msg` files.
- Deletes after successful processing to prevent duplicates.
- On teardown, `daemon.lock`, `ipc.fifo`, and entire `queue/` are cleaned.

## Non-Functional Requirements

- Wake-up latency <10ms from agent `notify --send` to orchestrator resuming.
- Zero CPU usage while orchestrators wait.
- No agent CLI process hangs if daemon is temporarily unavailable (non-blocking FIFO + queue fallback).
- All state under `/tmp/orc-state/` — no persistent disk writes beyond one-time queue fallback.

## Acceptance Criteria

1. **AC1**: `orc notify --send` delivers message to daemon within 100ms (FIFO path).
2. **AC2**: If daemon is killed, next `orc notify --send` auto-restarts it (verified by lock file + PID).
3. **AC3**: Orchestrator wakes from passive wait in <10ms after daemon sends `SIGUSR1`.
4. **AC4**: If FIFO is congested, messages queue to `/tmp/orc-state/queue/` and are processed when daemon is ready.
5. **AC5**: `orc teardown` kills daemon and cleans `/tmp/orc-state/daemon.lock`, `ipc.fifo`, `queue/`.
