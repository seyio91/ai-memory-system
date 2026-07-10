#!/usr/bin/env bash
# Antigravity hook archetype. agy.sh resolves the active project from the launch
# cwd and exports it (+ MEMORY_DIR + cwd) into agy's env — the PreInvocation hook
# has no workspace handle and reads these. preinvocation.sh emits injectSteps:
# full payload on invocationNum 0, the <memory:active> breadcrumb after, and
# dormant ({"injectSteps":[]}) with no project. Stub `agy` on PATH; no real binary.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
WRAP="$REPO/harnesses/antigravity/scripts/agy.sh"
HOOK="$REPO/harnesses/antigravity/hooks/preinvocation.sh"

MEM="$(new_sandbox)"; BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
printf 'working note\n' > "$MEM/projects/proj/working.md"
WORK="$MEM/work"; mkdir -p "$WORK/.agents"; printf 'proj\n' > "$WORK/.agents/memory-project"

# --- agy.sh: stub agy records its args AND the env agy.sh exported ---
CAP="$BIN/agy-args"; ENVCAP="$BIN/agy-env"
cat > "$BIN/agy" <<EOF
#!/usr/bin/env bash
printf '%s ' "\$@" > "$CAP"
{ printf 'PROJECT=%s\n' "\${AI_MEMORY_PROJECT:-}"
  printf 'CWD=%s\n'     "\${AI_MEMORY_CWD:-}"
  printf 'MEMORY_DIR=%s\n' "\${MEMORY_DIR:-}"; } > "$ENVCAP"
exit 0
EOF
chmod +x "$BIN/agy"
export PATH="$BIN:$PATH"

set +e
(cd "$WORK" && bash "$WRAP" -p "do the thing" --model gpt-x) >/dev/null 2>&1; CODE=$?
set -e
assert_exit 0 "$CODE" "agy.sh exits 0 via stub"
args="$(cat "$CAP")"
assert_contains "$args" "-p do the thing" "agy.sh passes the prompt through"
assert_contains "$args" "--model gpt-x"   "agy.sh passes the model flag through"
env_dump="$(cat "$ENVCAP")"
assert_contains "$env_dump" "PROJECT=proj"    "agy.sh exports resolved AI_MEMORY_PROJECT"
assert_contains "$env_dump" "CWD=$WORK"       "agy.sh exports the launch cwd"
assert_contains "$env_dump" "MEMORY_DIR=$MEM" "agy.sh exports MEMORY_DIR"

# --- agy.sh: missing agy binary -> clear error, no exec ---
set +e
(PATH="/usr/bin:/bin" bash "$WRAP" -p x) >/dev/null 2>&1; CODE=$?
set -e
assert_exit 1 "$CODE" "agy.sh errors when agy is absent"

# --- preinvocation.sh: inject payload by invocationNum + project ---
run_hook() { # run_hook <invnum> <project> ; sets OUT
    OUT="$(printf '{"invocationNum":%s}' "$1" \
        | AI_MEMORY_PROJECT="$2" AI_MEMORY_CWD="$WORK" MEMORY_DIR="$MEM" bash "$HOOK")"
}

# invocationNum 0 -> full payload
run_hook 0 proj
assert_contains "$OUT" '"injectSteps"'      "hook 0: emits injectSteps"
assert_contains "$OUT" 'ephemeralMessage'   "hook 0: uses ephemeralMessage"
assert_contains "$OUT" 'memory:identity'    "hook 0: full payload has identity"
assert_contains "$OUT" 'memory:project name=' "hook 0: full payload has project section"
assert_contains "$OUT" 'Project: proj'      "hook 0: full payload inlines the project body"

# later invocation -> lightweight breadcrumb (paths + re-read directive, no body)
run_hook 1 proj
assert_contains "$OUT" 'memory:active project=' "hook 1: emits the active breadcrumb"
assert_contains "$OUT" 'read them before proceeding' "hook 1: breadcrumb carries the re-read directive"
case "$OUT" in
    *"Project: proj"*) _bad "hook 1: breadcrumb should not inline the project body" ;;
    *) _ok "hook 1: breadcrumb omits the full body" ;;
esac

# no active project -> dormant
run_hook 0 ""
assert_eq '{"injectSteps":[]}' "$OUT" "hook: no project -> empty injectSteps"

# emitted payload is valid JSON
if command -v python3 >/dev/null 2>&1; then
    run_hook 0 proj
    if printf '%s' "$OUT" | python3 -m json.tool >/dev/null 2>&1; then
        _ok "hook 0: output parses as JSON"
    else
        _bad "hook 0: output is not valid JSON"
    fi
fi

# ================= PreToolUse guard (pretooluse.sh) =================
GUARD="$REPO/harnesses/antigravity/hooks/pretooluse.sh"

# guard <role> <toolName> <commandLine> ; sets OUT (AI_MEMORY_ROLE empty => unset)
guard() {
    local role="$1" name="$2" cmd="$3" payload
    payload="$(printf '{"toolCall":{"name":"%s","args":{"CommandLine":"%s"}}}' "$name" "$cmd")"
    if [ -n "$role" ]; then
        OUT="$(printf '%s' "$payload" | AI_MEMORY_ROLE="$role" bash "$GUARD")"
    else
        OUT="$(printf '%s' "$payload" | env -u AI_MEMORY_ROLE bash "$GUARD")"
    fi
}
denied()  { case "$1" in *'"decision":"deny"'*)  _ok "$2" ;; *) _bad "$2 (got: $1)" ;; esac; }
allowed() { case "$1" in *'"decision":"allow"'*) _ok "$2" ;; *) _bad "$2 (got: $1)" ;; esac; }

# interactive (no AI_MEMORY_ROLE) -> unguarded, everything allowed
guard "" run_command "terraform apply -auto-approve"; allowed "$OUT" "no role: interactive unguarded (allows terraform apply)"
guard "" write_to_file "";                            allowed "$OUT" "no role: interactive unguarded (allows a write tool)"

# deny-list applies in BOTH roles, matched on the CommandLine
for c in "terraform apply" "terraform destroy" "kubectl apply -f x.yaml" "kubectl delete ns foo" \
         "helm install a b" "helm upgrade a b" "gh pr merge 12" "bkt pr merge" "az repos pr update --status completed"; do
    guard task run_command "$c"; denied "$OUT" "task deny-list blocks: $c"
done

# task role: benign shell is allowed
guard task run_command "ls -la && git log --oneline"; allowed "$OUT" "task: benign run_command allowed"
guard task write_to_file "";                          allowed "$OUT" "task: write tool allowed (task is write-capable)"

# explore role: read-only allowlist — reads allowed, everything else denied
guard explore view_file "";        allowed "$OUT" "explore: view_file allowed"
guard explore grep_search "";      allowed "$OUT" "explore: grep_search allowed"
guard explore list_dir "";         allowed "$OUT" "explore: list_dir allowed (live tool name)"
guard explore run_command "ls";    denied  "$OUT" "explore: run_command denied (no shell in read-only)"
guard explore write_to_file "";    denied  "$OUT" "explore: write_to_file denied"
guard explore create_file "";      denied  "$OUT" "explore: create_file denied"
guard explore some_unknown_tool ""; denied "$OUT" "explore: unknown tool denied (allowlist fails safe)"

# explore deny-list still blocks destructive shell even though run_command is denied anyway
guard explore run_command "kubectl apply -f x"; denied "$OUT" "explore: destructive shell denied"

# validate role: read-only, same allowlist as explore
guard validate view_file "";         allowed "$OUT" "validate: view_file allowed"
guard validate grep_search "";       allowed "$OUT" "validate: grep_search allowed"
guard validate write_to_file "";     denied  "$OUT" "validate: write_to_file denied"
guard validate create_file "";       denied  "$OUT" "validate: create_file denied"
guard validate run_command "ls";     denied  "$OUT" "validate: run_command denied (no shell in read-only)"
guard validate some_unknown_tool ""; denied  "$OUT" "validate: unknown tool denied (allowlist fails safe)"

# validate deny-list still blocks destructive shell even though run_command is denied anyway
guard validate run_command "kubectl apply -f x"; denied "$OUT" "validate: destructive shell denied"

# ================= statusline (statusline.sh) =================
SL="$REPO/harnesses/antigravity/statusline.sh"
PAYLOAD='{"agent_state":"working","context_window":{"used_percentage":63.4},"vcs":{"branch":"main","dirty":true},"sandbox":{"enabled":true},"subagents":[1,2],"task_count":3,"model":{"display_name":"Gemini 3.5 Flash"},"terminal_width":100}'

# project + folder resolve from env; renders memory project, folder, branch, model, ctx
OUT="$(printf '%s' "$PAYLOAD" | AI_MEMORY_PROJECT=proj AI_MEMORY_CWD="$WORK" USE_NERD_FONTS=false bash "$SL")"
assert_contains "$OUT" "proj"            "statusline: shows the memory project"
assert_contains "$OUT" "$(basename "$WORK")" "statusline: shows the folder"
assert_contains "$OUT" "main"            "statusline: shows the git branch"
assert_contains "$OUT" "Gemini 3.5 Flash" "statusline: shows the model"
assert_contains "$OUT" "63.4%"           "statusline: shows context % (period decimal, any locale)"
assert_contains "$OUT" "WORKING"         "statusline: shows agent state"

# dormant when no project resolves
OUT="$(printf '%s' "$PAYLOAD" | env -u AI_MEMORY_PROJECT AI_MEMORY_CWD=/tmp/nowhere-xyz USE_NERD_FONTS=false bash "$SL")"
assert_contains "$OUT" "dormant" "statusline: dormant with no active project"

# no-jq fallback: must not error, still prints something
OUT="$(printf '%s' "$PAYLOAD" | PATH=/usr/bin:/bin AI_MEMORY_PROJECT=proj USE_NERD_FONTS=false bash "$SL" 2>&1)"; c=$?
assert_exit 0 "$c" "statusline: no-jq fallback exits 0"
assert_contains "$OUT" "proj" "statusline: no-jq fallback still renders the project"

# default glyphs are emoji (like Claude) \u2014 \ud83e\udde0 memory, renders in any terminal
OUT="$(printf '%s' "$PAYLOAD" | AI_MEMORY_PROJECT=proj bash "$SL")"
MEM_EMOJI=$'\U0001F9E0'
case "$OUT" in *"$MEM_EMOJI"*) _ok "statusline: default emoji glyph present (brain)" ;; *) _bad "statusline: missing default emoji glyph" ;; esac
# opt-in Nerd Font mode emits the pinned glyph codepoints (U+F1C0 database)
OUT="$(printf '%s' "$PAYLOAD" | AI_MEMORY_PROJECT=proj USE_NERD_FONTS=true bash "$SL")"
NF_GLYPH=$'\uf1c0'
case "$OUT" in *"$NF_GLYPH"*) _ok "statusline: USE_NERD_FONTS=true emits NF glyph (U+F1C0)" ;; *) _bad "statusline: NF glyph missing in nerd mode" ;; esac

# --- per-worktree overlay: a linked-worktree AI_MEMORY_CWD injects working.<wt>.md ---
if command -v git >/dev/null 2>&1; then
    WT="$(new_sandbox)"
    git -C "$WT" init -q
    git -C "$WT" -c user.name=T -c user.email=t@e commit --allow-empty -qm init
    git -C "$WT" worktree add -q -b feat "$WT/wt-feat" 2>/dev/null
    printf '# Working\n\nWT-ONLY-SCRATCH\n' > "$MEM/projects/proj/working.wt-feat.md"
    OUT="$(printf '{"invocationNum":0}' \
        | AI_MEMORY_PROJECT=proj AI_MEMORY_CWD="$WT/wt-feat" MEMORY_DIR="$MEM" bash "$HOOK")"
    assert_contains     "$OUT" "WT-ONLY-SCRATCH" "antigravity worktree: overlay working.<wt>.md injected"
    assert_not_contains "$OUT" "working note"     "antigravity worktree: base working.md NOT injected"
    rm -rf "$WT"
fi

finish
