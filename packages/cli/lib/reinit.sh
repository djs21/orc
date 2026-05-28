#!/usr/bin/env bash
# reinit.sh — Reinitialize environment, repair broken worktrees, and fix dependencies.

set -euo pipefail

# --force skips confirmation
force=0
args=()
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    *)       args+=("$arg") ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"

_reinit_env() {
  if [[ "$force" -eq 0 ]]; then
    printf '%s' "[orc] Reinitialize EVERYTHING? This will kill active agent sessions, clean temporary states, and prune corrupt git worktrees. [y/N] "
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || { _info "Cancelled."; exit "$EXIT_OK"; }
  fi

  _info "Reinitializing Orc Environment..."

  # 1. Teardown tmux session if active
  if _orc_tmux has-session -t "$ORC_TMUX_SESSION" 2>/dev/null; then
    _info "Active tmux session detected. Tearing down safely..."
    "${ORC_ROOT}/packages/cli/bin/orc" teardown --force
  fi

  # 2. Re-resolve all registered projects and fix their worktrees
  for key in $(_project_keys); do
    local project_path
    project_path="$(_require_project "$key")"
    _info "Repairing worktrees for project '$key'..."
    
    # Remove corrupt/stale worktrees
    rm -rf "$project_path/.worktrees/.project-orch" 2>/dev/null || true
    
    # Prune git worktrees metadata
    git -C "$project_path" worktree prune 2>/dev/null || true
  done

  # 3. Check for passive event-driven monitoring dependencies
  _info "Checking system monitoring tools..."
  if ! command -v inotifywait &>/dev/null && ! command -v fswatch &>/dev/null; then
    _warn "Missing fast event monitoring tools (inotifywait or fswatch). Using polling fallback."
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
      _info "To enable ultra-fast, zero-polling response: brew install fswatch"
    else
      _info "To enable ultra-fast, zero-polling response: sudo apt-get update && sudo apt-get install -y inotify-tools"
    fi
  else
    _info "Event-driven system monitor detected. OK."
  fi

  # 4. Clean socket state dir
  rm -rf "$(_orc_state_dir)" 2>/dev/null || true

  _info "Orc successfully reinitialized to a clean slate!"
}

_reinit_env
