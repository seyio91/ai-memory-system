Capture this session's salient state as a checkpoint in the active project's working memory. Do NOT ask the user questions — synthesize the four fields directly from this session's context (what's been discussed, decisions made, files touched, next steps, blockers).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — read `~/.claude-memory/projects/<active>/working.md`. Identify:
- Whether a `## Checkpoints` section exists. If not, you'll create one at the end of the file.
- The order of existing checkpoints (chronological, oldest at top, newest at bottom). New entries append at the bottom of the `## Checkpoints` section.
- Whether a `## Cross-project learnings (pending promotion)` section exists above `## Checkpoints` — leave it untouched.

Step 3 — synthesize the four fields from this session's context:
- **Task** — one sentence naming what we're working on. Concrete, not vague.
- **Done** — what's been completed *in this session* (files changed, decisions locked in, work that produced an artifact). Bulleted if multiple items. Reference file paths where useful.
- **Next** — the immediate next step(s). Bulleted if multiple. Should be specific enough that the next session can pick it up cold.
- **Blockers** — open decisions, unanswered questions, external dependencies. Use "None" if there genuinely are none.
- **Resume** — one prose line that drops a cold session straight into the work: which file to open, what's stubbed/half-done, and the exact line or function to start at (e.g. "open `scripts/foo.sh`; `parse()` is stubbed at L40 — wire it to `_lib.sh:bar` next"). This is the orienting pointer, not a restatement of Next.

Be honest. If nothing material happened in this session, say so in Done (e.g. "Discussion only — no artifacts produced") rather than padding. If Next is unclear, write "Awaiting user direction on …".

Step 4 — append the new checkpoint to the end of the `## Checkpoints` section in this exact shape (today's date is in the `<memory:identity>` injection context — use it; do not invent):

```
### YYYY-MM-DD — <Task summary, one line>

**Task:** <Task field as one sentence>

**Done:**
- <bullet>
- <bullet>

**Next:**
- <bullet>
- <bullet>

**Blockers:**
- <bullet or "None">

**Resume:** <one prose line — file to open, what's stubbed, exact line/function to start at>
```

If the day already has a checkpoint and the work is a continuation, you may append a fresh `### YYYY-MM-DD — <new framing>` entry rather than mutating the existing one. Never delete or overwrite a prior checkpoint — they form a chronological record.

If `## Checkpoints` doesn't exist, create it at the end of the file with this checkpoint as its first entry. If `working.md` is empty entirely, also add a top-level `# Working — <active>` heading and a `## Cross-project learnings (pending promotion)` section above the new `## Checkpoints` (with a `_(none yet)_` placeholder under it).

Step 5 — report back, three lines max:
- Path written.
- Heading of the new checkpoint.
- One-line summary of what was captured (e.g. "agent-friendly Terraform refactor — Track A files ready, awaiting go-ahead").
