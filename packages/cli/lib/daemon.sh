#!/usr/bin/env bash
# Orc Daemon: Handles lock-free IPC events and sends SIGUSR1 to waiting processes.

set -euo pipefail

ORC_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)"
source "$ORC_ROOT/packages/cli/lib/_common.sh"

_orc_state_dir_val="$(_orc_state_dir)"
LOCK_FILE="$_orc_state_dir_val/daemon.lock"
FIFO_FILE="$_orc_state_dir_val/ipc.fifo"
QUEUE_DIR="$_orc_state_dir_val/queue"

# Ensure we're the only daemon running
if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
  exit 0
fi

mkdir -p "$QUEUE_DIR"
echo "$$" > "$LOCK_FILE"

# Ensure FIFO exists
rm -f "$FIFO_FILE"
mkfifo "$FIFO_FILE"

_process_event() {
  local msg="$1"
  # Format: TIMESTAMP|SCOPE|EVENT|MESSAGE
  local ts scope event text
  
  # Read up to 4 fields
  IFS='|' read -r ts scope event text <<< "$msg"
  
  # Ensure we have required fields
  if [[ -z "$ts" || -z "$scope" || -z "$event" ]]; then
    return 0
  fi
  
  if [[ "$event" == "RESOLVED" ]]; then
    echo "$ts RESOLVED $scope \"$text\"" >> "$_orc_state_dir_val/notifications.log"
  else
    echo "$ts $event $scope \"$text\"" >> "$_orc_state_dir_val/notifications.log"
  fi

  # Wake up listening processes via SIGUSR1
  local pid_file="$_orc_state_dir_val/$scope/.worker-pid"
  
  if [[ -f "$pid_file" ]]; then
    local target_pid
    target_pid="$(cat "$pid_file")"
    if [[ -n "$target_pid" ]] && kill -0 "$target_pid" 2>/dev/null; then
      kill -SIGUSR1 "$target_pid" 2>/dev/null || true
    fi
  fi
  
  # Also try parent scope (e.g. if scope is project/goal/bead, wake up project/goal)
  local parent_scope
  parent_scope="$(dirname "$scope")"
  if [[ "$parent_scope" != "." && "$parent_scope" != "/" ]]; then
    local parent_pid_file="$_orc_state_dir_val/$parent_scope/.worker-pid"
    if [[ -f "$parent_pid_file" ]]; then
      local p_pid
      p_pid="$(cat "$parent_pid_file")"
      if [[ -n "$p_pid" ]] && kill -0 "$p_pid" 2>/dev/null; then
        kill -SIGUSR1 "$p_pid" 2>/dev/null || true
      fi
    fi
  fi
}

_process_queue() {
  for f in "$QUEUE_DIR"/*.msg; do
    [[ -f "$f" ]] || continue
    _process_event "$(cat "$f")"
    rm -f "$f"
  done
}

# Ensure cleanup on exit
trap 'rm -f "$LOCK_FILE" "$FIFO_FILE"' EXIT

# Main loop
while true; do
  _process_queue
  
  if read -r line < "$FIFO_FILE"; then
    _process_event "$line"
  fi
done
