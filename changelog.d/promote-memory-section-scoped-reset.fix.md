- **`/promote-memory` no longer destroys the rest of `working.md`.** Its Step 6 moved the *entire* file to
  `archive/working/` and started a fresh empty one, so a single promotion also wiped `## Checkpoints` —
  including mid-flight entries owned by `/checkpoint-archive` — and any free-form section such as
  `## Open threads` that no command owns. It now rolls only `## Cross-project learnings (pending
  promotion)`, leaving every sibling section byte-identical. This contradicted the command's own opening
  line, which had always said checkpoint archival was separate.
- **`checkpoint-archive.sh` grew a `--section <heading>` flag** (default `Checkpoints`, so the existing
  two-arg form is unchanged) and both commands now share it rather than keeping two copies of a
  fence-aware, overlay-aware section rewriter. The heading is matched as a literal string, not a regex:
  the learnings heading contains parentheses, which a regex reads as grouping — it would miss the section,
  roll nothing, and still exit 0.
- **`/promote-memory`'s abort condition was inconsistent with its own candidate scan.** Step 3 reads both
  `## Cross-project learnings` and `## Checkpoints`, but Step 2 aborted whenever the learnings section held
  only its placeholder — making a lesson recorded in a checkpoint unpromotable. It now aborts only when
  both sources are empty. A learning promoted out of a checkpoint leaves that checkpoint in place and may
  be offered again until checkpoints are rolled; `/checkpoint-archive` remains the sole owner of that
  section.
