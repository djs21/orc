## Context

OpenCode agents created by orc use a YAML front-matter block in `.opencode/agents/orc-{role}.md` files. Currently this block includes `description`, `mode`, and `permission` fields. The `model` field is not included — opencode falls back to its globally configured model for all agents.

The orc lifecycle uses four agent roles across a three-tier hierarchy:
- **orchestrator** (root & project) — planning, coordination, monitoring
- **goal-orchestrator** — bead decomposition, engineer dispatch, review loop
- **engineer** — autonomous coding in isolated worktrees
- **reviewer** — ephemeral code review sessions

Each role has different model requirements (planning needs reasoning depth, coding needs speed, review needs precision). The opencode agent system supports per-agent `model` configuration in its markdown front-matter, making this a configuration concern rather than a code change.

## Goals / Non-Goals

**Goals:**
- Add `[models]` TOML config section mapping role → `provider/model-id`
- Inject `model:` field into opencode agent YAML front-matter when configured
- Follow existing config resolution chain (project `.orc/config.toml` → `config.local.toml` → `config.toml`)
- Default to no-op: if `[models]` is not configured, agent files are generated exactly as before

**Non-Goals:**
- Per-session runtime model switching (open in one model, switch later)
- Model selection for non-opencode adapters (claude, codex, gemini)
- Adding other model parameters (`temperature`, `top_p`) — can be added later using the same pattern
- GUI or TUI for model selection — this is a config-file-only feature

## Decisions

### Decision 1: Config schema — flat `[models]` section

**Choice**: Use a flat `[models]` section with role names as keys:

```toml
[models]
orchestrator = "opencode-go/glm-5.1"
goal-orchestrator = "opencode-go/deepseek-v4-pro"
engineer = "opencode-go/deepseek-v4-flash"
```

**Rationale**: Simple, matches the existing orc config pattern (flat `[defaults]`, `[approval]` sections). No need for nested structures since each role gets one model.

**Alternative considered**: Nested `[models.<role>]` sections with sub-fields. Rejected for now — only one field (model) is needed per role. Can be extended to nested if other model parameters are added later.

### Decision 2: Config resolution — reuse existing chain

**Choice**: Use `_config_get "models.${role}"` which reads from the existing three-layer chain: project `.orc/config.toml` → `config.local.toml` → `config.toml`.

**Rationale**: No new config parsing logic needed. Each project can override models via its `.orc/config.toml`, and user can override globally via `config.local.toml`.

### Decision 3: Default schema in `config.toml`

**Choice**: Add the `[models]` section to the committed `config.toml` as a default/example:

```toml
[models]
# Uncomment to assign specific models to agent roles.
# Format: provider/model-id (use opencode models to list available models)
# orchestrator = "opencode-go/glm-5.1"
# goal-orchestrator = "opencode-go/deepseek-v4-pro"
# engineer = "opencode-go/deepseek-v4-flash"
```

**Rationale**: The `config.toml` serves as documentation and defaults. Commented examples show users what's possible without forcing a model choice.

### Decision 4: Model injection placement in YAML front-matter

**Choice**: Place the `model` field after `mode` and before `permission`:

```yaml
---
description: "orc engineer agent"
mode: primary
model: opencode-go/deepseek-v4-flash
permission:
  edit: ask
  bash: ask
  ...
---
```

**Rationale**: Follows the opencode convention seen in their documentation examples. Position has no functional significance — YAML front-matter field order is cosmetic.

### Decision 5: Adapter-scoped injection

**Choice**: Only the opencode adapter injects the `model` field. Other adapters ignore the `[models]` config.

**Rationale**: The `model` field is specific to opencode's agent YAML front-matter format. Claude Code, Gemini CLI, and Codex use different mechanisms for model selection (CLI flags, separate config files). Adding model injection to other adapters would require adapter-specific logic not in scope for this change.

### Decision 6: Empty config = no-op

**Choice**: When `_config_get "models.${role}"` returns an empty string (config not set), do NOT inject a `model` field. The generated agent file is identical to what it was before this change.

**Rationale**: Backward compatibility. Users who don't care about per-role models see zero behavioral change. opencode's default behavior (global model) applies.

## Risks / Trade-offs

- **[Risk] Invalid model ID causes agent launch failure** → Mitigation: The model ID is passed through to opencode unchanged. opencode validates it at agent launch time. If invalid, opencode will report a clear error. Users should verify model IDs with `opencode models` before configuring them.

- **[Risk] Model ID format changes in future opencode versions** → Mitigation: The format (`provider/model-id`) is opencode's documented convention. If it changes, users update their TOML config — no code change needed.

- **[Trade-off] Model switching requires agent restart** → This is inherent to opencode's architecture. The model is set at agent launch time via the agent file and cannot be changed during a session. Acceptable for orc's use case where agents are spawned per-bead/goal/project.

## Open Questions

_None_
