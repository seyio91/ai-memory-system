---
plan: consolidate-agents-to-memory
status: done
created: 2026-06-15
completed: 2026-06-16
owner: claude (orchestrator)
task_provider: local
task_ref: 380f6850-c619-80cb-821e-c68728eeb2ca
---

# Plan — Consolidate agents into the memory system (harness-agnostic, symlinked)

## Goal
Move the Claude Code subagent definitions (`~/.claude/agents/*.md`) into a canonical store in the memory system and symlink them back into each harness's agents dir — mirroring the existing skills consolidation — so agent definitions live in one source-of-truth, survive across harnesses, and can be reused with other LLM providers later. v1 is symlink-only; cross-provider translation is deferred behind a documented extension point.

## Success criteria
- `~/Downloads/personal/claude/memory/agents/` holds the 4 real agents (`azure-infra-engineer`, `devops-engineer`, `kubernetes-specialist`, `terraform-engineer`); the empty `platform-engineer.md` stub is **not** migrated.
- `~/.claude/agents/<name>.md` are symlinks into the store, and all 4 agents still resolve in Claude Code (visible to the Agent tool).
- `scripts/link-agents.sh` exists and: is idempotent (second run reports all already-current), repairs a deliberately-broken link, refuses to clobber a planted real file / foreign symlink, skips empty/frontmatter-less files, and supports `--list` + `--dry-run` + `[TARGET_DIR]` + `AGENTS_SRC` override.
- `domain/agent-tooling.md` records the agents-consolidation entry and the cross-provider translation extension point.

## Design
- **Chosen approach — sibling `link-agents.sh`** structurally identical to `link-skills.sh`, operating on flat `*.md` **files** (agents are single files, not dirs like skills). Per-file symlink; idempotent; repair-stale; refuse-to-clobber. Validity gate = file is non-empty and has a leading `---` frontmatter block (this is what drops the stub). Flags: `--list`, `--dry-run`, `[TARGET_DIR]` (default `~/.claude/agents`), `AGENTS_SRC` env override (default `<memory>/agents`).
- **Canonical store** = `<memory>/agents/`, flat `*.md` (mirrors source shape; sibling to `<memory>/skills/`).
- **Cross-provider** = symlink only for now; the system-prompt body is portable and Claude Code is the sole current consumer. Extension point: when a harness with a divergent agent schema appears, that target gets a transform-and-copy branch in the linker (emit a translated file instead of a symlink) — localized to the linker, no store change.
- **Alternative — generalize into a shared `_lib.sh` both linkers call** → rejected: factoring symlink/repair/clobber logic to handle both file- and dir-entries adds indirection for ~40 lines saved; defer until a third linker exists.
- **Alternative — add a `--agents` mode to `link-skills.sh`** → rejected: overloads one script with two entry shapes and two default targets; worse discoverability and higher risk to the working skills linker.

## Decisions (locked)
- Symlink-only in v1; no translation layer built now (YAGNI).
- Drop the empty `platform-engineer.md` stub.
- Sibling `link-agents.sh`, not a generalized lib or a mode flag on `link-skills.sh`.
- Store is flat `*.md` files under `<memory>/agents/` (not one-dir-per-agent).

## Phases
### Phase 1 — Create the canonical store + migrate
- Create `<memory>/agents/`; copy the 4 non-empty agents in; do not copy `platform-engineer.md`.

### Phase 2 — Write `scripts/link-agents.sh`
- Adapt `link-skills.sh`: flat-file entries, frontmatter/non-empty validity gate, default target `~/.claude/agents`, `AGENTS_SRC` override, `--list`/`--dry-run`.

### Phase 3 — Cut over the live dir
- Remove the 4 original real files from `~/.claude/agents/`; run `link-agents.sh --dry-run` to preview, then live; verify symlinks resolve and agents are visible.

### Phase 4 — Verify idempotency + safety
- Re-run (all current); break a link and confirm repair; plant a real file and confirm no-clobber; confirm stub skipped.

### Phase 5 — Document
- Add the agents-consolidation entry + translation extension point to `domain/agent-tooling.md`.

## Risks / open questions
- None blocking. Deferred: actual cross-provider translation (until a second consumer exists); optional later refactor of the two linkers into a shared lib.
