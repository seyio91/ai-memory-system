#!/usr/bin/env bash
# check-changelog-drift.sh — path-scoped dated-entry detection.
#
# Project `memory.md` and domain `*.md` hold the same two patterns (EVENT_RE,
# DATED_RE) with one deliberate divergence: `/promote-memory` writes
# `**[YYYY-MM-DD]**` entries into a domain file's `## Knowledge` section by
# design, so a bracketed or bulleted date must NOT flag there, while the same
# shapes in a project `## Decisions Log` are drift (that route never carried a
# date prefix in the first place, and the plan is shrinking it further). The
# pre-existing unbracketed `**YYYY-MM-DD` form stays flagged in BOTH tiers —
# this suite pins that it is not accidentally narrowed in the split.
. "$(dirname "$0")/_assert.sh"

CHECK="$SCRIPTS_DIR/check-changelog-drift.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
mkdir -p "$MEM/projects/alpha" "$MEM/domain"

PMEM="$MEM/projects/alpha/memory.md"
DMEM="$MEM/domain/terraform.md"

run() { set +e; OUT="$(bash "$CHECK" "$@" 2>&1)"; RC=$?; set -e; }

# --- project memory.md: all four dated shapes are flagged -------------------
cat > "$PMEM" <<'EOF'
## Decisions Log

**2026-08-13** plain dated line
**[2026-08-13]** bracketed dated line
- **2026-08-13** bulleted plain dated line
- **[2026-08-13]** bulleted bracketed dated line
EOF
run "$PMEM"
assert_exit 1 "$RC" "project memory.md with dated entries exits 1"
assert_contains "$OUT" "$PMEM:3:" "…flags plain **YYYY-MM-DD (project)"
assert_contains "$OUT" "$PMEM:4:" "…flags bracketed **[YYYY-MM-DD]** (project)"
assert_contains "$OUT" "$PMEM:5:" "…flags bulleted plain - **YYYY-MM-DD (project)"
assert_contains "$OUT" "$PMEM:6:" "…flags bulleted bracketed - **[YYYY-MM-DD]** (project)"

# --- domain file: only the pre-existing unbracketed form is flagged ---------
cat > "$DMEM" <<'EOF'
## Knowledge

**2026-08-13** plain dated line (legacy shape, stays flagged)
**[2026-08-13]** bracketed dated line — this is what /promote-memory writes
- **2026-08-13** bulleted plain dated line
- **[2026-08-13]** bulleted bracketed dated line
EOF
run "$DMEM"
assert_exit 1 "$RC" "domain file with a legacy unbracketed date still exits 1"
assert_contains "$OUT" "$DMEM:3:" "…flags plain **YYYY-MM-DD (domain, unchanged behavior)"
assert_not_contains "$OUT" "$DMEM:4:" "…does NOT flag bracketed **[YYYY-MM-DD]** (domain, promote-memory's shape)"
assert_not_contains "$OUT" "$DMEM:5:" "…does NOT flag bulleted plain (domain)"
assert_not_contains "$OUT" "$DMEM:6:" "…does NOT flag bulleted bracketed (domain)"

# --- inline mid-line dates are never a dateline, in either tier -------------
cat > "$PMEM" <<'EOF'
## Architecture Decisions

**Config = TOML** chosen for parity with the CLI (2026-08-13).
Latency numbers (measured 2026-09-23, go1.26.2) back the threshold above.
EOF
run "$PMEM"
assert_exit 0 "$RC" "inline datelines mid-line do not flag in project memory"
assert_eq "" "$OUT" "…and prints no findings"

cat > "$DMEM" <<'EOF'
## Knowledge

**Config = TOML** chosen for parity with the CLI (2026-08-13).
EOF
run "$DMEM"
assert_exit 0 "$RC" "inline datelines mid-line do not flag in domain files"

# --- empty file is clean -----------------------------------------------------
: > "$PMEM"
run "$PMEM"
assert_exit 0 "$RC" "empty project memory.md is clean"

: > "$DMEM"
run "$DMEM"
assert_exit 0 "$RC" "empty domain file is clean"

finish
