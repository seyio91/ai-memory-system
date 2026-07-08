# Todo snapshot — ai-memory — 2026-07-08 (skill-manifest-root + consolidation)

> Rolled snapshot of completed work. See archive/plans/skill-manifest-root-template.md.
> Landed across PR #36 (Phases 1–5) and PR #38 (Phase 6, after a dropped-commit recovery).

- [x] **Root skill manifest + template** — moved skills.toml to root, split into tracked `skills.toml.example` catalog + per-instance gitignored `skills.toml` seeded on install; consolidated authored skills into a single per-instance `skills/` dir (retired generic/local split) → [archive/plans/skill-manifest-root-template.md](../plans/skill-manifest-root-template.md)
  - [x] Phase 1 — `_lib.sh` + resolve-skills/list-skills/install-skill path updates
  - [x] Phase 2 — `install.sh` seed step
  - [x] Phase 3 — `.gitignore` + migrate content + `git rm skills/skills.toml`
  - [x] Phase 4 — tests + suite green
  - [x] Phase 5 — docs + decision record
  - [x] Phase 6 — consolidate authored dirs → single `skills/` (per-instance, gitignored); sweep `skills-local`; docs (PR #38)
