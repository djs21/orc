## MODIFIED Requirements

### Requirement: Keybinding Configuration

The system SHALL support a `[keybindings]` config section with the following fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Master toggle for prefix-free Alt+ keybindings |
| `project` | string | `"M-0"` | Jump to project orchestrator |
| `dashboard` | string | `"M-s"` | Jump to status dashboard |
| `prev` | string | `"M-["` | Previous window |
| `next` | string | `"M-]"` | Next window |
| `palette` | string | `"M-p"` | Open command palette |
| `menu` | string | `"M-m"` | Open context menu |
| `help` | string | `"M-?"` | Toggle help overlay |

Field names map to orc's hierarchy (`project`, `dashboard`) rather than generic tmux concepts, making them self-documenting in `config.toml`.

When `enabled` is `false`, no orc-specific keybindings SHALL be registered beyond `Prefix + Space` (palette), `Prefix + m` (context menu), and `Prefix + ?` (help), which are controlled by their respective feature toggles.

Setting any key field to `""` (empty string) SHALL disable that specific binding without affecting others.

Keys SHALL use tmux key notation (e.g., `M-` for Alt/Option, `C-` for Ctrl).

All keybindings SHALL be scoped to the orc tmux server (via `-L orc`). They SHALL NOT be applied to the user's default tmux server.

#### Scenario: Keybindings disabled by default
- **GIVEN** a fresh orc installation with default config
- **WHEN** the user starts an orc session
- **THEN** only `Prefix + Space`, `Prefix + m`, and `Prefix + ?` are bound in the orc tmux server
- **AND** no `Alt+` keybindings are registered in the orc tmux server
- **AND** no keybindings of any kind are registered in the user's default tmux server

#### Scenario: Keybindings enabled
- **GIVEN** the user sets `keybindings.enabled = true` in config
- **WHEN** the user starts an orc session
- **THEN** all non-empty `Alt+` keybindings are registered in the orc tmux server only
- **AND** the keybindings do NOT appear in the user's default tmux server
- **AND** the user's own tmux keybindings remain unchanged

#### Scenario: Individual key override
- **GIVEN** the user sets `keybindings.prev = "M-h"` and `keybindings.next = "M-l"`
- **WHEN** the orc session initializes
- **THEN** `Alt+h` switches to previous window and `Alt+l` switches to next window in the orc server
- **AND** the default `Alt+[` and `Alt+]` bindings are NOT registered in the orc server
- **AND** no bindings are registered in the user's default tmux server

#### Scenario: Individual key disabled
- **GIVEN** the user sets `keybindings.project = ""`
- **WHEN** the orc session initializes
- **THEN** no binding is registered for the "project" action in the orc server
- **AND** all other keybindings are registered normally in the orc server