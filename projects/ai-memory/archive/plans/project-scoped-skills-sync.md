---
plan: project-scoped-skills-sync
status: done
created: 2026-06-17
completed: 2026-06-17
owner: claude (orchestrator)
task_provider: local
task_ref: 382f6850-c619-8186-b68e-fe008675d926
---

# Plan — Project-scoped skills: co-locate in the project + per-harness repo sync

## Goal
Give a skill that only makes sense in one repo (or a small group) a home that scopes it to that repo instead of installing it globally. Store such skills co-located with their project (`projects/<project>/skills/<skill>/`, so the path is the scope), and add a harness-aware sync command that fans each skill into the target repo's per-harness skill dir — `.claude/skills/` (Claude Code) and/or `.agents/skills/` (Codex). Both harnesses consume the same `SKILL.md`, so no translation is needed.

## Success criteria
- `scripts/sync-project-skills.sh` exists: for each project under `projects/<project>/skills/`, resolves the project's absolute `repo_path` from its `memory.md`, and links/copies each skill into the chosen harness target(s). Supports `--harness claude|codex|all`, `--mode link|copy`, optional `[<project>…]` filter, `--list`, `--dry-run`; idempotent, repairs stale links, refuses to clobber real files / foreign symlinks, skips skill dirs lacking `SKILL.md`.
- `client-a-infrastructure-analyzer` is migrated to its project home under `projects/<project>/skills/`, its **global `~/.claude/skills/` symlink is removed** (Personal overrides Project — leaving it would shadow the scoped copy everywhere), and the skill resolves in its target repo(s) under the chosen harness(es).
- `repo_path` is absolute for every project (prerequisite — **done** this session).
- `domain/agent-tooling.md` records the project-scoped-skills pattern (co-location, per-harness targets, Claude `.claude/skills` vs Codex `.agents/skills`, link-vs-copy ownership rule, Personal>Project precedence gotcha).

## Design
- **Chosen approach — co-locate + harness-aware sync.** Source of truth = `projects/<project>/skills/<skill>/SKILL.md`; the path encodes the scope (no manifest). `sync-project-skills.sh` mirrors `link-agents.sh`/`link-skills.sh` mechanics (idempotent / repair / no-clobber) but: (1) iterates projects that have a `skills/` dir, (2) resolves each project's `repo_path` (now absolute) from `memory.md` frontmatter, (3) routes per `--harness` to `<repo_path>/.claude/skills/<skill>` and/or `<repo_path>/.agents/skills/<skill>`.
- **Link vs copy (`--mode`).** A symlink points at the absolute `~/Downloads/...` store path — fine personally, broken for teammates/CI. So: personal skill → `link` + gitignore in the repo; shared skill (Codex repo skills are designed to be committed) → `copy` + commit. Command supports both; chosen per skill at migration.
- **Multi-repo skills.** Pure co-location fits a single-repo skill. A skill spanning several repos (e.g. the client-a IaC analyzer, if it applies to more than one) needs a target list — handle via an optional `targets:` line in the skill's own metadata or a per-project sidecar; resolve the exact `client-a-infrastructure-analyzer` scope during Phase 3.
- **Alternative — central store + `scopes.tsv` manifest** → rejected as the default: co-location makes the scope self-evident from the path and keeps the skill next to its project memory. Manifest retained only as the multi-repo escape hatch.
- **Alternative — commit skills directly into each repo, no store** → rejected: loses single-source-of-truth and cross-harness sync from one canonical copy.

## Decisions (locked)
- Co-location (`projects/<project>/skills/`) is the home for project-scoped skills; path = scope.
- One sync command, harness-routed (`--harness`), with `--mode link|copy`.
- Claude target `.claude/skills/`, Codex target `.agents/skills/` — same `SKILL.md`, no translation.
- Migrating a skill to project scope REQUIRES removing its global `~/.claude/skills/` link (precedence).
- `repo_path` normalized to absolute (prerequisite done).

## Phases
### Phase 1 — repo_path normalization (DONE this session)
- All 12 project `memory.md` `repo_path:` values rewritten to absolute under `/Users/seyi/Downloads/personal/`; verified each resolves to a real dir.

### Phase 2 — Write `scripts/sync-project-skills.sh`
- Iterate `projects/*/skills/*/` with a `SKILL.md`; resolve project `repo_path`; route per `--harness`/`--mode`; idempotent/repair/no-clobber; `--list`/`--dry-run`.

### Phase 3 — Migrate `client-a-infrastructure-analyzer` (DECIDED: no-op)
- Decision (2026-06-17): the analyzer's trigger is generic ("any `<client>/<env>` IaC repo"), so it **stays global** in `~/.claude/skills/` — not migrated. No project-scoped skill exists yet; the sync mechanism is built and proven, ready for a genuinely single-repo skill. Recorded defaults for a future migration: `--mode link --harness all`.

### Phase 4 — Verify + safety
- Idempotent re-run; repair a broken link; no-clobber a planted real file; skip a SKILL.md-less dir; confirm link vs copy modes; confirm global removal took effect.

### Phase 5 — Document
- Add the project-scoped-skills entry to `domain/agent-tooling.md` (targets table, link/copy rule, precedence gotcha, multi-repo escape hatch).

## Risks / open questions
- `client-a-infrastructure-analyzer` scope (one repo vs many) — resolve in Phase 3; its trigger is generic, so confirm it should be scoped at all rather than left global.
- Codex symlink-following in `.agents/skills/` is undocumented (as is Claude's); empirically Claude follows symlinks — verify Codex does before relying on `link` mode for Codex (fall back to `copy`).
- Multi-repo target mechanism (metadata `targets:` vs sidecar) — pick when first needed.
