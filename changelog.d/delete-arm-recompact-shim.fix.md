- **The codex `arm_recompact.sh` compatibility shim is deleted.** It survived one release (v1.4.0) so a
  stale pre-flip `~/.codex/hooks.json` — from a manual `git pull` that never re-ran `install.sh` — kept
  working by delegating to the shared session-start script. That grace period is over.
  **Its name is deliberately retained in the hook-registration sweep set** (`scripts/drivers/hook.sh`), and
  that retention is what makes the deletion safe: re-running `install.sh` (or `sync-system.sh`, which calls
  it) rewrites the stale entry to point at `scripts/hooks/session_start_memory.sh`. Dropping the marker
  along with the file would leave a stale entry aimed at a path that no longer exists, and codex would
  error on every `SessionStart` — deleting a hook script and retiring its sweep marker are two different
  releases. The sweep is now covered by a test that was mutation-verified against exactly that mistake.
- **`test_codex_arm_recompact.sh` → `test_session_start_memory.sh`.** Every assertion in it was always
  about `scripts/hooks/session_start_memory.sh`'s compaction-arm behaviour rather than the shim's, so all
  six carry over unchanged. The rename also makes `run-tests.sh --changed` map
  `session_start_memory.sh` → `test_session_start_memory.sh` by naming convention instead of relying on
  the basename-grep fallback.
