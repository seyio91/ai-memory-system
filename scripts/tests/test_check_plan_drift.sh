#!/usr/bin/env bash
# check-plan-drift.sh — Files-touched union vs a git diff range, hermetic: every
# repo, worktree and plan lives in a mktemp sandbox.
. "$(dirname "$0")/_assert.sh"

DRIFT="$SCRIPTS_DIR/check-plan-drift.sh"
SB="$(new_sandbox)"
trap 'rm -rf "$SB"' EXIT

GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

g() { git -C "$REPO" "$@" >/dev/null 2>&1; }
run() { OUT="$(bash "$DRIFT" "$@" 2>&1)"; RC=$?; }

mkplan() {
    # mkplan <file> <created> — two phases; P1 owns scripts/ + a new file, P2 docs/*.md
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<PLAN
---
topic: demo
status: in_progress
created: $2
---

# Plan: demo

## Phases

### Phase 1 — Code
**Files touched:** \`scripts/*\`, \`lib/new.sh\` (new)
**Risk:** low
**Depends:** none

### Phase 2 — Docs
**Files touched:** \`docs/*.md\`
**Risk:** low
**Depends:** Phase 1

### Checkpoint
**Files touched:** \`never/*\`
PLAN
}

# --- target repo (not the memory root) ---------------------------------------
REPO="$SB/repo"
mkdir -p "$REPO/scripts" "$REPO/scripts-old" "$REPO/docs" "$REPO/lib"
git init -q -b main "$REPO"
echo a > "$REPO/scripts/a.sh"; echo a > "$REPO/scripts-old/a.sh"; echo a > "$REPO/docs/a.md"
g add -A; g commit -q -m base
BASE="$(git -C "$REPO" rev-parse HEAD)"

PLAN="$SB/mem/projects/demo/plans/demo.md"
mkplan "$PLAN" 2026-11-08

export MEMORY_DIR="$SB/mem"
mkdir -p "$MEMORY_DIR"

echo b >> "$REPO/scripts/a.sh"; echo n > "$REPO/lib/new.sh"
g add -A; g commit -q -m clean
run "$PLAN" --repo "$REPO" --range "$BASE...HEAD"
assert_exit 0 "$RC" "in-set changes (glob + (new) path) exit 0"
assert_eq "" "$OUT" "…and print nothing"

echo x > "$REPO/stray.txt"; g add -A; g commit -q -m stray
run "$PLAN" --repo "$REPO" --range "$BASE...HEAD"
assert_exit 1 "$RC" "out-of-set file exits 1"
assert_contains "$OUT" "drift: stray.txt" "…and names the file"
assert_not_contains "$OUT" "scripts/a.sh" "…without naming in-set files"

echo y >> "$REPO/scripts-old/a.sh"; g add -A; g commit -q -m trap
run "$PLAN" --repo "$REPO" --range "$BASE...HEAD"
assert_exit 1 "$RC" "prefix trap: scripts-old/ is not matched by scripts/*"
assert_contains "$OUT" "drift: scripts-old/a.sh" "…and is named"

run "$PLAN" --repo "$REPO" --range "$BASE...HEAD" --phase 1
assert_contains "$OUT" "drift: stray.txt" "--phase 1 still flags out-of-set files"
echo z >> "$REPO/docs/a.md"; g add -A; g commit -q -m docs
R2="$(git -C "$REPO" rev-parse HEAD)"
run "$PLAN" --repo "$REPO" --range "$R2~1...$R2" --phase 1
assert_exit 1 "$RC" "--phase 1: a docs/*.md change is outside phase 1"
assert_contains "$OUT" "drift: docs/a.md" "…and named"
run "$PLAN" --repo "$REPO" --range "$R2~1...$R2" --phase 2
assert_exit 0 "$RC" "--phase 2: the same change is inside phase 2"
run "$PLAN" --repo "$REPO" --range "$R2~1...$R2"
assert_exit 0 "$RC" "no --phase: union of all phases"
run "$PLAN" --repo "$REPO" --range "$R2~1...$R2" --phase 9
assert_exit 2 "$RC" "--phase naming no phase exits 2 (empty set)"

mkdir -p "$REPO/never"; echo c > "$REPO/never/x"; g add -A; g commit -q -m cp
run "$PLAN" --repo "$REPO" --range "HEAD~1...HEAD"
assert_exit 1 "$RC" "a file listed only under a non-phase ### section is not in the set"
assert_contains "$OUT" "drift: never/x" "…and is named"

# --- path patterns, fences, headings, archive, NUL names -------------------
mkdir -p "$REPO/scripts/drivers" "$REPO/dir/sub" "$REPO/deep/sub"
echo d > "$REPO/scripts/drivers/x.sh"; echo d > "$REPO/dir/sub/f"; echo d > "$REPO/fenced.txt"
echo d > "$REPO/sub.txt"; echo d > "$REPO/deep/sub/z"
g add -A; g commit -q -m pat
PAT="$SB/mem/projects/demo/plans/pat.md"
cat > "$PAT" <<'PLAN'
---
created: 2026-11-08
---

### Phase 1 — Pat
**Files touched:** `scripts/*`, `dir/`, `deep/sub/z`

```
**Files touched:** `fenced.txt`
```

~~~
**Files touched:** `fenced.txt`
~~~

````
```
**Files touched:** `fenced.txt`
~~~
````

  ```
**Files touched:** `*`
  ```

#### Sub-heading
**Files touched:** `sub.txt`

### Checkpoint
PLAN
run "$PAT" --repo "$REPO" --range "HEAD~1...HEAD"
assert_exit 1 "$RC" "pattern fixture: fenced.txt is the only drift"
assert_eq "drift: fenced.txt" "$OUT" "Files touched inside backtick and tilde fences is ignored; the rest match"
assert_not_contains "$OUT" "scripts/drivers/x.sh" "* matches across / (scripts/* covers scripts/drivers/x.sh)"
assert_not_contains "$OUT" "dir/sub/f" "a path ending in / means the whole directory"
assert_not_contains "$OUT" "sub.txt" "a #### sub-heading stays inside the phase"

ODD1="$(printf 'we\tird"na\\me')"
ODD2="$(printf 'new\nline')"
echo q > "$REPO/$ODD1"; echo q > "$REPO/$ODD2"
g add -A; g commit -q -m odd
ODDP="$SB/mem/projects/demo/plans/odd.md"
printf -- '---\ncreated: 2026-11-08\n---\n\n### Phase 1 — O\n**Files touched:** `we*`, `new*`\n' > "$ODDP"
run "$ODDP" --repo "$REPO" --range "HEAD~1...HEAD"
assert_exit 0 "$RC" "names with tab/quote/backslash/newline are matched whole (NUL-separated)"

# --- delete counts (rename detection off) ---------------------------------
git -C "$REPO" rm -q scripts/a.sh; g commit -q -m del
run "$PLAN" --repo "$REPO" --range "HEAD~1...HEAD"
assert_exit 0 "$RC" "deleting an in-set file is clean"

# --- exit 3 pre-cutover ---------------------------------------------------
OLD="$SB/mem/projects/demo/plans/old.md"
mkplan "$OLD" 2026-11-07
run "$OLD" --repo "$REPO" --range "$BASE...HEAD"
assert_exit 3 "$RC" "plan created before the cutover exits 3"

# --- exit 2 family --------------------------------------------------------
NOFT="$SB/mem/projects/demo/plans/noft.md"
printf -- '---\ncreated: 2026-11-08\n---\n\n### Phase 1 — X\n**Risk:** low\n' > "$NOFT"
run "$NOFT" --repo "$REPO" --range "$BASE...HEAD"
assert_exit 2 "$RC" "post-cutover plan with no Files touched exits 2"
NOCR="$SB/mem/projects/demo/plans/nocr.md"
printf -- '---\ntopic: x\n---\n\n### Phase 1 — X\n**Files touched:** `a`\n' > "$NOCR"
run "$NOCR" --repo "$REPO" --range "$BASE...HEAD"
assert_exit 2 "$RC" "plan with no created: exits 2 (fail-closed)"
run "$PLAN" --range "$BASE...HEAD"
assert_exit 2 "$RC" "missing --repo exits 2"
run "$PLAN" --repo "$REPO"
assert_exit 2 "$RC" "missing --range exits 2"
run
assert_exit 2 "$RC" "no arguments exits 2"
run "$PLAN" --repo "$REPO" --range "$BASE...HEAD" --bogus
assert_exit 2 "$RC" "unknown flag exits 2"
run "$PLAN" --repo "$REPO" --range "$BASE...HEAD" --phase x
assert_exit 2 "$RC" "non-numeric --phase exits 2"
run "$SB/nope.md" --repo "$REPO" --range "$BASE...HEAD"
assert_exit 2 "$RC" "unreadable plan exits 2"
run "$PLAN" --repo "$REPO" --range "deadbeef...HEAD"
assert_exit 2 "$RC" "unknown ref exits 2"
mkdir -p "$SB/plain"
run "$PLAN" --repo "$SB/plain" --range "$BASE...HEAD"
assert_exit 2 "$RC" "non-git --repo exits 2"
run "$PLAN" --repo "$SB/missing" --range "$BASE...HEAD"
assert_exit 2 "$RC" "nonexistent --repo exits 2"

# --- memory root: projects/<plan-project>/** ignored ----------------------
MR="$SB/mem"
git init -q -b main "$MR"
REPO="$MR"
mkdir -p "$MR/scripts" "$MR/projects/other"
echo a > "$MR/scripts/a.sh"; echo a > "$MR/README"
g add -A; g commit -q -m base
MBASE="$(git -C "$MR" rev-parse HEAD)"
git -C "$MR" checkout -q -b feat
echo b >> "$MR/scripts/a.sh"
echo t > "$MR/projects/demo/todo.md"; echo p >> "$PLAN"
g add -A; g commit -q -m work
run "$PLAN" --repo "$MR" --range "$MBASE...HEAD"
assert_exit 0 "$RC" "memory root: the plan's own projects/demo/** is ignored"
echo o > "$MR/projects/other/x.md"; g add -A; g commit -q -m other
run "$PLAN" --repo "$MR" --range "$MBASE...HEAD"
assert_exit 1 "$RC" "memory root: another project's files are still drift"
assert_contains "$OUT" "drift: projects/other/x.md" "…and named"
assert_not_contains "$OUT" "projects/demo" "…without the plan's own project"

# --- linked worktree of the memory root -----------------------------------
git -C "$MR" checkout -q main
WT="$SB/wt"
git -C "$MR" worktree add -q -b wt-branch "$WT" "$MBASE" >/dev/null 2>&1
echo b >> "$WT/scripts/a.sh"
mkdir -p "$WT/projects/demo"; echo t > "$WT/projects/demo/note.md"
git -C "$WT" add -A; git -C "$WT" commit -q -m wt
run "$PLAN" --repo "$WT" --range "$MBASE...HEAD"
assert_exit 0 "$RC" "linked worktree of the memory root: projects/demo/** ignored"
echo s > "$WT/stray.txt"; git -C "$WT" add -A; git -C "$WT" commit -q -m wtstray
run "$PLAN" --repo "$WT" --range "$MBASE...HEAD"
assert_exit 1 "$RC" "worktree with an out-of-plan change, primary on main, exits 1"
assert_contains "$OUT" "drift: stray.txt" "…and names it"
run "$PLAN" --repo "$MR" --range "$MBASE...HEAD"
assert_exit 0 "$RC" "the primary checkout on main (empty diff) is clean — only --repo's HEAD is read"

# --- archived plan resolves to its project -------------------------------
ARC="$SB/mem/projects/demo/archive/plans/arc.md"
mkdir -p "$(dirname "$ARC")"; cp "$PLAN" "$ARC"
run "$ARC" --repo "$MR" --range "$MBASE...feat~1"
assert_exit 0 "$RC" "plan under archive/plans/ excludes projects/<its project>/**, not projects/archive/**"

# --- scratch clone of a memory tree (no shared object store) ---------------
mkdir -p "$MR/doctrine"; echo o > "$MR/doctrine/orchestrator.md"
git -C "$MR" checkout -q feat
g add -A; g commit -q -m marker
SC="$SB/scratch"
git clone -q --no-hardlinks "$MR" "$SC" >/dev/null 2>&1
git -C "$SC" config user.name t; git -C "$SC" config user.email t@t
SBASE="$(git -C "$SC" rev-parse HEAD)"
mkdir -p "$SC/projects/demo"; echo t > "$SC/projects/demo/note.md"
git -C "$SC" add -A; git -C "$SC" commit -q -m scratch
run "$PLAN" --repo "$SC" --range "$SBASE...HEAD"
assert_exit 0 "$RC" "a separate clone of a memory tree (doctrine/orchestrator.md) still excludes projects/<plan-project>/**"

# --- an unrelated repo is not subject to the exclusion --------------------
UR="$SB/unrelated"
git init -q -b main "$UR"; echo a > "$UR/f"; git -C "$UR" add -A; git -C "$UR" commit -q -m b
UB="$(git -C "$UR" rev-parse HEAD)"
mkdir -p "$UR/projects/demo"; echo t > "$UR/projects/demo/x"; git -C "$UR" add -A; git -C "$UR" commit -q -m p
run "$PLAN" --repo "$UR" --range "$UB...HEAD"
assert_exit 1 "$RC" "a repo outside the memory root's object store gets no exclusion"

finish
