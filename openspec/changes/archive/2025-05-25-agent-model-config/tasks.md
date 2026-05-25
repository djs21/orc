## 1. Config schema — add `[models]` section to config.toml

- [x] 1.1 Add commented `[models]` section to `config.toml` with example entries for each role (orchestrator, goal-orchestrator, engineer, reviewer)
- [x] 1.2 Verify `_config_get "models.engineer"` returns the configured value from config.toml

## 2. Model injection in opencode adapter

- [x] 2.1 In `_adapter_inject_persona` (`packages/cli/lib/adapters/opencode.sh`), read `_config_get "models.${role}"` after building the permission block
- [x] 2.2 If model is non-empty, inject `model: <value>` line into the YAML front-matter between `mode` and `permission`
- [x] 2.3 If model is empty (config not set), do NOT include a `model` field — ensure backward compatibility

## 3. Smoke tests

- [ ] 3.1 Add `[models]` config to `config.local.toml` with test model IDs and verify generated agent files at `.opencode/agents/orc-*.md` contain the correct `model:` field
- [ ] 3.2 Remove `[models]` config and verify agent files are generated without `model:` field (no regression)
- [ ] 3.3 Verify per-project override: set different model in project's `.orc/config.toml` and confirm it takes precedence over global config
