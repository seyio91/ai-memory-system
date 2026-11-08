Capture this session's salient state as a checkpoint in the active project's working memory. Do NOT ask the user questions — synthesize the five fields from this session's context.

Step 1 — resolve the active project from the `<memory:active project="...">` breadcrumb or the `<memory:project name="...">` block; if neither is present, abort and tell the user to pin it (`/pin <project>` inside the repo, or add `.agents/memory-project`). Read and write the path on the breadcrumb's `working:` line verbatim (it may be a worktree overlay, `working.<key>.md`); never hand-build `projects/<active>/working.md`. Without that line, use `~/.claude-memory/projects/<active>/working.md`.

Step 2 — read the working file (create it if missing); leave `## Cross-project learnings (pending promotion)` untouched. `## Checkpoints` is the last section, in last-touched order (bottom = most recent).

**Work reference**
1. The session's reference: the identifiers its work carries — each plan it executed, wrote, revised or validated (`plan <slug>` / `plans/<slug>.md`), `task <ref>`, `PR #<n>`.
2. An entry's reference: its whole `**Task:**` paragraph, to the next blank line.
3. The PR identifier is the number: a bare `#<n>` equals `PR #<n>` where it reads as a PR (`PR #n`, a PR list), not an issue or count.
4. Compare literally, backticks stripped; `plan X` and `task X` differ.

**Match**
5. If both sides have plan slugs, match only on a shared slug; otherwise any shared task ref or PR matches.
6. A plan-slug match outranks a task/PR match; among equals, the bottom-most entry is the target and every other equal-rank match is a duplicate, merged into it (Step 4). An entry that is one piece's target is never another piece's duplicate.
7. An entry without a `**Task:**` line never matches.

**Pieces**
8. Each plan the session touched is a piece of work; so is each task or PR outside those plans. Run Steps 2–4 per piece, matching on that piece's identifiers only; Step 3a once.
9. Compute all matches and ranks before the first write; never re-match.
10. Pieces matching one entry are one pass: combined reference set, one reconciliation, one `[today]` group.
11. Write matched entries top to bottom, then new entries in the order their pieces first came up.
12. A pass writes only its piece's new content but reconciles every prior Next/Blockers bullet of its entry.
13. Work and side items of no piece go into the last entry written (its Done group / its Next); a session with no piece writes one new entry whose Task names no identifier.

Rationale and worked examples for Steps 2–4: `docs/file-formats.md`, "Why the `/checkpoint` rules".

Step 3 — for a matched entry, first:

**Lookups** — for each tracker a prior Next/Blockers bullet names, check: `todo.md` boxes (the entry's own plan section, or the union of its plans' sections); `bash ~/.claude-memory/scripts/taskctl get <ref>` (full ref, never `…`-shortened); plan frontmatter `status:`; `gh pr view <n> --json state`. Annotate the bullet — "(#50 merged)", "(box ticked)", "(task archived)", or "(state unknown)" on failure; never assume. A lookup never closes an item. Replace an old annotation, never stack one; drop "(state unknown)" once a lookup succeeds.

**Reconcile** — every prior Next/Blockers bullet, the duplicates' included, lands in exactly one place; none is dropped silently.
- It goes to today's Done group only if this session (a) did it; (b) saw it done through its own work (the user said so, or it produced the artifact — merged the PR, ticked the box), never via a lookup; or (c) gave it a home that now tracks it: `moved to <todo box | task <ref> | plan <slug> | initiative Target>`.
- Otherwise restate it in Next/Blockers, annotation included.
- `/checkpoint` performs no move: write `moved to …` only when the item had no home and one now names it; a plan or initiative merely existing is not a home.
- Point at what `todo.md`, a plan or an initiative tracks ("remaining phases: todo.md"), never copy it; unticked phases become that pointer, never "moved to todo box". In a mixed bullet ("Phases 3–4; also bump CHANGELOG") only the phase part collapses; restate the rest as its own item.
- An item has a home only if it names one (a todo box's text, `task <ref>`, `plan <slug>`, an initiative Target); never search for one.
- Inline prose in Next or Blockers is one item.

Then synthesize the five fields:
- **Task** — one concrete sentence naming every identifier of this piece, no other piece's, as `plan <slug>`, `task <ref>`, `PR #<n>` (a plan with `task_ref:` gets both).
- **Done** — what this session completed, plus items it saw done or moved; bulleted, file paths where useful.
- **Next** — immediate next steps, bulleted, specific enough to pick up cold.
- **Blockers** — open decisions, questions, external dependencies; else "None".
- **Resume** — one prose line: file to open, what's stubbed, exact line or function to start at; not a restatement of Next.

Be honest: if nothing material happened, Done says "Discussion only — no artifacts produced"; if Next is unclear, write "Awaiting user direction on …".

Step 3a — once per session, before writing: if an active initiative (`initiatives/<slug>.md` with `kind: initiative`, `status: active`) has a `### <active-project>/...` Target heading and this session settled anything that binds another repo, append it to that initiative's `## Decision stream` as the next `D<n> proposed <today>` entry with an `unconfirmed:` continuation line, without asking the user. A decision recorded only in a plan, runbook or project memory has not been recorded.

Step 4 — write to `## Checkpoints` with today's date from `<memory:identity>` (never invent one). Every entry this pass does not write or merge stays byte-identical.

- **Matched** — rewrite the entry in place and move it to the bottom:
  - Duplicates first: fold each into the target, then delete it. The heading keeps the target's title with the earliest start date among them; the Task paragraph gains each duplicate identifier it lacks (as below); Done becomes the duplicates' Done content, oldest entry first, then the target's, all byte-identical.
  - Otherwise leave the heading line unchanged (start date kept).
  - Append each identifier of this piece (every piece, in a combined pass) missing from the `**Task:**` paragraph — `, plan <slug>` etc. — before its final period, even when it wraps; change nothing else.
  - Keep existing Done content byte-identical (legacy blank lines and inline prose included; never reformat into bullets). Append ONE new group of `- [YYYY-MM-DD] ` bullets (today), no blank line inside — every run, never merged into an earlier group, even the same day (a same-day run just appends more `- [today]` bullets, no blank line before them).
  - Replace Next, Blockers and Resume; add a missing `**Resume:**`, and a missing `**Blockers:**` as "None".
- **No match** — append a new entry at the bottom in this exact shape:

```
### YYYY-MM-DD — <Task summary, one line>

**Task:** <Task field as one sentence>

**Done:**
- [YYYY-MM-DD] <bullet>
- [YYYY-MM-DD] <bullet>

**Next:**
- <bullet>
- <bullet>

**Blockers:**
- <bullet or "None">

**Resume:** <one prose line — file to open, what's stubbed, exact line/function to start at>
```

If `## Checkpoints` is missing, create it as the file's last section. If the file is empty, also add `# Working — <active>` and `## Cross-project learnings (pending promotion)` (holding `_(none yet)_`) above it.

Step 5 — report back, with no fixed cap:
- Per written entry: the path, its heading (new or rewritten), a one-line summary, and each duplicate heading merged into it.
- Then the appended decision-stream id, if any, once.
- Then one line per side item — an open Next/Blockers item of a written entry that is not one of its own piece's steps (phases, PR, close-out) and names no `todo.md` box, `task <ref>`, `plan <slug>` or initiative Target (do not search): `open item has no todo/task home: "<item>" — /task add? (or name its existing task/todo/plan on the item)`. Never capture a task yourself.
- Last, count the `### ` entries in `## Checkpoints` (fence-depth 0). Sessions load only the newest `AI_MEMORY_CHECKPOINT_WINDOW` (default 5); if count > window, add: "N checkpoint(s) are no longer loaded into sessions — run `/checkpoint-archive`?" (N = count − window; it can be 1). Do not run it unasked.
