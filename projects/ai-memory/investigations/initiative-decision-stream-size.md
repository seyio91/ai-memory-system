---
doc: initiative-decision-stream-size
kind: investigation
status: open
created: 2026-11-19
owner: claude (orchestrator)
task_ref: initiative-decision-stream-cut-its-size-and-read-cost
---

# Investigation — initiative decision stream: size and read cost

Follow-up to `initiative-now-view-surface-user-actions-and-blocking-decisions` (PR #157). That plan moved the stream below `## Targets` in vault-eks but left its size alone. Measured on the live `initiatives/vault-eks.md` on 2026-11-19.

## Goal of this investigation

Do not pick an approach up front. Several agents each explore and test one approach separately, on their own copy of vault-eks, against the same measures. The user and orchestrator then compare the results and agree on the best idea (or a combination). Only then does a plan get written.

## Measurements (baseline)

- The stream is 331 lines and 121,437 bytes, about 86% of the 600-line file.
- 96 decisions: 87 confirmed, 6 proposed, 3 superseded. 55 lines carry AMENDS/SUPERSEDES or forward pointers.
- Entry heads: median 885 characters, longest 4,501. The size problem is bytes per entry, not the number of entries.
- 229 continuation lines (evidence, unconfirmed, pointers).
- `legacy_through: D43` marks D1–D43 as legacy. 14 topics are declared and every decision has one.
- `/start` Step 1.5 tells a session to read the whole stream before the design gate: roughly 30k tokens each time.

## Who reads the stream today

- `scripts/initiative-render.sh` (Current rules, Open proposals, Decisions needed)
- `scripts/initiative-status.sh` (entry count for staleness, proposed summary)
- `scripts/lib/decision-stream.awk` (the grammar; shared by the two above and lint)
- `scripts/lint-memory.sh` (decision-stream rules)
- `scripts/hooks/memory_write_guard.sh`
- `commands/start.md`, `commands/checkpoint.md`, `commands/plan-done.md` (prose that tells a session to read or append)
- `migrations/1.7.0-decision-status-field.sh`, `migrations/3.0.0-initiative-format.sh`

All in-file readers stop at the next `## ` heading.

## Approaches to explore (one agent each)

1. **Short heads, detail below.** The head becomes one sentence stating the rule (for example a 300-character cap, like the status line). Rationale, history and "binds" lists move to continuation lines. Lint WARNs on long heads. Current rules could then show the head text. To test: rewrite a sample of vault-eks heads (include the 4,501-character one and a few median ones), check nothing is lost, measure how much shorter a head-only read is, and see what the grammar and lint need.

2. **Topic-filtered reader.** A command (or an `initiative-status.sh` mode) prints only the live decisions for given topics, and `/start` loads those instead of the whole stream. The file does not change. To test: build the reader, pick three real Targets, decide which topics each needs, and measure tokens loaded against the full read. Check whether a session misses a decision it needed (cross-topic decisions, AMENDS chains that cross topics).

3. **Archive the legacy block.** Move D1–D43 (or all confirmed entries older than some age) to a sibling file such as `initiatives/<slug>.decisions-archive.md`. To test: do it on a copy, then find out which readers break or lose ids (Current rules, the staleness count, lint pointer checks, plans that cite archived ids) and what it takes to make them read both files.

4. **Split the whole stream into its own file.** `initiatives/<slug>.decisions.md` holds the stream; the main file keeps Now, Targets and Current rules. To test: do it on a copy and list every reader, command and migration that must change. Check the stream-first rule and the Two-Path principle still hold, and what a migration for existing initiatives would look like.

An agent may report that its approach should be combined with another, or dropped.

## Shared measures (every agent reports all of these)

- Main-file size after the change: lines and bytes, and the stream's share.
- Tokens a session loads at `/start` for one realistic Target (state which one).
- Information lost: none allowed. Show a check (for example a word-set comparison between before and after).
- Readers, commands, docs and migrations that must change: list with file paths.
- Format change or not; whether existing initiatives need a migration.
- Fit with the stream-first rule, the Two-Path principle (a hand edit must produce the same result) and "markdown is the database".
- Effort for the one-off conversion of vault-eks, and who does it (script, model pass, hand).
- Risks and what the approach makes worse.

## Ground rules for the explore agents

- Work on a copy under a temp directory, never on the live `initiatives/vault-eks.md`. A temp memory tree must not symlink `config.local.sh`: it exports `MEMORY_DIR` back to the live tree (this caused an accidental live write on 2026-11-19).
- Prototype code stays in the temp directory or an isolated worktree. No commits to main, no PRs.
- vault-eks is gitignored personal memory: do not copy its text into tracked files or fixtures.

## Open questions

- Is the main pain reading by eye, session token cost, or both? The approaches split along that line (1 and 4 help the eye; 2 helps tokens; 3 helps both a little).
- Should a head cap be a WARN or an ERROR, and does it apply to legacy entries?
- Does Current rules need the head text, or are ids enough once heads are short?
