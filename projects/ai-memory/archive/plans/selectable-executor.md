---
plan: selectable-executor
status: done
created: 2026-06-29
completed: 2026-06-29
owner: claude (orchestrator)
---

# Selectable Executor — Implementation Plan

> **For agentic workers:** implement task-by-task. Steps use checkbox (`- [x]`) syntax. TDD: write the failing test, watch it fail, implement, watch it pass, commit. Targets macOS `bash` 3.2 (no associative arrays, no `mapfile`).

**Goal:** Make the orchestrator's executor user-selectable via `config.local.sh`, supporting a `claude-subagent` type (harness Agent tool) and generic CLI types (`codex` built-in + arbitrary command templates), resolving the shell-vs-harness plane split through a `scripts/executor.sh` resolver.

**Architecture:** `executor.sh` reads config (via `_lib.sh` → `config.local.sh`), resolves the preferred executor + availability + fallback, and reports *which plane* to use (`subagent` | `cli:<key>`). The orchestrator calls `--which` to branch: subagent → Agent tool; CLI → `executor.sh --run` over Bash. `codex-mem.sh` stays the unchanged codex adapter beneath it.

**Tech Stack:** POSIX/bash-3.2 shell; existing `scripts/_lib.sh` config loader; `scripts/tests/_assert.sh` test harness.

**Spec:** `docs/superpowers/specs/2026-06-29-selectable-executor-design.md`

---

## File structure

- **Create:** `scripts/executor.sh` — selection/dispatch layer. Single responsibility: resolve config → plane, and exec CLI executors.
- **Create:** `scripts/tests/test_executor.sh` — dependency-free test, auto-discovered by the suite runner.
- **Modify:** `config.local.sh.example` — document the three new keys.
- **Modify:** `identity.md` — replace hardcoded Codex-primary delegation rules with the `--which` protocol; reframe codex deny-rules as optional.
- **Modify:** `claude/CLAUDE.md` — same rewrite in the Orchestrator/Executor/Validator section.
- **Modify:** `README.md` — document executor selection.
- **Modify (repo):** `agents/kubernetes-specialist.md`, `agents/terraform-engineer.md` — add trailing newline (item 4).
- **Runtime only (not in repo):** create `$MEMORY_DIR/config.local.sh` setting `AI_MEMORY_EXECUTOR=claude-subagent`; re-symlink the 3 item-4 files into `~/.claude/`.

Run the suite with: `for t in scripts/tests/test_*.sh; do bash "$t"; done`

---

## Task 1: `executor.sh` skeleton + `claude-subagent` resolution — ✅ DONE (826cc05)

**Files:**
- Create: `scripts/executor.sh`
- Test: `scripts/tests/test_executor.sh`

- [x] **Step 1: Write the failing test**

Create `scripts/tests/test_executor.sh`:

```bash
#!/usr/bin/env bash
# executor.sh: selection/dispatch resolver. Uses stub binaries on PATH so no
# real codex/aider is needed. Targets bash 3.2.
. "$(dirname "$0")/_assert.sh"

EXE="$SCRIPTS_DIR/executor.sh"
MEM="$(new_sandbox)"
BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

run() { # run <args...> ; sets OUT (stdout), ERR (stderr), CODE
    local tmp_out tmp_err
    tmp_out="$BIN/.o"; tmp_err="$BIN/.e"
    set +e
    bash "$EXE" "$@" >"$tmp_out" 2>"$tmp_err"; CODE=$?
    set -e
    OUT="$(cat "$tmp_out")"; ERR="$(cat "$tmp_err")"
}

# --- 1. default (unset) -> subagent ---
set +e
( unset AI_MEMORY_EXECUTOR; export MEMORY_DIR="$MEM"
  bash "$EXE" --which ) > "$BIN/o" 2> "$BIN/e"; CODE=$?
set -e
assert_eq "subagent" "$(cat "$BIN/o")" "default executor resolves to subagent"
assert_exit 0 "$CODE" "default --which exits 0"

# --- 1b. explicit claude-subagent -> subagent ---
export AI_MEMORY_EXECUTOR="claude-subagent"
run --which
assert_eq "subagent" "$OUT" "explicit claude-subagent -> subagent"
assert_exit 0 "$CODE" "claude-subagent --which exits 0"

finish
```

- [x] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test_executor.sh`
Expected: FAIL — `executor.sh` does not exist yet (`bash: .../executor.sh: No such file`), assertions fail.

- [x] **Step 3: Write minimal implementation**

Create `scripts/executor.sh`:

```bash
#!/usr/bin/env bash
# Select and dispatch the orchestrator's executor — the selection layer above
# codex-mem.sh. Reads config.local.sh (via _lib.sh).
#
#   executor.sh --which            -> prints 'subagent' or 'cli:<key>'
#   executor.sh --run "<prompt>"   -> execs the CLI executor, or prints
#                                     EXECUTOR_USE_SUBAGENT (exit 3) for the subagent plane
#   executor.sh --show             -> human-readable diagnostics
#
# Exit codes: 0 resolved | 1 preferred unavailable + no fallback |
#             2 unknown executor / usage error | 3 --run resolved to subagent
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

EXECUTOR="${AI_MEMORY_EXECUTOR:-claude-subagent}"
# Unset -> default claude-subagent; set-but-empty -> no fallback (hard-fail).
FALLBACK="${AI_MEMORY_EXECUTOR_FALLBACK-claude-subagent}"

# Resolve a single executor key with NO fallback.
# Prints 'subagent' or 'cli:<key>' on success (0).
resolve_one() {
    local key="$1"
    if [ "$key" = "claude-subagent" ]; then
        printf 'subagent\n'; return 0
    fi
    printf 'executor: unknown executor %s\n' "$key" >&2
    return 2
}

resolve() { resolve_one "$EXECUTOR"; }

MODE="${1:-}"
case "$MODE" in
    --which) resolve; exit $? ;;
    *) printf 'usage: executor.sh --which | --run "<prompt>" | --show\n' >&2; exit 2 ;;
esac
```

- [x] **Step 4: Make executable + run test to verify it passes**

Run: `chmod +x scripts/executor.sh && bash scripts/tests/test_executor.sh`
Expected: PASS — `test_executor.sh: 4 passed, 0 failed`

- [x] **Step 5: Commit**

```bash
git add scripts/executor.sh scripts/tests/test_executor.sh
git commit -m "feat(executor): add executor.sh with --which claude-subagent resolution"
```

---

## Task 2: codex CLI resolution, availability probe, fallback — ✅ DONE (b5c42d0, +first_word set -f hardening)

**Files:**
- Modify: `scripts/executor.sh`
- Test: `scripts/tests/test_executor.sh`

- [x] **Step 1: Append failing test cases**

Append before `finish` in `scripts/tests/test_executor.sh`:

```bash
# --- 2. codex selected + codex present on PATH -> cli:codex ---
cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/codex"
OLDPATH="$PATH"; export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR="codex"
run --which
assert_eq "cli:codex" "$OUT" "codex present -> cli:codex"
assert_exit 0 "$CODE" "codex present --which exits 0"

# --- 3. codex selected + codex ABSENT + default fallback -> subagent ---
export PATH="$OLDPATH"   # codex no longer reachable
run --which
assert_eq "subagent" "$OUT" "codex absent -> falls back to subagent"
assert_exit 0 "$CODE" "codex absent w/ fallback exits 0"
assert_contains "$ERR" "falling back" "fallback note on stderr"

# --- 4. codex absent + empty fallback -> hard-fail exit 1 ---
export AI_MEMORY_EXECUTOR_FALLBACK=""
run --which
assert_exit 1 "$CODE" "codex absent + no fallback exits 1"
unset AI_MEMORY_EXECUTOR_FALLBACK
```

- [x] **Step 2: Run test to verify the new cases fail**

Run: `bash scripts/tests/test_executor.sh`
Expected: FAIL — codex cases hit the `unknown executor` branch (exit 2), assertions for `cli:codex`/`subagent` fail.

- [x] **Step 3: Implement codex resolution + availability + fallback**

In `scripts/executor.sh`, replace the `resolve_one` and `resolve` functions with:

```bash
first_word() { set -- $1; printf '%s' "${1:-}"; }

# Look up the command template for a generic CLI key (empty if unset/invalid name).
cmd_template() {
    local key="$1" var tmpl
    case "$key" in *[!A-Za-z0-9_]*) printf ''; return 0 ;; esac
    var="AI_MEMORY_EXECUTOR_CMD_${key}"
    eval "tmpl=\${${var}:-}"
    printf '%s' "$tmpl"
}

# Resolve a single executor key with NO fallback.
# Prints 'subagent' or 'cli:<key>' on success (0).
# Returns 1 = CLI binary unavailable, 2 = unknown key / bad template.
resolve_one() {
    local key="$1" tmpl bin
    if [ "$key" = "claude-subagent" ]; then
        printf 'subagent\n'; return 0
    fi
    if [ "$key" = "codex" ]; then
        bin=codex
    else
        tmpl="$(cmd_template "$key")"
        if [ -z "$tmpl" ]; then
            printf 'executor: unknown executor %s (set AI_MEMORY_EXECUTOR_CMD_%s or use a built-in)\n' "$key" "$key" >&2
            return 2
        fi
        case "$tmpl" in
            *'{prompt}'*) : ;;
            *) printf 'executor: AI_MEMORY_EXECUTOR_CMD_%s must contain {prompt}\n' "$key" >&2; return 2 ;;
        esac
        bin="$(first_word "$tmpl")"
    fi
    if command -v "$bin" >/dev/null 2>&1; then
        printf 'cli:%s\n' "$key"; return 0
    fi
    printf 'executor: %s unavailable (%s not in PATH)\n' "$key" "$bin" >&2
    return 1
}

# Resolve with fallback. Prints plane; returns 0/1/2.
resolve() {
    local out rc
    out="$(resolve_one "$EXECUTOR")"; rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    if [ "$rc" -eq 2 ]; then return 2; fi
    # rc=1 unavailable -> try fallback if set
    if [ -n "$FALLBACK" ]; then
        printf 'executor: %s unavailable; falling back to %s\n' "$EXECUTOR" "$FALLBACK" >&2
        out="$(resolve_one "$FALLBACK")"; rc=$?
        [ "$rc" -eq 0 ] && { printf '%s\n' "$out"; return 0; }
        return "$rc"
    fi
    printf 'executor: %s unavailable and no fallback set\n' "$EXECUTOR" >&2
    return 1
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test_executor.sh`
Expected: PASS — all cases green.

- [x] **Step 5: Commit**

```bash
git add scripts/executor.sh scripts/tests/test_executor.sh
git commit -m "feat(executor): codex resolution, availability probe, fallback"
```

---

## Task 3: generic CLI templates + unknown-key handling — ✅ DONE (3a54fe5, test-only)

**Files:**
- Modify: `scripts/tests/test_executor.sh` (logic already implemented in Task 2; this verifies the generic path)
- Test: `scripts/tests/test_executor.sh`

- [x] **Step 1: Append failing/verification test cases**

Append before `finish`:

```bash
# --- 5. unknown key (no template) -> exit 2 ---
export AI_MEMORY_EXECUTOR="bogus"
run --which
assert_exit 2 "$CODE" "unknown executor key exits 2"
assert_contains "$ERR" "unknown executor" "unknown key message"

# --- 5b. template without {prompt} -> exit 2 ---
export AI_MEMORY_EXECUTOR="aider"
export AI_MEMORY_EXECUTOR_CMD_aider="aider --yes"
run --which
assert_exit 2 "$CODE" "template missing {prompt} exits 2"
assert_contains "$ERR" "must contain {prompt}" "missing-token message"

# --- 6. generic CLI present on PATH -> cli:aider ---
cat > "$BIN/aider" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/aider"
export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR_CMD_aider="aider --yes --message {prompt}"
run --which
assert_eq "cli:aider" "$OUT" "generic CLI present -> cli:aider"
assert_exit 0 "$CODE" "generic CLI --which exits 0"
export PATH="$OLDPATH"
```

- [x] **Step 2: Run test to verify it passes**

Run: `bash scripts/tests/test_executor.sh`
Expected: PASS — generic-key resolution already implemented in Task 2's `resolve_one`/`cmd_template`. If case 6 fails, confirm `first_word` returns `aider` from the template.

- [x] **Step 3: (No new implementation expected)**

The generic path is covered by Task 2. Only implement if a case fails (e.g. a `bash -n` syntax slip). Skip otherwise.

- [x] **Step 4: Commit**

```bash
git add scripts/tests/test_executor.sh
git commit -m "test(executor): cover generic CLI templates and unknown-key errors"
```

---

## Task 4: `--run` execution + subagent sentinel + `{prompt}` substitution — ✅ DONE (b665bbc, +shq apostrophe-bug fix caught in review)

**Files:**
- Modify: `scripts/executor.sh`
- Test: `scripts/tests/test_executor.sh`

- [x] **Step 1: Append failing test cases**

Append before `finish`:

```bash
# --- 7. --run with generic CLI substitutes {prompt} and executes ---
MARK="$BIN/ran.txt"
cat > "$BIN/echoexec" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$MARK"
exit 0
EOF
chmod +x "$BIN/echoexec"
export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR="echoexec"
export AI_MEMORY_EXECUTOR_CMD_echoexec="echoexec ARG {prompt} END"
run --run "do the thing"
assert_exit 0 "$CODE" "--run generic CLI exits 0 via stub"
assert_eq "ARG do the thing END" "$(cat "$MARK")" "--run substitutes {prompt} (quoted)"
export PATH="$OLDPATH"

# --- 8. --run resolving to subagent -> sentinel + exit 3 ---
export AI_MEMORY_EXECUTOR="claude-subagent"
run --run "anything"
assert_eq "EXECUTOR_USE_SUBAGENT" "$OUT" "--run subagent prints sentinel"
assert_exit 3 "$CODE" "--run subagent exits 3"

# --- 8b. --run with missing prompt -> exit 2 ---
run --run
assert_exit 2 "$CODE" "--run without prompt exits 2"
```

- [x] **Step 2: Run test to verify the new cases fail**

Run: `bash scripts/tests/test_executor.sh`
Expected: FAIL — `--run` is unhandled (hits usage branch, exit 2 for all), sentinel/substitution assertions fail.

- [x] **Step 3: Implement `--run` + `run_cli`**

In `scripts/executor.sh`, add the `shq` and `run_cli` helpers after `cmd_template`:

```bash
# Single-quote a string for safe eval.
shq() { local s="${1:-}"; s="${s//\'/\'\\\'\'}"; printf "'%s'" "$s"; }

# Exec the resolved CLI executor for <key> with <prompt>. Does not return.
run_cli() {
    local key="$1" prompt="$2" tmpl q cmd
    if [ "$key" = "codex" ]; then
        exec "$SCRIPT_DIR/codex-mem.sh" --executor "$prompt" </dev/null
    fi
    tmpl="$(cmd_template "$key")"
    q="$(shq "$prompt")"
    cmd="${tmpl//\{prompt\}/$q}"
    eval "exec ${cmd} </dev/null"
}
```

Then replace the `case "$MODE"` block with:

```bash
MODE="${1:-}"
case "$MODE" in
    --which)
        resolve; exit $?
        ;;
    --run)
        PROMPT="${2:-}"
        if [ -z "$PROMPT" ]; then
            printf 'executor --run: missing prompt argument\n' >&2; exit 2
        fi
        PLANE="$(resolve)"; rc=$?
        [ "$rc" -eq 0 ] || exit "$rc"
        case "$PLANE" in
            subagent) printf 'EXECUTOR_USE_SUBAGENT\n'; exit 3 ;;
            cli:*)    run_cli "${PLANE#cli:}" "$PROMPT" ;;
        esac
        ;;
    --show)
        printf 'AI_MEMORY_EXECUTOR          = %s\n' "$EXECUTOR"
        printf 'AI_MEMORY_EXECUTOR_FALLBACK = %s\n' "${FALLBACK:-<empty>}"
        if PLANE="$(resolve 2>/dev/null)"; then
            printf 'resolved plane              = %s\n' "$PLANE"
        else
            printf 'resolved plane              = <unresolved, rc=%s>\n' "$?"
        fi
        ;;
    *)
        printf 'usage: executor.sh --which | --run "<prompt>" | --show\n' >&2
        exit 2
        ;;
esac
```

- [x] **Step 4: Run test to verify it passes + syntax check**

Run: `bash -n scripts/executor.sh && bash scripts/tests/test_executor.sh`
Expected: PASS — all cases green; `bash -n` silent.

- [x] **Step 5: Commit**

```bash
git add scripts/executor.sh scripts/tests/test_executor.sh
git commit -m "feat(executor): --run dispatch, subagent sentinel, {prompt} substitution, --show"
```

---

## Task 5: document config keys in `config.local.sh.example` — ✅ DONE (edd2827)

**Files:**
- Modify: `config.local.sh.example`

- [x] **Step 1: Add the executor block**

Append to `config.local.sh.example` (before the trailing `MEMORY_DIR` NOTE):

```sh
# ── Orchestrator executor selection ──
# Which executor the orchestrator delegates actionable work to.
#   claude-subagent  — in-harness Claude Agent tool (default; always available)
#   codex            — CLI via scripts/codex-mem.sh --executor
#   <other>          — generic CLI; define its command with AI_MEMORY_EXECUTOR_CMD_<key>
#                      (<key> must match [A-Za-z0-9_]+; the template must contain {prompt})
# export AI_MEMORY_EXECUTOR="claude-subagent"

# Generic CLI executor example ({prompt} is substituted, already shell-quoted):
# export AI_MEMORY_EXECUTOR="aider"
# export AI_MEMORY_EXECUTOR_CMD_aider='aider --yes --message {prompt}'

# Fallback used when the preferred CLI executor's binary is missing.
# Empty string = hard-fail instead of falling back.
# export AI_MEMORY_EXECUTOR_FALLBACK="claude-subagent"
```

- [x] **Step 2: Verify the example still sources cleanly**

Run: `bash -n config.local.sh.example`
Expected: silent (valid shell).

- [x] **Step 3: Commit**

```bash
git add config.local.sh.example
git commit -m "docs(config): document AI_MEMORY_EXECUTOR selection keys"
```

---

## Task 6: rewrite delegation rules in `identity.md` and `claude/CLAUDE.md` — ✅ DONE (c19bd29)

**Files:**
- Modify: `identity.md` (Orchestration section — the executor/fallback bullets, ~lines 58-59, and the codex deny-rules reference)
- Modify: `claude/CLAUDE.md` (Orchestrator/Executor/Validator workflow — items 2 & 3, and the "Executors never apply" deny-list note)

- [x] **Step 1: Read both files' relevant sections**

Run: `sed -n '55,82p' identity.md` and `sed -n '66,92p' claude/CLAUDE.md` to capture exact current wording before editing.

- [x] **Step 2: Rewrite `identity.md` executor bullets**

Replace the two bullets that currently read "Delegate non-trivial actionable execution to Codex via `codex-mem.sh --executor`…" and "Fallback executor: Claude `Agent` subagent…" with:

```markdown
- **Delegate non-trivial *actionable* execution via the configured executor.** Before delegating, run `scripts/executor.sh --which`:
  - prints `subagent` → delegate via the Claude `Agent` tool (`sonnet` default, `haiku` for lightweight work).
  - prints `cli:<key>` → delegate by running `scripts/executor.sh --run "<prompt>"` via Bash; if that prints `EXECUTOR_USE_SUBAGENT` (exit 3), switch to the Agent tool.
  The preferred executor is whatever `AI_MEMORY_EXECUTOR` is set to in `config.local.sh` (default `claude-subagent`); an unavailable CLI executor auto-falls-back per `AI_MEMORY_EXECUTOR_FALLBACK`. Never delegate exploration or research — handle those directly.
- **Hard rules bind every executor, both planes.** The delegation prompt MUST restate the deny-list (no `terraform apply`/`destroy`, `kubectl apply`/`delete`, PR merges, `helm install`/`upgrade`, or any destructive/additive action on running infra) regardless of which executor runs. For the `codex` CLI executor specifically, `~/.codex/rules/default.rules` is *optional* defense-in-depth — install it if you use codex; do not assume it is present.
```

- [x] **Step 3: Rewrite `claude/CLAUDE.md` items 2 & 3**

Replace workflow items **2 (Executor primary: Codex…)** and **3 (Executor fallback: Claude Agent…)** with a single item:

```markdown
2. **Executor: user-selectable via `AI_MEMORY_EXECUTOR`** (set in `config.local.sh`; default `claude-subagent`). To delegate, run `~/.claude-memory/scripts/executor.sh --which`:
   - `subagent` → use the Claude `Agent` tool (`sonnet` default, `haiku` lightweight).
   - `cli:<key>` → run `~/.claude-memory/scripts/executor.sh --run "<prompt>"`; on `EXECUTOR_USE_SUBAGENT` (exit 3), use the Agent tool instead.

   Built-in executor types: `claude-subagent` (in-harness) and `codex` (CLI via `codex-mem.sh --executor`). Add other CLI tools with `AI_MEMORY_EXECUTOR_CMD_<key>`. A missing CLI binary auto-falls-back per `AI_MEMORY_EXECUTOR_FALLBACK`.
3. **Validator: Claude `Agent` subagent (`sonnet`)** — (renumber the existing Validator item; unchanged content).
```

Then in the "Executors never apply or merge" hard-rule note, change "Blocked at the codex execpolicy layer (`~/.codex/rules/default.rules`) and reinforced in `identity.md`" to "Enforced by restating the deny-list in every delegation prompt (both planes); for the `codex` CLI executor, `~/.codex/rules/default.rules` is optional defense-in-depth if installed."

- [x] **Step 4: Verify no stale "Codex primary" / false deny-rules claims remain**

Run: `grep -n -i "primary.*codex\|codex.*primary\|regardless of prompt\|fallback executor" identity.md claude/CLAUDE.md`
Expected: no matches (the hardcoded-primary and "regardless of prompt" guarantees are gone).

- [x] **Step 5: Commit**

```bash
git add identity.md claude/CLAUDE.md
git commit -m "docs: make executor selection user-configurable in identity + CLAUDE.md"
```

---

## Task 7: document executor selection in `README.md` — ✅ DONE (5dc52eb, expanded to reconcile Roles table + hard-rules + cross-project)

**Files:**
- Modify: `README.md`

- [x] **Step 1: Find the right home**

Run: `grep -n -i "codex-mem\|executor\|config.local" README.md` to locate the scripts/config section.

- [x] **Step 2: Add an executor-selection subsection**

Add near the `codex-mem.sh` / config documentation:

```markdown
#### Executor selection

The orchestrator delegates actionable work to a **selectable executor**, configured in `config.local.sh`:

| Key | Default | Meaning |
|-----|---------|---------|
| `AI_MEMORY_EXECUTOR` | `claude-subagent` | Preferred executor. Built-ins: `claude-subagent` (in-harness Agent tool), `codex` (CLI via `codex-mem.sh`). Any other value names a generic CLI executor. |
| `AI_MEMORY_EXECUTOR_CMD_<key>` | — | Command template for generic CLI executor `<key>` (`{prompt}` substituted; `<key>` is `[A-Za-z0-9_]+`). |
| `AI_MEMORY_EXECUTOR_FALLBACK` | `claude-subagent` | Used when the preferred CLI binary is absent. Empty = hard-fail. |

`scripts/executor.sh --which` resolves config + availability and prints `subagent` or `cli:<key>`; `--run "<prompt>"` execs the CLI (or prints `EXECUTOR_USE_SUBAGENT`, exit 3, for the subagent plane); `--show` prints diagnostics.
```

- [x] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document executor selection"
```

---

## Task 8: activate `claude-subagent` on this machine — ✅ DONE (config.local.sh; --which→subagent)

**Files:**
- Runtime: `$MEMORY_DIR/config.local.sh` (gitignored; create or edit)

- [x] **Step 1: Set the active executor**

If `~/.claude-memory/config.local.sh` exists, append; else copy from example first:

```bash
[ -f ~/.claude-memory/config.local.sh ] || cp ~/.claude-memory/config.local.sh.example ~/.claude-memory/config.local.sh
printf '\nexport AI_MEMORY_EXECUTOR="claude-subagent"\n' >> ~/.claude-memory/config.local.sh
```

- [x] **Step 2: Verify resolution on this machine**

Run: `~/.claude-memory/scripts/executor.sh --which`
Expected: `subagent`

Run: `~/.claude-memory/scripts/executor.sh --show`
Expected: shows `AI_MEMORY_EXECUTOR = claude-subagent` and `resolved plane = subagent`.

- [x] **Step 3: (No commit — config.local.sh is gitignored)**

---

## Task 9: item-4 file symlink cleanup — ✅ DONE (304a485; 3 files now repo symlinks; backups → ~/backups/executor-task-item4-backups)

**Files:**
- Modify (repo): `agents/kubernetes-specialist.md`, `agents/terraform-engineer.md` (add trailing newline)
- Runtime: replace the 3 live non-symlink copies under `~/.claude/` with repo symlinks

- [x] **Step 1: Add trailing newline to the two repo agent files**

```bash
cd ~/Projects/ai-memory
for a in kubernetes-specialist terraform-engineer; do
  [ "$(tail -c1 agents/$a.md | wc -l)" -eq 0 ] && printf '\n' >> agents/$a.md
done
cmp ~/.claude/agents/kubernetes-specialist.md agents/kubernetes-specialist.md && echo "k8s now identical"
cmp ~/.claude/agents/terraform-engineer.md agents/terraform-engineer.md && echo "tf now identical"
```
Expected: both report identical.

- [x] **Step 2: Back up + remove the live copies (preserve the skill's local git clone)**

```bash
TS=$(date +%Y%m%d-%H%M%S)
mv ~/.claude/skills/excalidraw-diagram ~/.claude/skills/excalidraw-diagram.bak-$TS
mv ~/.claude/agents/kubernetes-specialist.md ~/.claude/agents/kubernetes-specialist.md.bak-$TS
mv ~/.claude/agents/terraform-engineer.md ~/.claude/agents/terraform-engineer.md.bak-$TS
```

- [x] **Step 3: Re-run the link scripts so the repo versions become symlinks**

```bash
bash ~/Projects/ai-memory/scripts/link-skills.sh
bash ~/Projects/ai-memory/scripts/link-agents.sh
ls -la ~/.claude/skills/excalidraw-diagram ~/.claude/agents/kubernetes-specialist.md ~/.claude/agents/terraform-engineer.md
```
Expected: all three are now symlinks into `~/Projects/ai-memory/{skills,agents}/`; link scripts report them linked.

- [x] **Step 4: Commit the repo newline fix**

```bash
cd ~/Projects/ai-memory
git add agents/kubernetes-specialist.md agents/terraform-engineer.md
git commit -m "fix(agents): add trailing newline to k8s + terraform agent files"
```

- [x] **Step 5: Clean up backups after confidence**

Once the symlinks are confirmed working, the `.bak-*` copies can be removed (the excalidraw `.bak` holds the old local git clone — keep until certain it's not needed).

---

## Task 10: full-suite verification + tracker updates — ✅ DONE (12/12 test files green incl. executor 23/23; lint clean; final holistic review passed)

**Files:**
- Modify: `projects/ai-memory/todo.md`, `projects/ai-memory/plans/github-core-migration.md`

- [x] **Step 1: Run the full shell suite + lint**

```bash
cd ~/Projects/ai-memory
for t in scripts/tests/test_*.sh; do bash "$t"; done
~/.claude-memory/scripts/lint-memory.sh
```
Expected: every test file reports `N passed, 0 failed`; lint clean.

- [x] **Step 2: Tick the migration trackers**

In `projects/ai-memory/todo.md` and `plans/github-core-migration.md`, check off the executor item (item 7) and the item-4 decision, referencing this plan.

- [x] **Step 3: Mark this plan done**

Set this file's frontmatter `status: done`, stamp `completed: 2026-06-29`, and (per lifecycle) move it to `archive/plans/` once the referencing todo items close.

---

## Success criteria

- [x] `scripts/executor.sh` exists with `--which`, `--run`, `--show`; `bash -n` clean; no associative arrays / `mapfile`.
- [x] `AI_MEMORY_EXECUTOR` unset or `claude-subagent` → `--which` prints `subagent`, exit 0.
- [x] `codex` selected + binary present → `cli:codex`; absent + default fallback → `subagent` (stderr note); absent + empty fallback → exit 1.
- [x] Generic CLI key via `AI_MEMORY_EXECUTOR_CMD_<key>` (with `{prompt}`) → `cli:<key>`; template without `{prompt}` → exit 2; unknown key → exit 2.
- [x] `--run` with a CLI executor substitutes `{prompt}` and execs; `--run` resolving to subagent prints `EXECUTOR_USE_SUBAGENT`, exit 3; `--run` without a prompt → exit 2.
- [x] `config.local.sh.example` documents all three keys.
- [x] `identity.md` + `claude/CLAUDE.md` no longer hardcode Codex-primary and no longer claim the codex deny-rules are always present; they describe the `--which`/`--run`/Agent-tool protocol with the deny-list restated as plane-independent.
- [x] `README.md` documents executor selection.
- [x] `scripts/tests/test_executor.sh` passes all 8+ cases; the full `scripts/tests/test_*.sh` suite stays green; lint clean.
- [x] This machine: `config.local.sh` sets `AI_MEMORY_EXECUTOR="claude-subagent"`; `executor.sh --which` prints `subagent`.
- [x] Item 4: `excalidraw-diagram` skill + the two agent files are repo symlinks under `~/.claude/`; the two repo agent files end with a trailing newline.
