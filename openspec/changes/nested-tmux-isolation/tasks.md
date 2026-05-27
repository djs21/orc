## 1. Extract Static tmux Config

- [x] 1.1 Create `packages/cli/lib/orc-tmux.conf` with all static tmux options extracted from `_common.sh:_tmux_ensure_session()`: `default-terminal`, server options (`set-option -s`), session options (`set-option -g`), window options (`set-option -wg`), key bindings (`bind-key`), and theme definitions
- [x] 1.2 Verify `orc-tmux.conf` is complete by diffing against the inline `set-option`/`bind-key` calls in `_tmux_ensure_session()` — every static setting must be accounted for
- [x] 1.3 Smoke test: `tmux -L orc-test -f packages/cli/lib/orc-tmux.conf new-session -d -s test && tmux -L orc-test kill-server` — confirm config loads without errors

## 2. Introduce Socket Constants and Wrapper

- [x] 2.1 Add `readonly ORC_TMUX_SOCKET="orc"` constant in `_common.sh` alongside the existing `ORC_TMUX_SESSION="orc"`
- [x] 2.2 Add `_orc_tmux()` wrapper function in `_common.sh` that calls `tmux -L "${ORC_TMUX_SOCKET}" "$@"`
- [x] 2.3 Add `_tmux_conf_path()` helper that resolves to `${_ORC_ROOT}/lib/orc-tmux.conf`

## 3. Refactor `_tmux_ensure_session()`

- [x] 3.1 Rewrite `_tmux_ensure_session()` to: (a) check if orc server exists via `_orc_tmux has-session -t "$ORC_TMUX_SESSION"`, (b) if not, create via `_orc_tmux -f "$(_tmux_conf_path)" new-session -d -s "$ORC_TMUX_SESSION" -n _orc_init`, (c) if yes, clean up stale `_orc_init` window
- [x] 3.2 Remove all inline `set-option -s`, `set-option -g`, `set-option -wg`, and `bind-key` calls from `_tmux_ensure_session()` — these are now in `orc-tmux.conf`
- [x] 3.3 Remove the `ORC_TMUX_NEEDS_CLEANUP` conditional logic for applying options only on first start — the config file handles this via `-f` on creation
- [x] 3.4 Keep only dynamic logic in `_tmux_ensure_session()`: session existence check, `_orc_init` cleanup, and environment propagation (`ORC_YOLO`)
- [x] 3.5 Smoke test: `_tmux_ensure_session` creates the orc server with correct config, and subsequent calls skip creation

## 4. Replace All Bare `tmux` Calls

- [x] 4.1 Replace all bare `tmux` calls in `_common.sh` with `_orc_tmux` (except the config-file load in `_tmux_ensure_session`)
- [x] 4.2 Replace all bare `tmux` calls in `start.sh` with `_orc_tmux`
- [x] 4.3 Replace all bare `tmux` calls in `spawn-goal.sh` with `_orc_tmux`
- [x] 4.4 Replace all bare `tmux` calls in `spawn.sh` with `_orc_tmux`
- [x] 4.5 Replace all bare `tmux` calls in `review.sh` with `_orc_tmux`
- [x] 4.6 Replace all bare `tmux` calls in `board.sh` with `_orc_tmux`
- [x] 4.7 Replace all bare `tmux` calls in `teardown.sh` with `_orc_tmux`
- [x] 4.8 Replace all bare `tmux` calls in `halt.sh` with `_orc_tmux`
- [x] 4.9 Replace all bare `tmux` calls in `leave.sh` with `_orc_tmux`
- [x] 4.10 Replace all bare `tmux` calls in `bin/orc` with `_orc_tmux`
- [x] 4.11 Replace all bare `tmux` calls in any other `lib/*.sh` files with `_orc_tmux`
- [x] 4.12 Verify no bare `tmux` calls remain for session management: `grep -rn 'tmux' packages/cli/ --include='*.sh' | grep -v '_orc_tmux' | grep -v 'orc-tmux.conf' | grep -v '# '` — only legitimate exceptions should remain

## 5. Update `_orc_goto()` for Nested Attach

- [x] 5.1 Rewrite `_orc_goto()` to detect whether `$TMUX` points to the orc socket or a different one
- [x] 5.2 If inside orc's tmux (`$TMUX` contains the orc socket path): use `_orc_tmux switch-client -t "$ORC_TMUX_SESSION:$target"` (navigate within the orc server)
- [x] 5.3 If inside another tmux (user's tmux): use `_orc_tmux attach` (nested attach in current pane)
- [x] 5.4 If not inside any tmux: use `_orc_tmux attach` (direct attach)
- [x] 5.5 Update `leave.sh` to use `_orc_tmux detach-client` instead of bare `tmux detach-client`
- [x] 5.6 Smoke test: from bare terminal → `orc start myapp` attaches to orc tmux. From within user tmux → nested attach works. From within orc tmux → `orc goto myapp` switches windows correctly.

## 6. Update Keybinding and Theme Application

- [x] 6.1 Verify that all keybindings in `orc-tmux.conf` are scoped to the orc server (they will be, since the config file is loaded only on the orc server — no `-g` flag needed, `bind-key` in a config file applies to the server it's loaded on)
- [x] 6.2 Verify that `_tmux_apply_goal_layout()` and other dynamic layout functions use `_orc_tmux` instead of bare `tmux`
- [x] 6.3 Verify that the `[keybindings]` config section in `config.toml` is still applied correctly — keybindings should be applied within the orc server via `_orc_tmux bind-key`, not to the default server

## 7. Update Teardown and Cleanup

- [x] 7.1 Update `teardown.sh` to use `_orc_tmux kill-session -t orc` instead of `tmux kill-session -t orc` (session kill, not server kill)
- [x] 7.2 Add `orc doctor` check for orphaned `orc` sessions on the default tmux server: warn if `tmux has-session -t orc 2>/dev/null` succeeds (meaning a session named `orc` exists on the user's default server, likely from a pre-migration installation)
- [x] 7.3 Smoke test: `orc teardown all` kills the `orc` session but leaves the `orc` server running. `tmux -L orc kill-server` kills the server entirely.

## 8. Update Environment Propagation

- [x] 8.1 Update `_tmux_ensure_session()` to propagate environment variables to the orc server using `_orc_tmux set-environment -t "$ORC_TMUX_SESSION"` instead of bare `tmux set-environment`
- [x] 8.2 Verify that `ORC_YOLO` propagation still works: `_orc_tmux set-environment -t "$ORC_TMUX_SESSION" ORC_YOLO 1`
- [x] 8.3 Verify that `bin/orc` reads `ORC_YOLO` from the orc tmux environment correctly when inside the orc server

## 9. Update Documentation and Config Example

- [x] 9.1 Update `CLAUDE.md` tmux architecture section to reflect socket isolation (`-L orc`, `_orc_tmux`, nested tmux)
- [x] 9.2 Update `docs/configuration.md` to document the `ORC_TMUX_SOCKET` constant and socket isolation approach
- [x] 9.3 Update `docs/config.toml.example` to add any new tmux-related config options (if applicable)
- [x] 9.4 Add migration note to `migrations/CHANGELOG.md`: orphaned `orc` sessions on default server should be cleaned up with `tmux kill-session -t orc`
- [x] 9.5 Update `packages/personas/root-orchestrator.md` to reference the orc server (nested tmux) vs. user's tmux

## 10. Integration Testing

- [x] 10.1 Test matrix: `orc start` from bare terminal → attaches correctly. `orc start` from user tmux → nested attach. `orc start` from within orc tmux → switch-client
- [x] 10.2 Test: `orc spawn-goal` creates windows in the orc server (verify with `_orc_tmux list-windows`)
- [x] 10.3 Test: `orc teardown all` kills the session but not the server. Verify with `tmux -L orc list-sessions`
- [x] 10.4 Test: User's tmux settings are unchanged after `orc start`. Compare `tmux show-options -s` before and after.
- [x] 10.5 Test: `orc doctor` warns about orphaned `orc` sessions on the default server