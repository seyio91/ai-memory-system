---
topic: codex
triggers: [codex, openai-codex, codex-mem, executor, executor-bare, stall, fallback, agents-md, sandbox]
summary: OpenAI Codex CLI — reliability/stall behavior and the codex-mem executor adapter (token-stripping, deny-rules, sandbox)
---

# Domain: Codex

## Knowledge
<!-- Append entries as: **[YYYY-MM-DD]** what — why it matters -->

**[2026-06-29]** Codex execpolicy (`~/.codex/rules/default.rules`, the executor guardrail) is **deny-override, not longest-match** — when several `prefix_rule`s match a command, `forbidden` always wins regardless of specificity. Verified with `codex execpolicy check --rules <file> <cmd…>` (non-mutating; use it to test rules): a specific `gh pr merge→forbidden` beats a broad `gh→allow`, AND a broad `kubectl→forbidden` overrides a specific `kubectl get→allow`. **Two consequences:** (1) you **cannot** build a default-deny allowlist (broad deny + read-only carve-outs) — the deny swallows the carve-outs; the file must stay a **denylist** (enumerate forbidden verbs, leave the rest). (2) An **unmatched** command yields `{"matchedRules":[]}` (no decision) — execpolicy defers to the sandbox, so under `codex exec --sandbox workspace-write -c …network_access=true` (the `codex-mem.sh --executor` mode, no approval prompts) any unmatched command that only needs the network **runs without prompt**. So a denylist must explicitly forbid every mutating verb (`terraform state push/rm/mv`, `terraform import/taint/force-unlock`, `gh api` (raw-REST merge bypass), `kubectl edit/set/drain/exec/run/cp/…`); whole un-enumerated tools (`aws`/`gcloud`/`psql`/`curl`) still run — the real backstop is the no-apply/no-merge instruction restated in every delegation prompt + human gates, with the deny-rules as defense-in-depth. `decision` keyword is `"forbidden"` (not `deny`/`block`).

**[2026-06-15]** `codex-mem.sh --executor-bare` strips the AGENTS.md memory stack (~13.6k tokens) via `-c project_doc_max_bytes=0` — a bare Codex executor lands at ~20.4k tokens, equal to a Claude `Agent` subagent. **Why:** read-only/throwaway subagent work (PR review, render, validate, search) doesn't need the memory stack, and the saving compounds when fanning out many subagents. **How to apply:** use `--executor-bare` as the primary for lean read-only fan-out (Claude `Agent` as fallback); reserve full `--executor` for work that needs project memory context. Deny-rules guardrails still apply in bare mode; the sandbox blocks `rm -rf`, so subagents clean up with a workspace-relative temp dir + `rm -r`.

**[2026-05-17]** OpenAI `codex` stalls silently after sustained use — observed pattern: reliable for the first ~5 tasks of a session, then exits 0 with no output and no diff. Retrying in-place does not help. **Proven fallback:** delegate to a general-purpose Claude subagent with the sonnet model — clean completions for code cutover, template review, and schema work. Rule: when codex stalls, switch agent rather than retry.
