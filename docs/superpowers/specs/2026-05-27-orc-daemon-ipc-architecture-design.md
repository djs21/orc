# Design: Orc Daemon & IPC Architecture

## Problem
Orchestrators poll `.worker-status` with `sleep` loops → 2-15s latency, user nudges needed, engineers make poor decisions while waiting.

## Solution
Self-healing daemon on `tmux -L orc` with named pipe IPC + SIGUSR1 wake-ups.

## Architecture Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Event dispatch | Single-threaded | Low volume, zero races |
| IPC | Named pipe (FIFO) | Kernel-native, multi-producer, zero polling |
| Wake-up | SIGUSR1 | UNIX-native instant, works with bash `wait` |
| Self-healing | Auto-spawn on CLI | Transparent, no manual restart |
| Congestion | Disk queue fallback | Non-blocking with 100ms timeout |
| PID tracking | `.worker-pid` file | Decoupled, daemon reads on event |
| Server | `tmux -L orc` (existing) | Already isolated |

## Flow

1. `_orc_daemon_ensure()` — check/craate lock → FIFO → spawn daemon
2. `orc notify --send` — 100ms timeout write to FIFO or queue file
3. Daemon loop — reads FIFO → parses event → finds PID → SIGUSR1 → update status
4. Orchestrator — trap SIGUSR1 → re-read status → proceed
5. Teardown — kill daemon PID, clean lock/FIFO/queue

## File Layout

```
/tmp/orc-state/
├── daemon.lock          PID of daemon process
├── ipc.fifo             Named pipe for event transport
└── queue/                Fallback msg files
    ├── <epoch-ns>.msg
    └── ...
```
