---
plan: skill-management-system
status: active
created: 2026-07-07
owner: claude (orchestrator)
task_provider: notion
task_ref: 396f6850-c619-814c-87b3-d066cfe059f4
---

# Plan — Skill management system

## Goal
Give the memory tree a proper **skill management system** organised around two orthogonal axes —
**scope** (does a skill sync to my other instances?) and **source** (did I author it, or is it
referenced from elsewhere?) — so skills install to the right place from the right source, remote skills
are **referenced not forked** (declaration syncs, content is cached per-instance and never drifts), and
every skills tool (enumeration, fan-out, validation, authoring, sync) understands the taxonomy. Adding a
skill — authored or remote, local or generic — is low-friction and needs no per-skill gitignore edits.

## The taxonomy (two orthogonal axes)
- **Scope** — `generic` (in `skills/`, git-tracked, synced to every instance — today's default) vs
  `local` (per-instance, gitignored, never synced). **Location is the signal.**
- **Source** — `authored` (self-created here; content lives in the store) vs `remote` (declared in a
  manifest, fetched from a git source into a gitignored cache, never committed).

| | authored (self-created) | remote (referenced) |
|--|--|--|
| **generic** (synced) | `skills/<name>/` (tracked content) | tracked entry in `skills/skills.json` → fetched to `.skill-cache/` on each instance |
| **local** (per-instance) | `skills-local/<name>/` (gitignored content) | gitignored entry in `skills-local/skills.json` → fetched to `.skill-cache/` |

Unifying rule: **generic = declared/stored in a tracked location; local = in a gitignored one.** Remote
*content* is always the gitignored cache; its scope is which manifest declared it.

## Success criteria
- **Scope:** a `skills-local/` folder, gitignored wholesale by one line; local skills fan out and run
  exactly like generic ones (no `SKILL.md` flag, no per-skill gitignore, no regen step).
- **Enumeration is centralized:** one `_lib.sh:list_skill_dirs` yields every skill dir across all roots
  (`skills/`, `skills-local/`, and the remote `.skill-cache/`); every skills tool routes through it, so a
  new root is added once, not in each of the ~11 globbing scripts.
- **Source:** a remote skill is declared in a manifest (`skills/skills.json` tracked / `skills-local/
  skills.json` gitignored) with `url` + `ref`; `sync` resolves it — git-fetches into a gitignored
  `~/.claude-memory/.skill-cache/<name>/`, pinned by a lockfile — and it fans out. Its content is never
  committed; bumping `ref` + sync updates it. No forking/vendoring of remote content.
- **Authoring:** `new-skill.sh --local` scaffolds an authored-local skill; `install-skill.sh` keeps
  `--from <dir>` (authored fork) **and** gains `--remote <url> [--ref] [--local]` (adds a manifest entry,
  no copy).
- Local, remote, and generic skills are all first-class locally — validated, boundary-checked, rated —
  differing only in git tracking + provenance.
- The `fiter-infrastructure-analyzer` one-off is migrated to `skills-local/` and its individual gitignore
  line removed.
- Docs describe the 2×2 taxonomy, the update flow, and the cache. Full suite green.

## Design
Reached via brainstorm (2026-07-07); expanded from the original "local vs generic" scope after surfacing
the source axis. Distinct from the per-repo `projects/<name>/skills/` axis (`sync-project-skills.sh`),
which is untouched.

**Scope axis — a dedicated ignored folder (chosen).** Generic in `skills/`; local in a sibling
`skills-local/`, gitignored by one static `/skills-local/` line. Path-based exclusion can't drift and
needs no metadata; moving a skill generic↔local is a `git mv`.
- *Rejected — `SKILL.md` frontmatter flag:* can't gitignore itself → needs a regen step + a per-skill edit
  (user rejected the bookkeeping).

**Source axis — a manifest + gitignored cache (chosen).** Remote skills are *declared*, not copied.
- **Manifests (split, symmetric with the folders):** `skills/skills.json` (tracked → generic remotes,
  shared to every instance) + `skills-local/skills.json` (gitignored → local remotes, per-instance). A
  tracked manifest can never leak a local/private entry.
- **Content = gitignored cache:** `~/.claude-memory/.skill-cache/<name>/`, populated by `sync` from the
  manifest (git clone/sparse-checkout of `url` at `ref` → optional `path` subdir). A lockfile pins the
  resolved sha. The cache is a third enumeration root.
- *Rejected — vendored-on-resolve (commit the fetched copy):* that is forking with extra steps — repo
  bloat + drift, the exact thing this avoids.

**Enumeration — the linchpin.** `_lib.sh:list_skill_dirs` is the single source of "what skills exist and
where," yielding dirs across `skills/` + `skills-local/` + `.skill-cache/` (override roots via
`AI_MEMORY_SKILL_ROOTS`). Consumers routed through it: `link-skills.sh`, `validate-skills.sh`,
`new-skill.sh`/`install-skill.sh`, `skill-boundary-check.sh`, `apply-partial.sh`, `skill-ratings.sh`.

## Decisions (locked)
- **Scope = folders:** `skills/` (generic) + wholesale-gitignored `skills-local/` (local); location is the
  signal, no per-skill metadata/gitignore.
- **Source = declare-not-fork:** remote skills declared in split manifests (`skills/skills.json` tracked,
  `skills-local/skills.json` gitignored); content fetched to a gitignored `.skill-cache/`, pinned by a
  lockfile, re-fetched per instance.
- **Centralized enumeration** (`_lib.sh:list_skill_dirs`) over all roots — added once, not per script.
- **All skills first-class locally** — fan-out, validation, boundary, ratings apply regardless of
  scope/source; only git tracking + provenance differ.
- **Migrate `fiter-infrastructure-analyzer`** to `skills-local/`; drop its individual gitignore line.
- Per-repo `projects/*/skills/` axis unchanged; generic-authored remains the default.

## Phases
### Phase 1 — Scope foundation
- `_lib.sh:list_skill_dirs` (roots `skills/` + `skills-local/`, `AI_MEMORY_SKILL_ROOTS` override); route
  `link-skills.sh` + `validate-skills.sh` through it; `.gitignore /skills-local/` (self-documenting
  `.gitkeep` un-ignored). Verify a skill in `skills-local/` fans out and is git-ignored.

### Phase 2 — Authored-skill authoring + migration
- `new-skill.sh --local` → `skills-local/`; `install-skill.sh --from` clarified as authored-fork.
- `git mv skills/fiter-infrastructure-analyzer skills-local/`; drop its `.gitignore` line.
- Route `skill-boundary-check.sh` / `apply-partial.sh` / `skill-ratings.sh` through `list_skill_dirs`.

### Phase 3 — Remote source layer (manifest + resolver + cache)
- Manifest schema + parser (`skills/skills.json` tracked, `skills-local/skills.json` gitignored).
- Resolver: git-fetch `url@ref` (+ `path`) → `~/.claude-memory/.skill-cache/<name>/`; a lockfile
  (`skills.lock`) pins resolved shas. Add `.skill-cache/` as a `list_skill_dirs` root; gitignore it.
- Verify a declared remote skill materializes into the cache and fans out.

### Phase 4 — Authoring + sync integration for remotes
- `install-skill.sh --remote <url> [--ref R] [--path P] [--local]` → append a manifest entry (no copy).
- `sync-system.sh` gains a resolve step (fetch/update remotes from the manifests before re-linking);
  `--update` re-resolves refs. Offline behavior: keep the cached content, warn on fetch failure.

### Phase 5 — Tests + docs
- Tests across the 2×2 (authored/remote × local/generic): fan-out, git-ignore, validate, manifest resolve
  (with a local file:// or fixture remote), update flow, offline.
- Docs: `docs/knowledge-lifecycle.md` + `docs/harnesses/claude.md` skills section — the taxonomy, the
  manifest, the cache, per-instance vs per-repo axes.

## Risks / open questions
- **Fetch mechanism/offline** — RESOLVED (Phase 3). Fetch is **sparse + shallow** (`git init` → `fetch
  --depth 1 origin <ref>`, full-fetch fallback for by-sha refs → `sparse-checkout` the `path` → pin
  `FETCH_HEAD`); the resolved skill is copied into `.skill-cache/<name>/` (no nested `.git`). Offline
  policy is **hard-fail on any fetch that must run**, with the corollary that a plain resolve is a
  **cache hit** (no network) for anything already in `skills.lock` — so re-linking is offline-safe and
  only first-resolve / `--update` touch the network. Lockfile pins give reproducibility.
- **Name collisions** across roots (an authored and a remote skill sharing a name) — `validate-skills`
  should flag cross-root duplicates; last-root-wins is confusing.
- **Cache location & cleanup** — `.skill-cache/` growth; a prune for entries no longer in any manifest.
- **Relation to packaging task** (`396f6850-…8132`, versioned zip releases) — both concern clean
  distribution vs git-master sync; the remote-skill resolver and the release packager may share fetch/pin
  machinery. Keep separate but cross-aware.
- **Trust** — pulling remote skills executes third-party instructions; note the provenance/trust surface
  (pin by sha, review on add).
