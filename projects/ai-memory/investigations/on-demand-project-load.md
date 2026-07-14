---
doc: on-demand-project-load
kind: investigation
status: open — design seed for /start (brainstormed 2026-07-12)
created: 2026-07-12
owner: claude (orchestrator)
task_ref: 38ff6850-c619-810e-93c9-e58480054bf2
---

# Investigation — on-demand project load / switch

Design seed for the backlog task originally captured as *"On-demand section-level context loading via '@'"*.
A brainstorming pass on 2026-07-12 **reframed the goal**: the headline capability the user wants is the
ability to **load / switch to a specific project mid-session, decoupled from cwd** — not the `@`-section
mechanism, which was only one candidate trigger. `@` and section/domain granularity are **deferred**
(project-level only, YAGNI). This file is the seed `/start` hands to `brainstorming`; the design below is
largely settled, so `/start` may skip the brainstorm gate and go near-straight to `/new-plan`.

## Motivating case

The harness is often opened at an arbitrary directory — a VS Code / Copilot window on a workspace root that
holds several repos or none of a project's roots. Today the active project is **derived from cwd**
(`detect_project()` walks up to a `.agents/memory-project` marker), so an arbitrary cwd resolves to the wrong
project or none. The user needs to say "work on project X" explicitly, on the same running instance, and have
memory, commands, and shell cwd all relocate to X.

## Settled decisions (from the 2026-07-12 brainstorm)

1. **Load semantics = switch / replace.** Loading project `foo` makes it *the* active project: its
   `memory.md` + `identity` load, the prior project's context is cleared/superseded, and both later commands
   and memory resolution target `foo`. Not an additive "pull alongside".
2. **Trigger = slash command** — `/project <name>` (deliberate, discoverable, script-backed). No in-prompt
   `@`/token parsing. Session-pin file backs it.
3. **Granularity = project-level only.** No `#section`, no `@domain/<topic>` refs. The original section-level
   ambition is explicitly parked; revisit as a follow-up task if the need survives.
4. **Harness scope = supported-only, declared as a version-gated capability.** The mid-session switch ships on
   any harness with a per-turn hook that injects context. **Update (2026-07-12): that now includes Codex.**
   Codex-cli ≥ ~0.135 exposes a native `UserPromptSubmit` hook that fires before the model processes the
   prompt and injects `additionalContext` — schema-identical to Claude's (`hookSpecificOutput.additionalContext`),
   per Codex docs (learn.chatgpt.com/docs/hooks; `UserPromptSubmit` landed 2026-03-18, hooks stable ~April
   2026). So **all three harnesses can support it.** The capability is still declared per-harness and
   **version-gated** (a harness/version lacking the injection hook doesn't advertise it) — but no harness is
   categorically excluded. Codex support is now **empirically confirmed** (2026-07-12 hook probe — the model saw
   `additionalContext` injected by a `UserPromptSubmit` hook). The earlier "Codex not supported" decision is
   retracted. Full cross-harness hook mechanics now live in [[hook-standardization]]; this feature is a
   *consumer* of its `per_turn_inject` role. Decision #4 above is authoritative over the older per-launch
   framing in the table/consequences below (kept for history). **Update (2026-07-14): the `per_turn_inject`
   role is now SHIPPED on all three harnesses** — Claude + Codex on the shared `scripts/hooks/inject.sh`
   (hook-standardization P2/P3, merged), Antigravity on its own `preinvocation.sh`. So this feature can build
   directly on a live per-harness injection hook; the only remaining harness caveat is the pin *key* (§ below),
   not injection support.

## Cross-harness architecture (must hold on claude / antigravity / codex)

**The one shared seam.** All three harnesses resolve the active project from **cwd → `.agents/memory-project`
marker** at their injection point — Claude `detect_project()` (`memory_common.sh:76`), Antigravity via
`agy.sh` env + `preinvocation.sh`, Codex via `$PWD` in `codex-mem.sh` / `build-context-md.sh` at launch.
So the universal mechanism is **a pin that supersedes cwd-derivation, read at every harness's resolution
point.** Everything else differs.

| Axis | Claude (hook/xml) | Antigravity (hook/xml) | Codex (file/md) |
|---|---|---|---|
| Injection cadence | per-prompt (UserPromptSubmit) + per-session (SessionStart) | per-model-call (PreInvocation) | **per-launch** — `AGENTS.md` rebuilt each `codex` start (`refresh=launch`) |
| Session id to hooks | yes (`session_id`) | **none for memory hooks** — single-workspace/session; project resolved once at launch via `agy.sh` env (`antigravity.md:52,67`) | **none** — `AGENTS.md` built from `$PWD` at launch (`build-context-md.sh:24`), each `codex exec` a new process |
| Context reset | `/clear` / `/compact` + SessionStart re-inject | PreInvocation re-injects **per model-call** → can switch mid-session IF the hook reads the pin (today it reads launch env) | **relaunch only** — no per-call injection hook; file built at launch |
| Command surface | native `/project` .md (`commands=native`) | skill (`commands=skill`) | skill + `~/.codex/prompts/*.md` (`commands=skill`) |
| Working dir | persistent shell across turns | `agy` env | `$PWD` at launch; each `exec` independent |

**Consequences (each breaks a Claude-only assumption):**

1. **Pin key must NOT be a harness `session_id`.** Codex has none and rebuilds per launch; Antigravity's is
   unclear. Key the pin by a harness-neutral handle — controlling **tty** (interactive isolation) with a
   **"last pin" global fallback** for the one-shot / degenerate case. This **demotes the
   `/clear`-survives-`session_id` probe to a Claude-only nicety** — it only affects Claude's optional
   hard-wipe path, not the portable design.
2. **No portable "wipe".** The portable reset primitive is *"re-inject with the new project at the next
   injection point"* — Claude: next prompt / SessionStart; Antigravity: next PreInvocation; Codex: next
   launch. Claude's `/clear` is an *enhancement* on top, not the mechanism.
3. **Mid-session switch is a capability-gated feature — supported only on harnesses whose archetype allows it,
   and explicitly NOT supported on Codex.** The dividing line is whether the harness re-injects on a
   **per-call** event (can switch live) or only **at launch**. This is declared as a manifest capability
   (see refactor below), the same way `guard_script` is a hook-only capability — a harness that doesn't
   support it simply doesn't advertise it.
   - **Claude** (supported) — per-prompt injection already reads cwd each prompt; make it read the pin first.
     Optional `/clear` reload + persistent-shell `cd` are enhancements.
   - **Antigravity** (supported) — `PreInvocation` fires per model-call, but today resolves the project from
     the launch-time `agy.sh` env, not a pin. Adapter change: make `preinvocation.sh` consult the pin each
     call. Workspace is fixed per session (single-workspace), so memory switches even if the working dir
     doesn't.
   - **Codex** (**not supported**) — `AGENTS.md` is built only at launch (`refresh=launch`) with no per-call
     hook to swap it. `/project` is **not delivered** to Codex; invoking it (if reached) reports *"mid-session
     project switch is not supported on Codex — start Codex in the target project's directory instead."*
     Codex already selects its project from `$PWD` at launch, which stays the switch path there (consistent
     with its worktree story: no in-session switch, manual `cd + codex`).
4. **Command delivery follows the existing dual pattern.** Claude gets a native `/project` command; Antigravity
   + Codex get it **as a skill** (`commands=skill`) — exactly how `/checkpoint` is delivered.

**The refactor that makes it shared.** Two pieces:
- **Shared pin resolver** — promote pin-resolution + `detect_project` into ONE lib function every injection
  point calls: the Claude hooks (`memory_common.sh`), Antigravity's `preinvocation.sh`, and (read-only, for
  consistency at launch) the file-archetype builder `build-context-md.sh`. One resolver, three call-sites.
- **A `project_switch` manifest capability**, advertised only by supporting harnesses — wired by the install
  driver exactly like today's `guard_script` (`scripts/drivers/hook.sh:135`). Claude declares it and gets the
  native `/project` command; Antigravity declares it and gets the switch skill (`commands=skill`); **Codex
  does not declare it**, so the command/skill is not delivered there. The load action is one shared script
  (`scripts/project-load.sh <name>`: write pin → resolve repo root → harness-appropriate `cd`), wrapped by a
  native command (Claude) or skill (Antigravity).

*(Inferred, pending file:line confirmation: Antigravity's session-id exposure and wipe equivalent; that
`build-context-md.sh` is the shared file-archetype builder. A codex explore survey is running to nail these.)*

## Mechanism — Claude adapter (reference implementation)

Everything hangs off one new input to project resolution: a **session-scoped pin that supersedes cwd
derivation**.

- **Pin store.** `~/.claude-memory/.sessions/<session_id>/active-project`, keyed by `session_id` (already
  available to both hooks — `inject_memory.sh:19`, `session_start_memory.sh:11`). Gitignored (personal data).
  Session-keyed so concurrent VS Code windows don't clobber each other — same isolation principle as the
  per-worktree `working.md` overlay (#54).
- **Resolution precedence.** New helper wrapping `detect_project()` (`memory_common.sh:76`):
  `1) session pin if present → 2) detect_project(cwd) → 3) empty`. Both `inject_memory.sh` and
  `session_start_memory.sh` call the wrapper instead of `detect_project` directly. Tag the emitted
  `<memory:active>` block with `source="pin|cwd"` so it's visible which path won.
- **Context wipe.** A hook *cannot* clear the transcript — only `/clear` / a new session can. So:
  the `/project` command writes the pin and **nudges the user to run `/clear`**; the existing
  **SessionStart** hook (`session_start_memory.sh`, fires on `source: clear`) re-reads the pin and injects
  `foo`'s full memory — a genuinely clean context on the right project. Soft fallback if the user skips
  `/clear`: `inject_memory.sh` re-injects `foo` on the next prompt and emits a `<system-reminder>` that prior
  project context is stale (newest injection wins; transcript not purged).
- **Commands from project root.** The command's final action is `cd "<foo repo root>"` in the **persistent
  Bash shell** (cwd survives across tool calls), so every later command runs from `foo`'s root — no
  PreToolUse rewrite hook (too much blast radius; breaks intentional-cwd commands). Resolver needed:
  `name → repo root`, read from `projects/<name>/memory.md` `repo_path` (or the dir holding its
  `.agents/memory-project` marker).
- **Command surface.** `/project <name>` (switch), `/project` (print current pin + source), `/project
  --unpin` (drop the pin, fall back to cwd derivation).
- **Cleanup.** GC `~/.claude-memory/.sessions/<id>/` on SessionEnd, or prune in `sync-system`.

## Rejected alternatives

- **In-prompt `@token` trigger** — inline, but relies on parsing free-text prompts and is less discoverable;
  slash command chosen for deliberate switches. (Lost on 2026-07-12.)
- **Pull-alongside semantics** — load X's memory without leaving current project; good for cross-project
  peeking but doesn't satisfy "relocate my work to X". (Lost — switch chosen.)
- **Section / domain granularity (`foo#architecture`, `domain/terraform`)** — the task's original framing;
  deferred as YAGNI for the first cut. (Parked, not killed.)
- **PreToolUse Bash cwd-rewrite** — force every command into project root via a hook; rejected for blast
  radius vs. the transparent persistent-shell `cd`.

## Open questions / risks

- **Pin key = tty + "last pin" fallback (DECIDED), not `session_id`.** Since only Claude exposes a session
  id and the feature must be harness-neutral, the pin is keyed by the controlling tty with a single "last
  pin" global fallback. **This retires the earlier `session_id`-survives-`/clear` concern** — it only ever
  mattered for a `session_id`-keyed pin. It survives now only as a *Claude-only nicety*: IF Claude's optional
  hard-wipe path (`/clear` → SessionStart re-read) is built, SessionStart must locate the pin by tty too (the
  hook can derive its controlling tty from its own process). A live probe remains staged at
  `/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/session-id-probe.md` but is **no
  longer load-bearing** — run only if the Claude hard-wipe path is pursued.
- **tty as a pin key across detached/piped invocations.** A headless/executor run may have no controlling tty;
  the "last pin" fallback covers it, but confirm the key derivation degrades cleanly (no crash, sensible
  default) when `tty` is absent.
- **`session_id` actually reaching SessionStart.** Confirmed present in both hook inputs today; re-check it's
  populated on the `clear` source specifically.
- **name → repo_root resolver** — no dedicated resolver script exists today (grep found none); either add one
  or read `repo_path` from `projects/<name>/memory.md`. Confirm `repo_path` is reliably present.
- **Pin vs. shell-cwd drift** — user may manually `cd` away after a switch; the pin (not the shell) stays the
  source of truth for memory resolution — keep them independent on purpose.

## Draft success criteria (for the eventual plan)

- From an arbitrary cwd, `/project <name>` makes `<name>` the active project for memory injection regardless
  of cwd, and this persists across the same session.
- After `/project <name>` + `/clear`, the reloaded context is `<name>`'s memory/identity only — no stale
  prior-project content.
- After a switch, a plain shell command (e.g. `git status`) runs from `<name>`'s repo root, not the original
  cwd.
- `/project` with no arg reports the current active project and whether it came from a pin or cwd.
- Two concurrent sessions pinned to different projects do not interfere.
- The same switch works on Antigravity (via the switch skill + pin-reading `preinvocation.sh`).
- On Codex, the feature is not delivered; if invoked it reports "not supported on Codex — launch in the
  target directory" rather than silently doing nothing.
