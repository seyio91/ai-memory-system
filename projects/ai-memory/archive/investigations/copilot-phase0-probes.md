---
kind: investigation
task_ref: 39ef6850-c619-8188-b28e-db9401f7e6fb
slug: copilot-phase0-probes
status: verified-with-repo-hook-discovery-gap
created: 2026-07-16
updated: 2026-07-16
---

# Copilot Phase 0 Probes

Probe target:
- Binary: `/opt/homebrew/bin/copilot`
- Version output: `GitHub Copilot CLI 1.0.71.`
- Scratch repo: `/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/62a0daf4-7e3d-4305-9633-0ea9704c1bfe/scratchpad/copilot-probe`
- Real home untouched: all successful hook probes used `COPILOT_HOME=$scratch/copilot-home`.
- Repo-level hook path `.github/hooks/probe.json` was tested first and did not fire in headless CLI, despite Copilot's own docs reporting it as supported. Scratch-home `$COPILOT_HOME/hooks/probe.json` did fire. Treat repo-level discovery as a separate verified gap, not an auth issue.

Raw pretty fixtures from real hook stdin:
- `scripts/tests/fixtures/copilot/session_start_camel.json`
- `scripts/tests/fixtures/copilot/session_start_pascal.json`
- `scripts/tests/fixtures/copilot/pre_tool_use_bash.json`
- `scripts/tests/fixtures/copilot/post_tool_use_bash.json`
- `scripts/tests/fixtures/copilot/pre_compact.json`

## 1. `sessionStart` stdin

VERIFIED.

CamelCase registration `sessionStart` works via `$COPILOT_HOME/hooks/probe.json`.
Stdin uses camelCase fields:

```json
{
  "sessionId": "8a383476-4ee4-4679-8235-b46d1c259e03",
  "timestamp": 1784210989591.0,
  "cwd": "/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/62a0daf4-7e3d-4305-9633-0ea9704c1bfe/scratchpad/copilot-probe",
  "source": "new",
  "initialPrompt": "Reply exactly: FIXTURE_SESSION_CAMEL"
}
```

PascalCase registration `SessionStart` also works and flips stdin to snake_case,
with `hook_event_name` included:

```json
{
  "hook_event_name": "SessionStart",
  "session_id": "28c24a04-c073-4a58-b1d6-73b78530f016",
  "timestamp": "2026-07-16T14:09:56.116Z",
  "cwd": "/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/62a0daf4-7e3d-4305-9633-0ea9704c1bfe/scratchpad/copilot-probe",
  "source": "new",
  "initial_prompt": "Reply exactly: FIXTURE_SESSION_PASCAL"
}
```

## 2. `preToolUse` stdin

VERIFIED.

For a shell command, camelCase `preToolUse` stdin is:

```json
{
  "sessionId": "5cc2ec69-977e-41c0-a1db-e6af53a4cd16",
  "timestamp": 1784211006690.0,
  "cwd": "/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/62a0daf4-7e3d-4305-9633-0ea9704c1bfe/scratchpad/copilot-probe",
  "toolName": "bash",
  "toolArgs": "{\"command\":\"printf fixture > fixture-tool.txt\",\"description\":\"Run the specified printf command\"}"
}
```

The shell command path is not a nested JSON path. `toolArgs` is a JSON string;
parse it, then read `.command`.

Guard extraction for camelCase registration:

```sh
tool_name=.toolName
command='(.toolArgs | fromjson | .command)'
```

## 3. Deny semantics

VERIFIED.

Three separate `touch DENYME.txt` runs were made. In every case `DENYME.txt`
was missing after the run and Copilot exited `0` after reporting the denial.

JSON deny, hook stdout `{"permissionDecision":"deny","permissionDecisionReason":"probe"}`,
hook exit `0`:

```text
case=json rc=0 file=missing
Denied by preToolUse hook: probe
The command was denied. A preToolUse hook named probe blocked execution of touch DENYME.txt before it could run.
```

Exit `2`, stderr message, no JSON:

```text
case=exit2 rc=0 file=missing
Denied by preToolUse hook: hook exited with code 2
The command was denied. A pre-tool hook blocked execution before touch DENYME.txt could run.
```

Exit `1`, stderr message, no JSON:

```text
case=exit1 rc=0 file=missing
Denied by preToolUse hook from "copilot-home/hooks/probe.json" (hook errored)
The command was denied - it did not succeed.
```

Use JSON deny anyway. It gives a stable reason string and avoids coupling the
guard to non-zero hook error UX.

## 4. `postToolUse`

VERIFIED.

For a successful shell command, camelCase `postToolUse` stdin is:

```json
{
  "sessionId": "5cc2ec69-977e-41c0-a1db-e6af53a4cd16",
  "timestamp": 1784211006829.0,
  "cwd": "/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/62a0daf4-7e3d-4305-9633-0ea9704c1bfe/scratchpad/copilot-probe",
  "toolName": "bash",
  "toolArgs": "{\"command\":\"printf fixture > fixture-tool.txt\",\"description\":\"Run the specified printf command\"}",
  "toolResult": {
    "resultType": "success",
    "textResultForLlm": "\n<shellId: 0 completed with exit code 0>"
  }
}
```

`postToolUse` `additionalContext` reaches the model. Hook stdout:

```json
{"additionalContext":"PROBE-CTX-MARKER-XYZ"}
```

Prompt result:

```text
The context marker string I received was:

PROBE-CTX-MARKER-XYZ
```

## 5. `preCompact`

VERIFIED, triggerable headlessly.

Prompting `copilot -p "/compact"` invoked `preCompact`, then Copilot exited `1`
with `Error executing prompt: Error: Nothing to compact.` The hook payload is
real:

```json
{
  "sessionId": "1f68d182-86aa-4463-8918-c0598716741d",
  "timestamp": 1784211012706.0,
  "cwd": "/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/62a0daf4-7e3d-4305-9633-0ea9704c1bfe/scratchpad/copilot-probe",
  "transcriptPath": "/private/tmp/claude-502/-Users-seyi-Downloads-personal-claude-memory/62a0daf4-7e3d-4305-9633-0ea9704c1bfe/scratchpad/copilot-probe/copilot-home/session-state/1f68d182-86aa-4463-8918-c0598716741d/events.jsonl",
  "trigger": "manual",
  "customInstructions": ""
}
```

## 6. Headless output

VERIFIED.

Default text mode:
- stdout: final answer, plus tool transcript if tools were used.
- stderr: stats footer (`Changes`, `AI Credits`, `Tokens`, `Resume`).

`--silent`:
- stdout: final answer only.
- stderr: empty.
- Verified with a tool call: `silent-tool.txt` was created, stdout contained only `FINAL_SILENT_TOOL`.

`--output-format json`:
- stdout: JSONL event stream.
- stderr: empty.
- Final answer is in the last `assistant.message.data.content` event before `result`.

Cleanest executor recipe:

```sh
copilot -p "$prompt" --allow-all --silent --stream off --no-color --no-auto-update
```

For `exec_last_message`, no parser is needed in silent mode beyond reading stdout.

## 7. Read-only tool set

VERIFIED.

`copilot help permissions` documents permission patterns such as
`shell(git:*)`, but those are not valid `--available-tools` tool IDs. Using
`--available-tools='shell(git:*)'` disabled all real tools and produced:

```text
Unknown tool name in the tool allowlist: "shell(git:*)"
```

Actual tool IDs are visible in Copilot's disabled-tools banner. Minimal useful
read-only set:

```sh
--available-tools=view,grep,glob --allow-all-tools --allow-all-paths --allow-all-urls
```

Write enforcement probe:

```text
rc=0 file=missing
Disabled tools: bash, create, edit, ...
I was unable to create the file. My available tools are read-only (view, grep, glob) - I have no write, edit, or shell execution tool in this environment, so readonly-deny.txt was not created.
```

## 8. Hooks config `version`

VERIFIED.

With `$COPILOT_HOME/hooks/probe.json` set to:

```json
{"version":2,"hooks":{"sessionStart":[...]}}
```

Copilot exited `0`, answered the prompt, and no hook capture was written. No
stderr warning was emitted. Unknown hook config versions are silently ignored,
not rejected loudly.

## 9. Repo-level hook discovery

VERIFIED GAP.

The requested repo-level `.github/hooks/probe.json` was tested with:
- `version: 1`
- `sessionStart`, `SessionStart`, `preToolUse`, `postToolUse`, `preCompact`
- hook file present in the scratch git repo
- hook file also staged with `git add`
- `--experimental`

No capture files were written. Adjacent repo settings probes also did not fire:
- `.github/settings.json`
- `.github/copilot/settings.json`
- `.github/copilot/hooks/probe.json`
- `.copilot/hooks/probe.json`

The same hook file copied to `$COPILOT_HOME/hooks/probe.json` fired immediately.
Copilot's own fetched docs say `.github/hooks/*.json` is supported, but the local
CLI did not load it in these headless probes. Do not implement repo-level
registration from docs alone.

## Implications for the plan

- Register Copilot hooks using camelCase event names to keep stdin camelCase.
- `sessionStart` project detection can read `.cwd` directly.
- `guard.sh` must add Copilot command extraction as:

```sh
.toolArgs | fromjson | .command
```

- Ship JSON deny for Copilot:

```json
{"permissionDecision":"deny","permissionDecisionReason":"..."}
```

- Non-zero hook exits also block tools in CLI `1.0.71`, including exit `2`, but
  JSON deny is the stable contract.
- `postToolUse` can carry compaction recovery or breadcrumb context through
  `additionalContext`.
- `preCompact` can arm the recompact sentinel from a headless `/compact` path;
  output is still not the delivery channel.
- `exec_cmd` should use:

```sh
copilot -p "{prompt}" --allow-all --silent --stream off --no-color --no-auto-update
```

- `exec_readonly` should use:

```sh
copilot -p "{prompt}" --available-tools=view,grep,glob --allow-all-tools --allow-all-paths --allow-all-urls --silent --stream off --no-color --no-auto-update
```

- `exec_last_message`: stdout as-is in `--silent` mode.
- `timeoutSec`: set explicitly on every hook. `5` seconds was sufficient for
  probe hooks; use a low single-digit timeout for guard hooks because timeout
  behavior remains a fail-open risk unless separately proven.
- Registration target must be revisited. `$COPILOT_HOME/hooks/*.json` works;
  repo-level `.github/hooks/*.json` did not fire locally in headless CLI `1.0.71`.
