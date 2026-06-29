#!/usr/bin/env bash
# skill-boundary-check.sh: target-tree + memory-confinement enforcement (#11).
. "$(dirname "$0")/_assert.sh"

SBC="$SCRIPTS_DIR/skill-boundary-check.sh"

git_quiet() { git -C "$1" -c user.email=t@t -c user.name=t -c init.defaultBranch=main "${@:2}"; }

MEM="$(new_sandbox)"; TGT=""
trap 'rm -rf "$MEM" "$TGT"' EXIT

# --- memory repo: skills/<self>/ writable, elsewhere not --------------------
git_quiet "$MEM" init -q
mkdir -p "$MEM/skills/myskill" "$MEM/skills/other" "$MEM/projects/p"
# initial commit so HEAD is a real sha (as the live memory repo always is)
touch "$MEM/skills/myskill/.gitkeep" "$MEM/skills/other/.gitkeep" "$MEM/projects/p/.gitkeep"
git_quiet "$MEM" add -A >/dev/null 2>&1
git_quiet "$MEM" commit -q -m init >/dev/null 2>&1
BASE="$MEM/.base"
bash "$SBC" snapshot --repo "$MEM" > "$BASE"

run_check() { # run_check <tier> <scope> [extra...]; sets out/code
    set +e
    out=$(bash "$SBC" check --skill myskill --tier "$1" \
            --memory "$MEM" --memory-baseline "$BASE" --memory-scope "$2" "${@:3}" 2>&1)
    code=$?
    set -e
}

# own folder only -> clean
printf 'notes\n' > "$MEM/skills/myskill/review-1.md"
run_check target-read-only full
assert_exit 0 "$code" "own-folder write is clean"
assert_contains "$out" "myskill OK" "reports OK"

# write into system memory -> violation under full scope
printf 'x\n' > "$MEM/projects/p/memory.md"
run_check target-read-only full
assert_exit 1 "$code" "system-memory write fails (full scope)"
assert_contains "$out" "wrote outside its own folder in memory repo: projects/p/memory.md" "names the stray path"

# same write is allowed under others-only scope (orchestrator co-edits memory)...
run_check target-read-only others-only
assert_exit 0 "$code" "projects/ write allowed under others-only scope"

# ...but writing into ANOTHER skill's folder is always a violation
printf 'x\n' > "$MEM/skills/other/leak.md"
run_check target-read-only others-only
assert_exit 1 "$code" "other-skill write fails even under others-only"
assert_contains "$out" "wrote into another skill's folder: skills/other/leak.md" "names the other-skill path"

# committed change (HEAD moves) is also detected
rm -f "$MEM/projects/p/memory.md" "$MEM/skills/other/leak.md" "$MEM/skills/myskill/review-1.md"
bash "$SBC" snapshot --repo "$MEM" > "$BASE"
printf 'y\n' > "$MEM/projects/p/committed.md"
git_quiet "$MEM" add -A >/dev/null 2>&1
git_quiet "$MEM" commit -q -m "stray commit" >/dev/null 2>&1
run_check target-read-only full
assert_exit 1 "$code" "committed stray change detected"
assert_contains "$out" "projects/p/committed.md" "names committed path"

# --- target repo: read-only must not touch it ------------------------------
TGT="$(new_sandbox)"
git_quiet "$TGT" init -q
mkdir -p "$TGT/src"
printf 'orig\n' > "$TGT/src/app.txt"
git_quiet "$TGT" add -A >/dev/null 2>&1
git_quiet "$TGT" commit -q -m init >/dev/null 2>&1
TBASE="$TGT/.base"
bash "$SBC" snapshot --repo "$TGT" > "$TBASE"

# clean memory baseline so only the target half is exercised (snapshot current
# state; nothing writes to MEM after this, so the memory half stays clean)
MBASE2="$MEM/.base2"
bash "$SBC" snapshot --repo "$MEM" > "$MBASE2"

# read-only skill modifies the target -> violation
printf 'tampered\n' >> "$TGT/src/app.txt"
set +e
out=$(bash "$SBC" check --skill myskill --tier target-read-only \
        --memory "$MEM" --memory-baseline "$MBASE2" \
        --target "$TGT" --target-baseline "$TBASE" 2>&1); code=$?
set -e
assert_exit 1 "$code" "read-only skill modifying target fails"
assert_contains "$out" "(target-read-only) modified the target repo: src/app.txt" "names target path"

# same target change is fine for a target-write skill (no target check)
set +e
out=$(bash "$SBC" check --skill myskill --tier target-write \
        --memory "$MEM" --memory-baseline "$MBASE2" \
        --target "$TGT" --target-baseline "$TBASE" 2>&1); code=$?
set -e
assert_exit 0 "$code" "target-write skill may modify the target"

# --- usage / arg validation -------------------------------------------------
set +e
bash "$SBC" check --skill x --tier bogus --memory "$MEM" --memory-baseline "$MBASE2" >/dev/null 2>&1; code=$?
set -e
assert_exit 2 "$code" "invalid tier is a usage error"

set +e
bash "$SBC" snapshot >/dev/null 2>&1; code=$?
set -e
assert_exit 2 "$code" "snapshot without --repo is a usage error"

finish
