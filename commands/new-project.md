Run `bash ~/.claude-memory/scripts/new-project.sh $ARGUMENTS` and confirm it succeeds.

Ask: "What is the absolute path to the project repo? I'll place a `.agents/memory-project` marker there so any Claude session opened in that directory auto-loads this project context. Leave blank to skip."

If a path is provided, run `mkdir -p <path>/.agents && echo "$ARGUMENTS" > <path>/.agents/memory-project` and confirm the marker was created.

Ask: "What client/category does this project belong to? This groups it under a client for `/state` and `/activity`. It is **personal** (stays gitignored). Leave blank for none."

If a category is provided, set the `category:` frontmatter field in `~/.claude-memory/projects/$ARGUMENTS/memory.md` (uncomment/replace the template's `# category:` line with `category: <value>`). If a repo path was also given, the equivalent one-shot is `~/.claude-memory/scripts/memory-pin.sh $ARGUMENTS --category "<value>"` run from that path (writes the marker, reverse map, and category together).

Then fill in `~/.claude-memory/projects/$ARGUMENTS/memory.md` by asking the user one question at a time in this order — wait for each answer before moving to the next:

1. **What It Is** — one line: what does this project do, what's the stack, who owns it
2. **Commands** — build/test/lint/render/release commands Claude couldn't guess (skip if the repo's README/CLAUDE.md has them)
3. **Conventions** — branch naming, commit/PR format, style rules that differ from defaults
4. **Architecture Decisions** — what's already locked in, and what approaches are off the table
5. **Known Constraints / Gotchas** — landmines, load-bearing hacks, things that will break if forgotten
6. **Pointers** — the repo's README/CLAUDE.md, docs, wikis or skills worth linking instead of copying

Apply the per-line test to every answer: keep only what would cause a mistake if missing — no status, versions, counts, PR numbers or dates (see the include/leave-out table in `docs/file-formats.md`). Write each answer into the corresponding section as it's given; an empty answer to an optional section (Commands, Conventions, Pointers) removes that section. What It Is, Architecture Decisions and Known Constraints / Gotchas are required by lint. The active goal goes in `todo.md`, not here. When done, write the completed file and confirm the path.
