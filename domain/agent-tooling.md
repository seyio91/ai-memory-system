---
topic: agent-tooling
triggers: [subagent, skill, symlink, link-skills, harness-agnostic, project-scoped-skills]
summary: Harness-agnostic skill & subagent management — one canonical store linked into each harness, project-scoped skills, per-harness containment (codex-specific behavior lives in domain/codex.md)
---

# Domain: Agent Tooling

## Knowledge
<!-- Durable patterns and traps only — no version pins, file:line refs, counts, dated status or incident narratives. Name the file or command that answers it. -->

**Skills and agents live in one canonical store, linked per entry into each harness.** Per-skill symlinks, never a whole-folder link (a folder link orphans skills the harness already had). The store is the set of roots in `AI_MEMORY_SKILL_ROOTS` (`skills/` and `.skill-cache/`; `SKILLS_SRC` is a legacy single-dir override); edit the file in the store, not through the harness path. Only dirs containing `SKILL.md` are linked, which keeps `*-workspace` scratch dirs out. Agents are flat `<name>.md` files with a validity gate in `scripts/link-agents.sh`. Mechanics: `scripts/link-skills.sh`, `scripts/link-agents.sh`, `docs/install.md`, `docs/harnesses/claude.md`.

**A global symlink shadows the project skill.** Claude Code resolves personal (`~/.claude/skills`) above project (`<repo>/.claude/skills`), so moving a skill to project scope requires removing its global link first, or the global copy wins everywhere. **Scope a skill by where it should trigger, not by its name:** a skill with a client-flavoured name but a generic trigger stays global; project scope (`scripts/sync-project-skills.sh`) is for skills that are genuinely single-repo.

**Skills and agents register at SessionStart.** A skill or agent written mid-session is invisible until the next session, and the first invocation fails as "Unknown skill", which reads like a frontmatter error rather than a registration-timing one. Run the `SKILL.md` procedure by hand to test it in the session that wrote it.

**Containment is per-harness, and the executor flags decide it.** Codex has a kernel sandbox plus execpolicy; the other CLI executors (antigravity, copilot, opencode) run as the plain user process with approval-bypass or allow-all flags in their manifest `exec_cmd`, so `.git` is writable, the keychain answers and `gh` is authenticated. Two consequences cut opposite ways: a "credential-free executor" posture only exists on codex, and elsewhere the only structural backstop is the `PreToolUse` guard (or nothing, where a harness has no guard). **Restating the deny-list in every delegation prompt is therefore load-bearing on exactly the harnesses that look safest to skip it on.** If a manifest ever adds a sandbox flag, re-probe both failure classes (`git commit` in a scratch repo; `git credential fill` inside vs outside) before trusting it. Read `harnesses/<name>/manifest` for what is actually passed.

**Executor commits are an orchestrator contract, not an executor feature.** Even where a worktree executor can commit (`codex-mem.sh` widens the git dirs), keep "executor edits and verifies, orchestrator commits" as the standing split: it is the review gate and the only shape needing no credential in the sandbox. Background dispatch and output shapes are in `docs/workflow.md`.

**Cross-model validation is evidence, not theory.** Prose contracts (a doctrine `else` that inverts its meaning, an ambiguous gate) pass same-model executor, validator and orchestrator review because the model reads past what it would have written; a different model reading cold catches them, and re-running a same-model validator on the same defect does not. Treat the two as complementary: one runs the suite and mutations, the other reads cold. The default lives in `docs/workflow.md`; see [[codex]].

**A CLI proxy or output filter makes "empty" unproven.** When a hook rewrites or compresses command output, confirm an "empty", "absent" or "ok" result through an unproxied channel (`find`, the Read/Glob tools, raw passthrough) before concluding data is missing; a silent exit-0 partial looks identical to a true result.
