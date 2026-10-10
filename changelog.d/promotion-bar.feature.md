- **Memory writes and `/promote-memory` apply a promotion bar.** Durable is no longer enough: a
  learning is kept only if Claude could not work it out from the code or the repo's docs, or it is
  specific to how you use the tool. `/promote-memory` tags each candidate `[non-obvious]` or
  `[usage]` and drops the rest, so durable-but-derivable facts stop accumulating in `memory.md`.
