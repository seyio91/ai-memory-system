---
plan: release-automation
status: in-progress
created: 2026-07-15
owner: claude (orchestrator)
task_provider: notion
task_ref: 397f6850-c619-81da-99e8-c98650bddd65
---

# Plan — Automate the release pipeline (changelog fragments + computed versioning)

## Goal
Move CHANGELOG + upgrade-guide authoring off release-time `git log` summarization onto
per-PR **news fragments** (`changelog.d/<id>.<kind>.md`), assembled deterministically at
release time, with the semver bump **computed from fragment kinds**. `release.sh` stays the
single implementation and gains a non-interactive `--ci` mode; the model drafts fragments
while the reasoning is live and the suite enforces the invariants. This plan lands the
**local machinery** (Phase A); the GitHub Actions wiring is deferred to Phase B because it
needs a PAT secret the user adds in repo settings.

## Success criteria
- `changelog.d/` exists with a `README.md` documenting the fragment format: filename
  `<pr-or-slug>.<kind>.md`, kinds `breaking | feature | fix | upgrade`, body is the
  human-facing note.
- A deterministic assembler turns `changelog.d/*` into a `## [x.y.z] - YYYY-MM-DD` CHANGELOG
  section grouped by kind (Breaking/Added/Fixed/Upgrade), stable-sorted — byte-identical for
  the same fragment set. No inference, no model.
- The **version bump is computed** from the highest-ranked fragment kind vs. the latest
  stable tag: `breaking→major`, `feature→minor`, `fix|upgrade→patch`. An explicit version
  arg overrides the computation.
- `release.sh` **consumes fragments**: when `changelog.d/` is non-empty it assembles the
  section from fragments and deletes them in the release commit, superseding the `git log`
  draft path. `--ci` runs fully non-interactive (no prompts, no editor) and creates the
  GitHub Release via `gh release create`. All existing guards (clean tree, `main`, origin
  agreement, monotonic semver, passing suite, `AI_MEMORY_ROLE` refusal) still hold.
- Tests (gated in `run-tests.sh`): fragment filename/kind validation; assembly determinism +
  kind grouping/order; version-bump computation across kind combinations; the `--ci` path;
  and the **existing** migration→`UPGRADING.md` test (`test_upgrading_doc.sh`) still passes.
- Docs updated: `changelog.d/README.md`, `docs/scripts.md` (new script + any env in the
  machine-checked table), and the per-PR "drop a fragment" step recorded in the PR/plan flow.
- `shellcheck`, `doc-vs-code`, and the full suite are green.

## Design
From the `release-automation` investigation (design settled there; brainstorm gate skipped
per the task summary):
- **News-fragment pattern** (towncrier / changesets): each PR drops a `changelog.d/` file.
  Payoffs: no `## [Unreleased]` merge conflicts, deterministic assembly, fragment reviewed in
  the PR that caused it while context is live.
- **Ownership split:** model writes fragments and *describes* an existing migration; a test
  enforces "migration ⇒ upgrade note"; the script assembles; publication is a human gate.
- **Hard line:** the model may only describe a `migrations/<semver>-<slug>.sh` that already
  exists — never synthesize upgrade steps from a diff. Already enforced by
  `test_upgrading_doc.sh`.
- **`release.sh` is the single implementation** — the future Action is a *trigger*, not a
  second code path. `--ci` is that seam.
- **No model in CI:** assembly is pure text manipulation; keeps an API key out of the publish
  path and the release deterministic.
- Fragment is the source of truth; the PR body quotes it (chosen over PR-body-first to avoid
  drift — one authored source).
- Avoid the tag-retrigger footgun (a `GITHUB_TOKEN`-pushed tag won't refire a tag-triggered
  workflow) by having `release.sh --ci` create the GH Release **inline** in the same job —
  no separate tag-triggered workflow (relevant in Phase B).

## Decisions (locked)
- **Phase A now (local machinery); Phase B later (GitHub Actions + PAT secret).**
- **Version computed from fragment kinds**, overridable by explicit arg.
- Fragment kinds: `breaking | feature | fix | upgrade`; filename `<id>.<kind>.md`.
- Fragment-first; PR body quotes the fragment.
- Fragments **fully replace** hand-editing `## [Unreleased]` once adopted (see migration risk).
- `release.sh` remains the one implementation; `--ci` adds a mode, not a path.

## Phases

### Phase A0 — CI runs the suite on every PR (no secret)
- `.github/workflows/tests.yml`: `bash scripts/run-tests.sh` on `pull_request` + `push`.
- Matrix `ubuntu-latest` + `macos-latest` — macOS ships **Bash 3.2**, the portability floor
  this repo commits to; ubuntu (bash 5) alone would miss 3.2 regressions.
- Install `shellcheck` in the job — the suite *skips* the shellcheck gate when the binary is
  absent, so CI must provide it or the gate silently never fires.
- Read-only, default `GITHUB_TOKEN`, no PAT — independent of the fragment machinery, lands
  first. This is the "run tests in the pipeline" goal.

### Phase A1 — Fragment convention, assembler, version computation
- Create `changelog.d/` with `.gitkeep` + `README.md` (format, kinds, examples).
- `scripts/assemble-changelog.sh` (or a `taskprovider`-style helper): read `changelog.d/*`,
  group by kind, stable-sort, emit a `## [x.y.z] - DATE` section to stdout; a `--bump` mode
  prints the computed next version from the fragment kinds + latest tag. Pure, no mutation.
- `scripts/tests/test_assemble_changelog.sh`: determinism, grouping/order, bad-filename
  rejection, bump computation (breaking/feature/fix/upgrade and mixtures, incl. empty = error).

### Phase A2 — `release.sh` integration + `--ci`
- When `changelog.d/` is non-empty, `release.sh` assembles the section from fragments (and
  stages their deletion) instead of the `git log` draft; empty ⇒ current behavior (back-compat).
- Version arg becomes optional: if omitted, compute from fragments; if given, must still be
  monotonic (existing guard).
- `--ci`: non-interactive; `gh release create <tag> --notes-from-tag` (or the assembled body);
  no prompts. Keep the `AI_MEMORY_ROLE` refusal (an Action isn't an executor, so it passes).
- Extend `scripts/tests/test_release.sh`: fragment-driven assembly, computed version, `--ci`
  path, fragment deletion in the release commit.

### Phase A3 — Adopt in process + docs
- `changelog.d/README.md` + `docs/scripts.md` rows (assembler; any new env in the checked table).
- Record the per-PR step ("drop `changelog.d/<id>.<kind>.md`") in the PR/plan workflow docs so
  it becomes routine, and note the cutover in `UPGRADING.md`/`CHANGELOG.md`.
- Migrate the current hand-edited `## [Unreleased]` content (if any) into fragments as the
  cutover.

### Phase B — GitHub Actions (DEFERRED — needs user's repo-settings/PAT)
- `.github/workflows/`: on merge to `main`, assemble `changelog.d/*` → open/update a
  "Release vX.Y.Z" PR (CHANGELOG + UPGRADING + version bump; deletes fragments).
- On release-PR merge: run `bash scripts/release.sh --ci` (tag + push + GH Release inline).
- Requires a PAT secret (the tag-retrigger footgun) — a human setup gate. Do NOT wire until
  Phase A is proven and the user provisions the secret.

## Risks / open questions
- **Cutover from `## [Unreleased]`.** The assembler must own the section cleanly; during
  transition, decide whether to assemble fragments *and* preserve any hand-written
  `[Unreleased]` body, or hard-cut. Locked: hard-cut to fragments, migrating existing content
  into fragments in A3.
- **`--dry-run` genuinely fetches** (existing open thread, `sync-system.sh`) — keep `--ci`
  honest about its side effects; assert side-effect boundaries in tests.
- **`gh` auth in local `--ci` testing** — tests must stub/guard `gh` so the suite stays
  hermetic and offline (no real GH Release from a test run).
- Phase B PAT/tag-retrigger footgun — mitigated by inline `gh release create`; revisit at B.
