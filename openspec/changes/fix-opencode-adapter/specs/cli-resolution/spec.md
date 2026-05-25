## MODIFIED Requirements

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

## ADDED Requirements

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
