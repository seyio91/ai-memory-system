#!/usr/bin/env bash
# assemble-changelog.sh — fragment assembly, validation, and computed version bump.
. "$(dirname "$0")/_assert.sh"

SCRIPT="$SCRIPTS_DIR/assemble-changelog.sh"
ROOT="$(new_sandbox)"
trap 'rm -rf "$ROOT"' EXIT

# --- helpers ---------------------------------------------------------------

frag_dir() {
    # frag_dir <name> — fresh empty fragment dir, print its path
    local d="$ROOT/frags/$1"
    rm -rf "$d"; mkdir -p "$d"
    printf '%s\n' "$d"
}

# tagged_repo <name> [tag...] — temp git repo with the given tags, print its path
tagged_repo() {
    local name="$1"; shift
    local r="$ROOT/repos/$name"
    mkdir -p "$r"
    git -C "$r" init -q
    git -C "$r" checkout -q -b main
    git -C "$r" config user.email t@e
    git -C "$r" config user.name t
    git -C "$r" commit -q --allow-empty -m base
    local t
    for t in "$@"; do
        git -C "$r" tag "$t"
    done
    printf '%s\n' "$r"
}

run() { bash "$SCRIPT" "$@" 2>&1; }
# run_in <repo> <args...> — run with cwd inside repo so latest_release_tag sees its tags
run_in() { local r="$1"; shift; ( cd "$r" && bash "$SCRIPT" "$@" 2>&1 ); }

# --- assemble: grouping + order + trailing-blank trim ----------------------

D="$(frag_dir assemble)"
printf -- '- feature note\n' > "$D/10.feature.md"
printf -- '- breaking note\n' > "$D/11.breaking.md"
printf -- '- fix note\n\n\n' > "$D/12.fix.md"
printf -- '- upgrade note\n' > "$D/13.upgrade.md"
OUT="$(run --dir "$D" assemble)"
assert_contains "$OUT" "### Breaking" "assemble: has Breaking heading"
assert_contains "$OUT" "### Added" "assemble: feature -> Added"
assert_contains "$OUT" "### Fixed" "assemble: fix -> Fixed"
assert_contains "$OUT" "### Upgrade" "assemble: has Upgrade heading"

# Section order must be Breaking < Added < Fixed < Upgrade, deterministically.
EXPECTED="$(printf '### Breaking\n\n- breaking note\n\n### Added\n\n- feature note\n\n### Fixed\n\n- fix note\n\n### Upgrade\n\n- upgrade note')"
assert_eq "$EXPECTED" "$OUT" "assemble: exact grouped/ordered/trimmed body"

# Determinism: same set in -> byte-identical out.
OUT2="$(run --dir "$D" assemble)"
assert_eq "$OUT" "$OUT2" "assemble: deterministic across runs"

# --- check -----------------------------------------------------------------

V="$(frag_dir check_valid)"
printf -- '- ok\n' > "$V/1.feature.md"
run --dir "$V" --check >/dev/null 2>&1
assert_exit 0 "$?" "check: valid set -> 0"

B="$(frag_dir check_bad)"
printf -- '- ok\n' > "$B/1.feature.md"
printf -- '- bad\n' > "$B/2.wibble.md"
: > "$B/3.fix.md"
CHK="$(run --dir "$B" --check)"; RC=$?
assert_exit 1 "$RC" "check: bad set -> 1"
assert_contains "$CHK" "INVALID 2.wibble.md" "check: names invalid kind"
assert_contains "$CHK" "EMPTY 3.fix.md" "check: names empty fragment"

E="$(frag_dir empty)"
run --dir "$E" --check >/dev/null 2>&1
assert_exit 2 "$?" "check: no fragments -> 2"
run --dir "$E" assemble >/dev/null 2>&1
assert_exit 2 "$?" "assemble: no fragments -> 2"
run --dir "$E" --bump >/dev/null 2>&1
assert_exit 2 "$?" "bump: no fragments -> 2"

# --- bump: level from highest kind vs latest tag ---------------------------

R="$(tagged_repo bumped v1.2.0 v1.3.0)"

FMAJOR="$(frag_dir major)"
printf -- '- x\n' > "$FMAJOR/1.fix.md"
printf -- '- y\n' > "$FMAJOR/2.breaking.md"
printf -- '- z\n' > "$FMAJOR/3.feature.md"
assert_eq "2.0.0" "$(run_in "$R" --dir "$FMAJOR" --bump)" "bump: any breaking -> major"

FMINOR="$(frag_dir minor)"
printf -- '- x\n' > "$FMINOR/1.fix.md"
printf -- '- y\n' > "$FMINOR/2.feature.md"
assert_eq "1.4.0" "$(run_in "$R" --dir "$FMINOR" --bump)" "bump: feature (no breaking) -> minor"

FPATCH="$(frag_dir patch)"
printf -- '- x\n' > "$FPATCH/1.fix.md"
assert_eq "1.3.1" "$(run_in "$R" --dir "$FPATCH" --bump)" "bump: fix only -> patch"

FUP="$(frag_dir upgrade)"
printf -- '- x\n' > "$FUP/1.upgrade.md"
assert_eq "1.3.1" "$(run_in "$R" --dir "$FUP" --bump)" "bump: upgrade only -> patch"

# No tags yet -> base 0.0.0.
R0="$(tagged_repo untagged)"
F0="$(frag_dir fresh)"
printf -- '- x\n' > "$F0/1.feature.md"
assert_eq "0.1.0" "$(run_in "$R0" --dir "$F0" --bump)" "bump: no tag -> from 0.0.0"

# --- id with dots: kind is the last dot-segment ----------------------------

DOT="$(frag_dir dotted)"
printf -- '- dotted id\n' > "$DOT/my.slug.v2.feature.md"
assert_eq "1.4.0" "$(run_in "$R" --dir "$DOT" --bump)" "kind_of: dotted id resolves kind"

finish
