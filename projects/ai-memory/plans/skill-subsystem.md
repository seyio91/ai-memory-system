---
plan: skill-subsystem
status: draft
created: 2026-06-30
owner: claude (orchestrator)
---

# Plan — Skill subsystem: tier schema, validation, boundary enforcement, creator/installer, self-rating

## Goal
Generalize the conventions `renovate-manager` already implements by hand — a declared write-boundary plus per-skill memory — into a shared, enforced subsystem every skill inherits. Add a neutral `metadata.tier` field, a static validator, an automatic post-run boundary check, a creator and an installer/intake pipeline, and a first-party-only self-rating loop. Enforcement stays harness-agnostic: no `allowed-tools`; safety rests on execpolicy (destructive floor) + the git-diff boundary check (tier) + the Validator (correctness). Source of decisions: `wikis/pos-adoption-backlog.md` items #4, #5, #6, #10, #11, #12, #13.

## Success criteria
- Every skill under `skills/*/SKILL.md` declares `metadata.tier` ∈ {`target-read-only`, `target-write`}, classified correctly (review/analyze skills read-only; generators write).
- `scripts/validate-skills.sh` exists, runs in <5s over the store, exits non-zero on any failure, and checks: SKILL.md present, valid frontmatter, required fields, `tier` is a valid value, file-size flag, no unresolved `{{PLACEHOLDER}}`. No `memory_store` check.
- A post-run boundary check rejects a `target-read-only` skill run that leaves the target repo dirty, or whose memory-repo diff touches anything outside `skills/<self>/` (i.e. `projects/`, `working.md`, `index.md`, or another skill's dir). Verified with a deliberate-violation fixture.
- A skill creator scaffolds a new skill to the schema (frontmatter incl. `tier`, and for first-party workflow skills the self-rating block) and ends by passing `validate-skills.sh`.
- A skill installer normalizes an existing/remote skill into the schema, validates, places it in `skills/<name>/`, and links via the existing `link-skills.sh`/`sync-project-skills.sh`. It does **not** inject self-rating into imported skills by default.
- The self-rating block is applied to first-party workflow skills only (`renovate-manager`, `observability-check`, `fiter-infrastructure-analyzer`, `brainstorming`); reference packs and imported skills are untouched. Aggregation over `skills/*/` produces a per-skill score summary.
- README + `identity.md` document the `tier` field, the three write zones, and the own-folder rule.
- All scripts are macOS bash-3.2 compatible with dependency-free tests under `scripts/tests/`.

## Design
- **Tier is a coarse label, not a tool array.** A tool list would be `allowed-tools` cosplay — Claude-only, unenforced. The neutral label is enforced by *us*, identically for Claude and Codex. (Rejected: `allowed-tools`, `metadata.tools: [...]`.)
- **No `memory_store` field.** The write rule is universal and implicit: a skill may write anywhere under its own `skills/<name>/` folder at any time, regardless of tier. So there is no declared sub-path to validate or keep in sync. (Rejected after initial inclusion — would just go stale.)
- **Three write zones:** target tree (tier-gated) · the skill's own `skills/<self>/` folder (always writable) · everything else (system memory + other skills' dirs, off-limits).
- **Enforcement = two git diffs, post-run.** Harness-agnostic, near-zero cost, detective-not-preventive. Sits under execpolicy (which prevents the destructive class). Trade-off accepted: a stray non-destructive write is caught after the fact and is git-recoverable.
- **Automatic per-run for read-only skills** via a lightweight dedicated check — not the full Validator, which stays reserved for correctness on state-mutating work.
- **`renovate-manager` is the reference implementation** — the subsystem lifts its hand-rolled convention into the default.
- **Self-rating is first-party only.** Imported/remote skills get the block only on explicit request, and then as a demarcated appended section (fork-safe across re-install). Different axis from the Validator (skill friction, not output correctness).
- **Partials (#5) are minimal** — a mechanism for the one injectable block (self-rating), not a general template engine. Don't build full templating (POS's own lesson: not before real duplication hurts).
- **Self-rating loop membership is marker-derived, not a static list.** A skill is in the loop iff its `SKILL.md` carries the block; first injection is a deliberate `--force` act (auto for `new-skill --kind workflow`). This was a hardcoded `FIRST_PARTY_SKILLS` list in v1 — replaced because the list drifted (a new workflow skill got the block but never joined the list). (Rejected: hand-maintained roster.)
- **#11 enforcement seam (settled via brainstorm, Approach A).** There is **no process boundary around an in-session Claude skill-run** (a skill is the model following markdown + calling Edit/Bash; the Skill-tool call loads instructions, it doesn't bound the effects). The executor path **is** bounded (`codex-mem.sh --executor` is a subprocess). So the seam is **a git checkpoint + a trigger**, not a wrapper — split into **one shared check + two harness-native triggers**:
  - **Shared check:** `scripts/skill-boundary-check.sh` (bash-3.2) — the *single* enforcement implementation. Inputs: target-repo path, memory-repo path, baseline refs, skill name → two git diffs → non-zero + report on violation.
  - **Executor trigger (Codex):** `codex-mem.sh` records the baseline around `codex exec` and runs the check after. Bounded, automatic.
  - **In-session trigger (Claude):** `PostToolUse` on the Skill tool writes a per-session marker (baseline git SHAs + the skill's `tier` from frontmatter) when a read-only skill loads; the **`Stop` hook** runs the check against that marker at turn-end, reports, and clears it. Uses the only reliable end-of-work event Claude exposes.
  - **Split enforcement (different false-positive profiles per half):** **target-repo-clean** is the universal hard line — enforced in-session *and* on executor. **memory-repo-confined-to-`skills/<self>/`** is enforced *fully* on the executor path (isolated subprocess, must not touch memory) but *narrowed in-session* to the always-wrong subset — **writes to *other* skills' dirs** — because the orchestrator legitimately co-edits `memory.md`/`todo.md`/`plans/` in the same turn; the rest of memory-confinement leans on the executor path + Validator.
  - **B is the documented MVP fallback:** if the Claude hook wiring proves fiddly, ship executor-side automatic first and add the in-session Stop trigger second.

## Decisions (locked)
- Harness-agnostic enforcement; no `allowed-tools`.
- `metadata.tier` single field; values `target-read-only` | `target-write`.
- Own-folder write rule; no `memory_store` declaration.
- Boundary check automatic per-run for read-only skills; layered under execpolicy.
- #11 seam = Approach A: one shared `skill-boundary-check.sh` + two triggers (Codex via `codex-mem.sh`; Claude via Skill-tool `PostToolUse` baseline marker + `Stop` hook). Target-tree check universal; memory-confinement full on executor, narrowed to other-skills'-dirs in-session. B = MVP fallback ordering.
- Self-rating: first-party workflow skills only; remote on request, demarcated block. **Membership marker-derived** (`skills_with_partial`), not a static list.
- Skill memory per-skill, co-located; aggregation is a `skills/*/` glob (not central).

## Phases
### Phase 1 — Tier schema (#10)
- Add `metadata.tier` to all 13 skills; classify each (read-only vs write).
- Document the field, three zones, and own-folder rule in README + `identity.md`.

### Phase 2 — Validator (#4)
- Write `scripts/validate-skills.sh` (checks above) + bash-3.2 tests. Wire into the test suite.

### Phase 3 — Boundary check (#11) — seam settled (Approach A)
- [x] **Core engine** `scripts/skill-boundary-check.sh` — `snapshot`/`check` subcommands; target-tree + memory-confinement halves; `full`/`others-only` scope; 14-assertion test.
- [x] **Claude in-session trigger** (the priority path — read-only skills run in-session): `claude/hooks/skill_boundary_marker.sh` (PostToolUse:Skill, arms read-only skills + captures memory baseline) + `claude/hooks/skill_boundary_check.sh` (Stop, checks `others-only` memory + registered target, exit 2 on violation, clears markers). Wired in `claude/settings.hooks.json`. 11-assertion hook test.
- [x] **Target-registration convention:** a read-only skill that resolves a target drops `skills/<skill>/.boundary-target` = "<repo-path>\n<baseline-file>" (writing its own folder, which it may). Stop hook checks it if present. (renovate-manager to adopt.)
- [ ] **Codex executor trigger — DEFERRED** (decision: Codex mostly runs target-write work, where the check is moot; read-only enforcement matters on the in-session path). Revisit if read-only skills get delegated to Codex; needs `codex-mem.sh` exec→run+check + a `--tier` delegation flag.
- [ ] **Live verification** (can't be unit-tested): confirm PostToolUse:Skill + Stop fire as expected in a real session.

### Phase 4 — Creator + Installer (#12, #13) — DONE
- [x] **Creator** `scripts/new-skill.sh` — scaffolds `skills/<name>/SKILL.md` to schema (name, description, `metadata.tier`, optional `kind`, compatibility); read-only vs write body guidance; validates the new skill; `--link`. 
- [x] **Installer** `scripts/install-skill.sh` — intakes a dir/SKILL.md → copies under `skills/<name>/` (preserves `references/`) → normalizes frontmatter to set `metadata.tier` (python3 line-rewrite; `--tier` required, never guessed) → validates → `--link`. **No self-rating injection** (imported skills left as-is). 27-assertion test.

### Phase 5 — Self-rating + partials (#6, #5) — DONE
- [x] **Partial source + injector** — `scripts/partials/self-rating.md` (canonical block, stored once, outside the skills tree so `validate-skills` is untouched) + `scripts/apply-partial.sh` (marker-delimited splice/re-sync; idempotent; first injection needs `--force`, re-sync doesn't; `--all` re-syncs carriers).
- [x] **Marker-derived membership** — `_lib.sh:skills_with_partial` derives the loop set from block presence (no static first-party list → no drift). Both `apply-partial --all` and `skill-ratings --all` read it.
- [x] **Aggregator** — `scripts/skill-ratings.sh` (per-skill latest/avg/count from `skills/*/self-rating.md`; `LC_ALL=C` pins the decimal point; `--all` lists in-loop skills with no ratings yet).
- [x] **Creator integration** — `new-skill.sh --kind workflow` injects the block via `apply-partial --force`. `install-skill.sh` still does NOT inject (imported skills clean).
- [x] **Applied to the four** first-party workflow skills (renovate-manager, observability-check, fiter-infrastructure-analyzer, brainstorming); block is on-request-only. Docs in README + identity.md. 32-assertion test + creator-test additions; full suite green.

## Risks / open questions
- ~~Boundary-check seam (#11)~~ — **settled + built** (Approach A): shared `skill-boundary-check.sh` + Claude PostToolUse/Stop triggers. Codex trigger deferred. See `## Design` + Phase 3.
- ~~Multi-turn marker-clear rule~~ — **v1 decided:** marker armed at invocation, checked + cleared at the next Stop = **single-turn coverage**. A read-only skill spanning a user question is only checked for its first turn — accepted limitation; v2 can move to per-turn baselines (UserPromptSubmit) + persistent markers. Documented in the Stop hook header.
- ~~SubagentStop~~ — **v1 decided:** `renovate-manager`'s read-only subagent fan-out is covered by the parent `Stop` check (memory writes land in the shared tree regardless of which subagent made them). Per-subagent `SubagentStop` wiring deferred unless subagents need independent target checks.
- **Live verification pending:** PostToolUse:Skill + Stop hook behavior (and exit-2 surfacing) can't be unit-tested — verify in a real session.
- **Self-rating signal thinness:** only four skills qualify; the aggregate may be low-volume. Acceptable — it's additive, not a quality gate.
- Phase ordering assumes #10 lands first (everything keys off the label). #5 is intentionally last and minimal.
