# Proposal: Orc Daemon & IPC Architecture (Approach C)

## Problem

The current orchestrator-agent communication relies on:
1. **File polling (`sleep` loops)** — orchestrators read `.worker-status` on a timer, causing delays and 100% CPU waste per loop iteration.
2. **Orphaned agent detection** — no instant signal when a pane/agent exits or crashes.
3. **User "nudge" requirement** — orchestrators that miss updates require manual intervention to re-awaken.

This results in:
- ~2-15s latency between an engineer signaling `done` and the goal orchestrator noticing
- Unresponsive orchestrators that need manual `send-keys Enter` nudges
- Engineers making poor coding decisions while waiting for orchestrator feedback

## Solution

Replace blind polling with a lightweight **self-healing daemon** on the isolated `tmux -L orc` server. The daemon:

1. **Auto-spawns** on every `orc` CLI invocation if dead — self-healing, no manual restart.
2. **Listens on a named pipe (FIFO)** — zero-CPU idle, instant wake on message.
3. **Sends `SIGUSR1`** to waiting orchestrators — sub-millisecond wake-up vs seconds of polling.
4. **Falls back to disk queue** if FIFO is congested — guarantees no message loss.

## Impact

- Orchestrator wake-up latency: ~2-15s → <10ms
- CPU usage: active polling → zero during idle
- User nudges: required → never needed
- Code complexity: `_orc_watch_status`, file polling → one daemon loop, one FIFO
