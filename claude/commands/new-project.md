Run `bash ~/.claude-memory/scripts/new-project.sh $ARGUMENTS` and confirm it succeeds.

Ask: "What is the absolute path to the project repo? I'll place a `.claude/memory-project` marker there so any Claude session opened in that directory auto-loads this project context. Leave blank to skip."

If a path is provided, run `mkdir -p <path>/.claude && echo "$ARGUMENTS" > <path>/.claude/memory-project` and confirm the marker was created.

Then fill in `~/.claude-memory/projects/$ARGUMENTS/memory.md` by asking the user one question at a time in this order — wait for each answer before moving to the next:

1. **What It Is** — one line: what does this project do, what's the stack, who owns it
2. **Current State** — what's deployed and stable vs. what's actively in flight
3. **Architecture Decisions** — what's already locked in, and what approaches are off the table
4. **Known Constraints / Gotchas** — landmines, load-bearing hacks, things that will break if forgotten
5. **Current Goal** — the single active milestone or ticket right now

Write each answer into the corresponding section as it's given. When all five are filled, write the completed file and confirm the path.
