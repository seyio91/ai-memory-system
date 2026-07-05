Scaffold a new plan file in the active project's `plans/` directory.

Argument: `$ARGUMENTS` — the plan name (kebab-case slug, no `.md` extension).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.claude/memory-project`).

Step 2 — guard against overwrite. If `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md` already exists, abort and tell the user the path exists — they should pick a different slug or edit the existing file.

Step 3 — write the file with this scaffold (today's date is in the `<memory:identity>` injection context — use it; do not invent):

```markdown
---
plan: $ARGUMENTS
status: draft
created: YYYY-MM-DD
owner: claude (orchestrator)
# task_provider / task_ref: written by the /start task-linking step when this plan
# is backed by a captured task (see README → Task-provider layer). Omit otherwise.
---

# Plan — <human-readable title>

## Goal
<one paragraph: what problem this plan solves>

## Success criteria
<the checkable conditions that define "done" — each one a Validator could verify by reading output, running a command, or inspecting state. Required for plan-tier work (see identity.md → Task Contract). If the user did not state criteria, draft best-effort ones from session context; never leave this blank.>
- <criterion>

## Design
<for feature-tier plans this is populated by the brainstorming skill: the chosen approach (unit boundaries/interfaces, data flow, error handling) plus a one-line note per rejected alternative and why it lost — a lightweight decision record. For settled-shape plans (mechanical refactors, renames, migrations) that skipped brainstorming, a one-line statement of the known approach suffices.>
- <chosen approach>
- <alternative considered → why rejected>

## Decisions (locked)
- <bullet>

## Phases
### Phase 1 — <name>
- <step>

## Risks / open questions
- <bullet>
```

Step 4 — ask the user one line: "Plan scaffolded at `<path>`. Want me to draft the Goal, Success criteria, and Phases from session context, or will you fill it in yourself?" Then act on the answer. If the user opts to fill it in, do not invent content — except **Success criteria**, where if the user proceeds to execution without stating them, draft best-effort criteria from context and surface them for confirmation (per identity.md → Task Contract).

Step 5 — remind the user to add a checkbox item in `projects/<active>/todo.md` linking to the new plan (use the existing `### <topic> → [plan](plans/<name>.md)` pattern).
