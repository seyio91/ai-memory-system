#!/usr/bin/env bash
# validate-manifest.sh: required keys, enum values, archetype-specific rules,
# name/dir match, and unknown-key warnings. Also asserts the shipped manifests
# are clean.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
VM="$SCRIPTS_DIR/validate-manifest.sh"

MEM="$(new_sandbox)"; trap 'rm -rf "$MEM"' EXIT

# write_manifest <harness-name> <body...>  -> prints the manifest file path
write_manifest() {
    local name="$1"; shift
    local d="$MEM/harnesses/$name"
    mkdir -p "$d"
    printf '%s\n' "$@" > "$d/manifest"
    printf '%s' "$d/manifest"
}

# run VM on one manifest; capture output + rc
run_vm() { OUT="$(bash "$VM" "$1" 2>&1)"; RC=$?; }

# --- a well-formed hook manifest passes clean ---
mf="$(write_manifest claude \
    'name = claude' 'archetype = hook' 'format = xml' \
    'hooks_dir = ~/.claude/hooks' 'commands = native' 'commands_dir = ~/.claude/commands')"
run_vm "$mf"
assert_exit 0 "$RC" "valid hook manifest: exit 0"
assert_not_contains "$OUT" "ERROR" "valid hook manifest: no errors"

# --- a well-formed file manifest with execute face passes clean ---
mf="$(write_manifest codex \
    'name = codex' 'archetype = file' 'format = md' \
    'context_target = ~/.codex/AGENTS.md' 'refresh = launch' \
    'exec_cmd = codex exec {prompt}')"
run_vm "$mf"
assert_exit 0 "$RC" "valid file manifest: exit 0"

# --- bad archetype ---
mf="$(write_manifest claude 'name = claude' 'archetype = webhook' 'format = xml' 'hooks_dir = ~/.claude/hooks')"
run_vm "$mf"; assert_exit 1 "$RC" "bad archetype: exit 1"
assert_contains "$OUT" "archetype must be hook|file" "bad archetype: message"

# --- bad format ---
mf="$(write_manifest claude 'name = claude' 'archetype = hook' 'format = yaml' 'hooks_dir = ~/.claude/hooks')"
run_vm "$mf"; assert_contains "$OUT" "format must be xml|md" "bad format: message"

# --- hook archetype missing hooks_dir ---
mf="$(write_manifest claude 'name = claude' 'archetype = hook' 'format = xml')"
run_vm "$mf"; assert_exit 1 "$RC" "hook w/o hooks_dir: exit 1"
assert_contains "$OUT" "requires 'hooks_dir'" "hook w/o hooks_dir: message"

# --- file archetype missing context_target ---
mf="$(write_manifest codex 'name = codex' 'archetype = file' 'format = md' 'refresh = launch')"
run_vm "$mf"; assert_contains "$OUT" "requires 'context_target'" "file w/o context_target: message"

# --- file archetype bad refresh ---
mf="$(write_manifest codex 'name = codex' 'archetype = file' 'format = md' 'context_target = ~/.codex/AGENTS.md' 'refresh = poll')"
run_vm "$mf"; assert_contains "$OUT" "refresh' must be launch|hook" "file bad refresh: message"

# --- commands=native without commands_dir ---
mf="$(write_manifest claude 'name = claude' 'archetype = hook' 'format = xml' 'hooks_dir = ~/.claude/hooks' 'commands = native')"
run_vm "$mf"; assert_contains "$OUT" "commands=native requires 'commands_dir'" "native w/o commands_dir: message"

# --- bad commands enum ---
mf="$(write_manifest claude 'name = claude' 'archetype = hook' 'format = xml' 'hooks_dir = ~/.claude/hooks' 'commands = slash')"
run_vm "$mf"; assert_contains "$OUT" "commands must be native|skill|doc|none" "bad commands: message"

# --- name does not match dir ---
mf="$(write_manifest claude 'name = klaude' 'archetype = hook' 'format = xml' 'hooks_dir = ~/.claude/hooks')"
run_vm "$mf"; assert_contains "$OUT" "does not match dir" "name mismatch: message"

# --- exec sentinel must be 'subagent' ---
mf="$(write_manifest claude 'name = claude' 'archetype = hook' 'format = xml' 'hooks_dir = ~/.claude/hooks' 'exec = codex')"
run_vm "$mf"; assert_contains "$OUT" "only be the sentinel 'subagent'" "bad exec sentinel: message"

# --- unknown key -> WARN, still exit 0 ---
mf="$(write_manifest claude 'name = claude' 'archetype = hook' 'format = xml' 'hooks_dir = ~/.claude/hooks' 'flavour = spicy')"
run_vm "$mf"
assert_exit 0 "$RC" "unknown key: still exit 0"
assert_contains "$OUT" "unknown key 'flavour'" "unknown key: WARN message"

# --- the shipped manifests are clean ---
OUT="$(bash "$VM" 2>&1)"; RC=$?
assert_exit 0 "$RC" "shipped manifests: validate clean"

finish
