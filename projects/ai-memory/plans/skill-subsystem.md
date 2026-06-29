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
- Self-rating: first-party workflow skills only; remote on request, demarcated block.
- Skill memory per-skill, co-located; aggregation is a `skills/*/` glob (not central).

## Phases
### Phase 1 — Tier schema (#10)
- Add `metadata.tier` to all 13 skills; classify each (read-only vs write).
- Document the field, three zones, and own-folder rule in README + `identity.md`.

### Phase 2 — Validator (#4)
- Write `scripts/validate-skills.sh` (checks above) + bash-3.2 tests. Wire into the test suite.

### Phase 3 — Boundary check (#11) — seam settled (Approach A)
- Build the shared `scripts/skill-boundary-check.sh` (two git diffs; split enforcement: target-tree universal, memory-confinement full on executor / other-skills'-dirs in-session) + bash-3.2 tests.
- Executor trigger: wire baseline-capture + post-run check into `codex-mem.sh`.
- In-session trigger: `PostToolUse`-on-Skill marker (baseline + tier) + `Stop` hook that runs the check and clears the marker.
- Violation fixture proving it fails closed on both paths.
- (MVP fallback B: land the executor trigger first; in-session Stop trigger second.)

### Phase 4 — Creator + Installer (#12, #13)
- Creator: scaffold-to-schema, runs validate at the end.
- Installer: intake/normalize an existing/remote skill → validate → place → link (no self-rating injection by default).

### Phase 5 — Self-rating + partials (#6, #5)
- Minimal partial mechanism for the self-rating block.
- Apply to the four first-party workflow skills; aggregation script over `skills/*/`.

## Risks / open questions
- ~~Boundary-check seam (#11)~~ — **settled** (brainstorm, Approach A): one shared `skill-boundary-check.sh` + two harness-native triggers. See `## Design`.
- **Multi-turn skills + Stop-hook granularity:** a read-only skill that spans turns (user answers a mid-skill question) leaves the marker active; the Stop hook re-checks each turn until the marker clears. Errs toward over-checking (safe) but the marker-clear condition needs a concrete rule (skill completion signal vs. session end).
- **Subagent path:** `renovate-manager` fans out to read-only *subagents* (Agent tool); `SubagentStop` is a cleaner per-subagent seam than `Stop`. Decide in Phase 3 whether to also wire `SubagentStop` or let the parent `Stop` check cover them.
- **Self-rating signal thinness:** only four skills qualify; the aggregate may be low-volume. Acceptable — it's additive, not a quality gate.
- Phase ordering assumes #10 lands first (everything keys off the label). #5 is intentionally last and minimal.
