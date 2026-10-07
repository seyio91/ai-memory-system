#!/usr/bin/env bash
# check-memory-size.sh — byte/line budgets on memory.md (--file) and session
# payload chunk-cap overflow (--payload). Both modes share one process; this
# suite exercises them independently, then the cross-cutting cwd-independence
# and usage-error behavior.
. "$(dirname "$0")/_assert.sh"

CHECK="$SCRIPTS_DIR/check-memory-size.sh"

run() { set +e; OUT="$(bash "$CHECK" "$@" 2>&1)"; RC=$?; set -e; }

# make_file <path> <total-bytes> — write an exact byte count, all lines <=64B
# (well under the 400B line budget) so it never trips the long-line check.
# The boundary cases below need the FILE check isolated from the LINE check.
make_file() {
    python3 - "$1" "$2" <<'PY'
import sys
path, total = sys.argv[1], int(sys.argv[2])
width = 64
with open(path, "wb") as f:
    written = 0
    while written + width + 1 <= total:
        f.write(b"a" * width + b"\n")
        written += width + 1
    remaining = total - written
    if remaining > 0:
        f.write(b"a" * remaining)
PY
}

# ============================================================================
# --file mode: whole-file budget
# ============================================================================

MEMF="$(new_sandbox)/memory.md"
mkdir -p "$(dirname "$MEMF")"

: > "$MEMF"
run --file "$MEMF"
assert_exit 0 "$RC" "--file: empty file is clean"
assert_eq "" "$OUT" "--file: empty file prints no findings"

make_file "$MEMF" 16384
assert_eq "16384" "$(wc -c <"$MEMF" | tr -d ' ')" "--file: boundary fixture is exactly 16384 bytes"
run --file "$MEMF"
assert_exit 0 "$RC" "--file: exactly 16384 bytes is clean (at the budget, not over it)"

make_file "$MEMF" 16385
assert_eq "16385" "$(wc -c <"$MEMF" | tr -d ' ')" "--file: over-boundary fixture is exactly 16385 bytes"
run --file "$MEMF"
assert_exit 1 "$RC" "--file: 16385 bytes (one over) warns"
assert_contains "$OUT" "WARN" "--file: over-budget finding is WARN-worded"
assert_contains "$OUT" "16385" "--file: over-budget finding names the byte count"
assert_contains "$OUT" "$MEMF:" "--file: finding is anchored to the file"

# ============================================================================
# --file mode: per-line budget
# ============================================================================

printf 'short line\n' > "$MEMF"
printf '%0400d\n' 0 >> "$MEMF"   # exactly 400 bytes + newline = 401-byte line record, but
# printf '%0400d' pads with zeros to 400 CHARS; confirm the line itself (sans
# newline) is exactly 400 bytes before asserting on it.
LINE_LEN="$(sed -n '2p' "$MEMF" | tr -d '\n' | wc -c | tr -d ' ')"
assert_eq "400" "$LINE_LEN" "--file: at-boundary line fixture is exactly 400 bytes"
run --file "$MEMF"
assert_exit 0 "$RC" "--file: a 400-byte line is clean (at the budget)"

printf 'short line\n' > "$MEMF"
printf '%0401d\n' 0 >> "$MEMF"
LINE_LEN="$(sed -n '2p' "$MEMF" | tr -d '\n' | wc -c | tr -d ' ')"
assert_eq "401" "$LINE_LEN" "--file: over-boundary line fixture is exactly 401 bytes"
run --file "$MEMF"
assert_exit 1 "$RC" "--file: a 401-byte line (one over) warns"
assert_contains "$OUT" "WARN" "--file: long-line finding is WARN-worded"
assert_contains "$OUT" "1 line(s)" "--file: long-line finding reports the count"
assert_contains "$OUT" "$MEMF:2:" "--file: long-line finding is anchored at the offending line"

# multiple long lines -> ONE finding naming the count, not one WARN per line.
{
    echo "short"
    printf '%0500d\n' 1
    printf '%0600d\n' 2
    printf '%0700d\n' 3
} > "$MEMF"
run --file "$MEMF"
assert_exit 1 "$RC" "--file: multiple long lines still exits 1"
LINE_COUNT="$(printf '%s\n' "$OUT" | grep -c 'long-line')"
assert_eq "1" "$LINE_COUNT" "--file: multiple long lines collapse into a single finding"
assert_contains "$OUT" "3 line(s)" "--file: collapsed finding names the count"
assert_contains "$OUT" "$MEMF:4:" "--file: collapsed finding points at the longest line"

# ============================================================================
# --payload mode
# ============================================================================

MEM="$(new_sandbox)"
HARN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$HARN"' EXIT

mkdir -p "$MEM/projects/proj/" "$MEM/projects/empty" \
    "$HARN/capped" "$HARN/uncapped"

cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: test fixture
---
# Project: proj
small and unremarkable
EOF

# A payload needing MORE than `width` slices: each line packs greedily into
# <=9000-byte slices (scripts/payload-slices.py), so N lines of ~4000 bytes
# each force roughly N/2 slices. `small.md` (1 line) stays comfortably under
# any cap tested here; `big.md` (6 lines) does not.
write_working() {
    python3 - "$1" "$2" <<'PY'
import sys
path, lines = sys.argv[1], int(sys.argv[2])
with open(path, "w") as f:
    for i in range(lines):
        f.write(("w%d" % i) * 1000 + "\n")
PY
}

write_working "$MEM/projects/proj/working.md" 1
write_working "$MEM/projects/proj/working.wt-feat.md" 6

cat > "$HARN/capped/manifest" <<'EOF'
name = capped
format = xml
session_chunks = 1
EOF
cat > "$HARN/uncapped/manifest" <<'EOF'
name = uncapped
format = md
EOF

runp() {
    set +e
    OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN" bash "$CHECK" "$@" 2>&1)"
    RC=$?
    set -e
}

# --- shared working.md stays under the cap; the overlay does not -----------
runp --payload proj
assert_exit 1 "$RC" "--payload: a project with one over-cap working file exits 1"
assert_contains "$OUT" "working.wt-feat.md" "--payload: the over-cap OVERLAY is named in a finding"
assert_contains "$OUT" "ERROR" "--payload: overflow finding is ERROR-worded"
assert_contains "$OUT" "capped" "--payload: overflow finding names the harness"
assert_not_contains "$OUT" "$MEM/projects/proj/working.md:" "--payload: the under-cap SHARED working.md is not flagged"
assert_not_contains "$OUT" "uncapped" "--payload: a harness without session_chunks is never reported"

# --- a harness with no session_chunks is skipped even when it would overflow
runp --payload proj
assert_not_contains "$OUT" "format = md" "--payload: no stray manifest text leaks into findings"

# --- everyone under cap is clean --------------------------------------------
write_working "$MEM/projects/proj/working.wt-feat.md" 1
runp --payload proj
assert_exit 0 "$RC" "--payload: every working file under every capped harness's budget is clean"
assert_eq "" "$OUT" "--payload: clean run prints nothing"
write_working "$MEM/projects/proj/working.wt-feat.md" 6   # restore for later cases

# --- --working pins exactly one file, ignoring the others -------------------
runp --payload proj --working "$MEM/projects/proj/working.md"
assert_exit 0 "$RC" "--payload --working: pinning the under-cap file alone is clean"
runp --payload proj --working "$MEM/projects/proj/working.wt-feat.md"
assert_exit 1 "$RC" "--payload --working: pinning the over-cap file alone still flags it"
assert_contains "$OUT" "working.wt-feat.md" "--payload --working: names the pinned file"

# --- project with no working file, and an empty project, are both clean ----
runp --payload empty
assert_exit 0 "$RC" "--payload: a project with no working file at all is clean"
assert_eq "" "$OUT" "--payload: ...and prints nothing"

runp --payload does-not-exist
assert_exit 0 "$RC" "--payload: a nonexistent project is clean (nothing to render)"

# --- cwd independence: running from inside a linked worktree must not change
# the result — the checker pins each working file explicitly rather than
# resolving one from AI_MEMORY_CWD/$PWD (see content-core.sh). A prior
# approach based on cwd resolution silently dropped the shared working.md the
# moment it ran from a directory that resolves to an overlay key.
# Baseline from a neutral cwd (whatever $PWD happens to be here — not inside
# any worktree), recomputed fresh rather than reusing a stale $OUT from an
# earlier case.
runp --payload proj
BASELINE="$OUT"

# WTBASE is its own fresh sandbox so the worktree's absolute path can never
# collide with another run's leftovers (an earlier `../wt-feat`-relative
# attempt collided with a stale sibling dir from a prior manual run — this
# nests both the repo and the worktree under one disposable parent instead).
WTBASE="$(new_sandbox)"
GITROOT="$WTBASE/repo"
WT="$WTBASE/wt-feat"
mkdir -p "$GITROOT"
# The git setup is the CONDITION of an if, not a bare statement: _assert.sh's
# run()-style helpers leave `set -e` on between cases, and -e does not fire on
# a command tested by if/while/until — a bare failing statement here would
# otherwise kill the whole suite instead of falling through to `_bad`.
if (
    cd "$GITROOT" \
        && git init -q . \
        && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
        && git worktree add -q -b wt-feat "$WT"
) >/dev/null 2>&1 && [ -d "$WT" ]; then
    # check-memory-size.sh exits 1 on a finding (it has one here, by design),
    # and this is a plain assignment outside any if/&&/|| — set -e would abort
    # the whole suite on that nonzero exit the instant it's captured.
    set +e
    OUT_FROM_WT="$(cd "$WT" && MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN" bash "$CHECK" --payload proj 2>&1)"
    set -e
    assert_eq "$BASELINE" "$OUT_FROM_WT" "--payload: result from inside a linked worktree matches the neutral-cwd result"
else
    _bad "--payload: cwd-independence setup (git worktree add failed) — skipped"
fi
rm -rf "$WTBASE"

# ============================================================================
# --payload mode: cheap byte pre-filter (perf)
# ============================================================================
# A fake slicer records whether the render|slice pipe actually ran, so a
# sub-threshold skip is proven by the ABSENCE of that marker — a clean exit
# code alone would not distinguish "skipped" from "rendered and found clean".
# No `MAX = ` line in the fake script, so check-memory-size.sh falls back to
# its own default (9000, PREFILTER_SLICE_MAX). With the $HARN/capped
# fixture's session_chunks=1 as the one cap in play, the current bound (see
# check-memory-size.sh's header comment) skips only when
# floor((raw*100/75) / (9000 - (longest_line+256))) + 1 <= 1, i.e. when
# raw < (9000 - longest_line - 256) * 75/100. That crossover moves with the
# longest line in the fixture, not a fixed byte count: the two fixtures below
# sit on opposite sides of it by LINE SHAPE, not just total size.
# write_working's one ~2,000-byte line pulls its own crossover down to
# 5,058 B; make_file's many 64-byte lines leave its crossover at 6,510 B.
# CMS_TEST_SLICER_COUNT lets a case choose the reported slice count (default
# 0, clean); the off-by-one case below needs it to equal the harness's cap
# exactly.
FAKE_SLICER="$(new_sandbox)/fake-slicer.py"
cat > "$FAKE_SLICER" <<'PY'
import os
marker = os.environ.get("CMS_TEST_SLICER_MARKER")
if marker:
    open(marker, "a").close()
print(os.environ.get("CMS_TEST_SLICER_COUNT", "0"))
PY
PF_MARKER="$(new_sandbox)/slicer-ran"
trap 'rm -rf "$MEM" "$HARN" "$(dirname "$FAKE_SLICER")" "$(dirname "$PF_MARKER")"' EXIT

runpf() { # runpf <args...> -> sets OUT, RC
    set +e
    OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN" AI_MEMORY_SLICER_OVERRIDE="$FAKE_SLICER" \
        CMS_TEST_SLICER_MARKER="$PF_MARKER" bash "$CHECK" "$@" 2>&1)"
    RC=$?
    set -e
}

# --- sub-threshold (~2,001 raw bytes in one ~2,000-byte line, under this
# fixture's ~5,058-byte crossover): skipped ---------------------------------
rm -f "$PF_MARKER"
write_working "$MEM/projects/proj/working.md" 1
runpf --payload proj --working "$MEM/projects/proj/working.md"
assert_not_file "$PF_MARKER" "--payload pre-filter: sub-threshold combo never invokes the render|slice pipe"
assert_eq "" "$OUT" "--payload pre-filter: sub-threshold combo reports nothing"

# --- above-threshold (7,200 raw bytes across many 64-byte lines, over this
# fixture's ~6,510-byte crossover): rendered exactly ------------------------
rm -f "$PF_MARKER"
make_file "$MEM/projects/proj/working.md" 7200
runpf --payload proj --working "$MEM/projects/proj/working.md"
assert_file "$PF_MARKER" "--payload pre-filter: above-threshold combo invokes the render|slice pipe (not skipped)"

# restore the fixture state later cases in this file (none, but keep it tidy)
write_working "$MEM/projects/proj/working.md" 1

# ============================================================================
# --payload mode: slices == cap is clean, not overflow (off-by-one)
# ============================================================================
# Reuses the above-threshold fixture (forces an exact render, bypassing the
# pre-filter) with the fake slicer reporting the harness's own cap exactly.
# "slices > cap" is overflow; "slices == cap" must stay clean — mutating
# check_one_payload's `-gt` to `-ge` must fail this.
make_file "$MEM/projects/proj/working.md" 7200
set +e
OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN" AI_MEMORY_SLICER_OVERRIDE="$FAKE_SLICER" \
    CMS_TEST_SLICER_MARKER="$PF_MARKER" CMS_TEST_SLICER_COUNT="1" \
    bash "$CHECK" --payload proj --working "$MEM/projects/proj/working.md" 2>&1)"
RC=$?
set -e
assert_exit 0 "$RC" "--payload: slices exactly at the cap (1 == 1) is clean, not overflow"
assert_eq "" "$OUT" "--payload: at-cap slices print no finding"
write_working "$MEM/projects/proj/working.md" 1   # restore

# ============================================================================
# --payload mode: the pre-filter bound must account for the longest line
# ============================================================================
# write_long_lines <path> <lines> <line-bytes> — each line is exactly
# line-bytes 'a' characters (plus newline), unlike write_working's repeated
# short token: these fixtures need a LINE long enough, on its own, to force a
# small number of lines per slice.
write_long_lines() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys
path, lines, width = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "w") as f:
    for _ in range(lines):
        f.write("a" * width + "\n")
PY
}

# --- validator repro: 13 lines x 4,600 B (~59.8 KB total raw) is too big for
# a session_chunks=12 harness — each 4,601-byte line is too long for two to
# share a 9,000-byte slice, so greedy packing needs exactly 13 slices (one
# line each). The OLD byte-only threshold (min_cap * MAX * 75% = 12 * 9000 *
# 0.75 = 81,000 B) skipped this combination outright because ~59.8 KB <
# 81,000 B, reporting clean while delivery would silently truncate past
# chunk 12. The new bound must NOT skip here — it must render exactly and
# report ERROR. ---
HARN_A="$(new_sandbox)"
mkdir -p "$HARN_A/capped12"
cat > "$HARN_A/capped12/manifest" <<'EOF'
name = capped12
format = xml
session_chunks = 12
EOF
write_long_lines "$MEM/projects/proj/working.md" 13 4600
assert_eq "59813" "$(wc -c <"$MEM/projects/proj/working.md" | tr -d ' ')" \
    "pre-filter bound: validator repro fixture is exactly 59,813 bytes"
set +e
OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN_A" bash "$CHECK" --payload proj --working "$MEM/projects/proj/working.md" 2>&1)"
RC=$?
set -e
assert_exit 1 "$RC" "pre-filter bound: validator repro (13x4.6KB lines, cap 12) is not skipped — reports overflow"
assert_contains "$OUT" "ERROR" "pre-filter bound: validator repro finding is ERROR-worded"
assert_contains "$OUT" "needs 13 chunk" "pre-filter bound: validator repro finding names the real (13) slice count"
assert_contains "$OUT" "capped12" "pre-filter bound: validator repro finding names the harness"
rm -rf "$HARN_A"

# --- a long single line keeps raw bytes small, but the bound must still
# render exactly (fake-slicer marker present) because L dominates the
# formula — this is the case "drop L from the formula" breaks. -------------
write_long_lines "$MEM/projects/proj/working.md" 1 8500
rm -f "$PF_MARKER"
runpf --payload proj --working "$MEM/projects/proj/working.md"
assert_file "$PF_MARKER" "pre-filter bound: one very-long line forces an exact render despite small raw bytes"

# --- a small short-line project is still skipped (the bound formula must not
# regress the common case). ------------------------------------------------
write_working "$MEM/projects/proj/working.md" 1
rm -f "$PF_MARKER"
runpf --payload proj --working "$MEM/projects/proj/working.md"
assert_not_file "$PF_MARKER" "pre-filter bound: a small short-line project is still skipped"

# --- md harness: domain content is not payload ----------------------------
# md_render carries a frontmatter index of domain/, not the files themselves.
# 20 KB of domain content under a sub-threshold project must not force a render.
HARN_MD="$(new_sandbox)"
mkdir -p "$HARN_MD/mdh"
printf 'name = mdh\nformat = md\nsession_chunks = 1\n' > "$HARN_MD/mdh/manifest"
mkdir -p "$MEM/domain"
printf -- '---\ntopic: big\ntriggers: big\nsummary: big domain file\n---\n' > "$MEM/domain/big.md"
head -c 20000 /dev/zero | tr '\0' 'x' >> "$MEM/domain/big.md"
rm -f "$PF_MARKER"
set +e
OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN_MD" AI_MEMORY_SLICER_OVERRIDE="$FAKE_SLICER" \
    CMS_TEST_SLICER_MARKER="$PF_MARKER" bash "$CHECK" --payload proj --working "$MEM/projects/proj/working.md" 2>&1)"
set -e
assert_not_file "$PF_MARKER" "--payload pre-filter: md harness counts the domain index, not domain/*.md content"
rm -rf "$MEM/domain" "$HARN_MD"

# ============================================================================
# --payload mode: the pre-filter bound must account for the initiative alert
# ============================================================================
# Validator case C7: a working.md that sits right at the OLD (alert-blind)
# bound's skip edge for a cap-12 harness, PLUS one active initiative that
# targets this project whose initiative-status.sh reports enough stale
# targets to push the REAL rendered payload one chunk over that cap. Before
# the alert was folded into raw/L, the prefilter skipped this combination
# outright (bound computed from working.md/memory.md bytes alone already
# cleared 12) and check-memory-size.sh reported clean while real delivery
# would silently truncate past chunk 12.
#
# fake_initiative_status <count> — writes $MEM/scripts/initiative-status.sh
# so a call with any slug touches $IA_STATUS_MARKER (proof of invocation,
# since a stale-target scan is normally ~0.9s against the real script — see
# lib.sh's _compute_initiative_alert_lines) and emits <count> WARN lines
# under a "## Stale targets" heading, the exact section
# _compute_initiative_alert_lines parses out of initiative-status.sh's real
# output.
IA_STATUS_MARKER="$(new_sandbox)/initiative-status-ran"
fake_initiative_status() {
    local count="$1"
    mkdir -p "$MEM/scripts"
    cat > "$MEM/scripts/initiative-status.sh" <<EOF
#!/usr/bin/env bash
touch "$IA_STATUS_MARKER"
printf '## Stale targets\n\n'
python3 - <<'PYEOF'
for i in range($count):
    print("WARN: proj/seeded%d stale target line padding xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx%d" % (i, i))
PYEOF
EOF
    chmod +x "$MEM/scripts/initiative-status.sh"
}

mkdir -p "$MEM/initiatives"
HARN_C7="$(new_sandbox)"
mkdir -p "$HARN_C7/capped12"
cat > "$HARN_C7/capped12/manifest" <<'EOF'
name = capped12
format = xml
session_chunks = 12
EOF

# 770 lines x 100 B (99 'a's + newline) = 77,000 B raw in working.md — chosen
# (empirically, against the real renderer/slicer, same way the validator
# repro fixture above was) so the bound computed from working.md + memory.md
# bytes ALONE sits at bound==12 (skip) for this cap, isolating the alert as
# the only thing that can push the real render over.
write_long_lines "$MEM/projects/proj/working.md" 770 99
assert_eq "77000" "$(wc -c <"$MEM/projects/proj/working.md" | tr -d ' ')" \
    "initiative-alert bound: C7 working.md fixture is exactly 77,000 bytes"

# --- an initiative targets proj and has stale targets: alert folded into the
# bound, real render needs 13 chunks against the cap-12 harness -------------
cat > "$MEM/initiatives/dispatch.md" <<'EOF'
---
kind: initiative
slug: dispatch
status: active
created: 2026-08-15
---
# Dispatch
## Targets
### proj/seeded
- execution_mode: manual
- depends_on: none
## Closure
Open.
EOF
# 400 WARN lines (~33 KB) — within the empirically-verified 360-440 line
# range where the real xml render needs exactly 13 chunks against the
# cap-12 harness (confirmed against the unmodified renderer/slicer).
fake_initiative_status 400
rm -f "$IA_STATUS_MARKER"
set +e
OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN_C7" bash "$CHECK" --payload proj --working "$MEM/projects/proj/working.md" 2>&1)"
RC=$?
set -e
assert_exit 1 "$RC" "initiative-alert bound: C7 (targeting initiative, stale alert) is not skipped — reports overflow"
assert_contains "$OUT" "ERROR" "initiative-alert bound: C7 finding is ERROR-worded"
assert_contains "$OUT" "needs 13 chunk" "initiative-alert bound: C7 finding names the real (13) slice count"
assert_contains "$OUT" "capped12" "initiative-alert bound: C7 finding names the harness"
assert_file "$IA_STATUS_MARKER" "initiative-alert bound: C7 — a targeting initiative DOES invoke initiative-status.sh"

# --- same working.md shape, but the active initiative targets a DIFFERENT
# project: the cheap "## Targets" predicate proves the alert is empty for
# proj, so initiative-status.sh must never run (marker stays absent) and the
# bound falls back to working.md/memory.md bytes alone (skip, clean). -------
cat > "$MEM/initiatives/dispatch.md" <<'EOF'
---
kind: initiative
slug: dispatch
status: active
created: 2026-08-15
---
# Dispatch
## Targets
### other-project/seeded
- execution_mode: manual
- depends_on: none
## Closure
Open.
EOF
fake_initiative_status 400
rm -f "$IA_STATUS_MARKER"
set +e
OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN_C7" bash "$CHECK" --payload proj --working "$MEM/projects/proj/working.md" 2>&1)"
RC=$?
set -e
assert_exit 0 "$RC" "initiative-alert bound: a non-targeting initiative's alert stays provably empty — clean"
assert_eq "" "$OUT" "initiative-alert bound: non-targeting case prints no finding"
assert_not_file "$IA_STATUS_MARKER" "initiative-alert bound: non-targeting initiative never invokes initiative-status.sh"

rm -rf "$MEM/initiatives" "$MEM/scripts" "$HARN_C7"
write_working "$MEM/projects/proj/working.md" 1   # restore for any later cases

# ============================================================================
# usage errors
# ============================================================================

run
assert_exit 2 "$RC" "usage: no args exits 2"

run --bogus
assert_exit 2 "$RC" "usage: an unknown flag exits 2"

run --file
assert_exit 2 "$RC" "usage: --file with no paths exits 2"

run --payload
assert_exit 2 "$RC" "usage: --payload with no project exits 2"

run --file "$MEMF" --working /nowhere
assert_exit 2 "$RC" "usage: --working only makes sense with --payload"

finish
