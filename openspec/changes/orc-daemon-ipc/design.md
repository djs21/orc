# Design: Orc Daemon & IPC Architecture

## System Diagram

```
[Agent CLI (Engineer)]
       │  `orc notify --send EVENT payload`
       ▼
_orc_daemon_ensure()          ← auto-spawn if dead
       │
       ├── FIFO available → write EVENT to /tmp/orc-state/ipc.fifo
       └── FIFO blocked  → write to /tmp/orc-state/queue/<ts>.msg
                                 │
                                 ▼
                          ┌──────────────┐
                          │  Orc Daemon  │  (daemon.sh — single-threaded FIFO reader)
                          └──────┬───────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
              Update state   Send SIGUSR1  Purge queue/
              (.worker-status)  to PID in   log file
                                .worker-pid
                                    │
                                    ▼
                            [Orchestrator]
                            (wakes from passive wait)
```

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Event dispatch | Single-threaded queue (sekuensial) | Low event volume, zero race conditions |
| IPC mechanism | Named pipe (FIFO) | Kernel-native, zero polling, multi-producer safe |
| Wake-up signal | `SIGUSR1` | UNIX-native, instant, works with bash `wait` |
| Self-healing | Auto-spawn on CLI invoc. | Transparent recovery, no manual restart |
| Congestion handling | Fallback to disk queue | FIFO non-blocking write with 100ms timeout |
| PID tracking | `.worker-pid` file per scope | Decoupled, daemon reads PID file on event |
| Server isolation | Inside `tmux -L orc` | Fully contained, no interference with user tmux |

## Lifecycle

1. **First CLI call** → `_orc_daemon_ensure` detects no lock file → creates FIFO → spawns `daemon.sh` via `_orc_tmux run-shell -b` → writes PID to `/tmp/orc-state/daemon.lock`
2. **Agent signals** (e.g., engineer completes) → `orc notify --send` tries FIFO write → if timeout 100ms, falls back to queue file
3. **Daemon processes** → reads FIFO or queue → parses `TIMESTAMP\|SCOPE\|EVENT\|MESSAGE` → finds PID in `.worker-pid` → sends `SIGUSR1` → updates `.worker-status`
4. **Orchestrator wakes** → trap handler fires → re-reads `.worker-status` → proceeds
5. **Teardown** → `orc teardown` kills daemon PID, removes lock/FIFO/queue
