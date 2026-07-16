---
kind: investigation
task_ref: 39ef6850-c619-8188-b28e-db9401f7e6fb
slug: onboard-copilot-harness
status: design settled (decisions locked); ready for /start plan scaffold
created: 2026-07-16
---

# Onboard GitHub Copilot as a harness

Register the **Copilot CLI** (`copilot`) as a new harness in the manifest-driven
engine, alongside `claude` (hook/xml), `codex` (file/md), `antigravity` (hook/xml).
Target is the CLI only — the cloud coding-agent can't take a per-user hook/executor
install, so it's out of scope.

## Locked decisions
- **Scope:** delivery **+** executor (both faces, like codex/antigravity).
- **Archetype:** **hook** (`sessionStart` live injection) — not file, not hybrid.
- **Format:** `md` (Copilot instructions are markdown; no XML). Settled, not a choice.

## Capability findings (Copilot CLI, v1.0.70, mid-2026)

| Capability | Copilot CLI | Implication |
|---|---|---|
| User-level instruction file | `~/.copilot/copilot-instructions.md` (or `$COPILOT_HOME`); also `~/.copilot/instructions/**/*.instructions.md` | file-archetype `context_target` exists (codex-analog) — but not chosen |
| Reads `AGENTS.md`/`CLAUDE.md`/`GEMINI.md` | Yes, nearest in tree wins | alt context path; `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` adds dirs |
| Global hooks | `~/.copilot/hooks/*.json` (+ `$COPILOT_HOME/hooks/`), `~/.copilot/settings.json` | **per-user hook install works** (not just repo `.github/hooks/`) |
| `sessionStart` hook | **Emits `{"additionalContext": "string"}`** ✓ | live full-payload injection at session start |
| `userPromptSubmitted` hook | **No context injection** ✗ | **no per-turn breadcrumb** (the one thing Claude does every prompt) |
| `preToolUse` hook | Returns `{"permissionDecision":"allow|deny|ask", ...}` | real `infra_guard` + read-only enforcement |
| Lifecycle events | sessionStart, sessionEnd, userPromptSubmitted, preToolUse, postToolUse, postToolUseFailure, preCompact, agentStop, subagentStart/Stop, errorOccurred, permissionRequest, notification | rich; only sessionStart/postToolUse/notification return additionalContext |
| Headless exec | `copilot -p {prompt}` + `--allow-all`/`--yolo`; `--available-tools`/`--excluded-tools`; `--autopilot --max-autopilot-continues` | real executor, both roles; read-only via `--available-tools` |

Sources: GitHub Docs — [Copilot CLI custom instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions),
[hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference),
[CLI overview](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/overview).

## Engine seams this touches (verified against current code)
- **`scripts/hooks/inject.sh` cannot be reused for injection** — it emits
  `{"hookSpecificOutput":{"hookEventName",...,"additionalContext"}}` (Claude/Codex
  schema). Copilot's `sessionStart` wants **flat** `{"additionalContext": "..."}`.
  → Copilot needs its own thin injection adapter, exactly like Antigravity's
  `preinvocation.sh`, reusing shared `content-core.sh` + the md formatter.
- **`scripts/hooks/guard.sh` IS reusable** — it already multiplexes the command
  path across harness stdin shapes (`tool_input.command` → `toolCall.args.CommandLine`)
  and matches the shared deny-list. → add Copilot's `preToolUse` command path to that
  fallback chain, **verified against real stdin** (wrong path fails OPEN — the repeated
  guard lesson). Deny-list only; read-only for `explore` handled at the CLI, not the guard.

## Chosen design — hook-archetype, delivery+executor
Modeled on **antigravity** (live hook injection + enforced executor, no harness-specific
engine code beyond a hook I/O adapter), `format = md`, native `sessionStart`/`preToolUse`.

Components:
- **`harnesses/copilot/manifest`** — `archetype = hook`, `format = md`;
  `[hooks] session_bootstrap = sessionStart`, `infra_guard = preToolUse`; execute face
  `exec_cmd`/`exec_readonly`/`exec_model_flag = --model {model}`/`exec_probe = copilot`;
  hooks registration under `~/.copilot/`.
- **`harnesses/copilot/hooks/sessionstart.sh`** — injection adapter: resolve project,
  render full `<memory:*>` payload via `content-core.sh` + md formatter, emit flat
  `{"additionalContext": …}`.
- **Shared `scripts/hooks/guard.sh`** — add verified Copilot `preToolUse` command path
  to the fallback chain (no new guard script).
- **`harnesses/copilot/scripts/copilot-mem.sh`** — executor/launch wrapper (codex-mem/agy
  analog): `exec_cmd = copilot -p {prompt} --allow-all` (task);
  `exec_readonly = copilot -p {prompt} --available-tools <read set>` (explore, read-only
  via CLI allowlist).
- **`scripts/drivers/hook.sh`** — Copilot registration branch for `~/.copilot/hooks/`
  (schema verified; a per-harness registration branch is accepted per doctrine).
- **`install.sh`** registry entry + probe; **tests** (guard stdin-path fixture +
  injection-schema assertion, both wired into `run-tests.sh`); **`docs/harnesses/copilot.md`**.

### Alternatives rejected (on the record)
- **File archetype (codex-clone)** — static, needs a launch wrapper for freshness even
  interactively and guards only inside the executor. `sessionStart` gives live injection
  and `preToolUse` gives an interactive+executor guard for free.
- **Hybrid (file base + hooks)** — most robust but the static base duplicates what
  `sessionStart` injects. Deferred as a hook-failure-resilience add-on if ever needed.

## Success criteria (Task Contract)
1. `install.sh --list` shows `copilot`; `--harness copilot` wires it idempotently
   (re-run = no dupes; preserves sibling `~/.copilot` config keys).
2. Launching `copilot` in a pinned repo injects the full payload at session start
   (identity + project memory present).
3. `executor.sh --role task|explore --which` → `cli:copilot`; both `--run` execute
   and return output.
4. The `preToolUse` guard denies a deny-list command (e.g. `gh pr merge`) for an
   executor role, verified against **real** Copilot stdin, failing closed.
5. `explore` is genuinely read-only — a write attempt is blocked.
6. New tests actually run (registered in the runner glob) and the suite stays green.
7. No Copilot-specific engine code beyond the hook I/O adapter + one registration branch.

## Risks / open questions (Phase-0 verification, per the fail-OPEN lessons)
- Does `sessionStart` stdin carry `cwd`? If not, injection needs the wrapper to export
  the project (antigravity pattern) — weakens the "no wrapper for interactive use" benefit.
- Exact `preToolUse` command JSON path — **probe-verified, never assumed** (fails OPEN).
- Copilot hooks-file registration schema (`~/.copilot/hooks/*.json` vs a settings array).
- Exact read-only `--available-tools` set + a clean transcript-free output flag
  (codex's `-o {file}` equivalent).
- **No per-turn breadcrumb** (userPromptSubmitted can't inject) — accepted, documented
  degradation; working-path advertised only at session start.
- A Copilot hooks version floor (`hooks_min_version` analog)?
