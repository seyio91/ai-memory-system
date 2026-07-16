---
plan: onboard-copilot-harness
status: done
completed: 2026-07-16
created: 2026-07-16
owner: claude (orchestrator)
task_provider: notion
task_ref: 39ef6850-c619-8188-b28e-db9401f7e6fb
---

# Onboard GitHub Copilot as a harness

## Goal

Register the Copilot CLI (`copilot`) as a hook-archetype, md-format, delivery+executor
harness in the manifest-driven engine, alongside claude/codex/antigravity — live
`sessionStart` memory injection, `preToolUse` infra guard, and both executor roles.
Design settled in investigation `onboard-copilot-harness` (decisions locked).

## Success criteria

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

## Design

Modeled on **antigravity** (live hook injection + enforced executor; no harness-specific
engine code beyond a hook I/O adapter), `format = md`, native `sessionStart`/`preToolUse`.
Full capability findings and sources: investigation `onboard-copilot-harness`.

Components:
- `harnesses/copilot/manifest` — `archetype = hook`, `format = md`;
  `[hooks] session_bootstrap = sessionStart`, `infra_guard = preToolUse`,
  `compaction_arm = preCompact`; execute face `exec_cmd`/`exec_readonly`/
  `exec_model_flag = --model {model}`/`exec_probe = copilot`; hooks registration
  under `~/.copilot/hooks/`.
- `harnesses/copilot/hooks/sessionstart.sh` — injection adapter sourcing
  **`scripts/hooks/lib.sh`** (deeper reuse than raw content-core: `detect_project`
  from stdin `cwd` — Copilot's sessionStart input carries `cwd`, docs-confirmed —
  plus `render_full` keyed on `AI_MEMORY_HOOK_FORMAT=md`, chunk helpers, and
  `recompact_sentinel`). Only the envelope is new: Copilot wants flat
  `{"additionalContext": "..."}`; the shared `session_start_memory.sh` hardcodes the
  Claude/Codex `hookSpecificOutput` wrapper at its final printf, so the adapter is
  that script with line-75 swapped, not a fork of the logic.
- Shared `scripts/hooks/guard.sh` — two edits, not one:
  (a) stdin: add the verified Copilot `toolArgs.*` command path to the fallback
  chain (camelCase events ⇒ camelCase fields; PascalCase registration flips to
  snake_case — pick one deliberately at registration and match it);
  (b) **deny signalling**: Copilot's preToolUse contract is JSON
  `{"permissionDecision":"deny","permissionDecisionReason":…}`; guard.sh's current
  deny is exit 2, which Copilot documents as *"treated as warning"* — an unadapted
  guard could deny-as-warning and let the command run. Emit the JSON decision
  (env-keyed output branch or thin wrapper), exit 0.
- **Compaction resilience (hooks-native):** Copilot's `preCompact` is
  notification-only (output ignored) but a command hook still runs — arming the
  recompact sentinel is a pure side effect, so the existing sentinel handshake works.
  Re-injection can't ride `userPromptSubmitted` (notification-only on Copilot);
  instead register `postToolUse` (which CAN return `additionalContext`): sentinel
  present → re-inject full payload → clear. Same lever optionally doubles as a
  lightweight per-turn breadcrumb.
- `harnesses/copilot/scripts/copilot-mem.sh` — executor/launch wrapper (codex-mem/agy
  analog): `exec_cmd = copilot -p {prompt} --allow-all` (task);
  `exec_readonly = copilot -p {prompt} --available-tools <read set>` (explore);
  `exec_last_message` equivalent only if `-p` emits more than the final message.
- `scripts/drivers/hook.sh` — Copilot registration branch (`_hook_register_copilot_json`,
  modeled on antigravity's `_hook_register_json`): Copilot's config is its own schema
  (`{"version":1,"hooks":{event:[{type:"command",bash:…,env:{…},timeoutSec:…}]}}`),
  not the Claude-native shape, so it can't flow through `_hook_register_native_json`.
  Per-hook `env` replaces the env-prefix command idiom; add the Copilot script names
  to the marker set so re-syncs sweep stale entries; set `timeoutSec` explicitly on
  the guard (timeout = fail-open on Copilot).
- `install.sh` registry entry + probe; tests (guard stdin-path + deny-shape fixtures
  from real payloads, injection-schema assertion, wired into `run-tests.sh`);
  `docs/harnesses/copilot.md`.

Rejected alternatives (on the record):
- **File archetype (codex-clone)** — static; needs a launch wrapper for freshness and
  guards only inside the executor, while `sessionStart`/`preToolUse` give both for free.
- **Hybrid (file base + hooks)** — static base duplicates the `sessionStart` payload;
  deferred as a hook-failure-resilience add-on if ever needed.

## Decisions (locked)

- Scope: delivery **+** executor (both faces, like codex/antigravity).
- Archetype: **hook** (`sessionStart` live injection) — not file, not hybrid.
- Format: `md` (Copilot instructions are markdown; no XML).
- Target: Copilot **CLI only** — the cloud coding-agent can't take a per-user
  hook/executor install; out of scope.
- Accepted degradation, softened: `userPromptSubmitted` cannot inject context, but
  `postToolUse` can — breadcrumb/re-inject rides postToolUse instead of per-prompt;
  a turn with zero tool calls still goes without a refresh (documented residual).
- Project resolution: native from sessionStart stdin `cwd` (docs-confirmed) — no
  launch wrapper needed for interactive use; `detect_project` reused as-is.

## Phases

- [x] Phase 0 — probe verification (fail-OPEN lessons): capture real `sessionStart`,
      `preToolUse`, `preCompact`, and `postToolUse` stdin from Copilot CLI; verify the
      exact `toolArgs` command path AND the case variant our registration produces
      (camelCase vs PascalCase/snake_case); **verify deny semantics empirically** —
      JSON `permissionDecision:"deny"` vs non-zero exit vs the documented
      exit-2-as-warning; confirm `~/.copilot/hooks/*.json` registration schema
      (`version: 1`, per-hook `env`/`timeoutSec`); pin the read-only
      `--available-tools` set + whether `copilot -p` needs an output-file flag;
      decide a version floor. Fixtures from *real* payloads.
- [x] Phase 1 — delivery face: manifest + `sessionstart.sh` adapter (sources
      `scripts/hooks/lib.sh`; flat-envelope emit) + `_hook_register_copilot_json`
      branch in `hook.sh` + marker-set entries + `install.sh` registry entry/probe
      (idempotent re-runs, sibling-key preservation).
- [x] Phase 2 — guard: Copilot stdin path in `guard.sh` fallback chain + JSON deny
      output branch + explicit `timeoutSec` + real-stdin fixture test proving a
      deny-list command is actually blocked (not warned) — fails closed.
      (Validator: ACCEPT. Phase-5 doc note: guard never consults `toolName` —
      schema-drift on the bash shape stays fail-open by design, same as
      claude/antigravity; document the residual in docs/harnesses/copilot.md.)
- [x] Phase 3 — compaction + breadcrumb: `preCompact` sentinel arm (side-effect
      registration of the shared arm logic) + `postToolUse` re-inject/clear adapter;
      verify a post-compaction session recovers full memory.
      (Validator: ACCEPT — handshake interoperable both directions with the
      Claude/codex sentinel consumers; empty-sessionId edge safe (no stray-sentinel
      match possible); sentinel-clear-on-empty-payload mirrors inject.sh exactly.
      Live /compact recovery check deferred to final validation.)
- [x] Phase 4 — executor face: `copilot-mem.sh` wrapper + manifest `exec_*` block;
      `executor.sh --which/--run` for task/explore; read-only enforcement for explore.
      (Validator: ACCEPT. Live smoke: task → EXEC-TASK-OK; explore write attempt
      refused, file absent — criteria 3+5 proven. Phase-5 test hardening carry-over:
      cover wrapper no-gh path, exit-code propagation, stdin closure.)
- [x] Phase 5 — tests wired into `run-tests.sh` (registration, injection schema, guard
      deny-shape, compaction handshake, executor probe) + `docs/harnesses/copilot.md`
      + changelog.d entry.
      (Done 2026-07-16. Live final validation: real install into ~/.copilot (4 hook
      rows, owned file) + live pinned-repo session correctly reported active project
      AND working.md checkpoint content — success criterion 2 verified end-to-end.
      All 7 success criteria now evidenced; live /compact recovery remains
      fixture-proven only (needs a long organic session).)

## Risks / open questions

- **Deny signalling** (top risk, replaces the resolved cwd question): docs say
  preToolUse fails closed on non-zero exit *but* exit 2 is "treated as warning" —
  guard.sh's existing deny IS exit 2. Probe empirically; ship the JSON
  `permissionDecision` deny and a fixture asserting the command was blocked.
- `preToolUse` **fails open on timeout** (default 30s) — guard must stay fast; set
  `timeoutSec` explicitly and document the residual window.
- Exact `preToolUse` command JSON path — probe-verified in Phase 0, never assumed
  (wrong path fails OPEN). Case-variant coupling: registration event-name casing
  decides camelCase vs snake_case stdin fields.
- Read-only `--available-tools` set completeness (criterion 5 depends on it).
- Version floor: hooks config requires `"version": 1`; pin the minimum CLI version
  whose probe (`copilot --version`) the installer can gate on.
- Zero-tool-call turns get no postToolUse refresh — accepted residual of the
  breadcrumb workaround; documented in `docs/harnesses/copilot.md`.

**Resolved during review (2026-07-16):** sessionStart stdin carries `cwd`
(docs-confirmed) — native project resolution, no launch wrapper for interactive use.

**Resolved by Phase 0 probes (2026-07-16, CLI 1.0.71 — full evidence in
investigation `copilot-phase0-probes`, fixtures in `scripts/tests/fixtures/copilot/`):**
- Deny semantics: JSON deny, exit 1, AND exit 2 all block (exit-2-as-warning from
  the docs did NOT reproduce) — ship JSON `permissionDecision:"deny"` as the stable
  contract anyway.
- Guard stdin path: `toolArgs` is a **JSON-encoded string** → double decode
  `.toolArgs | fromjson | .command` (new machinery for guard.sh, not just a path).
- Casing: camelCase event registration ⇒ camelCase stdin (`.cwd` present);
  PascalCase flips to snake_case. Register camelCase.
- Registration target: `$COPILOT_HOME/hooks/*.json` works; repo-level
  `.github/hooks/*.json` did NOT fire in headless CLI 1.0.71 → installer targets
  `~/.copilot/hooks/` only.
- postToolUse `additionalContext` reaches the model (breadcrumb/re-inject viable);
  `/compact` fires preCompact headlessly.
- exec face: `exec_cmd = copilot -p {prompt} --allow-all --silent --stream off
  --no-color --no-auto-update` (answer on stdout, stats on stderr; `--silent` =
  clean stdout ⇒ no `exec_last_message` file flag needed);
  `exec_readonly = … --available-tools=view,grep,glob …` (enforcement verified).
- Hooks config `"version": 2` is silently ignored (no strict validation);
  `copilot --version` parseable via `GitHub Copilot CLI ([0-9.]+)`.
- Auth: headless needs `COPILOT_GITHUB_TOKEN`/`GH_TOKEN`/`GITHUB_TOKEN` or prior
  `/login`; `copilot-mem.sh` should fall back to `gh auth token`.
