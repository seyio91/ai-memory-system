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
| `hooks_dir`, `statusline` | *(hook)* symlink targets for the hook scripts + statusline |
| `context_target`, `refresh` | *(file)* where the context file lives; `refresh = launch` (rebuilt by the wrapper) or `hook` |
| `commands` | `native` (symlink into `commands_dir`) · `skill` (wrap each command as a `SKILL.md` into `skills_dir`) · `doc` (render a reference) · `none` |
| `commands_dir`, `skills_dir`, `agents_dir` | fan-out targets (a shared `~/.agents/skills` is the cross-agent standard) |

**Execute face** (usable as an executor — consumed by `executor.sh`):

| key | meaning |
|-----|---------|
| `exec = subagent` | in-harness agent (Claude) |
| `exec_cmd` | headless command, `{prompt}` placeholder (e.g. `codex exec {prompt}`) |
| `exec_model_flag` | model flag template, `{model}` (e.g. `--model {model}`) |
| `exec_readonly` | optional read-only headless command; omit → the harness is a task-role executor only |

## 2. (file archetype) add a launch wrapper

A `file` harness rebuilds its context on each launch. Add `harnesses/<name>/scripts/<name>.sh`
that calls the shared builder then exec's the real CLI — mirror `harnesses/codex/scripts/codex-mem.sh`
or `harnesses/antigravity/scripts/agy.sh`:

```bash
bash "$MEM_SCRIPTS/build-context-md.sh" "$CONTEXT_TARGET" "<name>" "$OVERLAY"
exec <cli> "$@"
```

Users alias the real CLI to this wrapper.

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
