---
plan: write-path-robustness
status: in_progress
created: 2026-11-07
owner: claude (orchestrator)
task_provider: notion
task_ref: 411f6850-c619-81ec-8336-e6a24629c4a8
---

# Write-path robustness: index regen and local task provider

## Goal
Make index regeneration path-safe and concurrency-safe, and make the local task provider's create/update writes exclusive and atomic, so a memory root with spaces or two concurrent sessions cannot corrupt the index or task files.

## Success criteria
- `regenerate-index.sh` produces a correct index when `MEMORY_DIR` contains spaces (project and domain enumeration), verified by a fixture run; no `for f in $(find …)` remains in the script.
- `regenerate-index.sh` uses `mktemp` temp files in the index's directory, builds the complete index before replacing, and replaces with a single `mv`; no fixed `$INDEX.tmp*`/`.body` names remain; temp files are removed on failure (trap).
- A failed regeneration leaves the previous `index.md` byte-identical.
- Local provider `capture` creates task files with exclusive creation (`O_EXCL` / `open(..., "x")`); a name collision retries the next suffix instead of overwriting.
- Local provider writes (`_write_task`, `set_status`) go through temp file + `os.replace` in the destination directory; `set_status` never leaves a moved-but-unrewritten file.
- macOS `/bin/bash` 3.2 compatible; `bash scripts/run-tests.sh` passes (full run, signing off locally); existing `test_regenerate_index.sh`, `test_local.py`, `test_taskprovider_cli.sh` green.
- `changelog.d/write-path-robustness.fix.md` present.
- PR opened via `git-cli ship`; not merged.

## Design
Shell: `find -print0 | sort -z` (BSD sort supports `-z`) + `while IFS= read -r -d '' f` loops; `mktemp "$(dirname "$INDEX")/.index.XXXXXX"` for every intermediate, `trap` cleanup, single final `mv`. Python: `open(path, "x")` in `_unique_ref`'s create path (loop on `FileExistsError`); `_write_task` writes `tempfile.NamedTemporaryFile(dir=path.parent, delete=False)` then `os.replace`; `set_status` writes the rewritten content to the destination via the same atomic helper, then unlinks the source.
Rejected: file locking (`flock`) — not on macOS bash by default and lost-update protection is out of scope for a single-user tree; atomic replace + exclusive create cover the observed failure modes.

## Decisions (locked)
- No lost-update protection (revision checks/locks) — single-owner tree; reviewer flagged it as the stronger fix, deferred.
- Regression tests added for the space-path, failed-regen and name-collision cases (user, 2026-11-07).

## Phases

### Phase 1 — regenerate-index.sh: path-safe enumeration + atomic temp handling
**Verify:** criteria 1–3 hold; `test_regenerate_index.sh` green, plus a fixture run under a `MEMORY_DIR` with a space.

### Phase 2 — local task provider: exclusive create + atomic writes
**Verify:** criteria 4–5 hold; `test_local.py` and `test_taskprovider_cli.sh` green.

### Phase 3 — gate and ship
**Depends:** P1, P2
Changelog fragment, full suite, `git-cli ship`.
**Verify:** criteria 6–8 hold; PR open.

## Risks / open questions
- `sort -z` availability on the CI ubuntu + macos matrix (GNU and BSD both support it).
