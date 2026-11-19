---
topic: codex
triggers: [codex, codex-mem, executor, validator, sandbox, writable_roots, hooks.json, hook-trust, CODEX_HOME, execpolicy]
summary: OpenAI Codex CLI — executor traps (silent exit 0, sandbox and credential posture, execpolicy semantics) and hook/probe pitfalls; mechanics live in docs/harnesses/codex.md and codex-mem.sh
---

# Domain: Codex

## Knowledge
<!-- Durable patterns and traps only — no version pins, file:line refs, counts, dated status or incident narratives. Name the file or command that answers it. -->

**`codex exec` can exit 0 on a usage-limit error — never trust an executor's self-report.** The limit message is prose mid-transcript, the process still exits 0, and `executor.sh --run` reports success. What goes missing is everything after the failure point, usually the verification the delegation existed to obtain. A failure that is silent and exits 0 gets blamed on whatever looks suspicious nearby ("the executor skipped the tests"). Re-run the gates yourself against the tree. The Claude subagent plane has its own independent rate limit, so a fan-out across both planes can be halted by two quotas, only one of which announces itself.

**Credentials are a posture choice, not a technical blocker.** The sandbox cannot reach the macOS keychain, so `gh` and HTTPS `git push` fail inside it (`git credential fill | grep -c '^password='` is 1 outside, 0 inside; a push that works means the remote was SSH). The process env, however, passes through unstripped, so an exported token reaches the sandboxed shell. Either give the executor its own credential, or keep it credential-free and split the work: executor verifies and commits, orchestrator pushes and opens the PR. The deny-list forbids merges either way.

**`workspace-write` does not pin its own limits.** `network_access` and `writable_roots` are inherited from the user's `config.toml`, so a wrapper passing only `--sandbox` is silently widened by user config. Pin both on the command line (`-c` beats `config.toml`). The `.git` dir is read-only in the sandbox by design (a writable `.git/hooks` lets a sandboxed agent plant a hook that runs unsandboxed), so committing needs the git dirs as extra writable roots, which re-opens that escape; `codex-mem.sh` derives them. "Run code, never write the repo" is `workspace-write` rooted in a scratch dir, not `read-only`, because read-only blocks `mktemp` and so blocks running tests.

**Execpolicy is deny-override, so it cannot be an allowlist.** When several `prefix_rule`s match, `forbidden` wins regardless of specificity, so a broad deny swallows any narrower allow. An unmatched command gets no decision and defers to the sandbox, which with network enabled means it runs without a prompt. Whole un-enumerated tools still run. `~/.codex/rules/default.rules` is therefore optional defense in depth (see `docs/workflow.md`); the primary guard is the `PreToolUse` hook plus the deny-list restated in the delegation prompt. The `decision` value must be exactly `"forbidden"`; test rules with `codex execpolicy check --rules <file> <cmd...>`. Runs outside a git repo need `--skip-git-repo-check`.

**Hook stdin schemas differ by harness, and a wrong path fails open.** Codex puts the shell command at `tool_input.command`; Antigravity uses `toolCall.args.CommandLine`. A guard reading the wrong path extracts empty and allows everything, and a unit test hard-coding the wrong schema passes green. Read `tool_input.command` first and fall back to the Antigravity path, and capture real stdin with a dump-to-file hook before writing a guard. A `PreToolUse` guard exiting 2 with the reason on stderr is honored and blocks the tool.

**Bare mode skips injection, not the sandbox.** `AI_MEMORY_SKIP_INJECT=1` (set by `codex-mem.sh --executor-bare`) makes the memory hooks emit nothing; `project_doc_max_bytes=0` only skips a hand-owned `AGENTS.md`. Use it for lean read-only fan-out; deny rules and sandbox still apply.

**Probing codex hooks hermetically has two traps that give convincing wrong answers.** A hermetic `CODEX_HOME` isolates auth too, so every run fails 401 and a hook that did fire looks "not injected": seed `auth.json` from the real home first. And a standalone `codex exec` blocks on open stdin and hangs: always `</dev/null`. Make the probe falsifiable with a marker the model must echo. macOS has no `timeout(1)`, so a `timeout N cmd` guard exits 127 and every probe silently finds nothing.

Hook schema, trust model, size cap and chunking: `docs/harnesses/codex.md`. Cross-harness context: [[agent-tooling]].
