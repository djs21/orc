## Context

The opencode adapter has three independent bugs that together prevent any orchestrator session from working:

1. **Invalid `-q` flag**: `_adapter_build_launch_cmd` generates `opencode run --agent orc-{role} -q "$(cat $prompt_file)"`. The `-q` flag does not exist in opencode CLI. When opencode receives an unrecognized flag, it prints its `--help` output and exits — the user sees the help page instead of the agent TUI.

2. **Missing persona injection**: `_launch_agent_in_window` does not forward `working_dir` or `role` to `_build_and_launch`. Since `_build_and_launch` only calls `_adapter_inject_persona` and `_adapter_pre_launch` when `working_dir` is non-empty, all orchestrator sessions (root, project, goal, legacy engineer, setup, doctor) skip persona injection. The opencode adapter then references `--agent orc-{role}` but the agent file was never created, so opencode reports "agent not found" and falls back to its default agent — the orc persona is never loaded.

3. **Missing slash commands in worktrees**: opencode loads commands from `.opencode/commands/` relative to CWD. Agents run inside worktrees (e.g., `project/.worktrees/.project-orch`) which do not have `orc-*.md` command symlinks — the global install at `~/.config/opencode/commands/` is not loaded by opencode when a local `.opencode/commands/` directory exists. The orchestrator agent therefore cannot use `/orc:plan`, `/orc:dispatch`, `/orc:check`, or any other orc slash command.

Additionally, two design issues were discovered during implementation:

- **Wrong launch mode for orchestrators**: The adapter used `opencode run` (non-interactive, exits after processing) for all sessions with a prompt file. Orchestrators need `opencode --agent` (TUI mode) so the user can interact with them. The initial prompt is already embedded in the persona content via `_build_and_launch`, so the prompt file is redundant for orchestrators.
- **Missing `external_directory` permission**: The permission block in agent files only included `edit`, `bash`, and `webfetch`. Orchestrator worktrees are separate from project roots — without `external_directory: allow`, all access to project root paths is auto-rejected by opencode.

The engineer path via `_tmux_split_with_agent` works correctly because it passes both `role` and `working_dir` to `_build_and_launch`.

Current call flow for orchestrators:

```
start.sh / spawn-goal.sh / spawn.sh / setup.sh / doctor.sh
  └─ _launch_agent_in_window(window, persona, project_path, initial_prompt)
       └─ _build_and_launch(send_fn, project_path, persona, initial_prompt)
            ├─ role = "engineer" (default, wrong for orchestrators)
            ├─ working_dir = "" (empty → persona injection SKIPPED)
            └─ adapter builds: opencode run --agent orc-engineer -q "Begin."
                                                       ↑ wrong role    ↑ invalid flag
```

## Goals / Non-Goals

**Goals:**
- Fix the opencode adapter to generate valid CLI commands (no `-q` flag)
- Fix `_launch_agent_in_window` to forward `working_dir` and `role` so persona injection works for all session types
- Ensure all existing call sites of `_launch_agent_in_window` pass the correct `working_dir`
- Make orchestrators launch in TUI mode instead of non-interactive `opencode run`
- Add `external_directory: allow` to the permission block
- Install orc slash commands into worktree `.opencode/commands/` so they are available to agents

**Non-Goals:**
- Changing the adapter interface or adding new adapter hooks
- Modifying how other adapters (claude, codex, gemini) work — they don't use file-based persona injection or commands
- Changing the tmux window/pane management

## Decisions

### Decision 1: Replace `-q` with positional argument

**Choice**: Remove `-q` flag, pass message as positional argument to `opencode run`.

```bash
# Before:
cmd="$cmd run --agent orc-${role} -q \"\$(cat $prompt_file)\""
# After:
cmd="$cmd run --agent orc-${role} \"\$(cat $prompt_file)\""
```

**Rationale**: `opencode run [message..]` accepts the message as positional arguments. This is the documented interface. `-q` was either from an older opencode version or was never valid.

**Alternative considered**: Use `--command` flag of `opencode run`. Rejected — `--command` is for running shell commands, not sending chat messages.

### Decision 2: Extend `_launch_agent_in_window` signature

**Choice**: Add optional `role` and `working_dir` parameters to `_launch_agent_in_window`:

```bash
_launch_agent_in_window() {
  local window="$1"
  local persona="$2"
  local project_path="${3:-}"
  local initial_prompt="${4:-}"
  local role="${5:-engineer}"
  local working_dir="${6:-}"

  _send_to_window() {
    _tmux_send "$window" "bash $1"
  }

  _build_and_launch _send_to_window "$project_path" "$persona" "$initial_prompt" "$role" "$working_dir"
}
```

**Rationale**: This mirrors the existing pattern in `_launch_agent_in_review_pane` (which already accepts `working_dir` as `$5`) and `_tmux_split_with_agent` (which already passes both `role` and `working_dir`). The defaults maintain backward compatibility.

**Alternative considered**: Derive `working_dir` from the tmux window's current directory inside `_build_and_launch`. Rejected — would couple `_build_and_launch` to tmux internals and make testing harder. Explicit is better.

### Decision 3: Derive `working_dir` at each call site

Each call site of `_launch_agent_in_window` has access to the working directory that the tmux window was created with. The mapping:

| Call site | `working_dir` value |
|---|---|
| `start.sh` root orch | `$ORC_ROOT` |
| `start.sh` project orch | `$proj_worktree` |
| `spawn-goal.sh` goal orch | `$goal_worktree` |
| `spawn.sh` legacy engineer | `$worktree` |
| `setup.sh` project setup | `$proj_worktree` (same as project orch) |
| `doctor.sh` root doctor | `$ORC_ROOT` |

### Decision 4: Orchestrators use TUI mode, engineers use run mode

**Choice**: In `_adapter_build_launch_cmd`, use `opencode run` (non-interactive) only for the `engineer` role. All other roles (orchestrator, goal-orchestrator, reviewer) use `opencode --agent` (TUI mode).

```bash
if [[ -n "$prompt_file" && "$role" == "engineer" ]]; then
  # Engineers: non-interactive run mode with auto-start
  cmd="$cmd run --agent orc-${role} \"\$(cat $prompt_file)\""
else
  # Orchestrators/reviewers: interactive TUI mode
  cmd="$cmd --agent orc-${role}"
fi
```

**Rationale**: Orchestrators are interactive — the user needs to converse with them, approve plans, provide feedback. The initial prompt is already merged into the persona by `_build_and_launch`, so the prompt file is redundant. Engineers, by contrast, should start working immediately without user interaction.

**Alternative considered**: Use `opencode run` with an interactive flag for orchestrators. Rejected — opencode doesn't have such a flag. TUI mode IS the interactive mode.

### Decision 5: Add `external_directory: allow` to permission block

**Choice**: Add `external_directory: allow` to both yolo and normal permission blocks in `_adapter_inject_persona`.

**Rationale**: Orchestrator worktrees are separate from project roots. When an orchestrator needs to run `git -C <project_path>`, `bd`, or read files from the project root, opencode auto-rejects the access because the path is outside the worktree. This permission must be allowed for the orchestration flow to work.

**Alternative considered**: Only add it for orchestrator roles. Rejected — engineers also need to access project root for `bd` commands and status files. Simpler to allow universally.

### Decision 6: Install commands to worktree during persona injection

**Choice**: In `_adapter_inject_persona`, after creating the agent file, also symlink orc commands to `{worktree}/.opencode/commands/orc-*.md`.

**Rationale**: opencode loads commands from `.opencode/commands/` relative to CWD. When a worktree has its own `.opencode/` directory (created by `_adapter_inject_persona`), opencode uses the worktree's commands directory and does NOT fall through to `~/.config/opencode/commands/`. The orc commands must be installed in the worktree for the agent to access `/orc:plan`, `/orc:dispatch`, etc.

**Alternative considered**: Install commands globally only and remove the local `.opencode/commands/` directory. Rejected — the worktree may need project-specific commands that differ from the global set. Installing orc commands alongside project commands is cleaner.

## Risks / Trade-offs

- **[Risk] Other adapters may not expect persona injection for orchestrators** → Mitigation: The `_adapter_inject_persona` hook is optional. Adapters that don't need file-based persona injection (claude, codex) can implement it as a no-op or already do. The opencode adapter is the only one that relies on it for agent configuration.

- **[Risk] Role derivation at call sites may be wrong** → Mitigation: The `role` parameter follows the same convention already used in `_tmux_split_with_agent` (line 1239-1243). Root orchestrator → `"orchestrator"`, project orchestrator → `"orchestrator"`, goal orchestrator → `"goal-orchestrator"`, engineer → `"engineer"`, reviewer → `"reviewer"`.

- **[Trade-off] Adding parameters to `_launch_agent_in_window`** is a wider change than minimally required, but it's the correct structural fix. The alternative of hardcoding working_dir inside `_build_and_launch` would be more fragile.

- **[Risk] Command symlinks in worktrees may become stale** if orc commands are updated → Mitigation: Symlinks point to `$ORC_ROOT/packages/commands/_canonical/*.md` which is the source of truth. As long as ORC_ROOT is not moved, symlinks stay valid. The `_adapter_post_teardown` cleanup already removes agent files; it should also remove command symlinks.

- **[Trade-off] Installing commands per-worktree** duplicates the symlinks across worktrees, but this is negligible (symlinks are zero-size) and ensures isolation between worktrees.
