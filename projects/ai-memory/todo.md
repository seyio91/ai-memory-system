# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Antigravity hook-archetype (live injection + PreToolUse enforcement) → [plan](plans/antigravity-hook-archetype.md)
_Design approved 2026-07-06 (brainstorm). Pure-hook injection + executor-only PreToolUse guard. Phase 0 (probe tool catalog) gates the rest._
- [x] Phase 0 — probe `agy` tool catalog + `hooks.json` install location (prerequisite) — findings folded into plan; install target = global `~/.gemini/config/hooks.json`
- [x] Phase 1 — PreInvocation live injection (manifest `archetype=hook`; agy.sh exports project; hook driver registers hooks.json) — verified live: agy answered from injected memory
- [x] Phase 2 — PreToolUse guard (executor-only, `AI_MEMORY_ROLE`-gated) + shared deny-list + Antigravity `exec_readonly` — verified vs live agy payload shape
- [ ] Phase 3 — docs

### System showcase (doc + diagrams + live demo) → [plan](plans/system-showcase.md)
_Draft 2026-07-06. 60-min live technical deep-dive against the real system; educate/document. Mermaid + 2 Excalidraw heroes._
- [x] Phase 1 — content skeleton + capability→beat→diagram mapping _(docs/showcase.md skeleton; arc table locked)_
- [x] Phase 2 — diagrams (4 Mermaid inline + 2 Excalidraw heroes) _(all 4 mermaid render via mmdc; both heroes render + visually validated)_
- [x] Phase 3 — document body (`docs/showcase.md`, capability tour grounded in real files) _(8 sections + arc appendix; cross-linked to reference docs)_
- [x] Phase 4 — demo runbook (`docs/demo-runbook.md`, beats + commands + minute budget + kept-flexo note) _(pre-flight + 7 beats + timing sheet)_
- [x] Phase 5 — dry-run against real tree + validate against success criteria _(all read/generator cmds clean; onboarding chain proven on throwaway; fixed `/activity --all` + `bash install.sh`; surfaced install.sh non-exec defect; timing budgeted to 60m)_

## Done
_(checked items stay above until the file is rolled)_
