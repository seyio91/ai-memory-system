#!/usr/bin/env bash
# link-command-skills.sh (commands=skill) and gen-commands-doc.sh (commands=doc):
# wrapper frontmatter synthesis, the .from-command marker, collision guards
# (canonical symlink / foreign dir), idempotent regeneration, and doc rendering.
. "$(dirname "$0")/_assert.sh"

LCS="$SCRIPTS_DIR/link-command-skills.sh"
GCD="$SCRIPTS_DIR/gen-commands-doc.sh"

SB="$(new_sandbox)"; trap 'rm -rf "$SB"' EXIT
SRC="$SB/commands"; TGT="$SB/skills"
mkdir -p "$SRC"
printf 'Pin the current repo to project $ARGUMENTS.\n\nMore body here.\n' > "$SRC/pin.md"
printf 'Show the "In Flight" snapshot: what is on my plate.\n' > "$SRC/state.md"

# --- generate command-skills ---
out="$(bash "$LCS" "$SRC" "$TGT" 2>&1)"; rc=$?
assert_exit 0 "$rc" "link-command-skills exits 0"
assert_file "$TGT/pin/SKILL.md"        "pin SKILL.md generated"
assert_file "$TGT/pin/.from-command"   "pin marked .from-command"
assert_file "$TGT/state/SKILL.md"      "state SKILL.md generated"
body="$(cat "$TGT/pin/SKILL.md")"
assert_contains "$body" "name: pin"                 "pin: name frontmatter"
assert_contains "$body" "Pin the current repo"      "pin: description from first line"
assert_contains "$body" "tier: target-write"        "pin: tier frontmatter"
assert_contains "$body" "More body here."           "pin: command body carried through"
# description with an embedded double-quote is escaped (state.md has one)
assert_contains "$(cat "$TGT/state/SKILL.md")" '\"In Flight\"' "state: description double-quotes escaped"

# --- idempotent regenerate ---
bash "$LCS" "$SRC" "$TGT" >/dev/null 2>&1
assert_exit 0 "$?" "regenerate exits 0 (idempotent)"

# --- collision: a canonical (symlinked) skill of the same name is left alone ---
realskill="$SB/realpin"; mkdir -p "$realskill"; printf 'x\n' > "$realskill/SKILL.md"
rm -rf "$TGT/pin"; ln -s "$realskill" "$TGT/pin"
out="$(bash "$LCS" "$SRC" "$TGT" 2>&1)"
assert_contains "$out" "already a linked skill" "collision: linked skill skipped (WARN)"
assert_eq "$realskill" "$(readlink "$TGT/pin")" "collision: canonical symlink untouched"

# --- collision: a foreign real dir (no marker) is left alone ---
rm -rf "$TGT/state"; mkdir -p "$TGT/state"; printf 'mine\n' > "$TGT/state/SKILL.md"
out="$(bash "$LCS" "$SRC" "$TGT" 2>&1)"
assert_contains "$out" "not command-generated" "collision: foreign dir skipped (WARN)"
assert_eq "mine" "$(cat "$TGT/state/SKILL.md")" "collision: foreign dir untouched"

# --- gen-commands-doc ---
DOC="$SB/MEMORY-COMMANDS.md"
bash "$GCD" "$SRC" "$DOC" >/dev/null 2>&1
assert_exit 0 "$?" "gen-commands-doc exits 0"
doc="$(cat "$DOC")"
assert_contains "$doc" "# Memory Commands"   "doc: heading"
assert_contains "$doc" "**/pin**"            "doc: pin bullet"
assert_contains "$doc" "**/state**"          "doc: state bullet"

finish
