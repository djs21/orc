# Implementation Plan: Orc Daemon & IPC Architecture (Approach C)

**Date:** 2026-05-27  
**Status:** Plan  
**Spec:** `openspec/changes/orc-daemon-ipc/`

## Overview

Replaces file-polling orchestrator waits with a self-healing daemon + named pipe IPC + UNIX signal wake-ups. All running inside the isolated `tmux -L orc` server.

## Architecture

```
[Engineer] → `orc notify --send` → _orc_daemon_ensure (auto-spawn if dead)
                                       │
                                  ┌─────┴─────┐
                                  │  FIFO ok  │  ─→ write to /tmp/orc-state/ipc.fifo
                                  │ Congested │  ─→ /tmp/orc-state/queue/<ts>.msg
                                  └─────┬─────┘
                                        ▼
                                 ┌─────────────┐
                                 │  Orc Daemon │  (single-threaded FIFO reader)
                                 └──────┬──────┘
                                        │ SIGUSR1
                                        ▼
                                 [Orchestrator]
                                 (wakes from passive wait)
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `packages/cli/lib/daemon.sh` | NEW | FIFO event loop, SIGUSR1 dispatcher, queue purger |
| `packages/cli/lib/_common.sh` | MODIFY | Add `_orc_daemon_ensure()`, `_orc_wait_for_status()` |
| `packages/cli/lib/notify.sh` | MODIFY | Non-blocking FIFO write + queue fallback |
| `packages/cli/lib/spawn-goal.sh` | MODIFY | Replace sleep loops with `_orc_wait_for_status` |
| `packages/cli/lib/teardown.sh` | MODIFY | Clean daemon state |

## Tasks

1. **Create `daemon.sh`** — lock file, FIFO read loop, event parse, SIGUSR1 dispatch, queue purge
2. **Add helpers to `_common.sh`** — `_orc_daemon_ensure()`, `_orc_wait_for_status()`, `_orc_fifo_write()`, `_orc_queue_write()`
3. **Refactor `notify.sh`** — `--send` and `--resolve` use FIFO/queue
4. **Refactor `spawn-goal.sh`** — orchestrators use `_orc_wait_for_status` instead of sleep
5. **Update `teardown.sh`** — kill daemon, clean state
6. **Verify** — auto-spawn, non-blocking FIFO, SIGUSR1 latency, full flow
