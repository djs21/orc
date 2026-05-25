## 1. Fix opencode adapter `-q` flag

- [x] 1.1 In `packages/cli/lib/adapters/opencode.sh`, remove `-q` from `_adapter_build_launch_cmd`: change `cmd="$cmd run --agent orc-${role} -q \"\$(cat $prompt_file)\""` to `cmd="$cmd run --agent orc-${role} \"\$(cat $prompt_file)\""`
- [x] 1.2 Smoke test: verify `opencode run --agent build "$(echo 'Begin.')"` starts without printing help (should open TUI or process the message)

## 2. Extend `_launch_agent_in_window` signature

- [x] 2.1 In `packages/cli/lib/_common.sh`, update `_launch_agent_in_window` to accept optional `role` ($5) and `working_dir` ($6) parameters, forwarding both to `_build_and_launch`
- [x] 2.2 Verify `_launch_agent_in_review_pane` still works (no signature change needed — it already passes `role` and `working_dir` directly)

## 3. Update all `_launch_agent_in_window` call sites with `role` and `working_dir`

- [x] 3.1 `packages/cli/lib/start.sh` root orchestrator (lines 62, 83, 85): add `"orchestrator"` as role and `"$ORC_ROOT"` as working_dir
- [x] 3.2 `packages/cli/lib/start.sh` project orchestrator (line 142): add `"orchestrator"` as role and `"$proj_worktree"` as working_dir
- [x] 3.3 `packages/cli/lib/spawn-goal.sh` goal orchestrator (line 120): add `"goal-orchestrator"` as role and `"$goal_worktree"` as working_dir
- [x] 3.4 `packages/cli/lib/spawn.sh` legacy engineer (line 105): add `"engineer"` as role and `"$worktree"` as working_dir
- [x] 3.5 `packages/cli/lib/setup.sh` project setup (line 195): add `"orchestrator"` as role and `"$proj_worktree"` as working_dir
- [x] 3.6 `packages/cli/lib/doctor.sh` doctor session (line 564): add `"orchestrator"` as role and `"$ORC_ROOT"` as working_dir

## 4. Fix launch mode and permissions

- [x] 4.1 In `_adapter_build_launch_cmd`, use `opencode run` only for `engineer` role; all other roles use `opencode --agent` (TUI mode)
- [x] 4.2 In `_adapter_inject_persona`, add `external_directory: allow` to both yolo and normal permission blocks

## 5. Install orc slash commands into worktrees

- [x] 5.1 In `_adapter_inject_persona`, after creating the agent file, also symlink orc commands to `{worktree}/.opencode/commands/orc-*.md` (same pattern as `_adapter_install_commands` but targeting the worktree path)
- [x] 5.2 In `_adapter_post_teardown`, also remove orc command symlinks from `{worktree}/.opencode/commands/orc-*.md`
- [x] 5.3 Verify orchestrator in worktree can see `/orc:plan`, `/orc:dispatch`, etc. in opencode

## 6. Verify and smoke test

- [ ] 6.1 Run `orc` (root orchestrator) and verify opencode opens in TUI mode with the `orc-orchestrator` agent loaded and orc slash commands available
- [ ] 6.2 Run `orc <project>` (project orchestrator) and verify opencode opens in TUI mode with `orc-orchestrator` agent, commands available, and `external_directory` access working
- [ ] 6.3 Run `orc spawn-goal <project> <goal>` and verify goal orchestrator gets `orc-goal-orchestrator` agent with commands
- [ ] 6.4 Verify engineer spawn (`orc spawn`) still works correctly with `orc-engineer` agent in `opencode run` mode (regression check)
