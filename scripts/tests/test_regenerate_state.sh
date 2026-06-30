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

finish
