## ADDED Requirements

### Requirement: Socket-Isolated tmux Server

The system SHALL run orc's tmux session in a dedicated tmux server accessed via the `-L orc` socket flag. All tmux commands SHALL target this socket exclusively through the `_orc_tmux()` wrapper function.

The system SHALL define two constants:
- `ORC_TMUX_SOCKET="orc"` — the socket name passed to `tmux -L`
- `ORC_TMUX_SESSION="orc"` — the session name within the orc server

No bare `tmux` command SHALL be used anywhere in the CLI for session management. All calls SHALL go through `_orc_tmux()`, which injects `-L "${ORC_TMUX_SOCKET}"` before every tmux invocation.

#### Scenario: First start creates isolated server
- **GIVEN** no `orc` tmux server is running
- **WHEN** the user runs `orc start myapp`
- **THEN** a new tmux server is created via `tmux -L orc -f orc-tmux.conf new-session -d -s orc`
- **AND** the server's socket file is at `/tmp/tmux-$UID/orc`
- **AND** no tmux options, keybindings, or theme are applied to the user's default tmux server

#### Scenario: Subsequent commands reuse existing server
- **GIVEN** the `orc` tmux server is already running
- **WHEN** the user runs `orc spawn-goal myapp auth`
- **THEN** the command targets the existing `orc` server via `_orc_tmux`
- **AND** no new server is created

#### Scenario: User's tmux remains unaffected
- **GIVEN** the user has their own tmux session running on the default server
- **WHEN** the user starts an orc project
- **THEN** no server-level options, keybindings, theme, or environment variables from orc appear in the user's tmux server
- **AND** the user can `tmux list-sessions` on their default server without seeing `orc`

### Requirement: Static tmux Configuration File

The system SHALL extract all static tmux configuration (options, theme, keybindings) from `_common.sh:_tmux_ensure_session()` into a dedicated file at `packages/cli/lib/orc-tmux.conf`.

The file SHALL be loaded once during server initialization via `tmux -L orc -f "${_ORC_ROOT}/lib/orc-tmux.conf" new-session -d -s orc`.

After initialization, dynamic session management (window creation, pane splitting, cleanup) SHALL remain in shell scripts using `_orc_tmux` calls.

The configuration file SHALL include:
- `default-terminal "screen-256color"`
- All server options currently set via `set-option -s` in `_tmux_ensure_session()`
- All session options currently set via `set-option -g`
- All window options currently set via `set-option -wg`
- All key bindings currently set via `bind-key`
- All theme definitions (status bar, colors, borders)

#### Scenario: Config file loaded on first start
- **GIVEN** no `orc` server exists
- **WHEN** `_tmux_ensure_session()` is called
- **THEN** the orc server is initialized with `tmux -L orc -f "${_ORC_ROOT}/lib/orc-tmux.conf" new-session -d -s orc -n _orc_init`
- **AND** all theme, option, and keybinding settings from the file are applied

#### Scenario: Config file not re-loaded on subsequent starts
- **GIVEN** an `orc` server is already running
- **WHEN** `_tmux_ensure_session()` is called
- **THEN** the config file is NOT re-loaded (the server already has the config)
- **AND** only dynamic session management (cleanup `_orc_init`, check windows) runs

#### Scenario: Config file path resolution
- **GIVEN** orc is installed at `_ORC_ROOT`
- **WHEN** `_tmux_ensure_session()` needs the config file
- **THEN** it resolves the path as `"${_ORC_ROOT}/lib/orc-tmux.conf"`
- **AND** this works in both development (source tree) and installed (package manager) environments

### Requirement: Nested tmux Attach

The system SHALL support attaching to the orc tmux server from any environment: bare terminal, user's tmux, or already inside orc's tmux.

When the user runs `orc start`, `orc goto`, or `orc board`, the system SHALL:
1. Ensure the orc server exists (via `_tmux_ensure_session()`)
2. Attach via `_orc_tmux attach` in the current pane

If the user is inside another tmux (detected via `$TMUX` pointing to a non-orc socket), the attach creates a nested tmux session. The user can detach from the inner tmux with `Ctrl-b d` (orc's prefix) to return to their outer tmux.

If the user is in a bare terminal, the attach replaces the terminal with the orc tmux session.

#### Scenario: Attach from bare terminal
- **GIVEN** the user is in a terminal with no tmux running
- **WHEN** the user runs `orc start myapp`
- **THEN** `_orc_tmux attach` replaces the terminal with the orc tmux session
- **AND** the user can detach with `Ctrl-b d` to return to the bare terminal

#### Scenario: Attach from user's tmux (nested)
- **GIVEN** the user is inside their own tmux session
- **WHEN** the user runs `orc start myapp`
- **THEN** `_orc_tmux attach` opens orc's tmux inside the current pane (nested)
- **AND** `Ctrl-b d` detaches from orc's tmux, returning to the user's tmux
- **AND** the user's tmux keybindings and theme are unaffected

#### Scenario: Already inside orc's tmux
- **GIVEN** the user is inside the orc tmux server
- **WHEN** the user runs `orc goto myapp`
- **THEN** the system navigates to the target window without creating a nested session
- **AND** the system detects `$TMUX` points to the orc socket and switches windows directly

### Requirement: tmux Command Wrapper

The system SHALL provide an `_orc_tmux()` shell function in `_common.sh` that wraps all tmux invocations:

```bash
_orc_tmux() {
    tmux -L "${ORC_TMUX_SOCKET}" "$@"
}
```

Every shell script in `packages/cli/lib/` and `packages/cli/bin/` that calls `tmux` SHALL use `_orc_tmux` instead of bare `tmux`. The only exception is the config-file load command `tmux -L orc -f orc-tmux.conf new-session`, which is handled directly in `_tmux_ensure_session()`.

#### Scenario: All tmux calls go through wrapper
- **GIVEN** the orc CLI codebase
- **WHEN** searching for `tmux` command invocations across all shell scripts
- **THEN** no bare `tmux` calls exist for session/window/pane management
- **AND** all calls use `_orc_tmux` or the direct config-file load in `_tmux_ensure_session()`

#### Scenario: Wrapper targets correct socket
- **GIVEN** `ORC_TMUX_SOCKET="orc"`
- **WHEN** `_orc_tmux list-sessions` is called
- **THEN** the command executed is `tmux -L orc list-sessions`
- **AND** only sessions on the `orc` socket are listed

### Requirement: Teardown Session Kill

The system SHALL kill the `orc` session within the `-L orc` server when teardown is requested, but SHALL NOT kill the server itself.

`orc teardown all` SHALL run `_orc_tmux kill-session -t orc`, leaving the server process running. Users can manually kill the entire server with `tmux -L orc kill-server` if needed.

#### Scenario: Teardown all kills session
- **GIVEN** an `orc` session is running on the `orc` server
- **WHEN** `orc teardown all` is run
- **THEN** the `orc` session is killed via `_orc_tmux kill-session -t orc`
- **AND** the `orc` tmux server process remains running

#### Scenario: Doctor warns about orphaned session
- **GIVEN** an `orc` session exists on the default tmux server (pre-migration)
- **WHEN** the user runs `orc doctor`
- **THEN** doctor emits a warning: "Found orphaned 'orc' session on default tmux server. Run 'tmux kill-session -t orc' to remove it."