## Why

OpenCode agents created by orc all use the same global model, regardless of their role. An orchestrator planning goals needs a stronger model than an engineer writing boilerplate code. A reviewer examining code quality has different needs than a goal orchestrator managing bead dispatch. Without per-role model selection, orc users must accept a one-size-fits-all model or manually edit agent files after each spawn.

## What Changes

- Add `[models]` config section to orc's TOML config that maps role names to `provider/model-id` strings
- Inject the configured `model` field into the YAML front-matter of OpenCode agent files during persona injection
- All other adapters are unaffected (the `model` field is only injected when the config is set and only for the opencode adapter)
- Config resolution follows the existing chain: `.orc/config.toml` → `config.local.toml` → `config.toml`

## Capabilities

### New Capabilities

- `agent-model-config`: Per-role model selection in OpenCode agent configuration — each orc role (orchestrator, goal-orchestrator, engineer, reviewer) can use a different AI model without manual agent file edits.

### Modified Capabilities

- `cli-resolution`: The `_adapter_inject_persona` function in the opencode adapter now reads the `[models]` config section and injects the `model` field into the agent YAML front-matter when configured.

## Impact

- **packages/cli/lib/adapters/opencode.sh**: `_adapter_inject_persona` reads model config and includes `model:` in agent YAML front-matter when set
- **config.toml**: New optional `[models]` section with role-to-model mapping
- No breaking changes — when `[models]` is not configured, agent files are generated exactly as before
- All config layers support per-project override via `.orc/config.toml`
