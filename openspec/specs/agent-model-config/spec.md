# agent-model-config Specification

## Purpose
Defines how orc maps agent roles to AI models via the `[models]` TOML config section. Each role (orchestrator, goal-orchestrator, engineer, reviewer) can use a different model without manual agent file edits.

## Requirements

### Requirement: Per-role model selection via config

The system SHALL allow users to configure different AI models for different orc agent roles via a `[models]` section in the TOML configuration. The opencode adapter SHALL inject the configured model ID into the agent YAML front-matter when creating agent files.

Config keys SHALL be the role name (e.g., `orchestrator`, `goal-orchestrator`, `engineer`, `reviewer`) and values SHALL be model IDs in `provider/model-id` format.

#### Scenario: Model configured for a role
- **WHEN** `[models]` config has `engineer = "opencode-go/deepseek-v4-flash"`
- **AND** an engineer agent file is created via `_adapter_inject_persona`
- **THEN** the generated agent file SHALL include `model: opencode-go/deepseek-v4-flash` in its YAML front-matter

#### Scenario: No model configured for a role
- **WHEN** `[models]` config does not contain an entry for `engineer`
- **AND** an engineer agent file is created via `_adapter_inject_persona`
- **THEN** the generated agent file SHALL NOT contain a `model` field
- **AND** the generated file SHALL be identical to what was generated before this feature existed

#### Scenario: Entire [models] section absent
- **WHEN** no `[models]` section exists in any config layer
- **AND** any agent file is created
- **THEN** the generated agent file SHALL NOT contain a `model` field
- **AND** agent file generation SHALL be unchanged from prior behavior

#### Scenario: Multiple roles configured
- **WHEN** config contains:
  ```
  [models]
  orchestrator = "opencode-go/glm-5.1"
  goal-orchestrator = "opencode-go/deepseek-v4-pro"
  engineer = "opencode-go/deepseek-v4-flash"
  ```
- **AND** agent files are created for orchestrator, goal-orchestrator, and engineer roles
- **THEN** each agent file SHALL contain the `model` field with the corresponding model ID

### Requirement: Config resolution follows existing chain

Model configuration SHALL be resolved using the same config resolution chain as all other orc config: project `.orc/config.toml` → `config.local.toml` → `config.toml`. The first non-empty value wins.

#### Scenario: Project-level override
- **WHEN** `config.toml` has `engineer = "opencode-go/deepseek-v4-flash"`
- **AND** project's `.orc/config.toml` has `engineer = "opencode-go/claude-sonnet-4"`
- **THEN** the engineer agent SHALL use `opencode-go/claude-sonnet-4`

#### Scenario: User-level override via config.local.toml
- **WHEN** `config.toml` has `engineer = "opencode-go/deepseek-v4-flash"`
- **AND** `config.local.toml` has `engineer = "opencode-go/glm-5.1"`
- **THEN** the engineer agent SHALL use `opencode-go/glm-5.1`

### Requirement: Only opencode adapter injects model field

Model injection SHALL only be performed by the opencode adapter. Other adapters (claude, codex, gemini) SHALL ignore the `[models]` config section.

#### Scenario: Non-opencode adapter ignores model config
- **WHEN** the active adapter is claude, codex, or gemini
- **AND** `[models]` config is set
- **THEN** agent file generation SHALL be unchanged
- **AND** model selection SHALL follow the adapter's native mechanism
