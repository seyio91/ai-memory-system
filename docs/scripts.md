# Scripts reference

| Script | Purpose | Common invocations |
|--------|---------|---------------------|
| `codex-mem.sh` | Build AGENTS.md + run codex | `codex-mem.sh`, `codex-mem.sh exec --sandbox read-only "..."` |
| `codex-mem-checkpoint.sh` | Emit checkpoint scaffold | TTY → opens `$EDITOR`; `--for-codex` → stdout for Codex to consume |
| `regenerate-index.sh` | Rebuild `index.md` AUTOGEN block | `regenerate-index.sh` (idempotent) |
| `lint-memory.sh` | Mechanical lint | exit 0 if clean, 1 if any WARN/ERROR |
| `archive-cleanup.sh` | Prune old `archive/` files | `archive-cleanup.sh [--all-projects] [--days N]` (dry-run, then confirm) |
| `new-project.sh` | Scaffold a new project (pin a repo with `.claude/memory-project` to activate) | `new-project.sh <name>` |
| `memory-pin.sh` | Pin a checkout ↔ project (forward marker + reverse `repo`/`repo_path`) | `memory-pin.sh <name>` (run from inside the checkout) |
| `_lib.sh` | Shared helpers (sourced) | `detect_active_project`, `extract_fm_field`, `projects_root`, `resolve_repo_path` |
| `taskctl` | Bash wrapper for the task-provider CLI (used by `/task`, `/start`) | `taskctl <capture\|list\|get\|update\|set-status\|ping> ...` |
| `taskprovider/` | Python (stdlib-only) task-provider CLI — see [Task-provider layer](task-provider.md) | `PYTHONPATH=$MEMORY_DIR/scripts python3 -m taskprovider <verb>`; tests: `cd scripts && python3 -m unittest discover -s taskprovider/tests -t .` |
| `tests/*` | Dependency-free shell tests (bash 3.2) | `for t in scripts/tests/test_*.sh; do bash "$t"; done` |

All scripts target macOS `bash` 3.2 (no `mapfile`, no associative arrays) and resolve the memory tree via `MEMORY_DIR`. Each test sets `MEMORY_DIR` (and, for the hook, `MEMORY_SESSIONS_DIR`) to a `mktemp -d` sandbox so the suite never touches real memory.

## Environment overrides

| Var | Default | Used by |
|-----|---------|---------|
| `MEMORY_DIR` | repo root (self-locating); `~/.claude-memory` when installed | All scripts |
| `AI_MEMORY_PROJECTS_ROOT` | `$HOME/Projects` | `memory-pin.sh`, `resolve_repo_path`, `lint-memory.sh` |
| `config.local.sh` (file, not a var) | unset — copy from `.example` | Sourced by `_lib.sh` + `taskctl` for per-env overrides |
| `CODEX_INSTRUCTIONS_FILE` | `~/.codex/AGENTS.md` | `codex-mem.sh` |
| `CODEX_OVERLAY_FILE` | `~/.codex/AGENTS.local.md` | `codex-mem.sh` |
| `CODEX_HISTORY_FILE` | `~/.codex/history.jsonl` | `codex-mem-checkpoint.sh` |
| `CODEX_HISTORY_LINES` | `20` | `codex-mem-checkpoint.sh` |
| `MEMORY_STALE_DAYS` | `30` | `lint-memory.sh` |
| `MEMORY_ARCHIVE_RETAIN_DAYS` | `30` | `archive-cleanup.sh` |
| `MEMORY_SESSIONS_DIR` | `~/.claude/memory_sessions` | `inject_memory.sh` |
| `MEMORY_TASK_PROVIDER` | `local` | task-provider factory (`local`/`notion`) — see [Task-provider layer](task-provider.md) |
| `NOTION_TOKEN` | — | `NotionProvider` (integration secret; set in `~/.zshenv`) |
| `NOTION_DATA_SOURCE_ID` | — | `NotionProvider` (the data-source id, not the database id) |
| `NOTION_STATUS_KIND` | `status` | `NotionProvider` — set `select` if the board's `Status` is a select property |
| `AI_MEMORY_EXECUTOR` | `claude-subagent` | `executor.sh` — preferred executor **and validator** backend — see [Workflow › Executor selection](workflow.md#executor-selection) |
| `AI_MEMORY_EXECUTOR_CMD_<key>` | — | `executor.sh` — command template for a generic CLI executor |
| `AI_MEMORY_EXECUTOR_FALLBACK` | `claude-subagent` | `executor.sh` — used when the preferred CLI binary is absent |
