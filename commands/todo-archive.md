Snapshot the active project's `todo.md` into `archive/todos/` and reset it to the empty template.

Argument: `$ARGUMENTS` — optional one-line slug describing what the rolled batch was about (kebab-case).

**Auto-suggest:** if `$ARGUMENTS` is empty, before asking the user, scan `~/.claude-memory/projects/<active>/todo.md` for `plans/<name>.md` references. If exactly one unique plan is referenced, derive the slug from that filename (strip a trailing `-plan` suffix if present) and use it without asking. If zero or multiple distinct plans are referenced, fall back to asking the user.

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — sanity check. Read `~/.claude-memory/projects/<active>/todo.md`. Confirm to the user:
- How many items are checked vs. unchecked.
- If unchecked items remain, ask explicitly: "There are N unchecked items. Roll anyway, or keep working through them first?" Do NOT proceed without explicit yes when there are open items.

Step 3 — write the snapshot. Path: `~/.claude-memory/projects/<active>/archive/todos/YYYY-MM-DD-$ARGUMENTS.md` (today's date from the `<memory:identity>` injection context). Body = the current `todo.md` contents verbatim, preceded by a one-line frontmatter-free header `# Archived todo — <active> — YYYY-MM-DD`.

Step 4 — reset `todo.md`. Copy `~/.claude-memory/projects/_template/todo.md` over `~/.claude-memory/projects/<active>/todo.md`, then replace `<name>` with the active project name in the new file's H1.

Step 5 — report back, three lines max:
- Snapshot path.
- Open vs. closed item counts at roll time.
- One-line summary of what the batch covered.
