## Why

The opencode adapter is broken: every orchestrator launch shows the opencode `--help` page instead of starting the agent. Three independent bugs cause this: (1) the adapter uses a `-q` flag that no longer exists in opencode CLI, causing opencode to reject the command and print help; (2) persona injection is skipped for all orchestrator sessions because `_launch_agent_in_window` never passes `working_dir` to `_build_and_launch`, so the `orc-{role}` agent files are never created; (3) orc slash commands (`/orc:plan`, `/orc:dispatch`, etc.) are not available inside worktree sessions because opencode loads commands from `.opencode/commands/` relative to CWD, and worktrees lack these symlinks — the global install at `~/.config/opencode/commands/` is insufficient.

Additionally, two design issues were discovered during implementation: (a) the adapter used `opencode run` (non-interactive) for all sessions with a prompt file, but orchestrators need TUI mode with the initial prompt embedded in the persona; (b) the permission block was missing `external_directory: allow`, causing orchestrator access to project roots to be auto-rejected.

## What Changes

- Remove the invalid `-q` flag from `_adapter_build_launch_cmd` in the opencode adapter — messages should be passed as positional arguments to `opencode run`
- Fix `_launch_agent_in_window` to pass `working_dir` and `role` to `_build_and_launch` so persona injection runs for all session types
- Change orchestrator sessions to use TUI mode (`opencode --agent`) instead of non-interactive `opencode run` — initial prompts are already in the persona
- Add `external_directory: allow` to the opencode agent permission block so orchestrators can access project root directories from their worktree
- Install orc slash commands into each worktree's `.opencode/commands/` during persona injection so they are available to agents running in worktrees

## Capabilities

### New Capabilities

_None_

### Modified Capabilities

- `cli-resolution`: Adapter launch commands must produce valid CLI invocations; persona injection must work for all session types; slash commands must be available in worktree sessions; orchestrators must launch in TUI mode

## Impact

- **packages/cli/lib/adapters/opencode.sh**: Remove `-q` flag, add `external_directory` permission, use TUI mode for orchestrators, install commands to worktree
- **packages/cli/lib/start.sh**: Pass `working_dir` and `role` to `_build_and_launch` via `_launch_agent_in_window`
- **packages/cli/lib/_common.sh**: Signature change to accept and forward `working_dir` and `role`
- All three tiers affected: root orchestrator, project orchestrator, and engineer sessions
- No breaking changes to user-facing config or API — this is a bugfix
