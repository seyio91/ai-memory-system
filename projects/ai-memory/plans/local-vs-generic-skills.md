---
plan: local-vs-generic-skills
status: active
created: 2026-07-07
owner: claude (orchestrator)
task_provider: notion
task_ref: 396f6850-c619-814c-87b3-d066cfe059f4
---

# Plan — Local vs generic skills (per-instance skills that don't sync)

## Goal
Introduce a first-class distinction between **generic** skills (in `skills/`, git-tracked, synced across
every memory-system instance — today's default) and **local** skills (in a new, wholesale-gitignored
`skills-local/` folder, specific to one instance, never committed or synced) — while local skills are
**still installed and fanned out locally** so they work. Zero per-skill gitignore bookkeeping and no
`SKILL.md` edits: a skill is local iff it lives in `skills-local/`.

## Success criteria
- A `skills-local/` folder exists, gitignored **wholesale by one line** (`/skills-local/`); adding a local
  skill needs no further `.gitignore` edit and no `SKILL.md` change.
- Skills in `skills-local/` are fanned out by `link-skills.sh` into `~/.claude/skills` and
  `~/.agents/skills` exactly like generic skills (they load and run).
- `git` / `sync-system.sh` never commit or sync `skills-local/` content; a `git pull` leaves local skills
  untouched (they're ignored, not tracked).
- Skill enumeration is **centralized in one helper** (`_lib.sh`) that yields both roots, so every
  skills-globbing tool sees local skills — no tool silently skips them.
- `new-skill.sh --local` scaffolds into `skills-local/`; `validate-skills.sh` validates both roots;
  `install-skill.sh` can import a skill as local.
- `validate-skills.sh` / boundary + self-rating tooling treat a local skill identically to a generic one
  (write-boundary, ratings) — the only difference is git exclusion.
- The `fiter-infrastructure-analyzer` skill is migrated into `skills-local/` and its individual
  `/skills/fiter-infrastructure-analyzer/` gitignore line removed (now covered by the folder ignore).
- Docs updated (knowledge-lifecycle + the Claude harness skills section) describe the two-folder convention.
- Full suite green.

## Design
Reached via brainstorm (2026-07-07). Two axes exist and must not be conflated: **per-instance** (this plan:
generic-vs-local, the global canonical store) vs **per-repo** (the existing `projects/<name>/skills/` +
`sync-project-skills.sh`, untouched here).

**Chosen — a dedicated, wholesale-ignored folder.** Generic skills stay in `skills/` (tracked). Local
skills live in a sibling `skills-local/`, gitignored by a single static line. Git exclusion is **path-based**
(the most robust way to keep a class of files out of git — it can't drift per-skill), and "local" needs no
metadata: it's implied by location. Moving a skill generic↔local is a `git mv` (auditable). The only real
cost — many scripts currently glob `skills/` independently — is neutralized by **centralizing enumeration**:
add `list_skill_dirs()` to `scripts/_lib.sh` that emits `skills/*` **and** `skills-local/*`, and route the
skills-globbing scripts through it. One change instead of eleven; a new root is added in one place forever.

- *Rejected — `SKILL.md` frontmatter flag (`metadata.scope: local`):* a flag can't gitignore itself, so it
  needs a regen step (reinstall/script) to maintain `.gitignore` **and** a `SKILL.md` edit per skill. The
  user explicitly rejected that per-skill bookkeeping.
- *Rejected — declarative gitignore list (a `skills/.local` manifest):* same regen/bookkeeping cost, less
  self-evident than folder location.

**Enumeration helper.** `list_skill_dirs()` in `_lib.sh` is the single source of "what skills exist and
where." Consumers that must see local skills: `link-skills.sh` (fan-out), `validate-skills.sh` (validate),
`new-skill.sh`/`install-skill.sh` (authoring, via `--local`), `skill-boundary-check.sh` (boundary applies),
`apply-partial.sh` + `skill-ratings.sh` (a local workflow skill still self-rates). `sync-project-skills.sh`
is the *other* axis and is left alone.

## Decisions (locked)
- **Folder = `skills-local/`** (sibling of `skills/`), gitignored wholesale via one `/skills-local/` line.
- **Location is the signal** — no `SKILL.md` field, no per-skill gitignore entry, no regen step.
- **Centralized enumeration** (`_lib.sh:list_skill_dirs`) so both roots are added once, not per script.
- **Local skills are first-class locally** — fanned out, validated, boundary-checked, and rated exactly
  like generic; they differ only in being git-excluded.
- **Migrate `fiter-infrastructure-analyzer`** into `skills-local/` and drop its individual gitignore line.
- Generic remains the default; `skills/` and the per-repo `projects/*/skills/` axis are unchanged.

## Phases
### Phase 1 — the folder + centralized enumeration
- Add `list_skill_dirs()` to `scripts/_lib.sh` (yields `skills/*` + `skills-local/*`, SKILL.md-gated).
- Route `link-skills.sh` and `validate-skills.sh` (and the other globbing consumers) through it.
- Add `/skills-local/` to `.gitignore`. Create `skills-local/.gitkeep` (or document the empty folder).
- Verify fan-out: a skill dropped in `skills-local/` links into the harness skill dirs.

### Phase 2 — authoring + migration
- `new-skill.sh --local` writes to `skills-local/`; `install-skill.sh` gains a local-import path.
- `git mv skills/fiter-infrastructure-analyzer skills-local/`; remove the individual `.gitignore` line.
- Confirm `skill-boundary-check.sh` / `apply-partial.sh` / `skill-ratings.sh` operate on both roots.

### Phase 3 — tests + docs
- Tests: local skill fans out; `skills-local/` is git-ignored (git check-ignore); validate scans both;
  `new-skill --local` lands in the right folder; generic behavior unchanged.
- Docs: `docs/knowledge-lifecycle.md` + `docs/harnesses/claude.md` (skills section) describe the split;
  note the per-instance vs per-repo axes.

## Risks / open questions
- **Name collision** — a generic and a local skill with the same dir name would both try to link to the
  same harness target. Rare; `validate-skills` should warn on a cross-root duplicate.
- **Missed consumer** — if a skills-globbing script isn't routed through `list_skill_dirs()`, it silently
  ignores local skills. Mitigation: grep the `skills/` glob surface during Phase 1 and route all of it;
  a test that a local skill is visible to link + validate catches regressions.
- **`skills-local/` empty-folder tracking** — git won't track an empty dir; ship a `.gitkeep` (itself the
  only tracked thing under the otherwise-ignored folder) or have `install.sh` create it.
