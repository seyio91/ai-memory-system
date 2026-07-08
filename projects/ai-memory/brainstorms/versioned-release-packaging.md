---
doc: versioned-release-packaging
kind: brainstorm-input
status: design-settled (pending 3 small decisions)
created: 2026-07-08
updated: 2026-07-08
task_provider: notion
task_ref: 396f6850-c619-8132-bf77-e09e4bd2757e
owner: claude (orchestrator)
---

# Brainstorm — Versioned releases for the memory system

**Status:** direction settled in dialogue (2026-07-08): **tagged release channel over
git. No zip, no `.engine/` dir — zip/external-user distribution explicitly deferred
(§7), not tracked work.** Three small decisions remain (§6) before `/new-plan`.
When the resulting plan ships, archive this doc to `archive/wikis/`.

---

## 1. Problem (reframed from the captured task)

The captured task (`396f6850-c619-8132-bf77-e09e4bd2757e`) proposed "release as a
versioned zip". Brainstorming decomposed it into **four distinct problems** — the
zip was a suggestion, not a requirement:

1. **Stability** — consuming instances sync from a moving `main` (`sync-system.sh`
   ff-pull); a pull can land mid-change. Fix = sync a *tested cut* → needs **tags**.
2. **Identity / rollback** — no way to say "this instance runs X", pin, or go back.
   Needs **versioning**, not packaging.
3. **Change communication** — no CHANGELOG/UPGRADING; breaking changes (marker
   migration, manifest key renames, hooks.json re-registration) arrive silently.
   Needs **release discipline + a migration runner** — orthogonal to packaging.
4. **Clean artifact** — the repo tracks personal content (`identity.md`,
   `projects/ai-memory/**`, `domain/agent-tooling.md`, `domain/codex.md`), so no
   distributable artifact falls out of git naturally.

**Scope decision (user, 2026-07-08):** in-scope consumers are the user's own
instances, all with git + `gh` authed to the private repo. External "new user
downloads a release" is a real future want but **deferred** (§7). ⇒ Problem 4 is out
of scope for now; problems 1–3 are solved by **git tags as the package**.

## 2. Rejected / deferred approaches (decision record)

| Approach | Verdict |
|---|---|
| **Zip overlay in place** (extract over `$MEMORY_DIR`) | Rejected — no stale-file deletion, silently clobbers local edits, no rollback; answers none of the open questions. |
| **Zip + `.engine/<ver>/` + `current` symlink** (previously recommended as "B") | Rejected for now — sound design, but built to solve artifact-cleanliness and no-git distribution, which don't exist for the in-scope consumers. Costs it would impose: templates-out-of-data-tree refactor, `install.sh` `pwd -P`→logical change, 6 path-ref rewrites, leak-guard, bootstrap chicken-and-egg. All bought things git already provides (§3.1 table). Detailed design survives in this doc's git history. |
| **Fully separate roots** (`~/.ai-memory/{engine,data}`) | Rejected — forces a data migration on every instance, rewrites the `MEMORY_DIR` contract. YAGNI. |
| **Zip as external-user front door** | **Deferred, not tracked** — see §7 for the facts established, so the future thread doesn't restart from zero. |

## 3. Settled design: tagged release channel

### 3.1 Core idea

Git is the versioned artifact store; **a semver tag is the release**. Instances sync
to tags, never raw `main`.

What git provides that a zip design would have to build:

| Zip design must build | Git already does it |
|---|---|
| `VERSION` file | `git describe --tags` |
| Rollback machinery | `git checkout v1.3.0` |
| Checksums / integrity | commit + tag integrity |
| Local-edit reconciliation policy | `checkout` refuses on dirty tracked files — edits are *detected*, never clobbered |
| Stale-file deletion on upgrade | checkout removes files that left the tree |

### 3.2 Channels

Per-instance, in gitignored `config.local.sh`:

- **`AI_MEMORY_CHANNEL=release`** (default) — plain `sync-system.sh` syncs to the
  **latest `v*` tag**.
- **`AI_MEMORY_CHANNEL=dev`** — plain `sync-system.sh` keeps today's `--ff-only`
  pull of `main`. For instances deliberately riding the edge.
- The dev *machine* (the working checkout) needs no channel at all — every surface is
  a symlink into the tree, so edits are live instantly; sync is not involved.

| Instance | Channel | Gets |
|---|---|---|
| dev machine (this checkout) | working tree | every keystroke |
| dogfood instance | `dev`, or one-shot `--to <ref>` | main / branches on demand |
| stable instances | `release` | tagged cuts only |

### 3.3 Sync command (dogfood = sync to any ref)

```bash
sync-system.sh                   # channel default: release→latest tag, dev→ff-pull main
sync-system.sh --to v1.3.0       # pin / downgrade
sync-system.sh --to main         # one-shot dogfood of current dev state
sync-system.sh --to feat/x       # try an in-flight branch
sync-system.sh --to 3d0fbe8      # bisect a regression
```

Every path is identical after ref resolution: `git fetch --tags` → dirty-tree guard →
`git checkout <ref>` → **run pending migrations** → re-run `install.sh` (idempotent,
relinks all surfaces). "Which version is live" is purely "what's checked out".

**`--to` is ephemeral by design:** it does not change the channel; the next plain
`sync-system.sh` snaps the instance back to the latest tag. An instance can't be
forgotten on a stale branch — it self-heals at the next sync. A *standing* dogfood
requires the explicit channel flip.

### 3.4 Migration runner

New: `migrations/<semver>-<slug>.sh` (e.g. `migrations/1.1.0-agents-marker.sh` — the
existing `migrate-marker.sh` pattern is the template). Run during sync, between
checkout and `install.sh`.

Rules (the part that makes dogfooding safe):

1. **Runner keys on migration files, not tags.** Run every migration whose version >
   the applied marker; record the highest version run. Works identically for tagged
   and untagged (branch/sha) checkouts.
2. **Migrations are idempotent and forward-only.** Re-runnable; no down-migrations
   (not worth it for a single-owner system). They touch **data and harness config
   only** (`$MEMORY_DIR` data, `~/.claude/settings.json`, `~/.gemini/...`), never
   engine code.
3. **Downgrade = code moves back, data stays migrated.** The applied marker stays at
   the high-water mark; the runner never re-runs on snap-back. Consequence — the one
   standing rule in `UPGRADING.md`: **a migration must not break the previous
   release's code** (old code + new data must still work). Pattern: ship the compat
   fallback in release N, flip in N+1 — exactly how the `.agents/memory-project`
   marker migration was done (new reader with legacy fallback first, bulk-migrate
   after).

State: an **applied-version marker** — machine-written, gitignored (§6.3 for
location). Needed because "what code is checked out" and "what migrations have run
against this instance's data/harness config" are different facts.

### 3.5 Release cut — `scripts/release.sh <version>`

Manual first (per the task); automation later adds a trigger, not a second code path:

1. Refuse on dirty tree / not on `main` / failing test suite (`run-tests.sh`).
2. Finalize the `CHANGELOG.md` section for `<version>` (drafted from
   `git log v<prev>..HEAD`).
3. `git tag -a v<version>` + push the tag — orchestrator/manual, never an executor
   (tag-push is the publish act).
4. Later, GitHub Actions on-tag: generate the GitHub Release entry. Same script does
   the build-side work; CI adds only the trigger.

### 3.6 Docs shipped with the discipline

- **`CHANGELOG.md`** (tracked) — per-release: what changed, breaking changes.
- **`UPGRADING.md`** (tracked) — per-version migration notes + the standing rules:
  forward-only idempotent migrations; N/N+1 compat.

## 4. Codebase facts established (verified 2026-07-08; do not re-derive)

- **`sync-system.sh` today:** `git fetch` + `--ff-only` merge of `@{u}`, then re-run
  `install.sh`; `--update` re-resolves remote skills; `--dry-run`/`--no-pull` flags.
  The release channel slots in as an alternative to the ff-merge step; the
  post-checkout tail (migrations → `install.sh`) is shared by all paths.
- **`install.sh` is already the idempotent (re)wire step** — `link()` (skip-if-
  correct, back-up otherwise), python3 JSON merges for Antigravity hooks/statusline,
  seeds personal files only-if-missing, stamps `MEMORY_DIR` into `config.local.sh`.
  Re-running after checkout is the existing pattern (`sync-system.sh:93`).
- **All harness wiring is symlinks into the checkout** (or idempotent JSON merges),
  so checkout-flip = version-flip; nothing beyond the existing `install.sh` rerun.
- **`_lib.sh:5`** self-locates `MEMORY_DIR` from `BASH_SOURCE` and sources
  `config.local.sh` — the channel var lands there naturally.
- **`git describe --tags`** gives version identity free once tags exist; the dev
  machine reports e.g. `v1.2.0-3-g88bd7ba`.
- **Consumer instances never commit** — engine commits happen only in the dev
  checkout, so a detached-HEAD (or reset-branch) consumer state is safe.
- **Constraints:** macOS bash 3.2 (no `mapfile`, no assoc arrays, no `readlink -f`;
  `sort -V` availability should be verified on target macOS — fallback: a small
  semver-compare helper); python3 stdlib only; Two-Path principle; executors never
  tag-push/merge.

## 5. Scope of the eventual plan (sketch, for `/new-plan`)

1. **Channel + `--to` in `sync-system.sh`** — release/dev resolution, latest-tag
   discovery, dirty guard, checkout, shared tail. Tests.
2. **Migration runner + applied-version marker** — runner invoked from
   `sync-system.sh`, `migrations/` dir, marker read/write, bash-3.2 semver compare.
   Convert nothing retroactively; `migrate-marker.sh` stays as the historical
   example until a real next migration lands. Tests.
3. **`release.sh`** — guards, CHANGELOG drafting, tag + push (manual). Tests for the
   guards.
4. **Docs** — `CHANGELOG.md` (seeded), `UPGRADING.md` (standing rules), `docs/`
   updates (`scripts.md`, install/sync pages), README.
5. **Cut the first tag** (§6.1) and flip one real consumer instance to the release
   channel end-to-end.
6. **Out of scope:** GitHub Actions on-tag Release entry (later); zip / external
   users (§7, untracked).

## 6. Remaining decisions (small, before `/new-plan`)

1. **First tag: `v1.0.0` vs `v0.x`.** Recommendation: `v1.0.0` — the system is in
   daily use, stable, and breaking changes are already handled carefully.
2. **Consumer checkout state: detached HEAD vs a local `release` branch reset to
   each tag.** Recommendation: detached HEAD — simpler and honest; a branch only
   helps an instance that commits, and consumer instances never commit.
3. **Applied-version marker location.** Recommendation: a dedicated gitignored file
   at the tree root (e.g. `.applied-version`) — machine-written, so it doesn't
   belong in user-owned `config.local.sh`.
4. **Semver rule of thumb** (to write into `UPGRADING.md`): MAJOR = breaks an
   instance without a migration, or changes the `MEMORY_DIR`/marker/manifest
   contracts incompatibly; MINOR = new features, new harness, additive manifest
   keys, anything shipping an N-1-compatible migration; PATCH = fixes. Confirm or
   adjust.

## 7. Deferred: zip for external users (not tracked work)

Facts established so this thread doesn't restart from zero when revived:

- **External consumers reinstate problem 4** (clean artifact), but *not* the
  `.engine/` layout. The zip = "a clean clone minus personal content"; the extracted
  tree is the memory tree, and `install.sh` already seeds personal files
  only-if-missing — first install works structurally today.
- **`git archive` is the wrong build primitive while the repo tracks personal
  content** (`identity.md`, `projects/ai-memory/**`, `domain/agent-tooling.md`,
  `domain/codex.md`) — the build needs an explicit allowlist + a leak-guard
  assertion (hard-fail if a personal path reaches staging), enforceable as a test.
- **Private-repo Release assets require repo access to download** — so "new user
  downloads a release" implies either a public repo or invited collaborators.
  Public ⇒ untrack personal content going forward **and scrub git history** (it's
  in every past commit).
- **Zip-user upgrade paths considered:** (a) graduate to git — first
  `sync-system.sh` on a zip tree does `git init` + remote + join the tag channel
  (one upgrade mechanism total; needs repo access); (b) zip-to-zip via a shipped
  hash manifest (stale-delete + edit-detect; a second mechanism, reimplementing a
  slice of git in bash 3.2); (c) install-only, no upgrade story. Leaning (a) if the
  repo goes public.
