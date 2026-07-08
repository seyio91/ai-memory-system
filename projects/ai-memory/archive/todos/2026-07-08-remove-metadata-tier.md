# Todo snapshot — ai-memory — 2026-07-08 (remove-metadata-tier)

> Rolled snapshot of completed work. See archive/plans/remove-metadata-tier.md. Landed via PR #39.

- [x] **Remove metadata.tier + write-boundary** — dropped tier field, validate check, --tier scaffolding, and the entire boundary apparatus (scripts + hooks + settings blocks); rely on execpolicy + Validator → [archive/plans/remove-metadata-tier.md](../plans/remove-metadata-tier.md)
  - [x] Phase 1 — strip tier from SKILL.md + validate-skills/new-skill/install-skill
  - [x] Phase 2 — remove boundary apparatus (scripts, hooks, settings.hooks.json blocks)
  - [x] Phase 3 — identity.md + memory.md decisions + docs/harnesses/claude.md
  - [x] Phase 4 — tests (delete boundary tests, strip tier assertions) + suite green
