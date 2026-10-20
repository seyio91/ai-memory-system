---
plan: add-a-per-release-prune-memory-pass
status: draft
created: 2026-10-10
owner: claude (orchestrator)
task_provider: local
task_ref: add-a-per-release-prune-memory-pass
---

# Plan — Per-release `/prune-memory` pass

## Goal

Add a `/prune-memory` command, nudged at SessionStart whenever the Claude Code version or model changes. It re-tests memory rules tagged `[workaround: <tool> <version>]` and offers to delete each one that no longer binds or that a hook already enforces. It also flags over-budget memory files and runs `/lint-memory --audit` on projects whose memory changed since their last audit.

## Success criteria

- Lint rule 19 warns on a `[workaround: …]` tag with no version, and stays silent on a well-formed tag. A fixture test covers both cases, and a mutation that disables the rule fails the test.
- `scripts/prune-memory.sh --inventory` lists every tag in identity, doctrine core and overlay, `domain/*.md` and every project `memory.md`, with file:line, tool and version. The fixture count matches `grep -c`.
- `--budget` reports the same over-budget files as `check-memory-size.sh` and the lint size rules. No budget logic is duplicated.
- `--stale-audits` lists exactly the projects whose `memory.md` is newer than their latest `audits/audit-*.md`, plus projects never audited. Fixtures cover fresh, stale and never-audited projects.
- `--stamp` writes the current harness version (plus the model id if the P3 spike finds it) to gitignored instance state. The SessionStart payload carries one nudge line only when the current values differ from the stamp; tests cover both the differ case and the match case.
- `agents/pruner.md` runs read-only via `executor.sh --brief pruner`. It returns one verdict per tag (Binds / Gone / Enforced / Unverifiable), each with evidence. An Enforced verdict cites file:line of the covering hook, deny-list entry or lint rule.
- `/prune-memory` writes `projects/ai-memory/audits/prune-<date>.md` with a workaround section, a budget section and an audits section. It never edits memory before you confirm. Each confirmed deletion goes the right route: `projects/**` and gitignored `domain/` changes are committed to main, while tracked doctrine and domain changes go through a `git-cli ship` PR. It stamps last.
- Backfill: every existing workaround in prose across all layers either carries a confirmed tag or is listed as rejected in the backfill record.
- `bash scripts/run-tests.sh` passes in full. `docs/` covers the command, the tag syntax and the nudge. A `changelog.d/` feature fragment exists.
- One live `/prune-memory` run completes end to end and produces a report.

## Design

**Chosen: a deterministic script plus a thin command.**
- `scripts/prune-memory.sh` owns everything testable: tag inventory, budget, picking stale projects for audit, and the version stamp.
- `/prune-memory` (`harnesses/claude/commands/prune-memory.md`) orchestrates the agent work in this order:
  1. inventory;
  2. pruner fan-out, one invocation per tag;
  3. budget;
  4. stale-audit fan-out through the existing `/lint-memory --audit` A1–A5;
  5. write the report;
  6. confirm each deletion;
  7. stamp.
- **Tag syntax:** `[workaround: <tool> <version>]` inline on the rule, e.g. `[workaround: claude-code 2.3.1]` or `[workaround: model claude-opus-5-5]`. The version is mandatory, following the existing "date and version every workaround" learning in `domain/agent-tooling.md`.
- **Re-test:** the pruner re-runs the original failing case at its original scale, and greps hooks, `scripts/deny-list*.txt` and lint rules for a covering mechanism. Untagged doctrine and identity rules are checked for Enforced only, never for Gone.
- **Trigger:** manual. The SessionStart hook compares the current harness version and model with the stamp and adds one nudge line. Claude-only at first.
- **D11 holds:** the sweep and its agents never edit memory. Deletions happen only through your confirmation in the orchestrator.

Rejected alternatives:
- `/lint-memory --prune` mode: lint-memory already has two modes, and this is cross-project orchestration.
- A command written only in prose: tag parsing, staleness and stamp logic would be untestable.
- Classifying untagged rules with a model at every run: nondeterministic, and it mixes backfill into every pass forever.
- A central workaround registry file: it drifts from the rule text.
- Re-checking by version comparison only: proves nothing.
- A repro command embedded in each tag: heavy to author, and many cases aren't a single command.
- Auto-deleting: breaks D11, and is risky for tracked doctrine.
- Auditing all 19 projects on every pass: cost with no new signal on unchanged memory.

## Decisions (locked)

- Trigger: manual, with a SessionStart nudge on a version or model change.
- Workarounds are identified by inline versioned tags, and lint requires the version.
- Action: report, then confirm each deletion, routed by file type.
- Scope: all memory layers (identity, doctrine core and overlay, domain, every project `memory.md`).
- Audit fan-out: stale projects only.
- Re-test: an agent re-reproduces each case. Hook enforcement is detected by the agent and cited with file:line.
- A one-time backfill phase tags the existing workaround prose.

## Phases

### Phase 1 — Tag syntax + lint rule 19
Define `[workaround: <tool> <version>]` in `docs/` (content contract). Add lint rule 19 to `scripts/lint-memory.sh`: a tag with no version produces a WARN.
**Depends:** none
**Verify:** fixture tests for the bad and good cases pass, and a mutation that disables rule 19 fails them. `lint-memory.sh` on the live tree gives no new WARNs beyond the rule-19 hits it is meant to find.

### Phase 2 — `scripts/prune-memory.sh` deterministic modes
Add `--inventory`, `--budget` (delegating to `check-memory-size.sh` and the lint size rules), `--stale-audits` and `--stamp`. bash 3.2 compatible and shellcheck clean.
**Depends:** P1
**Verify:** hermetic fixture tests for every mode pass, the inventory count matches `grep -c`, and stale-audit fixtures cover the fresh, stale and never-audited cases.

### Phase 3 — Version nudge at SessionStart (spike first)
Spike: does Claude's SessionStart hook input expose the model id? Record the answer. Then add the nudge line to the SessionStart payload when the version or model differs from the stamp.
**Depends:** P2
**Verify:** the spike result is recorded in Risks. Tests show the nudge appears when the values differ, is absent when they match, and is absent when no stamp exists. The payload tail (`working`) is still intact under the ~10,000-char cap.

### Phase 4 — `agents/pruner.md` read-only brief
Model it on `agents/auditor.md`: one verdict per tag (Binds / Gone / Enforced / Unverifiable), an evidence rule, re-tests at the original scale, an Enforced-only check for untagged rules, and the deny-list. Register it for `executor.sh --brief pruner` and link it via `/sync-system`.
**Depends:** P1
**Verify:** `executor.sh --brief pruner` resolves. A dry run against a fixture tag set returns a verdict with evidence for every tag. The agent has no write tools.

### Phase 5 — `/prune-memory` command + docs
Write the command flow: inventory, pruner fan-out, budget, stale audits, then the report at `projects/ai-memory/audits/prune-<date>.md`. Then confirm each deletion with routing by file type, and stamp last. Update `docs/`, the command reference and `changelog.d/prune-memory.feature.md`.
**Depends:** P2, P4
**Verify:** `run-tests.sh` passes in full (including doc-vs-code). The command text names all seven steps in order and the routing table. Nothing in the flow edits memory before you confirm.

### Phase 6 — One-time backfill of existing workaround prose
An agent proposes tags, with versions taken from dates or git blame, for workaround prose across all layers. You confirm each one. Tracked doctrine and domain tags go through a PR; gitignored files are edited in place. Rejected candidates are listed in the plan's Risks.
**Depends:** P1
**Verify:** `prune-memory.sh --inventory` lists every confirmed tag, rule 19 is clean, and every candidate is either tagged or recorded as rejected.

### Phase 7 — First live run
Run `/prune-memory` end to end on this instance.
**Depends:** P3, P5, P6
**Verify:** the report exists with all three sections. Each confirmed deletion landed on its correct route. The stamp is written, and the next SessionStart shows no nudge.

## Risks / open questions

- **The model id may not be in the SessionStart hook input.** The P3 spike settles it. Fallback: stamp and compare the Claude Code version only.
- Nudges for non-Claude harnesses (codex, copilot, antigravity) are deferred, and so is CLI-plane pruner support (codex has no network, copilot has no shell; the same limits as the audit).
- Re-test cost grows with the tag count, because each tag is one agent invocation. Revisit batching if the inventory goes past ~20 tags.
- Some workarounds can't be reproduced (they're timing-dependent, or the old version is unavailable). They become Unverifiable and are kept, never deleted.
- Assumed, and to be confirmed during P2/P5: the stamp lives in gitignored instance state, and the report lives under `projects/ai-memory/audits/`.
