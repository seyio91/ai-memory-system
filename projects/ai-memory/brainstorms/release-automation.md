---
doc: release-automation
kind: brainstorm-input
status: open (investigation only — no code, no plan)
created: 2026-07-08
owner: claude (orchestrator)
---

# Brainstorm input — Automate the release pipeline (changelog fragments + GitHub Actions)

**Status:** investigation, 2026-07-08. No code written, no plan filed. Backlog task captured
against this doc. When a plan eventually ships from it, archive to `archive/wikis/`.

**Question asked:** can the model own the CHANGELOG and the upgrade guide? Should a skill exist
for it? Long-term goal is a GitHub Action owning the release process, changelog, and upgrade
guide, with changelog/upgrade drafted locally during development.

**Repo state at time of writing:** no `.github/` directory at all — greenfield CI.
`migrations/` holds only its `README.md`. Zero tags cut.

---

## 1. Short answer

Yes for prose, no for the publish act, and a qualified **no for *inventing* upgrade steps**.

But the question contains an assumption worth rejecting first.

## 2. The assumption to reject: release-time summarization

`release.sh` (Phase 3, PR #42) drafts the changelog **at release time, from `git log --oneline`**.
That is why its bullets carry commit shas — there is nothing better to say. "Model writes the
changelog in CI" inherits the same flaw.

By release time the *why* is gone. You have 40 commit subjects and a model reconstructing intent
from them. That is precisely where hallucinated release notes come from.

**The right moment is when the change is made, while the reasoning is live.** Which is exactly what
"changelog/upgrade can be drafted locally when developing" is reaching for.

## 3. Design: news fragments (towncrier / changesets pattern)

Each PR drops a fragment file:

```
changelog.d/
  42.feature.md      release.sh: guarded, resumable tag cuts
  43.breaking.md     manifest key `hooks_dir` renamed to `hooks_target`
  43.upgrade.md      Run migrations/1.4.0-hooks-rename.sh; re-register hooks with install.sh
```

Kinds: `breaking` | `feature` | `fix` | `upgrade`.

Three payoffs, only one of which is about quality:

1. **No merge conflicts.** Every concurrent PR editing `CHANGELOG.md`'s `## [Unreleased]` section
   collides. Fragments never do. PRs #40 / #41 / #42 would have conflicted three ways.
2. **Assembly becomes deterministic.** Release-time changelog generation is `cat` + sort, not
   inference. Nothing left to hallucinate.
3. **The fragment is reviewed in the PR that caused it**, with full context, by a human.

## 4. Ownership split

| Step | Owner | Why |
|---|---|---|
| Write the fragment for a PR | **Model** | It just made the change; it holds the reasoning. |
| Describe what a migration does | **Model** | Describing an artifact that already exists. |
| *Invent* upgrade steps | **Never the model** | See the hard line below. |
| Assemble fragments → CHANGELOG section | Script | `cat` + sort. Deterministic. |
| Enforce "migration ⇒ upgrade note exists" | **Test** | Not model discipline. |
| Tag, push, publish GH Release | Action, gated on a human merge | Publication is a human gate. |

### The hard line

An upgrade guide is **executed by a human against a real tree**. A subtly-wrong migration step is
worse than no guide at all. So the model may only ever **describe a migration script that already
exists** — never synthesize steps from a diff.

`migrations/<semver>-<slug>.sh` is the source of truth; `UPGRADING.md` is its human-readable
narration. The artifact constrains the model, which is what makes the job safe.

### The invariant is mechanically checkable

> every `migrations/<v>-*.sh` has a matching `## <v>` section in `UPGRADING.md`

So it belongs in the test suite, not in a prompt. This is the project's own recorded
**soft-vs-hard enforcement principle** (see `memory.md`): model-facing instructions are advisory;
the deterministic gates are tests, hooks, and execpolicy. **The model drafts; the suite enforces.**

## 5. Do we need a skill?

**Two candidates. Build neither — yet.**

- **`changelog-fragment` skill.** Probably unnecessary. The PR bodies already produced for #40 /
  #41 / #42 are better changelog copy than any `git log` summary. The fragment is a **by-product of
  the existing PR step**, not a new capability. Add "write `changelog.d/<pr>.<kind>.md`" to the
  plan/PR flow and you have 90% of it with zero new machinery. Promote to a skill only if the
  fragment format needs re-explaining.
- **`upgrade-note` skill.** The valuable parts are the **trigger** ("you just added a migration, now
  write its note") and the **check** — not prose generation. The trigger is a test failure. The note
  is three sentences. A skill would be ceremony around a `grep`.

**The honest test:** a skill earns its keep when it encodes knowledge that is *hard to re-derive*.
"Write a changelog bullet" isn't. "Here is exactly how a migration must describe itself, and the
N/N+1 compat rule it must respect" *is* — and that already lives in `migrations/README.md`, which
the model reads.

## 6. End-state pipeline

```
PR merged to main
  └─ Action: assemble changelog.d/* → open/update a "Release vX.Y.Z" PR
       (CHANGELOG section + UPGRADING sections + version bump; deletes the fragments)

You merge the release PR          ← the human gate. Merging IS the authorization.
  └─ Action on merge: bash scripts/release.sh <version> --ci
       └─ tag + push + GitHub Release entry
```

Two properties worth noticing:

1. **`release.sh` stays the single implementation.** The Action adds a *trigger*, not a second code
   path — exactly what `plans/versioned-release-channel.md` §Design and
   `archive/wikis/versioned-release-packaging.md` §3.5 already commit to. It needs a `--ci` mode; the
   guards otherwise hold as-is.
2. **The `AI_MEMORY_ROLE` executor gate does not block CI.** `release.sh` (Phase 3) refuses when
   that var is set; `executor.sh` exports it on every delegated run. An Action is not an executor,
   so it passes — while a delegated Codex/Claude executor still cannot cut a release. The gate
   discriminates exactly the way you'd want.

### Keep the model off the critical path in CI

A model inside the release Action means an API key in CI, nondeterminism in a publish step, and a
release that can be blocked by a provider outage. Since the fragments are already committed prose,
CI assembly is pure text manipulation. Model-in-CI stays **optional polish** (e.g. a prettier GH
Release summary), never load-bearing.

## 7. Open questions

- **Fragment ↔ PR-body duplication.** Write the fragment first and have the PR body quote it, or
  vice versa? Duplication invites drift.
- **Who chooses the version number?** Fragment kinds (`breaking`/`feature`/`fix`) can **compute**
  the semver bump — how changesets works. That would let the release PR title itself, and would
  implement the semver rule of thumb already locked in `plans/versioned-release-channel.md` in
  *code* rather than prose.
- **`v0.x` vs `v1.0.0` interacts with this.** Under `0.x`, "breaking" doesn't bump major, so the
  computed-bump logic differs. The plan currently locks `v1.0.0`.
- **Private repo + Actions** works fine, but `GITHUB_TOKEN` pushing a tag will **not** retrigger a
  tag-triggered workflow — a classic footgun. Needs a PAT or `workflow_dispatch`.

## 8. Relationship to the in-flight plan

`plans/versioned-release-channel.md` (task `396f6850-c619-8132-bf77-e09e4bd2757e`) — Phases 1–3
shipped (PRs #40 / #41 / #42). Phase 4 (CHANGELOG.md + UPGRADING.md prose) and Phase 5 (cut
`v1.0.0`) are pending.

This supersedes nothing in that plan, but it **changes what Phase 4's docs should look like** if
picked up first. And if fragments ship, `release.sh`'s `git log` drafting — and its sha-carrying
bullets — becomes dead code.
