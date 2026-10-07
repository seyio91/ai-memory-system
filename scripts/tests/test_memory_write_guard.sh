#!/usr/bin/env bash
# memory_write_guard.sh: PostToolUse guard on wiki-tier memory writes.
#   projects/*/memory.md           -> drift + --file budget + --payload (every
#                                      working file)
#   projects/*/working.md or
#   projects/*/working.<key>.md    -> --payload --working <that file> ONLY
#                                      (no drift check)
#   domain/*.md                    -> drift only (unchanged scope)
#   anything else                  -> exit 0
# Any finding on an in-scope write -> stderr report + exit 2. Fails open on a
# missing checker. See scripts/hooks/memory_write_guard.sh for the full
# rationale.
. "$(dirname "$0")/_assert.sh"

GUARD="$SCRIPTS_DIR/hooks/memory_write_guard.sh"

write_payload() { # write_payload <file_path> — PostToolUse Write/Edit shape
    printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"
}

run_guard() { # run_guard <file_path> -> sets OUT, CODE
    set +e
    OUT="$(write_payload "$1" | bash "$GUARD" 2>&1)"
    CODE=$?
    set -e
}

# build_tree <memdir> — identity + template + domain + index (seed_min_tree)
# plus one minimal, section-complete "good" project with an empty working.md.
build_tree() {
    local m="$1"
    seed_min_tree "$m"
    mkdir -p "$m/projects/good"
    cat > "$m/projects/good/memory.md" <<'EOF'
---
topic: good
scope: project
summary: A good project
---
# Project: good

## What It Is
x

## Current State
x

## Architecture Decisions
x

## Known Constraints / Gotchas
x

## Current Goal
x
EOF
    : > "$m/projects/good/working.md"
}

# write_overflow <path> <lines> — enough bytes per line, repeated, to push a
# session_chunks=1 / 9000-byte-slice harness (the $HARN fixture below) over
# its cap. Mirrors test_check_memory_size.sh's write_working fixture.
write_overflow() {
    python3 - "$1" "$2" <<'PY'
import sys
path, lines = sys.argv[1], int(sys.argv[2])
with open(path, "w") as f:
    for i in range(lines):
        f.write(("w%d" % i) * 1000 + "\n")
PY
}

# HARN: one harness capped at session_chunks=1, shared by every over-cap case
# below. AI_MEMORY_HARNESSES_DIR is the same test seam test_check_memory_size.sh
# and test_lint_memory.sh use — check-memory-size.sh (the guard's subprocess)
# reads it straight from the environment.
HARN="$(new_sandbox)"
mkdir -p "$HARN/capped"
cat > "$HARN/capped/manifest" <<'EOF'
name = capped
format = xml
session_chunks = 1
EOF
trap 'rm -rf "$HARN"' EXIT

# --- memory.md over budget -> exit 2, names the size-budget section --------
M1="$(new_sandbox)"; export MEMORY_DIR="$M1"; build_tree "$M1"
python3 - "$M1/projects/good/memory.md" <<'PY'
import sys
with open(sys.argv[1], "ab") as f:
    f.write(b"\n" + b"x" * 20000 + b"\n")
PY
run_guard "$M1/projects/good/memory.md"
assert_exit 2 "$CODE" "oversized memory.md exits 2"
assert_contains "$OUT" "Size budget" "oversized memory.md names the size-budget section"
assert_contains "$OUT" "budget" "oversized memory.md report mentions the budget finding"
assert_contains "$OUT" "Trim this file" "size-only finding gets trim advice"
assert_not_contains "$OUT" "to the project's working.md" "size-only finding never tells the writer to move lines into working.md"
rm -rf "$M1"

# --- memory.md with a dated log line but within budget -> drift advice only --
MD="$(new_sandbox)"; export MEMORY_DIR="$MD"; build_tree "$MD"
printf '\n**2026-01-01:** PR #1 merged.\n' >> "$MD/projects/good/memory.md"
run_guard "$MD/projects/good/memory.md"
assert_exit 2 "$CODE" "dated line in memory.md exits 2"
assert_contains "$OUT" "to the project's working.md" "drift-only finding gets the move-to-working.md advice"
assert_not_contains "$OUT" "Trim this file" "drift-only finding gets no trim advice"
rm -rf "$MD"

# --- clean memory.md -> exit 0 ----------------------------------------------
M2="$(new_sandbox)"; export MEMORY_DIR="$M2"; build_tree "$M2"
run_guard "$M2/projects/good/memory.md"
assert_exit 0 "$CODE" "clean memory.md exits 0"
rm -rf "$M2"

# --- a memory.md write also checks the rendered SESSION PAYLOAD (every
#     working file), not just the file's own byte budget ------------------
M3="$(new_sandbox)"; export MEMORY_DIR="$M3"; build_tree "$M3"
write_overflow "$M3/projects/good/working.md" 6
export AI_MEMORY_HARNESSES_DIR="$HARN"
run_guard "$M3/projects/good/memory.md"
unset AI_MEMORY_HARNESSES_DIR
assert_exit 2 "$CODE" "memory.md write catches an over-cap payload from working.md too"
assert_contains "$OUT" "Session payload" "memory.md write's report names the payload section"
rm -rf "$M3"

# --- working.md pushing the rendered payload over cap -> exit 2 ------------
M4="$(new_sandbox)"; export MEMORY_DIR="$M4"; build_tree "$M4"
write_overflow "$M4/projects/good/working.md" 6
export AI_MEMORY_HARNESSES_DIR="$HARN"
run_guard "$M4/projects/good/working.md"
unset AI_MEMORY_HARNESSES_DIR
assert_exit 2 "$CODE" "over-cap working.md exits 2"
assert_contains "$OUT" "Session payload" "over-cap working.md names the payload section"
assert_not_contains "$OUT" "Changelog drift" "a working.md write never runs the drift check"
assert_not_contains "$OUT" "to the project's working.md" "a working.md write's advice never tells the user to move lines INTO working.md (it already is working.md)"
assert_contains "$OUT" "session_chunks" "a working.md write's advice still mentions raising the harness cap"
rm -rf "$M4"

# --- a working.<key>.md overlay write is checked with THAT file, not the
#     shared working.md: shared stays empty/clean, only the overlay overflows --
M5="$(new_sandbox)"; export MEMORY_DIR="$M5"; build_tree "$M5"
write_overflow "$M5/projects/good/working.wt-feat.md" 6
export AI_MEMORY_HARNESSES_DIR="$HARN"
run_guard "$M5/projects/good/working.wt-feat.md"
unset AI_MEMORY_HARNESSES_DIR
assert_exit 2 "$CODE" "over-cap working.<key>.md overlay exits 2"
assert_contains "$OUT" "working.wt-feat.md" "overlay report names the overlay file that was pinned"
rm -rf "$M5"

# --- working.md with a dated log line but small -> exit 0: no drift check
#     ever runs against working.md, so the dated-log SHAPE is irrelevant, and
#     the content is far too small to overflow any real harness's cap --------
M6="$(new_sandbox)"; export MEMORY_DIR="$M6"; build_tree "$M6"
printf '**2026-08-13:** PRs #1 and #2 merged\n' > "$M6/projects/good/working.md"
run_guard "$M6/projects/good/working.md"
assert_exit 0 "$CODE" "small working.md with a dated log line exits 0"
rm -rf "$M6"

# --- an out-of-scope path (todo.md) -> exit 0 -------------------------------
M7="$(new_sandbox)"; export MEMORY_DIR="$M7"; build_tree "$M7"
printf '# Todo\n' > "$M7/projects/good/todo.md"
run_guard "$M7/projects/good/todo.md"
assert_exit 0 "$CODE" "out-of-scope path (todo.md) exits 0"
rm -rf "$M7"

# --- domain/*.md is still drift-only: no size budget applies ---------------
M8="$(new_sandbox)"; export MEMORY_DIR="$M8"; build_tree "$M8"
printf '%s\n' "**2026-08-13:** both open PRs merged" >> "$M8/domain/terraform.md"
run_guard "$M8/domain/terraform.md"
assert_exit 2 "$CODE" "a dated domain/*.md entry still exits 2 (drift unchanged)"
assert_contains "$OUT" "Changelog drift" "domain write names the drift section"
assert_not_contains "$OUT" "Size budget" "domain write never runs the size-budget check"
assert_not_contains "$OUT" "Session payload" "domain write never runs the payload check"
# The advice text must match what this branch actually ran (drift only) — it
# must never point the writer at a size/payload check this branch skipped.
assert_not_contains "$OUT" "size budget" "domain write's advice never mentions the size budget (never checked here)"
assert_not_contains "$OUT" "session_chunks" "domain write's advice never mentions raising session_chunks (never checked here)"
rm -rf "$M8"

# --- fail-open: checkers missing from the guard's own install location
#     (resolved from the guard's OWN path, never from MEMORY_DIR) -> exit 0
#     even against an objectively oversized memory.md -----------------------
M9="$(new_sandbox)"; export MEMORY_DIR="$M9"; build_tree "$M9"
python3 - "$M9/projects/good/memory.md" <<'PY'
import sys
with open(sys.argv[1], "ab") as f:
    f.write(b"\n" + b"x" * 20000 + b"\n")
PY
FAKE_INSTALL="$(new_sandbox)"
mkdir -p "$FAKE_INSTALL/hooks"
cp "$GUARD" "$FAKE_INSTALL/hooks/memory_write_guard.sh"
chmod +x "$FAKE_INSTALL/hooks/memory_write_guard.sh"
set +e
OUT="$(write_payload "$M9/projects/good/memory.md" | MEMORY_DIR="$M9" bash "$FAKE_INSTALL/hooks/memory_write_guard.sh" 2>&1)"
CODE=$?
set -e
assert_exit 0 "$CODE" "checkers missing from the install dir fail open (exit 0)"
rm -rf "$M9" "$FAKE_INSTALL"

unset MEMORY_DIR
finish
