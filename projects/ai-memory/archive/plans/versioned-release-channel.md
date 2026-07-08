---
plan: versioned-release-channel
status: done
created: 2026-07-08
completed: 2026-07-08
owner: claude (orchestrator)
task_provider: notion
task_ref: 396f6850-c619-8132-bf77-e09e4bd2757e
---

# Versioned release channel (git tags)

> Design record: `projects/ai-memory/brainstorms/versioned-release-packaging.md`
> (archive it to `archive/wikis/` when this plan ships).

## Goal

Give the memory system versioned releases over git: consumer instances sync to
semver **tags** (tested cuts) instead of a moving `main`, with pin/rollback via
checkout, a forward-only migration runner for breaking changes, and a manual
`release.sh` that cuts tags with CHANGELOG/UPGRADING discipline. No zip, no layout
change — zip/external-user distribution is explicitly deferred (brainstorm doc §7).

## Success criteria

1. On an instance with `AI_MEMORY_CHANNEL=release` (the default when unset), plain
   `sync-system.sh` checks out the **latest `v*` tag** — never raw `main` — then
   runs pending migrations and re-runs `install.sh`. `AI_MEMORY_CHANNEL=dev`
   preserves today's `--ff-only` pull of `main`, including the `--dry-run`
   incoming-commits/diffstat preview. Two intended deltas from the old script (do
   not treat as regressions): the shared dirty-tracked-file guard now runs on the
   dev path too, and `fetch` now passes `--tags`.
2. `sync-system.sh --to <ref>` works for a tag, branch, or sha; it does **not**
   change the channel, and the next plain `sync-system.sh` snaps back to the
   channel default **on both channels** — `release` re-checks-out the latest tag,
   `dev` returns to its tracking branch even from detached HEAD. A dirty tracked
   tree aborts before checkout with a clear message, on every path that checks out.
   `--to` with `--no-pull` is a usage error, not a silent no-op.
3. The migration runner executes every `migrations/<semver>-<slug>.sh` with version
   strictly greater than the applied marker, in semver order, then records the
   highest version run in the gitignored `.applied-version`. Re-running sync is a
   no-op (idempotent); a downgrade (`--to` an older ref) runs nothing and never
   errors on the marker being ahead.
4. `scripts/release.sh <version>` refuses on: dirty tree, not on `main`, failing
   `run-tests.sh`, tag already exists, or version not greater than the latest tag.
   On success it finalizes the CHANGELOG section and creates + pushes the annotated
   tag `v<version>`.
5. `git describe --tags` reports the version on any synced instance; consumer
   checkout state after a release sync is detached HEAD at the tag.
6. `CHANGELOG.md` and `UPGRADING.md` exist, are tracked, and `UPGRADING.md` states
   the two standing rules (forward-only idempotent migrations; N/N+1 compat: a
   migration must not break the previous release's code).
7. New tests cover: channel resolution, latest-tag discovery, `--to` ephemerality,
   dirty-guard abort, migration ordering/marker/idempotency/downgrade, and
   `release.sh` guard refusals. Full suite green; all scripts bash-3.2-clean.
8. End-to-end proof: first tag cut with `release.sh`, and one real consumer
   instance flipped to the release channel syncs to it successfully.

## Design

**Chosen: tagged release channel over git.** A semver tag is the release; git is the
artifact store. Per-instance `AI_MEMORY_CHANNEL` in `config.local.sh`
(`release` default | `dev`); `sync-system.sh --to <ref>` for one-shot pin/dogfood/
bisect. All sync paths share one tail after ref resolution: fetch (+tags) →
dirty-tree guard → checkout → migration runner → `install.sh` (already the
idempotent rewire step — all harness wiring is symlinks into the checkout or
idempotent JSON merges, so checkout-flip = version-flip).

**Migration runner:** `migrations/<semver>-<slug>.sh`, forward-only, idempotent,
touching data + harness config only (never engine code). Keys on migration files
(not tags) so untagged dogfood refs migrate identically; `.applied-version`
(gitignored, machine-written) is the high-water mark — downgrades leave data
migrated, which is safe because of the N/N+1 compat rule (ship compat fallback in
release N, flip in N+1 — the `.agents/memory-project` marker pattern).

**Release cut:** `release.sh` = guards → CHANGELOG finalize → annotated tag + push.
Manual/orchestrator-only (tag-push is the publish act; never an executor). GitHub
Actions later adds only a trigger on the tag, not a second code path.

**Alternatives rejected** (full record in the brainstorm doc §2):
- *Zip overlay in place* — no stale-file deletion, clobbers local edits, no rollback.
- *Zip + `.engine/<ver>/` + `current` symlink* — sound, but solves artifact-
  cleanliness/no-git distribution, which don't exist for the in-scope consumers
  (all the user's own authed instances); would cost a templates refactor, path-ref
  rewrites, leak-guard, and a bootstrap chicken-and-egg.
- *Separate engine/data roots* — forces data migration everywhere; YAGNI.
- *Zip for external users* — deferred, untracked (brainstorm doc §7 holds the facts:
  allowlist + leak-guard build, public-repo/history-scrub question, graduate-to-git
  upgrade path).

## Decisions (locked)

- **First tag: `v1.0.0`** — system is stable and in daily use.
- **Consumer checkout state: detached HEAD** at the tag; consumer instances never
  commit (engine commits happen only in the dev checkout).
- **Applied-version marker: gitignored `.applied-version` at the tree root** —
  machine-written, so not in user-owned `config.local.sh`.
- **Semver rule** (goes in `UPGRADING.md`): MAJOR = breaks an instance without a
  migration, or incompatibly changes the `MEMORY_DIR`/marker/manifest contracts;
  MINOR = new features, new harness, additive manifest keys, N-1-compatible
  migrations; PATCH = fixes.
- **`--to` is ephemeral**; a standing dogfood requires the explicit channel flip.
- **Migrations are forward-only**; no down-migrations.
- **`migrate-marker.sh` is not retroactively converted** — it stays as the
  historical example; the `migrations/` dir starts empty (with a README stub).

## Phases

- [x] **Phase 1 — Channel + `--to` in `sync-system.sh`.** `AI_MEMORY_CHANNEL`
      resolution (source `config.local.sh` via `_lib.sh`; default `release`… but
      keep the dev checkout's behavior: `dev` = today's ff-pull path unchanged);
      latest-tag discovery (bash-3.2-safe semver sort — verify `sort -V` on target
      macOS, else a compare helper); `--to <ref>`; dirty guard; shared tail
      (checkout → \[migrations placeholder\] → `install.sh`). Preserve existing
      flags (`--dry-run`, `--no-pull`, `--update`). Tests in
      `scripts/tests/test_sync_channels.sh` (fixture repo with tags).
- [x] **Phase 2 — Migration runner + `.applied-version`.** Runner helper (invoked
      from the shared tail), `migrations/` dir + README, marker read/write, semver
      compare, ordering, idempotency, downgrade no-op. Gitignore the marker. Tests.
- [x] **Phase 3 — `release.sh`.** Guards (dirty/branch/tests/tag-exists/version-
      monotonic), CHANGELOG section finalize (drafted from `git log v<prev>..HEAD`),
      annotated tag + push. Tests for every guard refusal (tag/push mocked or
      dry-run flag).
- [x] **Phase 4 — Docs.** Seed `CHANGELOG.md` + `UPGRADING.md` (standing rules +
      semver rule); update `docs/scripts.md`, install/sync docs, README (channel
      table: dev machine / dogfood / stable); note the deferred zip thread.
- [x] **Phase 5 — Cut `v1.0.0` end-to-end.** Run `release.sh 1.0.0` (orchestrator
      runs the tag-push step), flip one real consumer instance to the release
      channel, verify sync + `git describe`, then dogfood-test `--to main` +
      snap-back on that instance.

## Outcome (2026-07-08)

Shipped across PRs #40–#46, in one day. Two tags cut: `v1.0.0`, then `v1.1.0`.

- **#40** channel + `--to`; **#41** migration runner + `.applied-version`;
  **#42** `release.sh`; **#43** CHANGELOG/UPGRADING + the enforced per-version test;
  **#44** `--cleanup=verbatim` (tag messages were silently losing every `#` line);
  **#45** untrack `identity.md`; **#46** conversion runbook + stale-doc corrections.
- `v1.0.0` was retagged after #44 restored its stripped headings.
- **`v1.0.0` is a trap tag** — it predates #45, so checking it out silently overwrites a
  personalised `identity.md`. `v1.1.0` is the first consumer-safe tag. Warned in
  `UPGRADING.md` and `/sync-system`.
- Phase 5b done: a real consumer instance was flipped to the release channel.

What the validator caught that green tests did not: `--to` stranding dev-channel
instances on a detached HEAD; a hardcoded `main` fallback; duplicate migration versions
making a failed migration unresumable; a producer failure swallowed inside
`while ... < <(...)`; and a 4-step release mutation with no recovery. What *nothing*
caught until it shipped: `git tag -a -m` stripping every `#` line — 107 assertions
verified a tag was created, none verified what it said.

## Risks / open questions

- **`sort -V` availability on macOS bash-3.2 environments** — verify early in
  Phase 1; fallback is a small semver-compare function (needed by the runner
  anyway).
- **Detached-HEAD ergonomics** on consumer instances: `git status` noise, and a
  future accidental commit would be orphaned — acceptable since consumers never
  commit; revisit (local `release` branch) only if it bites.
- **The dev checkout must never be auto-flipped to a tag** — it has local channel
  `dev` semantics only if `config.local.sh` says so; Phase 1 must make the default
  safe for it (e.g. this instance sets `AI_MEMORY_CHANNEL=dev` before the default
  flips to `release`).
- **First real migration is hypothetical** — the runner ships with an empty
  `migrations/`; its contract is only proven by tests until a real migration lands.
- Deferred entirely: GitHub Actions on-tag Release entry; zip/external users
  (brainstorm doc §7).
