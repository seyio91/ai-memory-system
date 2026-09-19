`AI_MEMORY_EXECUTOR_GH_TOKEN=1` (opt-in, `config.local.sh`) makes `codex-mem.sh --executor`
fetch `gh auth token` at launch and export `GH_TOKEN` plus a `gh` git credential helper into
the run. The codex sandbox cannot read the macOS keychain, so without it `gh` returns
HTTP 401 and an HTTPS `git push` finds no credential. Default stays credential-free: the
executor commits and pushes, the orchestrator opens the PR. Loud on stderr if `gh auth token`
comes back empty, and it leaves an existing `GIT_CONFIG_COUNT` chain alone.
