# cli-resolution Specification

## Purpose
Defines how orc resolves, launches, and configures agent CLIs — including init-time selection, runtime detection, valid command generation, persona injection, and worktree command availability.
## Requirements
### Requirement: Adapter launch commands must produce valid CLI invocations

Every adapter's `_adapter_build_launch_cmd` SHALL generate a command string that the target CLI accepts without error. Flags that do not exist in the target CLI's interface SHALL NOT be included.

For the opencode adapter specifically:
- The `opencode run` subcommand accepts the message as positional arguments (`opencode run [message..]`), not via a `-q` flag
- The adapter SHALL pass the message content as a positional argument to `opencode run`
- The adapter SHALL use `opencode run` only for engineer sessions (non-interactive); orchestrator and reviewer sessions SHALL use `opencode --agent` (TUI mode)

#### Scenario: opencode adapter generates valid non-interactive command for engineers
- **WHEN** the opencode adapter builds a launch command with a prompt file AND the role is "engineer"
- **AND** the prompt file contains "Begin."
- **THEN** the generated command SHALL be `opencode run --agent orc-engineer "$(cat {prompt_file})"`
- **AND** the command SHALL NOT contain the `-q` flag

#### Scenario: opencode adapter generates valid interactive command for orchestrators
- **WHEN** the opencode adapter builds a launch command AND the role is NOT "engineer"
- **THEN** the generated command SHALL be `opencode --agent orc-{role}`
- **AND** opencode SHALL open its TUI without printing help output

#### Scenario: opencode adapter generates valid interactive command without prompt file
- **WHEN** the opencode adapter builds a launch command without a prompt file
- **THEN** the generated command SHALL be `opencode --agent orc-{role}`
- **AND** opencode SHALL open its TUI without printing help output

### Requirement: Agent permission block must allow external directory access

The opencode adapter's `_adapter_inject_persona` SHALL include `external_directory: allow` in the permission block for all roles. Orchestrator worktrees are separate from project roots, and agents need to access project root paths for `git`, `bd`, and status file operations.

#### Scenario: orchestrator can access project root
- **WHEN** an orchestrator agent runs in a worktree at `project/.worktrees/.project-orch`
- **AND** the agent attempts to read a file at `project/README.md`
- **THEN** opencode SHALL NOT auto-reject the access

#### Scenario: Agent file includes model field when configured
- **WHEN** `[models]` config has `orchestrator = "opencode-go/glm-5.1"`
- **AND** an orchestrator agent file is created
- **THEN** the YAML front-matter SHALL include `model: opencode-go/glm-5.1` between `mode` and `permission`

### Requirement: Persona injection must work for all session types

`_launch_agent_in_window` SHALL forward `role` and `working_dir` to `_build_and_launch` so that adapter persona injection hooks (`_adapter_inject_persona`, `_adapter_pre_launch`) are called for all session types, including root orchestrator, project orchestrator, goal orchestrator, and legacy engineer sessions.

#### Scenario: Root orchestrator session receives persona injection
- **WHEN** `orc` starts a root orchestrator session
- **THEN** `_adapter_inject_persona` SHALL be called with `working_dir` set to the root orchestrator's working directory
- **AND** `_adapter_pre_launch` SHALL be called with the correct role
- **AND** the agent file SHALL be created at `{working_dir}/.opencode/agents/orc-{role}.md`

#### Scenario: Project orchestrator session receives persona injection
- **WHEN** `orc <project>` starts a project orchestrator session
- **THEN** `_adapter_inject_persona` SHALL be called with `working_dir` set to the project worktree directory
- **AND** the agent file SHALL be created at `{worktree}/.opencode/agents/orc-{role}.md`

#### Scenario: Goal orchestrator session receives persona injection
- **WHEN** `orc spawn-goal <project> <goal>` starts a goal orchestrator session
- **THEN** `_adapter_inject_persona` SHALL be called with `working_dir` set to the goal worktree directory
- **AND** the agent file SHALL be created at `{goal_worktree}/.opencode/agents/orc-{role}.md`

#### Scenario: Engineer session continues to work (no regression)
- **WHEN** `orc spawn <project> <bead>` spawns an engineer via `_tmux_split_with_agent`
- **THEN** persona injection SHALL work as before (this path already passes `working_dir`)
- **AND** no behavioral change SHALL occur for engineer sessions

#### Scenario: Legacy engineer window session receives persona injection
- **WHEN** `orc spawn <project> <bead>` spawns an engineer in its own window (legacy path via `_launch_agent_in_window`)
- **THEN** `_adapter_inject_persona` SHALL be called with `working_dir` set to the engineer's worktree directory

### Requirement: Orc slash commands must be available in worktree sessions

The opencode adapter SHALL install orc slash commands (`orc-*.md` symlinks) into each worktree's `.opencode/commands/` directory during persona injection. opencode loads commands from `.opencode/commands/` relative to CWD and does not fall through to `~/.config/opencode/commands/` when a local commands directory exists.

#### Scenario: orchestrator in worktree can use orc slash commands
- **WHEN** an orchestrator agent runs in a worktree at `project/.worktrees/.project-orch`
- **THEN** the worktree SHALL have `.opencode/commands/orc-plan.md`, `.opencode/commands/orc-dispatch.md`, and all other orc command symlinks
- **AND** the agent SHALL be able to use `/orc:plan`, `/orc:dispatch`, etc.

#### Scenario: commands are cleaned up on teardown
- **WHEN** `_adapter_post_teardown` is called for a worktree
- **THEN** orc command symlinks SHALL be removed from `{worktree}/.opencode/commands/orc-*.md`

### Requirement: Init-Time CLI Selection

When `orc init` detects **two or more** installed agent CLIs and `config.local.toml` does not already have an explicit (uncommented) `agent_cmd` value, the system SHALL present a numbered list and prompt the user to choose their preferred CLI.

The selected CLI SHALL be written as an uncommented `agent_cmd = "<choice>"` under `[defaults]` in `config.local.toml`, making the preference durable across all future sessions.

When `config.local.toml` already has an explicit `agent_cmd`, the prompt SHALL be skipped entirely.

When only one CLI is detected, it SHALL be written to `config.local.toml` without prompting.

#### Scenario: Multiple CLIs detected during init
- **WHEN** the user runs `orc init`
- **AND** `claude`, `codex`, and `gemini` are all found on PATH
- **AND** `config.local.toml` has `agent_cmd` commented out or set to `"auto"`
- **THEN** the system displays:
  ```
  Multiple agent CLIs detected:
    1) claude
    2) codex
    3) gemini
  Choose your default CLI [1-3]:
  ```
- **AND** writes the selection to `config.local.toml` as `agent_cmd = "<choice>"`
- **AND** the prerequisites check shows the selected CLI

#### Scenario: Explicit agent_cmd already configured
- **WHEN** the user runs `orc init`
- **AND** `config.local.toml` already has `agent_cmd = "codex"` (uncommented)
- **THEN** the system does not prompt for CLI selection
- **AND** the prerequisites check shows `codex`

#### Scenario: Single CLI detected during init
- **WHEN** the user runs `orc init`
- **AND** only `claude` is found on PATH
- **THEN** the system does not prompt
- **AND** writes `agent_cmd = "claude"` to `config.local.toml`

#### Scenario: Re-running init preserves existing choice
- **WHEN** the user previously chose `codex` via `orc init`
- **AND** they run `orc init` again
- **THEN** the system sees the explicit `agent_cmd = "codex"` and skips the prompt

### Requirement: Transparent Multi-CLI Runtime Logging

When `defaults.agent_cmd` is `"auto"` and auto-detection finds **two or more** CLIs at runtime, the system SHALL log both the selected CLI and the alternatives that were found, once per session.

The log SHALL also include a one-time hint directing the user to set `defaults.agent_cmd` in `config.local.toml`.

When only one CLI is found, the existing log format (`"Auto-detected agent CLI: <name>"`) SHALL be preserved.

When the user has set an explicit `agent_cmd` (not `"auto"`), no auto-detection logging SHALL occur.

#### Scenario: Multiple CLIs found at runtime with auto mode
- **WHEN** `defaults.agent_cmd` is `"auto"`
- **AND** `claude` and `codex` are both found on PATH
- **THEN** the system logs once per session:
  ```
  [orc] Using claude (also found: codex)
  [orc] Tip: Set defaults.agent_cmd in config.local.toml to change
  ```

#### Scenario: Single CLI found at runtime
- **WHEN** `defaults.agent_cmd` is `"auto"`
- **AND** only `claude` is found on PATH
- **THEN** the system logs: `"Auto-detected agent CLI: claude"`
- **AND** no tip is shown

#### Scenario: Explicit agent_cmd skips logging
- **WHEN** `defaults.agent_cmd` is `"codex"` (not `"auto"`)
- **THEN** no auto-detection logging occurs

#### Scenario: Spawned sub-processes do not re-log
- **WHEN** the hint has already been logged in this session (per-PID flag file exists)
- **AND** `_resolve_agent_cmd` is called again (e.g., by `orc spawn`)
- **THEN** no duplicate log or hint is emitted

### Requirement: Doctor Advisory for Ambiguous Auto-Detection

`orc doctor` SHALL check whether `defaults.agent_cmd` is `"auto"` and multiple agent CLIs are installed. If so, it SHALL report an **informational** advisory (not an error) recommending the user set an explicit preference.

The advisory SHALL list the detected CLIs and show the exact config line to add.

#### Scenario: Multiple CLIs with auto mode
- **WHEN** `orc doctor` runs
- **AND** `defaults.agent_cmd` is `"auto"`
- **AND** `claude`, `codex`, and `gemini` are all found on PATH
- **THEN** the doctor reports:
  ```
  Info: Multiple agent CLIs found (claude, codex, gemini) but agent_cmd is "auto".
        Currently using: claude (first in priority order).
        To choose explicitly, set in config.local.toml:
          [defaults]
          agent_cmd = "codex"   # or claude, gemini
  ```

#### Scenario: Explicit agent_cmd set
- **WHEN** `orc doctor` runs
- **AND** `defaults.agent_cmd` is `"codex"`
- **THEN** no advisory about CLI selection is reported

#### Scenario: Single CLI with auto mode
- **WHEN** `orc doctor` runs
- **AND** `defaults.agent_cmd` is `"auto"`
- **AND** only `claude` is found on PATH
- **THEN** no advisory is reported (no ambiguity)

