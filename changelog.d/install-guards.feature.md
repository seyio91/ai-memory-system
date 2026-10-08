- **Claude installs now register the memory write guard and the infra deny-list guard.**
  `install.sh --harness claude` adds `scripts/hooks/memory_write_guard.sh` as a
  `PostToolUse` (`Write|Edit`) hook and `scripts/hooks/guard.sh` as a `PreToolUse` (`Bash`)
  hook, so neither needs wiring by hand. The write guard is newly active on every Claude
  install: after a write to a project `memory.md`, `working.md` or `domain/*.md` it reports
  changelog drift and size-budget findings back to the model (it never blocks or reverts a
  write). `AI_MEMORY_GUARD_SCOPE` in `config.local.sh` sets which Claude calls the guard
  covers: `executor` (default) guards executor runs only, as before; `all` guards every
  session — a deny-listed command from a subagent is denied, from the main session it asks
  for confirmation. Any other value fails the install. Install now removes hand-wired copies
  of its hooks so each is registered once, and prints any removed entry that differs from
  what it writes, verbatim, with the `settings.json` backup path.
- **`executor.sh --run` prepends the deny-list to every CLI executor prompt.** The rules from
  `scripts/deny-list.txt` (plus `scripts/deny-list.local.txt`) go ahead of the prompt for
  every role, and `--run` exits 1 without running if the list is missing, unreadable or has
  no rules. `doctrine/orchestrator.md` now points at `scripts/deny-list.txt` instead of
  carrying its own copy of the command list.
