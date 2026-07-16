# GitHub Copilot CLI

GitHub Copilot is registered as a **hook** archetype harness with `md` output.
It targets the local Copilot CLI only: the cloud coding agent has no per-user
hook or executor install surface, so it is out of scope.

The probed floor is Copilot CLI 1.0.70/1.0.71. Hook config files must declare
`"version": 1`; unknown versions are silently ignored by the CLI, so the
installer writes the owned file with that version explicitly.

## Daily use

```bash
copilot
```

Interactive Copilot does not need a memory launch wrapper. The `sessionStart`
hook receives `cwd` in stdin, so the memory system resolves the active project
from the real workspace path.

Headless executor use goes through the wrapper:

```bash
~/.claude-memory/harnesses/copilot/scripts/copilot-mem.sh -p "do the thing" --allow-all --silent --stream off --no-color --no-auto-update
```

The wrapper is executor-only. It fills a GitHub token from `gh auth token` when
no token env is already present, closes stdin, then execs `copilot`.

## Native hooks

`install.sh --harness copilot` writes one user-level hook file:
`~/.copilot/hooks/ai-memory.json`. Copilot loads every `*.json` under
`~/.copilot/hooks/`, so the memory system owns one file and leaves sibling files
untouched by construction.

Repo-level `.github/hooks/*.json` did **not** fire in headless Copilot CLI 1.0.71,
despite upstream docs describing repo-level hooks. The installer therefore uses
the user-level hooks directory only.

| Role | Event | Script | Effect |
|------|-------|--------|--------|
| `session_bootstrap` | `sessionStart` | `harnesses/copilot/hooks/sessionstart.sh` | Injects the full memory base once at session load, using the flat Copilot `{"additionalContext":"..."}` envelope. |
| `infra_guard` | `preToolUse` | shared `scripts/hooks/guard.sh` with `AI_MEMORY_GUARD_OUTPUT=copilot-json` | Under an executor role, denies shared infra deny-list commands with Copilot's JSON permission-decision contract. |
| `compaction_arm` | `preCompact` | `harnesses/copilot/hooks/precompact.sh` | Arms the shared `.recompact` sentinel as a side effect. |
| `per_turn_inject` | `postToolUse` | `harnesses/copilot/hooks/posttooluse.sh` | If a sentinel is present, re-injects the full payload once and clears it. |

## What gets injected

The `sessionStart` adapter sources the shared hook library and renders the same
markdown payload as Codex: identity, active project memory, index, domain index,
and non-empty working memory. Project detection comes from the hook stdin `cwd`;
no launcher-exported project variable is needed for interactive use.

There is no Copilot per-turn breadcrumb. `userPromptSubmitted` is notification-only
and cannot inject context. `postToolUse` can inject, but only after a tool call, so
a turn with zero tool calls gets no refresh. That is the accepted residual for
Copilot's hook model.

## Enforcement

The `preToolUse` guard is the shared `scripts/hooks/guard.sh`. For Copilot shell
tool calls, the command lives in a JSON-encoded string:

```text
.toolArgs | fromjson | .command
```

The guard checks the Codex/Claude path first, Antigravity second, and Copilot's
double-decoded path third. When `AI_MEMORY_GUARD_OUTPUT=copilot-json`, deny emits:

```json
{"permissionDecision":"deny","permissionDecisionReason":"..."}
```

and exits 0. The legacy exit-2 deny path remains for other harnesses. The no-parser
edge still fails closed: under an executor role, if neither `jq` nor `python3` can
inspect stdin, Copilot receives a valid JSON deny decision.

Two residuals are deliberate:

- Copilot fails open if the guard times out. The registered timeout is 5 seconds;
  the guard path measured at roughly 120 ms in validation.
- The guard does not consult `toolName`; it is keyed on the extracted command shape.
  A future schema drift in the shell payload can therefore fail open. A stricter
  tool-name-keyed deny was considered and rejected for now, matching the Claude and
  Antigravity posture.

## Compaction recovery

Copilot's `preCompact` output is ignored, but the hook command still runs. The
adapter arms the same `<session_id>.recompact` sentinel used by Claude and Codex.
The next `postToolUse` sees the sentinel, injects the full payload once, and clears
it. The handshake is interoperable with the Claude/Codex sentinel consumers.

`preCompact` arms unconditionally. A stale or unnecessary sentinel is self-cleaning
on the next matching post-tool injection, and old sentinels are pruned by the shared
state-dir logic.

## The executor face

The manifest declares Copilot as a CLI executor:

```text
exec_cmd        = $MEMORY_DIR/harnesses/copilot/scripts/copilot-mem.sh -p {prompt} --allow-all --silent --stream off --no-color --no-auto-update
exec_readonly   = $MEMORY_DIR/harnesses/copilot/scripts/copilot-mem.sh -p {prompt} --available-tools=view,grep,glob --allow-all-tools --allow-all-paths --allow-all-urls --silent --stream off --no-color --no-auto-update
exec_model_flag = --model {model}
exec_probe      = copilot
```

`--silent` gives clean final-answer stdout, with no transcript or stats footer, so
there is no `exec_last_message` parser. The wrapper closes stdin so a delegated run
cannot hang consuming the orchestrator's input stream.

Read-only execution is enforced by Copilot's own available-tool set:
`view,grep,glob`. The `--allow-all-*` flags auto-approve only within that reduced
tool set; they do not re-enable shell, create, or edit tools.

Headless Copilot must be authenticated. Set `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or
`GITHUB_TOKEN`, or run `/login` beforehand. If no token env is present and `gh` is
available, `copilot-mem.sh` falls back to `gh auth token` and exports it as
`GH_TOKEN`.
