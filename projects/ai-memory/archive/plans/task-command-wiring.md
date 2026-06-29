---
plan: task-command-wiring
status: done
created: 2026-06-12
completed: 2026-06-12
owner: claude (orchestrator)
---

# Plan — /task and /start slash-command wiring

## Goal
Make the task-provider layer usable from inside Claude via two slash commands. `/task` is a multi-verb surface (`add|list|done|archive|show`) that defaults the project to the active `.claude/memory-project` marker and accepts a leading `@project` override. `/start <ref>` pulls a captured task from the flat store (project-agnostic — reads the task's own project from frontmatter), classifies its tier against the pulled summary, runs the brainstorming skill for feature-with-open-design tasks (else straight to plan scaffold), creates the plan in the task's project with `task_provider`/`task_ref` linked, pushes the refined Goal back to the task via `update`, and flips status to `started`. This realizes the `/start` delegation contract previously documented-not-implemented.

## Success criteria
- `scripts/taskctl` exists, executable, honors `MEMORY_DIR`, sets `PYTHONPATH=$MEMORY_DIR/scripts`, execs `python3 -m taskprovider "$@"`; `taskctl ping` → `{"ok": true}` exit 0.
- `~/.claude/commands/task.md` exists: resolves active project from the injected `<memory:active project="...">` breadcrumb; supports `add` (default verb), `list`, `done`, `archive`, `show`; `@project` overrides; `add` splits `title — summary` on ` — `/` | `; no active project AND no `@project` on a project-needing verb → clear abort.
- `~/.claude/commands/start.md` exists: `/start <ref>` → `taskctl get <ref>` → reads project+summary+status; warns if not `backlog`; classifies feature-open-design vs settled/quick; feature-open-design → invokes the `brainstorming` skill with the summary as seed; settled/quick → scaffolds the plan directly; plan lands in the **task's** project (`projects/<task-project>/plans/<slug>.md`) with frontmatter `task_provider: local` + `task_ref: <ref>`, design folded into Goal/Design/Success criteria/Risks; pushes clarified Goal back via `taskctl update <ref> --summary "..."`; `taskctl set-status <ref> started`; adds a `todo.md` entry in the task's project. Bare `/start` lists the active project's backlog to choose.
- README updated coherently: `/task` + `/start` rows in the Slash commands table; `task.md`/`start.md` in the `~/.claude/commands/` tree; the "`/start` delegation contract" section flips from "documented, not implemented" to implemented (contract unchanged); `/task` noted in the Task-provider layer section.
- `scripts/tests/test_taskctl.sh` passes in the existing harness; full harness green; `lint-memory.sh` exit 0; `regenerate-index.sh` index unchanged.
- Nothing in the provider layer (`scripts/taskprovider/`) changed — slash wiring is pure orchestration above the CLI.

## Design
Settled after two clarifications (multi-verb `/task`; by-ref project-agnostic `/start`). Slash commands are markdown instruction files (interpreted by Claude, like `new-plan.md`/`pin.md`), not executables — they translate friendly syntax into `scripts/taskctl` calls and read the active project from the injected breadcrumb. A thin `taskctl` bash wrapper removes the `PYTHONPATH`/`-m` boilerplate and is shell-usable too. Cross-project `/start`: because the local store is flat with `project:` in frontmatter, a `ref` is globally unique, so `/start` resolves the task's project from `get` and scaffolds the plan into THAT project rather than the active one — sidestepping `/new-plan`'s active-only assumption (so `/start` owns plan placement, using the `/new-plan` scaffold as the template + folding in the brainstorm design). Alternatives rejected: active-project-only `/start` (can't start cross-project, which the user explicitly wants — rejected); capture-only `/task` (user chose full multi-verb); a Python CLI subcommand for the friendly parsing (keeps bash/Claude as glue per the layer's boundary — rejected, parsing stays in the command instruction).

## Decisions (locked)
- `/task` full multi-verb, active-project default, `@project` override; `add` is the implicit default verb.
- `/start` by-ref, project-agnostic; plan lands in the task's project; bare `/start` = active-backlog picker.
- Provider layer untouched; new code is one bash wrapper + two command markdown files + docs + one test.
- `taskctl` honors `MEMORY_DIR` (single location knob); no new env vars.

## Phases
### Phase 1 — `taskctl` wrapper + test
- Write `scripts/taskctl` (bash 3.2, `MEMORY_DIR`, `PYTHONPATH`, exec `python3 -m taskprovider`). `chmod +x`. Add `scripts/tests/test_taskctl.sh` (temp MEMORY_DIR, seed a project, ping + capture + list round-trip).

### Phase 2 — `/task` command
- `~/.claude/commands/task.md` with verb parsing, active-project resolution, `@project` override, friendly output.

### Phase 3 — `/start` command
- `~/.claude/commands/start.md` with get→classify→brainstorm/scaffold→link→update→started, project-agnostic, bare-list mode.

### Phase 4 — Docs
- README: Slash-commands table rows, commands tree entries, flip the `/start` section to implemented, note `/task`. Keep coherent with brainstorming + provider sections.

### Phase 5 — Verify + live demo
- Harness green, lint 0, index unchanged. Then demo `/start` on the user's real `fiter-argo-apps` captured task (their stated goal).

## Risks / open questions
- Active project ≠ task project on cross-project `/start`: plan must land in the task's project (handled by reading project from `get`, not the breadcrumb).
- Brainstorming skill's terminal handoff is `/new-plan` (active project); `/start` instead owns scaffolding into the task's project to avoid the mismatch — keep the two consistent so a same-project `/start` and a direct `/new-plan` produce the same plan shape.
- Slash commands are model-interpreted, not deterministic scripts — keep the instructions explicit and the `taskctl` calls exact so behavior is reliable.
