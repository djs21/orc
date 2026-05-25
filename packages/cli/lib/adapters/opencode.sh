#!/usr/bin/env bash
# opencode.sh — Adapter for OpenCode CLI (opencode-ai/opencode).
#
# Prompt delivery: agent config files at .opencode/agents/*.md (YAML front-matter)
# Commands:        .opencode/commands/*.md (markdown with optional front-matter)
# Auto-approval:   per-agent permission block in front-matter (default: allow all)
# Docs:            https://opencode.ai/docs/

_adapter_inject_persona() {
  local persona_content="$1"
  local worktree_path="$2"
  local role="${3:-engineer}"

  local agents_dir="$worktree_path/.opencode/agents"
  mkdir -p "$agents_dir"

  local agent_file="$agents_dir/orc-${role}.md"

  # Build permission block based on yolo mode
  local permission_block
  if [[ "${ORC_YOLO:-0}" == "1" ]]; then
    permission_block="permission:
  edit: allow
  bash: allow
  webfetch: allow
  external_directory: allow"
  else
    permission_block="permission:
  edit: ask
  bash: ask
  webfetch: ask
  external_directory: allow"
  fi

  cat > "$agent_file" <<AGENT_EOF
---
description: "orc ${role} agent"
mode: primary
${permission_block}
---

${persona_content}
AGENT_EOF

  local commands_dir="$worktree_path/.opencode/commands"
  mkdir -p "$commands_dir"

  local canonical_dir="$ORC_ROOT/packages/commands/_canonical"
  if [[ -d "$canonical_dir" ]]; then
    for f in "$canonical_dir"/*.md; do
      [[ -f "$f" ]] || continue
      local name
      name="$(basename "$f" .md)"
      ln -sf "$f" "$commands_dir/orc-${name}.md"
    done
  fi
}

_adapter_build_launch_cmd() {
  local persona_file="$1"
  local prompt_file="${2:-}"
  local agent_flags="${3:-}"

  # Role is stored by _adapter_pre_launch for build_launch_cmd to use
  local role="engineer"
  local role_file="${TMPDIR:-/tmp}/orc-adapter-role"
  if [[ -f "$role_file" ]]; then
    role="$(cat "$role_file")"
  fi

  local cmd="opencode"
  [[ -n "$agent_flags" ]] && cmd="$cmd $agent_flags"

  if [[ -n "$prompt_file" && "$role" == "engineer" ]]; then
    # Engineers: non-interactive run mode with auto-start
    cmd="$cmd run --agent orc-${role} \"\$(cat $prompt_file)\""
  else
    # Orchestrators/reviewers: interactive TUI mode
    cmd="$cmd --agent orc-${role}"
  fi
  echo "$cmd"
}

_adapter_yolo_flags() {
  # OpenCode uses per-agent permission config, not CLI flags.
  # Yolo setup is handled in _adapter_inject_persona.
  echo ""
}

_adapter_install_commands() {
  local source_dir="$1"
  local project_path="${2:-}"

  local canonical_dir="$ORC_ROOT/packages/commands/_canonical"
  [[ -d "$canonical_dir" ]] || return 0

  # OpenCode commands live at .opencode/commands/ (project) or ~/.config/opencode/commands/ (global)
  local cmd_target
  if [[ -n "$project_path" ]]; then
    cmd_target="$project_path/.opencode/commands"
  else
    cmd_target="$HOME/.config/opencode/commands"
  fi
  mkdir -p "$cmd_target"

  for f in "$canonical_dir"/*.md; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .md)"
    # Symlink canonical markdown files — OpenCode commands use same MD format
    ln -sf "$f" "$cmd_target/orc-${name}.md"
  done
}

_adapter_pre_launch() {
  local worktree_path="$1"
  local role="${2:-engineer}"

  # Store role for _adapter_build_launch_cmd to reference
  echo "$role" > "${TMPDIR:-/tmp}/orc-adapter-role"
}

_adapter_post_teardown() {
  local worktree_path="$1"
  # Clean up orc-generated agent and command files
  rm -f "$worktree_path/.opencode/agents/orc-"*.md 2>/dev/null || true
  rm -f "$worktree_path/.opencode/commands/orc-"*.md 2>/dev/null || true
}
