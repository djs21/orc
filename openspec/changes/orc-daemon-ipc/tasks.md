# Tasks: Orc Daemon & IPC

## Task 1 — Create `packages/cli/lib/daemon.sh`
- Source `_common.sh`
- Write PID to `/tmp/orc-state/daemon.lock`
- Main loop: `read -r line < /tmp/orc-state/ipc.fifo`
- Parse event format: `TIMESTAMP|SCOPE|EVENT|MESSAGE`
- On EVENT=RESOLVED: send `SIGUSR1` to PID in `<scope>/../.worker-pid`
- On idle: purge `/tmp/orc-state/queue/*.msg`

Files: `packages/cli/lib/daemon.sh` (NEW)

## Task 2 — Add `_orc_daemon_ensure()` + `_orc_wait_for_status()` to `_common.sh`
- `_orc_daemon_ensure()`: lock check, FIFO creation, daemon spawn
- `_orc_wait_for_status()`: PID write, trap setup, passive `sleep + wait`

Files: `packages/cli/lib/_common.sh`

## Task 3 — Refactor `orc notify --send` in `notify.sh`
- Call `_orc_daemon_ensure`
- Non-blocking FIFO write with `timeout 0.1`
- Fallback: write to `/tmp/orc-state/queue/<ts>.msg`

Files: `packages/cli/lib/notify.sh`

## Task 4 — Refactor `orc notify --resolve` in `notify.sh`
- Also calls `_orc_daemon_ensure`
- Sends RESOLVED event to FIFO (daemon handles SIGUSR1 dispatch)

Files: `packages/cli/lib/notify.sh`

## Task 5 — Replace orchestrator poll loops with `_orc_wait_for_status`
- `spawn-goal.sh`: replace `while sleep` with `_orc_wait_for_status`

Files: `packages/cli/lib/spawn-goal.sh`

## Task 6 — Update `teardown.sh` daemon cleanup
- Kill daemon PID from lock file
- Remove `/tmp/orc-state/daemon.lock`, `ipc.fifo`, `queue/`

Files: `packages/cli/lib/teardown.sh`

## Task 7 — Verify & integration test
- Test auto-spawn (kill daemon, verify next CLI call restarts it)
- Test non-blocking FIFO (write with no reader, verify queue fallback)
- Test SIGUSR1 wake-up (measure latency <10ms)
- Test full flow: notify → daemon → SIGUSR1 → orchestrator wakes
