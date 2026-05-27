# Issue tracker: Beads (`bd`)

Issues for this repo live in a local Dolt database managed by Beads. Use the `bd` CLI for all operations. Sync pushes to `refs/dolt/data` on the git remote.

## Conventions

- **Create an issue**: `bd new --title "..." --body "..."`
- **Read an issue**: `bd show <id>`
- **List open issues**: `bd ready` (lists available work)
- **Claim an issue**: `bd update <id> --claim`
- **Close an issue**: `bd close <id>`
- **Full reference**: `bd prime`
- **Persistent knowledge**: `bd remember`

Issue data is exported passively to `.beads/issues.jsonl`, but always read/write through the `bd` CLI — never edit the JSONL directly.

## When a skill says "publish to the issue tracker"

Create a Beads issue via `bd new`.

## When a skill says "fetch the relevant ticket"

Run `bd show <id>`.

## When a skill says "apply / remove labels"

Beads uses tags. Apply with `bd update <id> --tag <tag>`, remove with `bd update <id> --remove-tag <tag>`. Map triage role names (see `docs/agents/triage-labels.md`) to tag strings.
