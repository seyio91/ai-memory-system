Prune `archive/{plans,todos,working}/` files older than the retention threshold (default 30 days, overridable via `MEMORY_ARCHIVE_RETAIN_DAYS`). `.gitkeep` files are preserved unconditionally.

Argument: `$ARGUMENTS` — optional flags forwarded to the script. Recognized:
- `--all-projects` — clean every project's archive; default is active project only.
- `--days N` — override retention threshold for this run.

Always runs dry-run first, surfaces results to the user, asks for explicit confirmation, then re-runs without `--dry-run`. Never deletes without a yes.

Step 1 — resolve the active project (only relevant when `--all-projects` is NOT passed) from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present and `--all-projects` wasn't passed, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>`) or pass `--all-projects`.

Step 2 — dry-run pass:
```
bash ~/.claude-memory/scripts/archive-cleanup.sh --dry-run $ARGUMENTS
```
Capture stdout. The script reports per-project counts and lists each file that would be deleted.

Step 3 — present the result to the user:
- If 0 files: report "archive-cleanup: nothing to do" and stop. Don't ask for confirmation when there's nothing to delete.
- Otherwise: show the dry-run output verbatim (or a tidy summary if the list is long), then ask: "Proceed with deleting N file(s)?" Do not infer consent from anything other than an explicit yes.

Step 4 — on confirmation, re-run without `--dry-run`:
```
bash ~/.claude-memory/scripts/archive-cleanup.sh $ARGUMENTS
```

Step 5 — report back, two lines max:
- Files deleted count + scope (active project name or `all projects`).
- The retention threshold used.
