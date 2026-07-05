Promote one or more learnings from the active project's `working.md` into either a domain file (cross-project) or the project's `memory.md` (engagement-specific). Multi-select: the agent generates candidates, the user picks which to keep.

Use today's actual date (from `<memory:identity>` injection context) for all entries — do not invent.

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — read `~/.claude-memory/projects/<active>/working.md`. If empty (or only the `_(none yet)_` placeholder under "Cross-project learnings"), abort and tell the user there's nothing to promote.

Step 3 — extract candidate learnings. Walk both sections:
- `## Cross-project learnings (pending promotion)` — explicit candidates, usually each their own bullet with `**Why:**` / `**How to apply:**` sub-bullets.
- `## Checkpoints` — implicit candidates from `Done:` / `Blockers:` / `Next:` bullets that captured a durable lesson (gotcha, decision, pattern, constraint).

For each candidate, produce:
- A one-line summary in the form `<what> — <why it matters>`.
- An inferred destination tag:
  - **`[domain:<existing-topic>]`** if the learning is a cross-project pattern matching an existing domain file. Existing domain topics live under `~/.claude-memory/domain/*.md` — read the directory to enumerate. Match by topic (e.g. anything about Terraform modules/state → `terraform`; codex/agent-tool quirks → `agent-tooling`).
  - **`[domain:new]`** if the learning is cross-project but no existing domain file fits. On selection, the agent will prompt for the new topic name, triggers, and summary.
  - **`[project]`** if the learning is engagement-specific (a decision, constraint, or gotcha tied to *this* project).

Before finalizing a candidate, apply the **present-tense test**: would this still be true and worth reading in 6 months with no edit? If its payload is an *event* — "we did X", "PR #N merged", "track closed" — it's git history; drop it, or reduce it to the durable decision/gotcha underneath. Memory keeps decisions and constraints; git keeps events.

Cap the candidate list at 4 (the `AskUserQuestion` per-question limit). If more emerge, keep the most load-bearing ones — the rest can be promoted next round. Never invent candidates; only surface what's actually in `working.md`.

Step 4 — present the candidates via a multi-select question. Use `AskUserQuestion` with `multiSelect: true`. Each option's label MUST start with the destination tag in square brackets so the user can see destinations at a glance, e.g.:

- `[domain:terraform] tfstate locks must be released before re-running plan — prevents 30-min wait`
- `[project] AB-281 chart kept in PR #7 for reference, not merged — see Decisions Log`
- `[domain:new] codex execpolicy decision keyword is "forbidden", not "deny" — wrong values fail at exec time, not parse time`

If there are zero candidates, abort and tell the user there's nothing promotable.

Step 5 — for each selected candidate, write to its destination (using today's date):

- **`[domain:<existing>]`** — append `**[YYYY-MM-DD]** <summary>` to the `## Knowledge` section of `~/.claude-memory/domain/<existing>.md`.

- **`[domain:new]`** — ask the user three questions in one batch (single `AskUserQuestion` call with multiple questions, or sequential if the topic is partly inferable): topic name (kebab-case), triggers (comma-separated keywords/aliases), one-line summary. Then create `~/.claude-memory/domain/<name>.md` with this seed (substitute answers):
  ```
  ---
  topic: <name>
  triggers: [<comma-separated triggers>]
  summary: <one-line summary>
  ---

  # Domain: <Name>

  ## Knowledge
  <!-- Append entries as: **[YYYY-MM-DD]** what — why it matters -->
  ```
  Then append the candidate's `**[YYYY-MM-DD]** <summary>` to the new file's `## Knowledge` section.

- **`[project]`** — engagement-specific learning. Classify before writing:
  - A durable **decision** (a choice + its rationale) → append `**[YYYY-MM-DD]** <summary>` under `## Decisions Log` (create the section at end of file if absent). Write it present-tense ("infra applies stay CI-only because …"), not as an event ("decided X in PR #N"). If it **supersedes** an existing Decisions Log entry, OVERWRITE that entry — do not append a second one. Append-only is how the log decays into a changelog.
  - A **constraint/gotcha** or a reusable **pattern/convention** → fold it into the matching structured section (`## Known Constraints / Gotchas` or `## Architecture Decisions`), NOT Decisions Log. The log is for choices, not for landmines or conventions.
  - A pure **event** (work landed, PR merged, track closed) → do NOT promote; that's git history. (Step 3's present-tense test should already have dropped it.)

Step 6 — archive `working.md` exactly once at the end of the run (regardless of how many candidates were promoted): move it to `~/.claude-memory/projects/<active>/archive/working/YYYY-MM-DD-HHMM.md`, then create a fresh empty `working.md` in the project directory.

If the user selected zero candidates from Step 4, skip the archive step — nothing was promoted, working.md should remain.

Step 7 — regenerate the memory index:
```
bash ~/.claude-memory/scripts/regenerate-index.sh
```

Step 8 — report back, concise (≤6 lines):
- For each promoted item: destination path + one-line summary.
- Archive path of the rolled `working.md` (or "kept — no promotions selected").
- `index unchanged` or `index updated`.
