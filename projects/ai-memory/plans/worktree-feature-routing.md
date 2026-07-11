---
plan: worktree-feature-routing
status: in_progress
created: 2026-07-11
owner: claude (orchestrator)
task_provider: notion
task_ref: 399f6850-c619-812d-be9c-df01bce8ea1f
---

# Plan — Route feature work through harness worktrees

## Goal

Make starting a Tier-3 feature in an isolated git worktree a one-flag operation. `/start --worktree`
(or an interactive offer) enters a fresh worktree named after the task, so concurrent features on one
repo get isolated scratchpads — leveraging the PR #54 overlay, which already routes `working.<key>.md`
off the session cwd. The harness does the heavy lifting (Claude `EnterWorktree` switches + refreshes
in-session); this plan is the thin routing layer on top, plus documented+tested processes for the
harnesses without an in-session switch.

## Scope note — the mechanism already shipped

PR #54 (task `385f6850`) built the overlay resolver and wired it into every harness's read + write
path, and it composes with native worktree support (verified end-to-end for Claude's
`.claude/worktrees/` layout with a separate memory tree). So this task adds **no new resolver code** —
it is a `/start` command-instruction change + cross-harness process validation + docs.

## Success criteria

1. `/start` accepts `--worktree` and, when the flag is absent on a **Tier-3 feature** task, offers it
   interactively ("start in a fresh worktree? [y/N]"). On yes, it invokes `EnterWorktree name=<slug>`
   as its **final** step — after the plan is linked, status flipped, and todo written — before offering
   Phase 1. Bookkeeping stays in the main checkout; execution moves into the worktree.
2. Guards, verified by inspection of the command text: already **in** a worktree → skip + warn (already
   isolated); not a git repo / no worktree support → skip gracefully. Never errors the `/start` flow.
3. The worktree name = the plan slug (kebab of the title, ≤64 chars, `EnterWorktree` charset), so the
   overlay auto-resolves to `working.<slug>.md` with zero new wiring.
4. **Codex process test** — starting from a linked worktree, BOTH the context build (`codex-mem.sh` →
   `AGENTS.md`) and the checkpoint writer (`codex-mem-checkpoint.sh`) use `working.<wt>.md`, not the
   base — validating the documented "`git worktree add` + run codex in it" process end to end.
5. **Antigravity process test** — with `AI_MEMORY_CWD` = a linked worktree, `preinvocation.sh` injects
   `working.<wt>.md`, not the base — validating the documented "open the worktree as a workspace" process.
6. Docs: `docs/harnesses/claude.md` documents `/start --worktree`; `docs/harnesses/codex.md` and
   `docs/harnesses/antigravity.md` document the manual-worktree process; the deferred `/prune-overlays`
   is noted as a future option.
7. Full `run-tests.sh` green (incl. the command-surface test, which still passes with the `/start` edit).

## Design

**A. Trigger — `/start --worktree` (Decision 1b).** Edit `harnesses/claude/commands/start.md`: add a
`--worktree` flag and an interactive offer for Tier-3 feature tasks. When chosen, the very last `/start`
action (after link + status flip + todo) is an `EnterWorktree name=<slug>` call — a tool the model
invokes while following the command. Entering last keeps `/start`'s memory-tree bookkeeping in the main
checkout; only the subsequent execution runs in the worktree. The plan/todo live in `MEMORY_DIR`
(unaffected by the code-repo cwd switch); the scratchpad becomes `working.<slug>.md` automatically.

**B. Naming.** Worktree name = the plan slug already computed by `/start`, truncated to 64 chars. It is
kebab-case (letters/digits/dashes) — inside `EnterWorktree`'s allowed charset — so no sanitization is
needed. The overlay resolver (PR #54) keys off the worktree name, closing the loop.

**C. Cleanup — none new (Decision 2a).** PR #54 already gitignores `working*.md` and lints stale
overlays. A removed worktree's overlay lingers harmlessly; the stale-warning is the cleanup nudge.

**D. Cross-harness.** Codex/Antigravity have no `EnterWorktree`, so the routing rule is Claude-only.
Their docs get the manual process ("`git worktree add`, then open/launch the session in that dir; the
overlay keys off cwd"). No code — but the process is **tested** (criteria 4-5) so the documented steps
can't silently rot.

**E. Nature & verification.** The Claude trigger is a command-instruction (prompt) change — not
unit-testable as code; its criteria are inspectable + the command-surface test. The real test coverage
this task adds is the **Codex + Antigravity process tests**, which pin the overlay-under-worktree
behavior those harnesses' documented flows depend on.

**Alternatives considered:**
- *1a — fully automatic worktree on every new feature* → rejected: "another feature in progress" is
  fuzzy to detect and would spawn surprise worktrees for features that don't need isolation.
- *1c — explicit phrase/command only* → rejected as primary: relies on the user remembering to say
  "worktree"; `/start` integration is more discoverable.
- *2b `/prune-overlays` / 2c lint auto-detect* → deferred: overlays are gitignored + already stale-linted;
  YAGNI until they actually accumulate.

## Decisions (locked)

- **1b** `/start --worktree` integration (flag + interactive offer), enter the worktree as the last step.
- **2a** cleanup = existing gitignore + stale-warning; `/prune-overlays` deferred.
- Routing rule is **Claude-only**; Codex/Antigravity = documented + tested manual process.
- Worktree name = the plan slug.

## Phases

### Phase 1 — `/start --worktree`
- Edit `harnesses/claude/commands/start.md`: the flag, the interactive offer (Tier-3 feature only),
  the `EnterWorktree name=<slug>` last step, and the two guards (already-in-worktree; non-git).

### Phase 2 — Cross-harness process tests (per the explicit ask)
- Codex: a test that, from a linked worktree, runs the context build AND the checkpoint writer and
  asserts both target `working.<wt>.md` (extends/creates alongside `test_codex_mem.sh` /
  `test_working_overlay_write.sh`).
- Antigravity: a test that, with `AI_MEMORY_CWD` a linked worktree, asserts `preinvocation.sh` injects
  the overlay. Each mutation-verified.

### Phase 3 — Docs + green
- `claude.md` (`/start --worktree`), `codex.md` + `antigravity.md` (manual process), Risks note on
  `/prune-overlays`. Full `run-tests.sh` green.

## Risks / open questions

- **`/start` is a prompt-instruction** — the model's `EnterWorktree` call can't be unit-tested; mitigated
  by the command-surface check + the process tests that prove the overlay mechanism the flow relies on.
- **`worktree.baseRef` default** is `fresh` (branches from `origin/<default>`, not local HEAD) — worth
  documenting so a new feature worktree doesn't surprise the user by not carrying uncommitted local work.
- **Deferred `/prune-overlays`** (Decision 2a) if stale overlays ever accumulate enough to matter.
- **Already-in-worktree / nested** `/start --worktree` → skip + warn; never chain worktrees.
