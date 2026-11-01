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

# --- near-cap marker ------------------------------------------------------

NEAR="[ai-memory: payload at"
# gen N: N-1 full slices (9 x 1000-byte lines) plus a short tail line.
gen_slices() { python3 -c "
import sys
n = int(sys.argv[1])
sys.stdout.write(('x' * 999 + chr(10)) * (9 * (n - 1)) + 'tail' + chr(10))" "$1"; }
# emit_all FILE TOTAL: every chunk 1..TOTAL, concatenated.
emit_all() {
    local i
    for i in $(seq 1 "$2"); do
        AI_MEMORY_CHUNK_INDEX="$i" AI_MEMORY_CHUNK_TOTAL="$2" python3 "$HELPER" < "$1"
    done
}
max_chunk_bytes() {
    local i
    for i in $(seq 1 "$2"); do
        AI_MEMORY_CHUNK_INDEX="$i" AI_MEMORY_CHUNK_TOTAL="$2" python3 "$HELPER" < "$1" | wc -c
    done | sort -n | tail -1 | tr -d ' '
}

CAP=4
for n in 2 3 4 5; do gen_slices "$n" > "$SANDBOX/near-$n.txt"; done
assert_eq "3" "$(python3 "$HELPER" --count < "$SANDBOX/near-3.txt")" \
    "near-cap: --count still counts content slices only"

out="$(emit_all "$SANDBOX/near-3.txt" $CAP)"
assert_contains "$out" "$NEAR 3/4 chunks — trim memory.md or Open threads]" \
    "near-cap: cap-1 slices carry the marker"
last="$(AI_MEMORY_CHUNK_INDEX=3 AI_MEMORY_CHUNK_TOTAL=$CAP python3 "$HELPER" < "$SANDBOX/near-3.txt")"
assert_contains "$last" "tail" "near-cap: cap-1 last slice keeps the payload tail"
case "$last" in
    *"threads]
</memory:chunk>") _ok "near-cap: marker closes the last slice" ;;
    *) _bad "near-cap: marker closes the last slice" ;;
esac
assert_eq "1" "$(printf '%s' "$out" | grep -c -F "$NEAR")" \
    "near-cap: cap-1 payload carries exactly one marker"

out="$(emit_all "$SANDBOX/near-4.txt" $CAP)"
assert_contains "$out" "$NEAR 4/4 chunks" "near-cap: exactly-cap slices carry the marker"
assert_contains "$out" "tail" "near-cap: exactly-cap payload keeps the tail"

out="$(emit_all "$SANDBOX/near-2.txt" $CAP)"
assert_not_contains "$out" "$NEAR" "near-cap: cap-2 slices carry no marker"

out="$(emit_all "$SANDBOX/near-5.txt" $CAP)"
assert_contains "$out" "memory base truncated" "near-cap: over-cap keeps the overflow marker"
assert_not_contains "$out" "$NEAR" "near-cap: over-cap carries no near-cap marker"

for n in 2 3 4 5; do
    assert_eq "ok" "$([ "$(max_chunk_bytes "$SANDBOX/near-$n.txt" $CAP)" -le 9300 ] && echo ok)" \
        "near-cap: $n-slice payload keeps every chunk within MAX plus framing"
done

# Full last slice below cap: the marker gets its own slice, nothing dropped.
python3 -c "import sys; sys.stdout.write(('x' * 999 + chr(10)) * 18)" > "$SANDBOX/full-2.txt"
out="$(emit_all "$SANDBOX/full-2.txt" 3)"
assert_contains "$out" '<memory:chunk index="3" of="3">' \
    "near-cap: full last slice below cap puts the marker in a new slice"
assert_eq "18" "$(printf '%s' "$out" | grep -c -E '^x+$')" \
    "near-cap: full last slice below cap drops no content"

# Exactly cap, last slice full: the note never costs content.
python3 -c "import sys; sys.stdout.write(('x' * 999 + chr(10)) * 8 + 'y' * 8999 + chr(10))" > "$SANDBOX/cap-room.txt"
out="$(emit_all "$SANDBOX/cap-room.txt" 2)"
assert_contains "$out" "$NEAR 2/2 chunks" "near-cap: exactly-cap full last slice puts the marker in an earlier slice"
assert_eq "1" "$(printf '%s' "$out" | grep -c -E '^y+$')" "near-cap: exactly-cap full last slice keeps the tail line"
python3 -c "import sys; sys.stdout.write(('x' * 999 + chr(10)) * 18)" > "$SANDBOX/cap-full.txt"
out="$(emit_all "$SANDBOX/cap-full.txt" 2)"
assert_eq "18" "$(printf '%s' "$out" | grep -c -E '^x+$')" "near-cap: exactly-cap with no room drops no content"
assert_not_contains "$out" "$NEAR" "near-cap: exactly-cap with no room skips the marker"

finish
