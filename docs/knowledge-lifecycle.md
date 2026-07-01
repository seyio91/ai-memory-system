# Knowledge lifecycle

```
                                          ┌──▶ domain/<topic>.md      cross-project
projects/<active>/working.md  ─/promote-──┤    [+ index.md regen]
   [per-project scratchpad]               └──▶ projects/<active>/memory.md ## Decisions Log
                                               project-specific
```

- **Working memory** — per-project scratchpad. Injected on every prompt while non-empty. Each project has its own — concurrent sessions on different projects don't collide.
- **Direct project memory updates** — for engagement-specific decisions, edit `projects/<active>/memory.md` directly (Architecture Decisions / Known Constraints / Current State / Current Goal).
- **Checkpoint discipline** — before pauses, tool switches, or session end. `/checkpoint` in Claude; `/checkpoint` in Codex. Both write to the same `working.md`.
- **Promotion** — `/promote-memory` reads `working.md`, asks domain-or-project, captures a one-line summary, archives the old `working.md`, regenerates `index.md`.
- **Graduation** — manual. When a domain file matures into a reusable pattern, package it as a Claude Code skill.

## Domain vs. skill

A **domain file is knowledge** (something an agent *knows*); a **skill is a capability** (something an agent *does*).

| | `domain/<topic>.md` | Skill |
|---|---|---|
| Purpose | Durable cross-project knowledge — conventions, gotchas, decisions | A repeatable procedure/capability |
| Content | Descriptive markdown + frontmatter | Procedural instructions, often with bundled scripts/templates |
| How it's reached | Lazy read — its row in `index.md` (Claude) / the Domain Index in `AGENTS.md` (Codex) matches your request's triggers, then the agent opens the file | Invoked — auto-discovered via its `description`, or called explicitly; its instructions are loaded and followed |
| Lives in | The memory tree (`domain/`) | The agent's skill system — Claude Code skills, or Codex `~/.codex/skills/` (e.g. the `checkpoint` skill) |

They sit on one maturation path: `working.md` (scratch) → `domain/*.md` (stable knowledge) → skill (reusable procedure). Not every domain file graduates — most stay as reference; graduation is deliberate, since a skill is heavier (structured, versioned, broadly triggered). Often the two coexist and point at each other: a short `domain/<topic>.md` records the facts and *points to* the skill(s) that hold the detailed procedure. **Rule of thumb:** a *fact you want to recall* → domain file; a *procedure you want to re-run* → skill. Because skills are per-agent, a cross-agent procedure may need both a Claude skill and a Codex skill sharing the same domain file as source of truth.

Not every skill graduates from a domain file, either. The `brainstorming` skill (see [Skills](harnesses/claude.md#skills)) was authored directly as a Claude-only, orchestrator-only capability — it encodes a procedure (the Tier-3-feature design pass) that never existed as cross-project *knowledge*, so it has no `domain/*.md` source and gets no index row. Authoring a skill outright is fine when the thing is a procedure from the start; the maturation path is the common case, not the only one.

---

# Memory governance

- `archive/` is the audit trail (plans, todos, working-memory snapshots). **Never delete it** during a "reorganize memory" pass.
- The directory is **not git-managed** by design — treat as personal, never commit secrets.
- `_template` is excluded from index, lint, and regeneration. Edit it when changing the project scaffold.
- Frontmatter is the contract. Skipping it breaks the index and the Codex Domain Index. Lint catches it.

---

# Design rationale

- **Markdown over a DB:** every editor, every diff tool, every grep works on it. No infra.
- **Hook-injected, not retrieved:** Claude doesn't need to "remember to look" — context arrives in-band via `additionalContext` on the first prompt of each session. Codex gets the equivalent via a generated `AGENTS.md`.
- **Per-session injection markers:** once-per-session blocks are tracked per `session_id` under `memory_sessions/`, so concurrent Claude sessions don't re-inject, and dead markers self-expire after 2 days.
- **Distributed cross-project relationships:** a relationship lives in the project where the work starts (`## Related Projects`), and siblings are delegated to executors, never preloaded — so a multi-repo sequence is coordinated without resident sibling memory.
- **Enforced, not just documented, where it matters:** the task-tool block is a real `PreToolUse` deny and the executor infra-deny is a real codex execpolicy rule — load-bearing conventions are backed by mechanism.
- **Tested scaffolding:** the `scripts/tests/` suite pins script behavior (index-regen idempotence, lint failure modes, scaffold-only new-project, hook output contract, AGENTS.md build order) so a rebuild can be verified, not assumed.
- **Frontmatter-driven catalog:** the index never lags behind the files. Adding a new domain file is one drop + one regen.
- **Index is a path-less roster:** `index.md` carries only names/topics + summaries — no file paths, no per-project metadata. Paths are derivable (`projects/<name>/memory.md`, `domain/<topic>.md`), and metadata (`tags`/`repo_path`/`repo`, domain `triggers`) lives in the source file. The active project's memory is auto-injected; everything else is loaded on demand by deriving its path. (Codex's `AGENTS.md` domain index keeps absolute paths — its shell tool reads by path.)
- **Lazy domain loads in Codex:** the index is in the system prompt; the bodies are read on demand. Scales as `domain/` grows without bloating every Codex session.
- **One-way reverse sync from Codex:** the `/checkpoint` skill captures Codex session takeaways back into `working.md`, so insights don't die in `logs_2.sqlite`.
- **Two operations distinguished:** *reorganize* is structural (dedup, merge, split). *Lint* is content-quality (contradictions, staleness, orphans). They live separately because they fail differently.
