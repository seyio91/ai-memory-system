#!/usr/bin/env bash
# regenerate-activity.sh — per-category "plans created in a window" report (Phase 3).
# Windows are relative to today, so dates are computed with the same date math the
# script uses (macOS `date -v`, GNU fallback) to stay deterministic.
. "$(dirname "$0")/_assert.sh"

GEN="$SCRIPTS_DIR/regenerate-activity.sh"

# date N days ago -> YYYY-MM-DD
dago() { date -v-"$1"d +%F 2>/dev/null || date -d "$1 days ago" +%F; }
D0="$(date +%F)"; D5="$(dago 5)"; D30="$(dago 30)"; D31="$(dago 31)"; D200="$(dago 200)"

CM="$(new_sandbox)"; trap 'rm -rf "$CM"' EXIT
export MEMORY_DIR="$CM"
mkdir -p "$CM/projects"

# categorized / uncategorized project memory
mkproj()  { mkdir -p "$CM/projects/$1"; printf -- '---\ntopic: %s\nscope: project\nsummary: s\ncategory: %s\n---\n' "$1" "$2" > "$CM/projects/$1/memory.md"; }
mkproju() { mkdir -p "$CM/projects/$1"; printf -- '---\ntopic: %s\nscope: project\nsummary: s\n---\n' "$1" > "$CM/projects/$1/memory.md"; }
# a plan file: mkplan <project> <plans|archive/plans> <slug> <created> <status>
mkplan() {
    mkdir -p "$CM/projects/$1/$2"
    printf -- '---\nplan: %s\nstatus: %s\ncreated: %s\nowner: x\n---\n# %s\n' "$3" "$5" "$4" "$3" > "$CM/projects/$1/$2/$3.md"
}

mkproj  acme-web acme-corp
mkplan  acme-web plans          recent-web      "$D0"  active   # today -> in window
mkplan  acme-web plans          boundary-web    "$D30" active   # exactly cutoff -> inclusive
mkplan  acme-web plans          justout-web     "$D31" active   # one day before -> excluded
mkplan  acme-web plans          old-web         "$D200" done    # far past -> excluded at 30d
mkplan  acme-web archive/plans  archived-web    "$D5"  done      # archived but in window -> counted

mkproj  beta-svc beta-inc
mkplan  beta-svc plans          beta-one        "$D5"  active

mkproju loose
mkplan  loose    plans          loose-one       "$D5"  active

# gamma has ONLY an out-of-window plan -> empty report for its category
mkproj  gamma-svc gamma-inc
mkplan  gamma-svc plans         gamma-old       "$D200" done

run() { set +e; out="$(bash "$@" 2>&1)"; code=$?; set -e; }

# === arg validation =========================================================
run "$GEN";                         assert_exit 2 "$code" "no scope -> exit 2"
run "$GEN" acme-corp --all;         assert_exit 2 "$code" "category AND --all -> exit 2"
run "$GEN" --all --since abc;       assert_exit 2 "$code" "non-numeric --since -> exit 2"

# === single category, default 30d window ====================================
run "$GEN" acme-corp --stdout
assert_exit 0 "$code" "category report runs"
assert_contains "$out" "# Activity — acme-corp" "title names the category"
assert_contains "$out" "| Project | Plan | Created | Status |" "table header present"
assert_contains "$out" "recent-web"   "today's plan is in window"
assert_contains "$out" "boundary-web" "plan created exactly at cutoff is included (inclusive)"
assert_contains "$out" "archived-web" "archived plan in window is counted (archive/plans scanned)"
assert_contains "$out" "active"       "status column rendered"
assert_not_contains "$out" "justout-web" "plan one day before cutoff is excluded"
assert_not_contains "$out" "old-web"     "far-past plan excluded at 30d"
assert_not_contains "$out" "beta-one"    "other category excluded under a category filter"
assert_not_contains "$out" "loose-one"   "uncategorized excluded under a category filter"

# === widening the window pulls in the old plan ==============================
run "$GEN" acme-corp --since 365d --stdout
assert_exit 0 "$code" "wide window runs"
assert_contains "$out" "old-web" "far-past plan included with --since 365d"

# === --all groups every category, uncategorized last ========================
run "$GEN" --all --stdout
assert_exit 0 "$code" "--all runs"
assert_contains "$out" "## acme-corp"      "acme-corp section present"
assert_contains "$out" "## beta-inc"       "beta-inc section present"
assert_contains "$out" "(uncategorized)"   "uncategorized section present"
assert_contains "$out" "loose-one"         "uncategorized plan listed"
# uncategorized section sorts last
acl="$(printf '%s\n' "$out" | grep -n '## acme-corp' | head -1 | cut -d: -f1)"
ucl="$(printf '%s\n' "$out" | grep -n '(uncategorized)' | head -1 | cut -d: -f1)"
{ [ "$acl" -lt "$ucl" ]; } && _ok "uncategorized section is last" || _bad "uncategorized section is last"

# === empty window for a category -> friendly message ========================
run "$GEN" gamma-inc --stdout
assert_exit 0 "$code" "empty-window category runs"
assert_contains "$out" "No plans created in this window" "empty window reports no plans"
assert_not_contains "$out" "gamma-old" "out-of-window plan not listed"

# === --since accepts bare number and Nd form; order-independent =============
run "$GEN" --stdout --since 30 acme-corp
assert_exit 0 "$code" "bare --since number + flag order works"
assert_contains "$out" "recent-web" "bare --since 30 still windows correctly"

# === file mode writes the gitignored artifact ===============================
run "$GEN" --all
assert_exit 0 "$code" "file-mode run succeeds"
assert_file "$CM/activity.md" "writes activity.md"
assert_contains "$out" "wrote" "reports the write"

finish
