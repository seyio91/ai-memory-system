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

## How decisions depend on each other (measured 2026-11-19)

The user's point: decisions sometimes depend on each other, so a reader that filters by topic can miss one that matters. Measured on the live vault-eks with a rough script (D-ids and ranges such as `D36–D44` found anywhere in an entry's text):

- 67 of 96 decisions cite at least one other decision. Only 43 do so through a structured line (AMENDS, SUPERSEDES or a forward pointer); the rest cite inline in prose.
- 186 citations in total, and 96 of them (52%) point at a decision in a different topic. 34 of the 96 decisions have at least one cross-topic citation. One entry (D83) cites 24 others.
- Topic plus every decision reachable through citations (full transitive closure) is 64–74% of the stream's bytes for 8 of the 14 topics (rollout, consumer-charts, postgres, consumption, seal-kms, fallback, mysql, estate-prereqs). It saves little. Topic only is 1–16%.
- Topic plus the directly cited decisions only (one hop) is 1–39% of the stream, depending on topic (rollout 39%, postgres and consumer-charts 33%, seal-kms 3%).

Verified 2026-11-19: every stream line parses as a head or continuation line; the topic sets equal the renderer's Current rules table; an independent awk count gives the same 67; six random cross-topic citations were read in context and are real references. Sub-item mentions such as `D15b` count as a citation of D15.

Limit of the measurement: a citation is a mention, not proven dependence. Some are surveys ("MySQL D50–D55"), comparisons ("as for Postgres (D44)") or forward pointers (D46 superseded → D58). How many a session needs in full cannot be told by script, so one hop is an upper bound on what must load, not a proven requirement.

So a topic-only filter is unsafe, full closure is pointless, and one hop is the workable middle. Anything past one hop would have to arrive as a short pointer (id plus a one-line statement of the rule), which only works if heads are short. That ties approach 2 to approach 1. The inline citations also mean a reader must either parse D-ids out of prose or the format needs an explicit dependency line.

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

5. **Narrow the reads, no stream change.** Three instructions load the whole file today: `/start` Step 1.5 ("read the initiative file", "read the Decision stream"), the doctrine's "consult the initiative file before delegating", and appending a decision (an Edit needs a Read, and the rule says to re-check the highest D-id). Change them to load only the Target, Now, Current rules and the filtered decisions, and add a script that appends a decision and returns the next D-id. To test: write the changed instructions and the append script, replay `/start` for three real Targets, and measure tokens loaded against the full read. This is also the baseline the other approaches must beat. It needs approach 2's reader or a simpler stand-in; say which.

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

## Decisions from the user (2026-11-19)

- **Goal: token cost only.** The user does not need to read every decision, because the system brings decisions to them (Now, Current rules, proposals at `/plan-done`). An earlier answer the same day said the stream was also too long to read; this replaces it. Approaches are judged on what a session loads, and the "Human view" measure is dropped.
- **The narrow-reads fix is a fifth approach**, tested against the same measures as the others (approach 5).
- **Head cap, if adopted:** lint WARN, with legacy entries (up to `legacy_through`) exempt.
- **Current rules with or without the one-line rule text:** not decided. The short-heads agent renders both forms on a vault-eks copy and reports the size and token cost of each.

## Open questions

- How many citations are real dependencies? An agent classifies a sample by hand (survey, comparison, forward pointer, real dependency) so the one-hop upper bound can be tightened.

## Exploration results (2026-11-19)

Six agents ran on sandbox copies of vault-eks (146,272 bytes, taken 09:51). Tokens = bytes / 3.6. Four approach agents could not write their report file, so this section is the record; "judged" means one reader's judgement, and no agent replayed a real `/start` session.

| Approach | Verdict | `/start` load vs 40,631-token baseline | Why |
|---|---|---|---|
| 1 Short heads | drop alone | file grows 16% to ~47,000; 42–68% of baseline with a reader | costs more than a reader alone (23–50%); 8 of 21 sampled heads need judgement to shorten; a head cannot be updated after an AMENDS |
| 2 Topic reader | combine | topic + one hop: 30,276 / 10,923 / 7,653 for the three Targets | topics cannot be derived from a Target; every narrowed mode omitted a needed decision for two Targets |
| 3 Archive D1–D43 | drop | main + archive 40,704 | 41 of 43 archived entries are live, 44% of Current rules; all three Targets need the archive |
| 4 Split file | drop | main only 6,902; main + stream 40,631 | lines 1–269 + 600 of the single file are byte-identical to the split main file; unmodified readers fail silently |
| 5 Narrow reads | combine | simple selector 3,383 / 2,658 / 2,237 | selector omits D58 and D93 for tpe-stacks; append drops from 40,915 to 229 tokens |

Findings that shaped the design:

- **Citations:** 53 of 186 (28%) are real dependencies, 19 of 96 cross-topic (judged census, close calls give 22–37%). Classes are not separable mechanically; structured-only loading misses 17 of the 53. D83's 24 citations are 22 surveys.
- **Uncited needs:** D58, D93, D63 (tpe-stacks) and D18, D81, D20 (audit) are reachable by neither topic nor citation. Only a pointer for every live decision makes them visible: 93 pointers at 160 bytes are 17,546 bytes / 4,874 tokens.
- **Pointers:** about 7 in 10 truncated heads state the rule; D58, D55, D45 and D79 show a title only.
- **Repo binding:** 51 entries list repos in an inline prose list; the documented `binds:` line is used 0 times. 18 live entries name tpe-stacks.
- **Amendments:** 18 are prose-only with no `AMENDS` line.
- **Prose id parsing:** 66 of 66 citations found in a 29-entry hand check, no false positives after two skip rules for foreign ids.
- **Append:** a `mkdir` lock gave 8 distinct ids for 8 simultaneous appends; without it all 8 took the same id and 2 entries survived. Script and hand edit were byte-identical.
- **Above-stream part:** 24,846 bytes (6,902 tokens), of which Targets are 18,013. Target block + Now + Current rules is about 5,500–5,950 bytes.

## Outcome

The user chose narrow reads + a one-line pointer index + a locked append script, a `binds:` line (lint WARN plus vault-eks backfill), an optional `rule:` line for pointers, and instructions without a hook. Plan: `initiative-decision-stream-cut-its-size-and-read-cost`.
