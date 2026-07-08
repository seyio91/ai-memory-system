---
plan: skill-manifest-root-template
status: in-progress
created: 2026-07-08
owner: seyi
---

# Root remote-skill manifest + tracked template

## Goal
Move the remote-skill manifest to the repo root and split tracking: ship a
tracked `skills.toml.example` catalog, keep each instance's actual `skills.toml`
per-instance (gitignored, seeded from the template on install). Makes "where
skills are defined" findable, and turns remote skills from force-synced into
opt-in-from-a-catalog.

## Success criteria
- Root `skills.toml` is gitignored; root `skills.toml.example` is tracked.
- `skills/skills.toml` no longer exists (content migrated).
- `resolve-skills.sh` and `list-skills` read the single root manifest.
- A fresh install with no root `skills.toml` seeds it from `skills.toml.example`
  (entries active) and does **not** auto-resolve; it prints next-step guidance.
- `install-skill --remote --save` appends to the root per-instance `skills.toml`.
- This instance still resolves all its current skills after migration (its
  per-instance `skills.toml` carries the full real set, incl. private agent-skills).
- `skills.toml.example` contains public entries active (`grafana/*`, `bkt`,
  `teach`) + a commented `agent-skills` example.
- Generic/local **authored-skill-dir** split (`skills/`, `skills-local/`) unchanged.
- Docs ("Skill scope & source" decision + `docs/harnesses/claude.md`) updated;
  test suite green including a new seeding test.

## Design
For *remote declarations*, tracking flips: the repo ships a **catalog** (tracked
`skills.toml.example`), each instance keeps its **choices** (gitignored root
`skills.toml`). No remote is force-synced. The generic/local split still governs
authored skill dirs — untouched.

- **Files:** root `skills.toml` (per-instance, gitignored, single home for all
  remote declarations — collapses `skills-local/skills.toml`); root
  `skills.toml.example` (tracked catalog); remove `skills/skills.toml`; `.gitignore`
  adds `/skills.toml`, keeps `/skills.toml.example` tracked.
- **Seed flow:** `install.sh` copies `skills.toml.example` → `skills.toml` (active)
  only if absent; no auto-resolve; prints "prune, then resolve-skills.sh". Opt-out.
- **Code:** `_lib.sh` `skill_manifest` → root `skills.toml`; add
  `skill_manifest_template` → `skills.toml.example`; `skill_roots` unchanged.
  `resolve-skills.sh` reads one root manifest. `install-skill --save` → root
  `skills.toml` (catalog curated by hand — no `--catalog` flag, YAGNI). `list-skills`
  reads root manifest.
- **This-instance migration:** current 12 entries split — `skills.toml.example`
  gets the curated catalog; per-instance root `skills.toml` gets the full real set.

**Alternatives considered:**
- *Keep two manifests (root + skills-local remote lane)* — rejected: extra lane
  undercuts the findability goal.
- *Template = all current entries verbatim (incl. agent-skills active)* — rejected:
  bakes the private repo into a shared catalog; not portable.
- *Template = field-doc skeleton only* — rejected: no curated catalog to opt into.
- *Seed commented (opt-in) / seed empty* — rejected in favor of copy-active-then-prune
  (opt-out), per the approved design.

## Risks / open questions
- The `skills/prometheus` authored in-tree straggler is a **separate** cleanup
  (dedup with the remote prometheus), out of scope here.
- Any `skills-local/skills.toml` entries must be hand-merged into root on migration
  (none exist on this instance).
- `install-skill --save` and any harness install override that referenced the old
  `skills/skills.toml` path must be swept for stale path assumptions.

## Phases
- [x] Phase 1 — `_lib.sh` (`skill_manifest` → root, add `skill_manifest_template`) + `resolve-skills.sh` / `list-skills` / `install-skill` path updates
- [x] Phase 2 — `install.sh` seed step (copy template if absent, no auto-resolve, print guidance)
- [x] Phase 3 — `.gitignore` + migrate content: create `skills.toml.example` (curated) + per-instance root `skills.toml` (full set); `git rm skills/skills.toml`
- [x] Phase 4 — tests (update `test_skill_manifest.sh` / `test_resolve_skills.sh` / install test; add seeding test) + full suite green
- [x] Phase 5 — docs (`docs/harnesses/claude.md`) + "Skill scope & source" decision record

## Phase 6 — consolidate authored-skill dirs to a single `skills/` (addendum)
The remote migration emptied the tracked generic `skills/`; the only authored
content now lives in the per-instance `skills-local/`. Collapse the two: `skills/`
becomes **the** authored-skills dir — per-instance, gitignored — and the
generic/local *authored* distinction is **retired** (to share a skill you publish
it to a remote and reference it via the catalog; there is no tracked in-tree
authored skill anymore). The only axis left is source: authored `skills/` vs
remote `.skill-cache/`.

- [x] Move `skills-local/*` → `skills/` (incl. per-instance `fiter-infrastructure-analyzer` + `.gitkeep`); remove `skills-local/`
- [x] `.gitignore`: `/skills-local/*` → `/skills/*`, `!/skills-local/.gitkeep` → `!/skills/.gitkeep`
- [x] `_lib.sh` `skill_roots` → `skills` + `.skill-cache` (drop `skills-local`)
- [x] Sweep all `skills-local` references (scripts, hooks, tests) to the single `skills/` authored dir; retire the generic/local target/flag distinction (authored target is always `skills/`)
- [x] Docs: **explicitly document how the skill system works now** — `skills/` (authored, per-instance) + `.skill-cache/` (remote, from root manifest/catalog); update `docs/harnesses/claude.md`, `docs/scripts.md`, `docs/knowledge-lifecycle.md`, `docs/install.md`, and the "Skill scope & source" decision record
- [x] Full suite green

### Additional success criteria (Phase 6)
- `skills-local/` no longer exists; `skills/` is gitignored per-instance (except `.gitkeep`); `fiter-infrastructure-analyzer` lives under `skills/` and still enumerates.
- `skill_roots` = `skills` + `.skill-cache`; no `skills-local` references remain in scripts/hooks/docs/tests (outside `archive/`).
- Docs clearly state the two-location model (authored `skills/` vs remote `.skill-cache/`) and that the generic/local authored split is retired.
- Suite green.
