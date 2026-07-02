#!/usr/bin/env bash
# regenerate-state.sh — derived "In Flight" snapshot (#8).
. "$(dirname "$0")/_assert.sh"

GEN="$SCRIPTS_DIR/regenerate-state.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
mkdir -p "$MEM/projects"

mkproj() { mkdir -p "$MEM/projects/$1"; }
setgoal() { printf '## Current Goal\n%s\n' "$2" > "$MEM/projects/$1/memory.md"; }
nogoal()  { printf '# Project %s\n\nNo goal section here.\n' "$1" > "$MEM/projects/$1/memory.md"; }

# alpha: has a goal + 2 open / 1 done todos. memory.md is OLD but working.md is NEW
# -> last-touched must follow the newest file (working.md), proving mtime-of-newest.
mkproj alpha
setgoal alpha "Ship the alpha pipeline"
printf -- '- [ ] one\n- [x] done\n- [ ] two\n' > "$MEM/projects/alpha/todo.md"
printf 'scratch\n' > "$MEM/projects/alpha/working.md"

# beta: no goal section, no todo.md -> goal '—', open 0.
mkproj beta
nogoal beta

# gamma: goal with a table-breaking pipe early + a long tail (> 70 chars) -> escaped + truncated.
mkproj gamma
setgoal gamma "a | b and then a deliberately long goal tail that runs well past seventy characters in total length"

# delta: a "- [ ]" inside a fenced code block must NOT be counted (only the real one).
mkproj delta
setgoal delta "Delta with a code-fenced checkbox"
printf -- '- [ ] real open\n```\n- [ ] fake in a code fence\n```\n- [x] done\n' > "$MEM/projects/delta/todo.md"

# _template must be excluded.
mkproj _template
setgoal _template "should never appear"

# Controlled mtimes (macOS touch -t CCYYMMDDhhmm): alpha newest, gamma mid, beta oldest.
touch -t 202601010900 "$MEM/projects/alpha/memory.md" "$MEM/projects/alpha/todo.md"
touch -t 202606300900 "$MEM/projects/alpha/working.md"   # newest signal for alpha (2026-06-30)
touch -t 202606150900 "$MEM/projects/gamma/memory.md"
touch -t 202606010900 "$MEM/projects/beta/memory.md"

run() { set +e; out="$(bash "$@" 2>&1)"; code=$?; set -e; }
row_line() { printf '%s\n' "$out" | grep -n "| $1 " | head -1 | cut -d: -f1; }

# === generate (stdout) ======================================================
run "$GEN" --stdout
assert_exit 0 "$code" "generator runs"
assert_contains "$out" "In Flight" "has the header"
assert_contains "$out" "| Project | Last touched | Current goal | Open todos |" "has the table header"

# alpha row: goal + open count 2
assert_contains "$out" "Ship the alpha pipeline" "alpha goal present"
alpha_row="$(printf '%s\n' "$out" | grep '| alpha ')"
assert_contains "$alpha_row" "| 2 |" "alpha open-todo count = 2 (done box excluded)"
assert_contains "$alpha_row" "2026-06-30" "alpha last-touched follows newest file (working.md), not memory.md"

# beta row: missing goal -> em dash, open 0
beta_row="$(printf '%s\n' "$out" | grep '| beta ')"
assert_contains "$beta_row" "| — |" "beta goal renders as em dash"
assert_contains "$beta_row" "| 0 |" "beta open-todo count = 0 (no todo.md)"

# gamma: pipe escaped, long goal truncated
gamma_row="$(printf '%s\n' "$out" | grep '| gamma ')"
assert_contains "$gamma_row" 'a \| b' "table-breaking pipe is escaped"
assert_contains "$gamma_row" "…" "long goal is truncated with an ellipsis"

# fenced-code checkbox not counted
delta_row="$(printf '%s\n' "$out" | grep '| delta ')"
assert_contains "$delta_row" "| 1 |" "code-fenced '- [ ]' excluded from open-todo count"

# _template excluded
assert_not_contains "$out" "should never appear" "_template excluded from the view"
assert_not_contains "$out" "| _template " "_template row absent"

# sort: newest (alpha) above mid (gamma) above oldest (beta)
a="$(row_line alpha)"; g="$(row_line gamma)"; b="$(row_line beta)"
[ "$a" -lt "$g" ] && [ "$g" -lt "$b" ] && _ok "rows sorted by last-touched desc" \
    || { _bad "rows sorted by last-touched desc"; printf '       alpha=%s gamma=%s beta=%s\n' "$a" "$g" "$b"; }

# === idempotency ============================================================
run "$GEN" --stdout; first="$out"
run "$GEN" --stdout; second="$out"
assert_eq "$first" "$second" "re-run is byte-identical (no drift from unchanged sources)"

# === file mode ==============================================================
run "$GEN"
assert_exit 0 "$code" "file-mode run succeeds"
assert_file "$MEM/state.md" "writes state.md"
assert_contains "$out" "wrote" "reports the write"
assert_contains "$(cat "$MEM/state.md")" "NOT auto-injected" "file carries the on-demand / not-injected notice"

# empty projects dir -> still emits a valid (header-only) table, exit 0
EMPTY="$(new_sandbox)"; mkdir -p "$EMPTY/projects"
MEMORY_DIR="$EMPTY" run "$GEN" --stdout
assert_exit 0 "$code" "tolerates a projects dir with no projects"
assert_contains "$out" "| Project | Last touched |" "still emits the table header when empty"
rm -rf "$EMPTY"

# === category column, grouping, and filter (Phase 2) ========================
CM="$(new_sandbox)"; mkdir -p "$CM/projects"
# categorized project: frontmatter category + goal
mkc() {
    mkdir -p "$CM/projects/$1"
    printf -- '---\ntopic: %s\nscope: project\nsummary: s\ncategory: %s\n---\n## Current Goal\n%s\n' \
        "$1" "$2" "$3" > "$CM/projects/$1/memory.md"
}
# uncategorized project: frontmatter without category
mku() {
    mkdir -p "$CM/projects/$1"
    printf -- '---\ntopic: %s\nscope: project\nsummary: s\n---\n## Current Goal\n%s\n' \
        "$1" "$2" > "$CM/projects/$1/memory.md"
}
mkc acme-web acme-corp "Acme web goal"
mkc acme-api acme-corp "Acme api goal"
mkc beta-svc beta-inc  "Beta service goal"
mku loose              "Loose uncategorized goal"
# mtimes: 'loose' is the NEWEST overall, but must still sort LAST (uncategorized).
# within acme-corp, acme-web is newer than acme-api.
touch -t 202606100900 "$CM/projects/acme-api/memory.md"
touch -t 202606200900 "$CM/projects/acme-web/memory.md"
touch -t 202606050900 "$CM/projects/beta-svc/memory.md"
touch -t 202606250900 "$CM/projects/loose/memory.md"

# --- unfiltered: grouped by category, uncategorized last ---
MEMORY_DIR="$CM" run "$GEN" --stdout
assert_exit 0 "$code" "category view runs"
assert_contains "$out" "| Category | Project | Last touched | Current goal | Open todos |" "5-col header includes Category"
assert_contains "$out" "| acme-corp | acme-web " "category value shown in the row"
assert_contains "$out" "| — | loose " "uncategorized project shows em dash in category column"
aw="$(printf '%s\n' "$out" | grep -n '| acme-web ' | head -1 | cut -d: -f1)"
aa="$(printf '%s\n' "$out" | grep -n '| acme-api ' | head -1 | cut -d: -f1)"
bs="$(printf '%s\n' "$out" | grep -n '| beta-svc ' | head -1 | cut -d: -f1)"
lo="$(printf '%s\n' "$out" | grep -n '| loose ' | head -1 | cut -d: -f1)"
[ "$aw" -lt "$aa" ] && _ok "within a category, newer project sorts first" \
    || { _bad "within a category, newer project sorts first"; printf '       acme-web=%s acme-api=%s\n' "$aw" "$aa"; }
{ [ "$aa" -lt "$bs" ] && [ "$bs" -lt "$lo" ]; } && _ok "categories grouped (acme<beta), uncategorized last despite newest mtime" \
    || { _bad "categories grouped, uncategorized last"; printf '       acme-api=%s beta=%s loose=%s\n' "$aa" "$bs" "$lo"; }

# --- filtered: /state <category> ---
MEMORY_DIR="$CM" run "$GEN" acme-corp --stdout
assert_exit 0 "$code" "filtered view runs"
assert_contains "$out" "In Flight — acme-corp" "filtered title names the category"
assert_contains "$out" "| acme-web " "filter includes a matching project"
assert_contains "$out" "| acme-api " "filter includes the other matching project"
assert_not_contains "$out" "| beta-svc " "filter excludes other categories"
assert_not_contains "$out" "| loose " "filter excludes uncategorized projects"

# --- filter + --stdout order independence ---
MEMORY_DIR="$CM" run "$GEN" --stdout beta-inc
assert_exit 0 "$code" "filter works with flags in either order"
assert_contains "$out" "| beta-svc " "beta-inc filter includes beta-svc"
assert_not_contains "$out" "| acme-web " "beta-inc filter excludes acme projects"
rm -rf "$CM"

finish
