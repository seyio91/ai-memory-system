---
plan: re-runnable-memory-audit
status: done
completed: 2026-10-10
created: 2026-10-09
owner: claude (orchestrator)
task_provider: local
task_ref: add-the-twice-rule-and-a-per-release-prune-pass-for-memory
---

# Plan — Re-runnable per-claim memory audit

## Goal

Make the trim validators' check re-runnable: `/lint-memory --audit <project>` has a read-only, cross-model agent verify every claim in a project's `memory.md` against the repo and APIs with recorded evidence, and writes a dated report. `lint-memory.sh` gains two precise checks (exact cross-file duplicate lines, `NEEDS REVIEW`/`TODO` markers).

## Success criteria

- [x] `agents/auditor.md` exists and is the single source of the audit brief: verdict vocabulary, the per-claim evidence rule, and the three trim failure types as named checks.
- [x] `/lint-memory --audit <project>` resolves the project's repo, dispatches the validate role with the auditor brief, and writes `audit-YYYY-MM-DD.md` in the agreed location without editing any memory file.
- [x] Every claim in `memory.md` appears in the report with exactly one verdict (Wrong / Stale / Derivable / Move / Keep / Unverified) and, for every verdict except Unverified, the command(s) run and their result. A bullet is split when its facts could get different verdicts; descriptive glue needs no row of its own. A row whose evidence describes the command instead of quoting it meets this bar only if `/lint-memory --audit` step A4 flags it as weak evidence and the row still shows the deciding output. (Amended 2026-10-10, user-approved, after final-pass rounds 2–3: one verdict per bullet hid mixed bullets, and an LLM auditor does not quote every command.)
- [x] No Keep without evidence; a claim the agent could not reach (repo or read-only API) is Unverified.
- [x] Audit runs make only read-only calls: no file outside the report is written, and every API call is a GET.
- [x] `lint-memory.sh` WARNs on (a) an exact normalised line duplicated across project `memory.md` and `domain/*.md` files and (b) `NEEDS REVIEW` / `TODO` markers in those files; `_template` exempt. Each rule has a positive and a negative test fixture, and a mutation of each rule makes its test fail.
- [x] Live tree: every new WARN on the current memory tree is a real finding (or the rule is tightened until it is).
- [x] The audit report file does not trip lint (rule 9 or any other).
- [x] Full `run-tests.sh` green; `changelog.d` fragment; docs updated (`docs/scripts.md` / command docs as applicable).

## Design

**Chosen approach.** The audit is a brief plus a thin dispatcher:
- `agents/auditor.md` holds all audit logic, modelled on `agents/validator.md`:
  - **Unit:** one verdict per checkable claim in `memory.md`; a bullet is split when its facts could get different verdicts.
  - **Evidence:** every verdict except Unverified needs the command run (grep, ls, `git`, `find`, read-only TFC or GitHub GET) and its output.
  - **Named checks** from the 2026-10-09 trim lessons:
    - *False universal:* a claim about "every/all X" is checked against every X, not a sample.
    - *Direction:* a relationship (A tracks B, merge→apply) is confirmed in its direction.
    - *Cut needs a home:* Derivable or Move must name where the fact already lives.
  - **Derivable** is the promotion bar (PR #128) applied after the fact: true, but Claude could work it out from the code or repo docs.
  - Domain files are read only to classify Move and duplicate findings. They are not audited in this task.
- `/lint-memory --audit <project>` resolves `repo_path`, runs `scripts/executor.sh --role validate` (cross-model, read-only) with the brief, and writes the report. One project per run; all-projects is a loop the user starts.
- Lint gets only near-zero-false-positive checks. Fuzzy cases (paraphrased duplicates, PR#/SHA/version pins) stay with the audit agent, consistent with rule 7's narrow-by-design stance.

**Rejected.**
- *Rubric read-through:* the prose review that missed the trim defects.
- *Report + proposed diff:* puts editing into an audit; a trim acts on the report instead.
- *Parallel all-project fan-out:* 19 agents per run with cost hidden.
- *Explore role:* not decorrelated from the model that wrote the memory.
- *Broad lint regexes for PR#/SHA/pins:* noisy WARNs get ignored (rule 7).
- *Audit logic inline in `/lint-memory`:* `/prune-memory` (separate task) needs to reuse it.

**Split out (separate backlog tasks, 2026-10-09):**
- `add-a-per-release-prune-memory-pass`, which depends on this plan.
- `detect-and-track-repeated-claude-mistakes-during-a-run`, criterion (1) of the promotion bar.

The promotion bar itself shipped as PR #128.

## Decisions (locked)

- Per-claim evidence; Unverified is never Keep.
- Dated report file; the audit never edits memory.
- One project per run.
- Validate role; read-only TFC/GitHub GETs allowed.
- Single-sourced `agents/auditor.md`.
- Lint additions are precise-only, WARN level.

## Phases

### Phase 1 — Auditor brief + spike on one real project
Write `agents/auditor.md`. Hand-dispatch it through the validate role against one project whose memory has API-only claims (`tpe` or `network`). Record wall time and rough token cost, and settle the report location (see Risks).
**Verify:** the spike report gives every checkable claim of that project's `memory.md` one verdict; every non-Unverified verdict carries a command and its output, or is flagged by A4 as weak evidence (amended 2026-10-10, see Success criteria); nothing outside the report was written (`git status` clean in both repos); cost is recorded under Risks.

### Phase 2 — `/lint-memory --audit <project>` dispatcher
**Depends:** P1
Extend `commands/lint-memory.md` with the `--audit <project>` path: resolve `repo_path`, dispatch, write the report to the location P1 settled, and handle a missing or unresolvable repo with a clear error.
**Verify:** running it on a second project (not the P1 one) produces a dated report meeting the P1 bar; `lint-memory.sh` emits nothing for the report file; an unknown project name errors without dispatching.

### Phase 3 — Precise lint rules
Add two WARN rules to `scripts/lint-memory.sh`, with tests:
- an exact normalised duplicate line across project `memory.md` and `domain/*.md`;
- `NEEDS REVIEW` / `TODO` markers in those files.
**Verify:** new tests pass, with a positive and a negative fixture per rule; mutating each rule's match makes its test fail (mutation verified with `cmp`); on the live tree, every new WARN is reviewed and real.

### Phase 4 — Docs, changelog, ship
**Depends:** P2, P3
Add a `changelog.d` fragment, update `docs/scripts.md` and the command docs, run the full suite with signing off, then `git-cli ship`.
**Verify:** full `run-tests.sh` green (no NOT A FULL RUN banner); `check-docs` 0 findings; PR open.

## Risks / open questions

- **Report location: settled in P1 → `projects/<p>/audits/audit-YYYY-MM-DD.md`.** Not `investigations/`, to stay out of rule 9. Retention (`archive-cleanup`?) is still open.
- **P1 spike result (tpe, 2026-10-10):**
  - **Cost:** 36 claims, about 6 minutes, about 100k subagent tokens, 48 tool calls. Acceptable per project; running all 19 at once would be about 2M tokens.
  - **Findings:** 7 Wrong, 1 Stale, 17 Derivable, 2 Move, 9 Keep, 0 Unverified. This memory was trimmed and validated on 2026-10-09 and still had 7 Wrong claims, which supports per-claim evidence over a prose review.
  - **Brief fixes folded in:** scratch files go in a `mktemp` dir; no checkout or fetch, with ref dates recorded; loops run in bash, not zsh; Move vs Keep defined for cross-repo contrast notes.
  - **Spot-checks:** the orchestrator re-ran #4 and #17 and confirmed both Wrong verdicts.
  - **Follow-up:** acting on tpe's findings is a separate trim and is not part of this plan.
- **Exact-duplicate lint** may fire on shared boilerplate lines (e.g. standard pointers); P3's live-tree review tightens normalisation if so.
- **API credentials:** TFC/GitHub GETs depend on the user's tokens being available to the validate-role plane; otherwise those claims are Unverified (acceptable, but reduces value).
- **Initiative Target** `ai-memory/twice-and-prune` still describes the original bundled scope. Its status text, and Targets for the two split-out tasks, are a user-approved initiative edit; `/start` does not touch it.
- **Brief compliance varies (final-pass round 2, 2026-10-10).** The re-runs under the stricter brief were saved byte-for-byte from the agent transcripts with `jq`:
  - `network`: 30/30 rows open with a backticked command.
  - `tpe`: 30/35 do. Five rows describe the command instead of quoting it ("TFC workspaces API →", "python scan of …"). The rows still carry their output.
  - Mitigation: `/lint-memory --audit` step A4 now counts these rows and reports them as weak evidence, without editing the report.
  - Tooling can't fully enforce the evidence rule, because the agent is an LLM following a brief.
- **Accepted nits (final-pass round 3, 2026-10-10)** — deferred as known limits, not fixed:
  - Rule 17 misses a duplicate when a lone `-` line sits between, or when markers are nested (`- 1. `).
  - Rule 17's location list can include a repeat within the same file.
  - On the cli plane the deny-list is pasted twice (once by the caller, once by `executor.sh`). Harmless.
  - CLI validate planes limit the audit. Codex runs with the network off, so every API claim comes back Unverified. Copilot's validate face is view/grep/glob only, so A4 flags every row. The subagent plane, which is today's default, has neither limit.
  - `projects/*` is gitignored, so `git status` can't show a stray `memory.md` edit. P1 relied on mtimes for that.
- **Carried forward (final-pass round 4, PR-READY, 2026-10-10):**
  - Rule 18 misses `TODO...` and `TODO..`.
  - Rule 18 scans fenced code inside a blockquote (`> ```) and 4-space indented code as text, so it can warn falsely there.
  - Rule 17 doesn't skip setext (`===`) headings.
  - A4 skips rows with irregular spacing after the opening `|`.
  All are WARN-precision limits, and none fires on today's tree.
