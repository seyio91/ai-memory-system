#!/usr/bin/env bash
# check-docs.sh must FAIL on real doc rot and PASS on legitimate indirection.
#
# Red before green. Every defect class below is asserted to produce a non-zero
# exit; a checker nobody has watched fail is not a gate, it is decoration. The
# suite's own history says so: scripts/taskprovider/tests/ sat outside the
# runner's glob and reported green for months without ever executing.
#
# Two cases pin bugs that shipped in check-docs.sh's first draft and were found
# only by probing, never by reading it:
#
#   self-reference  the checker lives in scripts/ and its comments name
#                   MEMORY_SESSIONS_DIR as a worked example, so the forward axis
#                   PASSED for the very var it exists to catch.
#   sed delimiter   s|...(\.|source)...| ends at the alternation's '|'; sed dies,
#                   2>/dev/null ate the error, and source-following silently
#                   found nothing -> four false positives that looked like drift.
#
# The fixture is synthetic: a tiny fake tree, not a copy of the real one, so the
# test cannot rot when real scripts move.
. "$(dirname "$0")/_assert.sh"
set -uo pipefail

CHECK="$SCRIPTS_DIR/check-docs.sh"
FX="$(new_sandbox)"
trap 'rm -rf "$FX"' EXIT

# --- fixture tree ----------------------------------------------------------
mkdir -p "$FX/docs" "$FX/scripts" "$FX/harnesses"

# depth-0: var written directly in the script
printf '#!/usr/bin/env bash\necho "${FX_DIRECT:-}"\n' >"$FX/scripts/direct.sh"

# the shared lib, reached only through helpers
printf '#!/usr/bin/env bash\nfx_helper() { printf "%%s" "${FX_DEEP:-fallback}"; }\n' >"$FX/scripts/_lib.sh"

# depth-1: sources _lib.sh, never names FX_DEEP itself
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/_lib.sh"\nfx_helper\n' >"$FX/scripts/mid.sh"

# depth-2: top -> mid -> _lib. Also exercises the `source "$(dirname "$0")/x"`
# form whose space inside $( ) defeats a naive \s+(\S+) capture.
printf '#!/usr/bin/env bash\nsource "$(dirname "$0")/mid.sh"\n' >"$FX/scripts/top.sh"

# cycle: a <-> b. The visited-set guard must terminate.
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/cyc_b.sh"\n' >"$FX/scripts/cyc_a.sh"
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/cyc_a.sh"\necho "${FX_CYCLE:-}"\n' >"$FX/scripts/cyc_b.sh"

# The real checker, dropped into the fixture's scripts/ so its own comments are
# inside the code roots. This is what makes the self-reference case meaningful.
cp "$CHECK" "$FX/scripts/check-docs.sh"

printf 'FX_EXEMPT  # prose cell, deliberately unowned\n' >"$FX/.docscheck-exempt"
printf '#!/usr/bin/env bash\necho "${FX_EXEMPT:-}"\n' >"$FX/scripts/exempt_user.sh"

# tests/ is a legitimate consumer location; tests/fixtures/ is sample data.
# only_fx.sh exists ONLY under fixtures, so the two policies give opposite
# verdicts and neither depends on find(1)'s enumeration order.
mkdir -p "$FX/scripts/tests/fixtures/legacy"
printf '#!/usr/bin/env bash\necho "${FX_TEST_SEAM:-}"\n' >"$FX/scripts/tests/test_seam.sh"
printf '#!/usr/bin/env bash\necho "${FX_FIXTURE_ONLY:-}"\n' >"$FX/scripts/tests/fixtures/legacy/only_fx.sh"

TABLE="$FX/docs/scripts.md"
HDR='| Var | Default | Used by |
|-----|---------|---------|'

table() { printf '%s\n' "$HDR" >"$TABLE"; for r in "$@"; do printf '%s\n' "$r" >>"$TABLE"; done; }

OUT=""
RC=0
run() { OUT="$(bash "$CHECK" "$FX" 2>&1)"; RC=$?; }

# --- sanity: the checker is present and executable -------------------------
assert_file "$CHECK" "check-docs.sh exists"

# --- PASS cases ------------------------------------------------------------
table '| `FX_DIRECT` | x | `direct.sh` |'
run
assert_exit 0 "$RC" "direct match passes"

table '| `FX_DEEP` | x | `mid.sh` |'
run
assert_exit 0 "$RC" "indirection through a sourced _lib.sh passes (depth 1)"

table '| `FX_DEEP` | x | `top.sh` |'
run
assert_exit 0 "$RC" "transitive source-following passes (depth 2)"
assert_contains "$OUT" "0 findings" "depth-2 reports zero findings"

# Deleting closure()'s visited-set guard makes this exit 2 ("cycle guard broken").
# It did NOT, until check-docs.sh grew CLOSURE_MAX: the runaway recursion nests
# inside `| while` subshells, fork() eventually fails, the dead subshells vanish,
# and `seen` already holds the right files -- so the wrong program returned the
# right answer and this assertion passed vacuously. Verified by mutation.
table '| `FX_CYCLE` | x | `cyc_a.sh` |'
run
assert_exit 0 "$RC" "source cycle terminates and resolves"

table '| `FX_EXEMPT` | x | All scripts |'
run
assert_exit 0 "$RC" "prose cell listed in .docscheck-exempt passes"

# --- FAIL cases: each defect class must produce a non-zero exit -------------
table '| `FX_GHOST` | x | `direct.sh` |'
run
assert_exit 1 "$RC" "documented-nonexistent var fails"
assert_contains "$OUT" "absent from all code roots" "…with the forward-axis message"

table '| `FX_DIRECT` | x | `mid.sh` |'
run
assert_exit 1 "$RC" "wrong consumer fails"
assert_contains "$OUT" "not found in mid.sh" "…naming the script it is missing from"

table '| `FX_DIRECT` | x | All scripts |'
run
assert_exit 1 "$RC" "unexempted prose cell fails"
assert_contains "$OUT" ".docscheck-exempt" "…pointing at the exempt file"

table '| `FX_DIRECT` | x | `ghost.sh` |'
run
assert_exit 1 "$RC" "\`Used by\` naming a nonexistent script fails"
assert_contains "$OUT" "does not exist" "…saying the script does not exist"

# --- REGRESSION: the checker must not satisfy the forward axis from its own
# comments. check-docs.sh mentions MEMORY_SESSIONS_DIR as a worked example, and
# it is the ONLY file in the fixture containing that string. Without
# --exclude=check-docs.sh this row passes, and a deleted var stays documented
# forever, certified green by the control written to catch it.
table '| `MEMORY_SESSIONS_DIR` | x | `direct.sh` |'
run
assert_exit 1 "$RC" "a var named only inside check-docs.sh does NOT satisfy the forward axis"
assert_contains "$OUT" "absent from all code roots" "…self-reference cannot certify a ghost var"

# --- REGRESSION: source-following must actually run. If the sed that extracts
# `source` lines breaks (delimiter collision) and its stderr is swallowed, every
# indirected row reports "not found ... nor anything it sources". FX_DEEP lives
# only in _lib.sh, so this row passing IS the proof the closure executed.
table '| `FX_DEEP` | x | `top.sh` |'
run
assert_not_contains "$OUT" "nor anything it sources" "source-following runs (sed regex is not silently broken)"

# --- REGRESSION: tests/fixtures/ is not a consumer -------------------------
# resolve_script() matches by basename and takes `head -1`, so a fixture sharing
# a basename with a real script can win. In the real tree scripts/hooks/
# session_start_memory.sh collides with a claude-legacy-hooks fixture, and find
# returned the fixture -- which would have failed the AI_MEMORY_SKIP_INJECT row
# against sample data. The fail-open mirror is worse: a fixture that happens to
# contain the var certifies a consumer that no longer uses it.
#
# only_fx.sh exists ONLY under tests/fixtures/, so this is order-independent:
# pruned -> resolves to nothing -> "does not exist". Drop the -path prune from
# resolve_script and the fixture resolves, contains FX_FIXTURE_ONLY, and the row
# passes -- mutation-verified in both directions.
table '| `FX_FIXTURE_ONLY` | x | `only_fx.sh` |'
run
assert_exit 1 "$RC" "a script that exists only under tests/fixtures/ is not a consumer"
assert_contains "$OUT" "does not exist" "…fixtures resolve to nothing, not to sample data"

# The complement: tests/ itself MUST stay resolvable. The real table names
# test_upgrading_doc.sh as a consumer, so pruning all of tests/ would break it.
table '| `FX_TEST_SEAM` | x | `test_seam.sh` |'
run
assert_exit 0 "$RC" "tests/ (not fixtures/) is still a legitimate consumer location"

# --- setup errors ----------------------------------------------------------
printf 'no table here\n' >"$TABLE"
run
assert_exit 2 "$RC" "a table with zero parseable rows is a setup error, not a pass"
assert_contains "$OUT" "table format changed" "…and says the format changed"

rm -f "$TABLE"
run
assert_exit 2 "$RC" "a missing table is a setup error"

# --- the real tree must be clean (pins Phase 1's clean-to-floor) -----------
REAL_OUT="$(bash "$CHECK" 2>&1)"
REAL_RC=$?
assert_exit 0 "$REAL_RC" "the repo's own docs/scripts.md table passes"
assert_contains "$REAL_OUT" "0 findings" "…with zero findings"

finish
