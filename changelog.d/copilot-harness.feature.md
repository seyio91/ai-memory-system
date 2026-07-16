- **GitHub Copilot CLI is now a first-class harness.** `install.sh --harness copilot`
  wires user-level `sessionStart`, `preToolUse`, `preCompact`, and `postToolUse` hooks
  for live markdown memory injection, guarded executor runs, compaction recovery, and
  a Copilot CLI executor face with a read-only `view,grep,glob` mode.
