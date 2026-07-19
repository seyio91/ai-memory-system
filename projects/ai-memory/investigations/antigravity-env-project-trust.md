---
doc: antigravity-env-project-trust
kind: investigation
status: open — defect confirmed by reading, not yet reproduced live
created: 2026-07-20
owner: claude (orchestrator)
task_ref: 3a2f6850-c619-81ac-ac8c-dc2c9204af21
---

# Investigation — antigravity trusts an inherited `AI_MEMORY_PROJECT`

## The defect

`harnesses/antigravity/hooks/preinvocation.sh:30`:

```sh
PROJECT="${AI_MEMORY_PROJECT:-}"
...
[ -n "$PROJECT" ] || no_inject     # empty -> dormant
```

The project comes **solely** from an inherited environment variable. There is no
`detect_project "$CWD"` fallback and no cross-check: whatever value is in the
environment is trusted unconditionally, and injects that project's `identity` /
`orchestrator` / `project` / `index` / `working` payload into every model call.

`harnesses/antigravity/scripts/agy.sh:27-28` exports both `AI_MEMORY_PROJECT` and
`AI_MEMORY_CWD` into the launched process's environment, and env inherits into
every descendant.

## Scope — narrower than first claimed

**An earlier claim of mine, repeated in the PR #87 body and in a working.md
checkpoint, was wrong**: I stated that an executor launched from an antigravity
session inherits the orchestrator's project. It does not, on the supported path.
`harnesses/antigravity/manifest:47-48` routes both `exec_cmd` and `exec_readonly`
through `agy.sh`, which re-runs `detect_active_project` at every launch and
overwrites the inherited value. The wrapper's own header says exactly this:

> Alias `agy` to this so every launch (interactive, or `agy -p` executor
> delegation) resolves the right project.

So the delegation path is sound. What remains is the *unconditional trust*:

- Any `agy` invoked **without** the wrapper — a bare binary call, a shell whose
  alias is absent (non-interactive shells do not inherit aliases), a nested tool
  call — inherits the parent's exported value and injects that project.
- The failure is **silent and total**: not a wrong path in a breadcrumb, but the
  whole memory payload for the wrong engagement, with nothing to contradict it.
- It is also the only project resolver in the tree with **no** cwd fallback.
  Claude and Codex both walk from `cwd` and, since PR #87, consult a
  session-keyed pin file whose failure paths all degrade to that walk.

## Why a file beat env in PR #87 — the same reasoning applies here

The session-pin design deliberately rejected an env var precisely because env
inherits into child processes; a session-keyed file cannot leak into a child,
since the child is a different session or none. Antigravity is the harness that
took the other branch, and this is the residual cost.

## Proposed fix

Give `preinvocation.sh` the fallback every other resolver has:

1. Resolve `cwd_project = detect_project(cwd)`.
2. Use `AI_MEMORY_PROJECT` when set **and** it agrees with `cwd_project`, or when
   `cwd_project` is empty (a launch outside any pinned checkout).
3. When they disagree, prefer `cwd_project` — the launch location is the stronger
   signal — and surface the divergence the way `<memory:active>` now does.

## Open questions

- **Not reproduced live.** This is read from the source; the failure mode should
  be demonstrated with a real nested `agy` before the fix is written, so the fix
  is verified against an observed defect rather than an inferred one. This
  project's own doctrine — a control is not trusted until watched to fail —
  applies to the bug as much as to the control.
- Does antigravity's hook payload really carry no workspace handle? `agy.sh`'s
  header asserts it, which is why the env channel exists at all. If a handle does
  exist in a newer build, the env dependency could be removed entirely rather
  than merely guarded.
- `statusline.sh:60` reads the same variable. Lower stakes (display only), but it
  inherits the identical assumption and should be checked in the same pass.
