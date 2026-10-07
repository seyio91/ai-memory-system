#!/usr/bin/env bash
# scripts/payload-slices.py: --count semantics and emit-mode framing, tested
# directly against the shared helper (independent of the emit_hook_chunk
# wrapper in hooks/lib.sh, which has its own reassembly/overflow coverage in
# test_shared_hooks.sh).
. "$(dirname "$0")/_assert.sh"

HELPER="$SCRIPTS_DIR/payload-slices.py"

SANDBOX="$(new_sandbox)"
trap 'rm -rf "$SANDBOX"' EXIT

# --- --count -----------------------------------------------------------

assert_eq "0" "$(printf '' | python3 "$HELPER" --count)" \
    "count: empty payload needs 0 slices"

assert_eq "1" "$(printf 'hello\n' | python3 "$HELPER" --count)" \
    "count: single line needs 1 slice"

# Exactly-at-boundary: one line totalling exactly MAX (9000) bytes stays a
# single slice ("a"*8999 + trailing newline == 9000 bytes).
AT_BOUNDARY_FILE="$SANDBOX/at-boundary.txt"
python3 -c "import sys; sys.stdout.write('a' * 8999 + chr(10))" > "$AT_BOUNDARY_FILE"
assert_eq "9000" "$(wc -c < "$AT_BOUNDARY_FILE" | tr -d ' ')" \
    "count: boundary fixture is exactly 9000 bytes"
assert_eq "1" "$(python3 "$HELPER" --count < "$AT_BOUNDARY_FILE")" \
    "count: a line exactly at the 9000-byte boundary stays 1 slice"

# One byte over: appending a second, unterminated one-byte line brings the
# running slice to exactly 9001 bytes -- one byte past MAX -- so it must
# split into 2. (Deliberately a 1-byte margin, not a few: a looser margin
# would stay green even if MAX drifted by a byte or two.)
OVER_BOUNDARY_FILE="$SANDBOX/over-boundary.txt"
cat "$AT_BOUNDARY_FILE" > "$OVER_BOUNDARY_FILE"
printf 'b' >> "$OVER_BOUNDARY_FILE"
assert_eq "9001" "$(wc -c < "$OVER_BOUNDARY_FILE" | tr -d ' ')" \
    "count: over-boundary fixture is exactly 9001 bytes"
assert_eq "2" "$(python3 "$HELPER" --count < "$OVER_BOUNDARY_FILE")" \
    "count: one byte over the boundary splits into 2 slices"

# --- emit identity on fixtures ------------------------------------------

SINGLE_FILE="$SANDBOX/single.txt"
printf 'line one\nline two\nline three\n' > "$SINGLE_FILE"
emitted="$(AI_MEMORY_CHUNK_INDEX=1 AI_MEMORY_CHUNK_TOTAL=1 python3 "$HELPER" < "$SINGLE_FILE")"
expected='<memory:chunk index="1" of="1" note="ordered fragments of one memory payload; hook delivery order is not guaranteed -- concatenate by index">
line one
line two
line three
</memory:chunk>'
assert_eq "$expected" "$emitted" \
    "emit: single-slice fixture framed with index/of/note"

first="$(AI_MEMORY_CHUNK_INDEX=1 AI_MEMORY_CHUNK_TOTAL=2 python3 "$HELPER" < "$OVER_BOUNDARY_FILE")"
second="$(AI_MEMORY_CHUNK_INDEX=2 AI_MEMORY_CHUNK_TOTAL=2 python3 "$HELPER" < "$OVER_BOUNDARY_FILE")"
assert_contains "$first" '<memory:chunk index="1" of="2" note="ordered fragments' \
    "emit: two-slice fixture chunk 1 carries the reassembly note"
assert_contains "$second" '<memory:chunk index="2" of="2">' \
    "emit: two-slice fixture chunk 2 has no note"
case "$second" in
    *"</memory:chunk>") _ok "emit: two-slice fixture chunk 2 closes the envelope" ;;
    *) _bad "emit: two-slice fixture chunk 2 closes the envelope" ;;
esac

# Overflow: natural slices (2) exceed the requested total (1), so the last
# requested chunk carries the truncation marker instead of raw content.
overflow="$(AI_MEMORY_CHUNK_INDEX=1 AI_MEMORY_CHUNK_TOTAL=1 python3 "$HELPER" < "$OVER_BOUNDARY_FILE")"
assert_contains "$overflow" "[ai-memory: memory base truncated — raise session_chunks in the harness manifest]" \
    "emit: overflow chunk carries the truncation marker"

finish
