---
topic: <name>
scope: project
summary: <one-line description for the index — replace before use>
# Optional — populated by scripts/memory-pin.sh (run from inside the checkout):
# repo: git@github.com:org/repo.git   # git remote (portable fallback id)
# repo_path: repo                     # checkout path relative to AI_MEMORY_PROJECTS_ROOT (may be absolute)
# tags: [terraform, aws, eks]         # surfaced in the index to aid recall
# category: acme-corp                 # client/group this project belongs to — PERSONAL (gitignored);
#                                     #   set via `/pin <project> --category <client>` or by hand
---

<!-- Per line: would removing it cause a mistake? If not, cut it. Include/leave-out table: docs/file-formats.md -->
# Project: <name>

## What It Is
One-line description. Stack, scale, ownership — what you can't read off the repo.

## Commands
Build, test, lint, render, release commands Claude can't guess. Omit if the repo's own README/CLAUDE.md has them.

## Conventions
Branch naming, commit/PR format, style rules that differ from defaults.

## Architecture Decisions
Locked-in choices, with the why if non-obvious. Things that are off the table.

## Known Constraints / Gotchas
Landmines, load-bearing hacks, non-obvious behaviour that will break you if you forget it.

## Pointers
Links instead of copies: the repo's README/CLAUDE.md, docs, wikis, skills.

<!-- Uncomment only if this project's work spans into other projects.
## Related Projects

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| <other-project> | <trigger condition> | <what it owns — entry file/path> |

> Ordering: <cross-repo sequencing, if any>
-->
