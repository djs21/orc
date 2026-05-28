## MODIFIED Requirements

### Requirement: Goal Orchestrator Worktree

The system SHALL create a dedicated git worktree for each goal orchestrator, isolating it from the project root and from other concurrent goal orchestrators.

The worktree SHALL:
- Be located at `{project}/.worktrees/goal-{goal-name}` (the `goal-` prefix distinguishes from bead worktrees)
- Be checked out to the goal branch (e.g., `feat/WEN-886-booking-flow-name-decoupling`)
- Serve as the working directory for the goal orchestrator's tmux window
- Be the working directory for all sub-agents spawned by the goal orchestrator (planner, scouts)

The project root SHALL remain on its current branch (typically `main`) and SHALL NOT be modified by any orc goal orchestrator or sub-agent.

The goal orchestrator's tmux window SHALL be created inside the orc tmux server (via `_orc_tmux new-window`), NOT on the default tmux server.

#### Scenario: Goal orchestrator spawned in isolated worktree
- **WHEN** `orc spawn-goal myapp WEN-886-booking-flow` is run
- **THEN** a git worktree is created at `.worktrees/goal-WEN-886-booking-flow`
- **AND** the worktree is checked out to the goal branch `feat/WEN-886-booking-flow`
- **AND** the tmux window `myapp/WEN-886-booking-flow` opens inside the orc server (via `_orc_tmux new-window`)
- **AND** the working directory is set to the worktree
- **AND** the project root remains on `main` with no uncommitted changes

#### Scenario: Multiple concurrent goal orchestrators
- **WHEN** three goals are dispatched concurrently
- **THEN** three separate worktrees are created: `goal-WEN-886-...`, `goal-WEN-885-...`, `goal-notification-mgmt`
- **AND** each goal orchestrator works in its own worktree
- **AND** changes in one worktree do not affect the others or the project root
- **AND** all three goal orchestrator windows are in the orc tmux server

#### Scenario: Planner sub-agent runs in goal worktree
- **WHEN** the goal orchestrator delegates plan creation to a planner sub-agent
- **THEN** the planner operates in the goal worktree, not the project root
- **AND** planning artifacts are created within the goal worktree