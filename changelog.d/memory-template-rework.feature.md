- **The project `memory.md` template now follows the CLAUDE.md include/leave-out test.** New
  optional `## Commands`, `## Conventions` and `## Pointers` sections join the three that stay
  required (`## What It Is`, `## Architecture Decisions`, `## Known Constraints / Gotchas`).
  `## Current State` and `## Current Goal` are retired: they invited frequently-changing status
  that went stale. `/state` now reads each project's goal from the first plan heading under
  `## Active` in `todo.md`, and `/promote-memory` writes project decisions into
  `## Architecture Decisions` instead of a `## Decisions Log`. `docs/file-formats.md` carries the
  include/leave-out table. **Existing instances:** `lint-memory.sh` now WARNs on each project that
  still has `## Current State` or `## Current Goal` (two WARNs per project until the sections are
  removed); the WARN names where the content belongs. No files are rewritten for you.
