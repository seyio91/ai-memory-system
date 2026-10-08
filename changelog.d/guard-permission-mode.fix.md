- **The infra guard now denies deny-listed commands in a bypass-permissions main session.** Under
  `AI_MEMORY_GUARD_SCOPE=all` the main session got a confirmation prompt (`ask`), but Claude
  skips that prompt in `bypassPermissions` mode and lets the command run. The guard now reads
  `permission_mode` and asks only in `default`, `plan` and `acceptEdits`, where Claude shows
  the prompt. In any other mode, or with no mode in the payload, it denies the command and the
  reason names the mode. Subagents and executor runs are unchanged.
