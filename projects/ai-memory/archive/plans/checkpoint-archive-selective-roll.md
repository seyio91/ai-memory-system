---
plan: checkpoint-archive-selective-roll
status: done
completed: 2026-11-05
created: 2026-11-03
owner: claude (orchestrator)
task_provider: local
task_ref: checkpoint-archive-should-roll-only-closed-and-superseded-checkpoints
---

# checkpoint-archive: roll only closed and superseded checkpoints

## Goal

`/checkpoint-archive` moves only superseded and closed checkpoint entries to `archive/working/` and keeps in-flight ones in place, by having the command pass the entries it classified as in-flight to `checkpoint-archive.sh`, which today snapshots and resets the whole section.

## Success criteria

1. **S1 — list.** `checkpoint-archive.sh --list <working-file>` prints one line per fence-depth-0 `### ` entry in the target section, `<n><TAB><heading>`, 1-based in file order, and writes nothing (test).
2. **S2 — keep.** `--keep <n>` (repeatable) rolls every entry except the kept ones. The snapshot holds the section heading plus the rolled entries in original order. The live section holds a dated rolled placeholder line, then the kept entries byte-identical and in original order. Every other section and the H1 stay byte-identical (tests: keep newest, keep a middle entry, keep several non-adjacent).
3. **S3 — fail closed.** A `--keep` that is non-numeric, zero, or past the entry count exits 2, writes no snapshot and leaves the file byte-identical (test per case).
4. **S4 — keep-all is a no-op.** Keeping every entry exits 0, reports nothing to roll, writes no snapshot, and leaves the file byte-identical (test).
5. **S5 — legacy unchanged.** With no `--keep`, behaviour is today's whole-section roll, including `--section` use by `/promote-memory`. Existing `test_checkpoint_archive.sh` assertions pass unmodified.
6. **S6 — fence parity.** Entry and section boundaries ignore `## `/`### ` lines inside backtick and `~~~` fences of any length, matching `scripts/formatters/working.sh` (tests: `~~~` fence holding `## ` and `### ` lines inside an entry).
7. **S7 — preamble.** Non-entry text between `## Checkpoints` and the first `### ` (an earlier rolled placeholder, carried notes) is replaced by the new placeholder in the live file and included in the snapshot (test).
8. **S8 — command.** `commands/checkpoint-archive.md` runs `--list`, classifies, and passes `--keep <n>` for each in-flight entry. The ask gate fires only for open items carried by rolled (closed/superseded) entries that are untracked elsewhere. The "carry the listed items into the fresh section" offer is gone. The report states rolled and kept counts.
9. **S9 — docs and gate.** `docs/harnesses/claude.md` row updated; `changelog.d/<id>.fix.md` fragment; `bash scripts/run-tests.sh` green with signing disabled; each new deny/fail-closed test mutation-checked.

## Design

Script = mechanism, command = policy, unchanged split. The command already classifies entries from content; the script gains an entry-level interface so the classification decides what moves.

- `--list` exposes the script's own entry numbering, so the command never counts headings by hand and fence handling is single-sourced in the script.
- `--keep <n>` selects by position, not heading: two same-day same-title entries are possible, and `/checkpoint` forbids editing a prior entry to disambiguate.
- One awk pass assigns each line of the target section to preamble (0) or entry n, then routes lines to snapshot or live file. Fence logic is copied from `formatters/working.sh`'s `fenceline` into both awk programs, replacing the backtick-only toggle.
- `--keep`/`--list` are generic over the `--section` target; `/promote-memory` passes neither.

Rejected: `--keep <heading>` (ambiguous on duplicate headings); `--keep-last N` (an in-flight entry can sit above newer closed ones); classification inside the script (content judgement in awk, the fragility the original design avoided).

## Decisions (locked)

- Position-based `--keep`, numbered by `--list` from the same script.
- Fail closed on any invalid keep; never roll an entry the caller asked to keep.
- Kept entries keep original order; the rolled placeholder sits above them.
- Malformed input fails closed in every mode, legacy included (validator round 1, 2026-11-03): a duplicate target `## ` heading, or a fence left open at EOF that opened before the target section ends, exits 2 and writes nothing. This is a deliberate exception to S5 and is called out in the changelog.

## Phases

### Phase 1 — script: `--list`, `--keep`, fence parity
**Verify:** S1–S7 tests in `scripts/tests/test_checkpoint_archive.sh` pass, existing assertions unmodified; shellcheck clean.

### Phase 2 — command text, docs, changelog
**Depends:** P1
**Verify:** S8 by reading the command against the script's real `--list` output on a fixture; S9 docs row and fragment present; `check-docs.sh` clean.

### Phase 3 — validate and ship
**Depends:** P1, P2
**Verify:** full gate green; validator Part A pass on S1–S9 and Part B no bug-grade finding; PR opened via `git-cli ship --intent`.

## Risks / open questions

- Positions can drift if the file changes between `--list` and the roll. Both run in one command turn, so the window is negligible; not guarded.
- A kept in-flight entry older than `AI_MEMORY_CHECKPOINT_WINDOW` stays in the file but out of the session payload. Out of scope here.
- Same-minute snapshot collision handling is unchanged and still applies.
- Fences indented 4+ spaces (code inside list items) are not fences, matching `formatters/working.sh`; a `## `/`### ` inside one shifts boundaries. Accepted for parity.
- The fence parser now exists in three copies (this script, `formatters/working.sh`, a backtick-only one in `_lib.sh`). Extracting a shared awk include is a follow-up, not this plan.
