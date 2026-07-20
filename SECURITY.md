# Security Policy

## Reporting a vulnerability

**Use [GitHub private vulnerability reporting](https://github.com/seyio91/ai-memory-system/security/advisories/new)** — Security → Report a vulnerability. It's enabled on this repo.

Please don't open a public issue for anything exploitable. There is no SLA — this is a single-maintainer personal project — but reports are read and you'll get an acknowledgement.

## Supported versions

Only the **latest `v*` tag** is supported. Releases are git tags; there is no backport branch, and fixes land on `main` and ship in the next tag.

Note that `v1.0.0` is a known-bad tag: it predates `identity.md` being untracked, so syncing an instance to it can overwrite local identity data. Don't pin to it. `v1.1.0` is the earliest safe release.

## What this project actually does to your machine

Worth stating plainly, because the risk surface isn't obvious from "it's a folder of markdown files":

- **Hooks run shell on every prompt.** `install.sh` registers hook scripts with your harness (Claude Code, Codex CLI, Antigravity). They execute on `SessionStart` and `UserPromptSubmit`, in your shell, with your permissions.
- **`install.sh` writes into harness config directories** — `~/.claude/`, `~/.codex/`, and equivalents — and symlinks `~/.claude-memory` at the clone. It backs up what it overwrites, but it is not a sandboxed install.
- **Memory content is injected into model context verbatim.** Anything in your memory tree becomes instructions-adjacent text the model reads. Treat files you didn't write — a shared `domain/` file, a skill pulled from a remote repo — as untrusted input in the prompt-injection sense.
- **Executors invoke agentic CLIs with tool access.** `scripts/executor.sh` can launch write-capable agents. `scripts/deny-list.txt` blocks destructive infrastructure operations, but a deny-list is defense in depth, not a sandbox. Read-only roles (`explore`, `validate`) resolve through a harness's read-only face and are never silently upgraded to write-capable.
- **Remote skills are referenced, not vendored.** `skills.toml` + `.skill-cache/` materialize third-party skill content that the model then follows as instructions. Pin what you trust; the lockfile exists for this reason.

## Reporting scope

In scope: anything that escalates the above beyond what a user reasonably consented to — a hook that executes attacker-controlled input, an installer path traversal, a deny-list bypass, an injection vector that turns memory content into unintended tool calls, or accidental disclosure of gitignored personal content through a tracked file or release tag.

Out of scope: the fact that hooks and executors run code at all (that's the design, documented above), and anything requiring an attacker who already has write access to your memory tree or your shell.
