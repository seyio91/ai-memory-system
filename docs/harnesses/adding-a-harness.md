# Adding a harness

The installer is a generic engine; a harness is **registered by a manifest**, not by new
engine code. To add one:

## 1. Write `harnesses/<name>/manifest`

Declarative `key = value` (comments `#`, `~`/`$HOME` expanded). It is **data, never sourced**.
Declare either or both capability faces:

**Deliver face** (install target):

| key | values / meaning |
|-----|------------------|
| `name` | must equal the dir name |
| `archetype` | `hook` (live per-prompt injection) or `file` (materialize a context file read at launch) |
| `format` | `xml` (`<memory:*>` tags) or `md` (`# === X ===` headers) |
| `hooks_dir`, `statusline` | *(hook, symlink style)* symlink targets for the hook scripts + statusline — Claude |
| `hooks_json`, `hook_script`, `guard_script` | *(hook, JSON style)* a JSON hooks file to register into + the injection script (`hook_script`) and optional enforcement guard (`guard_script`) — Antigravity |
| `context_target`, `refresh` | *(file)* where the context file lives; `refresh = launch` (rebuilt by the wrapper) or `hook` |
| `commands` | `native` (symlink into `commands_dir`) · `skill` (wrap each command as a `SKILL.md` into `skills_dir`) · `doc` (render a reference) · `none` |
| `commands_dir`, `skills_dir`, `agents_dir` | fan-out targets (a shared `~/.agents/skills` is the cross-agent standard) |

A `hook` harness declares **one of two registration styles**: `hooks_dir` (Claude
— the driver symlinks `harnesses/<name>/hooks/*.sh` into a runtime dir; you merge
the entries into `settings.json`) **or** `hooks_json` + `hook_script` (Antigravity
— the driver registers a namespaced entry running `hook_script` into the harness's
JSON hooks file, idempotently). Both flavours build the *same* `<memory:*>` payload
via the shared `content-core.sh` + formatter; only the I/O envelope and
registration differ.

**Execute face** (usable as an executor — consumed by `executor.sh`):

| key | meaning |
|-----|---------|
| `exec = subagent` | in-harness agent (Claude) |
| `exec_cmd` | headless command, `{prompt}` placeholder (e.g. `codex exec {prompt}`) |
| `exec_model_flag` | model flag template, `{model}` (e.g. `--model {model}`) |
| `exec_readonly` | optional read-only headless command; omit → the harness is a task-role executor only |

`executor.sh` exports `AI_MEMORY_ROLE` (`task`/`explore`) before running the command,
so a **hook-capable** harness can *enforce* read-only rather than rely on a CLI flag:
Antigravity's `exec_readonly` is the same command as `exec_cmd`, and its `PreToolUse`
guard (see `guard_script`) denies every non-read tool when `AI_MEMORY_ROLE=explore`,
plus the shared `scripts/deny-list.txt` for both roles. Interactive sessions (no role)
stay unguarded.

## 2a. (file archetype) add a launch wrapper

A `file` harness rebuilds its context on each launch. Add `harnesses/<name>/scripts/<name>.sh`
that calls the shared builder then exec's the real CLI — mirror `harnesses/codex/scripts/codex-mem.sh`:

```bash
bash "$MEM_SCRIPTS/build-context-md.sh" "$CONTEXT_TARGET" "<name>" "$OVERLAY"
exec <cli> "$@"
```

Users alias the real CLI to this wrapper.

## 2b. (hook archetype, JSON contract) add a hook script

A `hook` harness with a JSON hooks file (`hooks_json`) needs an injection script that
reads the harness's stdin JSON, builds the payload from the **shared**
`content-core.sh` + `formatters/xml.sh`, and wraps it in the harness's inject
envelope — mirror `harnesses/antigravity/hooks/preinvocation.sh`:

```bash
. "$REPO/scripts/content-core.sh"; . "$REPO/scripts/formatters/xml.sh"; . "$REPO/scripts/jsonutil.sh"
# resolve project (from env if the payload has no workspace handle), pick full vs
# breadcrumb by the harness's per-call counter, then emit the harness's envelope.
```

If the payload carries no cwd/workspace (Antigravity's does not), resolve the project
at launch in a wrapper (`agy.sh`) that exports `AI_MEMORY_PROJECT`/`MEMORY_DIR` for the
hook to read. Optionally add a `guard_script` for `PreToolUse` enforcement.

## 3. Register a detection signal

Add a case to `detect_harness()` in `install.sh` so a bare `install.sh` can auto-detect it
(e.g. a runtime dir or a binary on `PATH`). Explicit `install.sh --harness <name>` works
regardless.

## 4. Validate and install

```bash
scripts/validate-manifest.sh harnesses/<name>/manifest   # required keys, enums, archetype rules
install.sh --harness <name>
```

## Escape hatch (oddball harnesses)

For a harness the generic materializer can't express (multi-file rule dirs, TOML commands),
add `harnesses/<name>/<name>.sh`; the engine calls `<name>.sh --install` when present. Use it
for genuine format oddities — not to bypass the manifest.
