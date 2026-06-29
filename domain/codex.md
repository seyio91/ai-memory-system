---
topic: codex
triggers: [codex, openai-codex, codex-mem, executor, executor-bare, stall, fallback, agents-md, sandbox]
summary: OpenAI Codex CLI — reliability/stall behavior and the codex-mem executor adapter (token-stripping, deny-rules, sandbox)
---

# Domain: Codex

## Knowledge
<!-- Append entries as: **[YYYY-MM-DD]** what — why it matters -->

**[2026-06-15]** `codex-mem.sh --executor-bare` strips the AGENTS.md memory stack (~13.6k tokens) via `-c project_doc_max_bytes=0` — a bare Codex executor lands at ~20.4k tokens, equal to a Claude `Agent` subagent. **Why:** read-only/throwaway subagent work (PR review, render, validate, search) doesn't need the memory stack, and the saving compounds when fanning out many subagents. **How to apply:** use `--executor-bare` as the primary for lean read-only fan-out (Claude `Agent` as fallback); reserve full `--executor` for work that needs project memory context. Deny-rules guardrails still apply in bare mode; the sandbox blocks `rm -rf`, so subagents clean up with a workspace-relative temp dir + `rm -r`.

**[2026-05-17]** OpenAI `codex` stalls silently after sustained use — observed pattern: reliable for the first ~5 tasks of a session, then exits 0 with no output and no diff. Retrying in-place does not help. **Proven fallback:** delegate to a general-purpose Claude subagent with the sonnet model — clean completions for code cutover, template review, and schema work. Rule: when codex stalls, switch agent rather than retry.
