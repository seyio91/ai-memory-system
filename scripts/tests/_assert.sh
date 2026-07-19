#!/usr/bin/env bash
# Dependency-free assertion helpers for the memory script test suite.
# Source this at the top of each test_*.sh. Targets bash 3.2 (macOS):
# no associative arrays, no mapfile.
#
#   . "$(dirname "$0")/_assert.sh"
#   assert_eq "expected" "$actual" "label"
#   ...
#   finish

set -uo pipefail

# Resolve the scripts dir (parent of tests/) so tests can call siblings by path.
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"

_PASS=0
_FAIL=0
_TEST_NAME="$(basename "${0}")"

_ok()   { _PASS=$((_PASS + 1)); printf '  ok   %s\n' "$1"; }
_bad()  { _FAIL=$((_FAIL + 1)); printf '  FAIL %s\n' "$1"; }

assert_eq() {
    # assert_eq <expected> <actual> <label>
    if [ "$1" = "$2" ]; then _ok "$3"; else
        _bad "$3"; printf '       expected: [%s]\n       actual:   [%s]\n' "$1" "$2"
    fi
}

assert_contains() {
    # assert_contains <haystack> <needle> <label>
    case "$1" in
        *"$2"*) _ok "$3" ;;
        *) _bad "$3"; printf '       missing substring: [%s]\n' "$2" ;;
    esac
}

assert_not_contains() {
    case "$1" in
        *"$2"*) _bad "$3"; printf '       unexpected substring present: [%s]\n' "$2" ;;
        *) _ok "$3" ;;
    esac
}

assert_exit() {
    # assert_exit <expected_code> <actual_code> <label>
    if [ "$1" = "$2" ]; then _ok "$3"; else
        _bad "$3"; printf '       expected exit %s, got %s\n' "$1" "$2"
    fi
}

assert_file() {
    if [ -e "$1" ]; then _ok "$2"; else _bad "$2"; printf '       missing path: %s\n' "$1"; fi
}

assert_not_file() {
    if [ -e "$1" ]; then _bad "$2"; printf '       unexpected path: %s\n' "$1"; else _ok "$2"; fi
}

finish() {
    printf '%s: %d passed, %d failed\n' "$_TEST_NAME" "$_PASS" "$_FAIL"
    [ "$_FAIL" -eq 0 ] || exit 1
    exit 0
}

# strip_chunks <file>... — reassemble enveloped hook chunks to stdout.
# emit_hook_chunk frames each slice as <memory:chunk index="i" of="N">…</memory:chunk>
# because hook entries are NOT delivered in registration order (Claude, 2026-07-18).
# Sorts by the header index, so callers may pass files in any order; empty files
# (chunks past the natural slice count) are skipped. Fails loudly on a missing
# envelope rather than silently passing raw bytes through.
strip_chunks() {
    python3 - "$@" <<'PY'
import re, sys
parts = []
for path in sys.argv[1:]:
    data = open(path, "rb").read()
    if not data:
        continue
    head, _, rest = data.partition(b"\n")
    m = re.match(rb'^<memory:chunk index="(\d+)" of="(\d+)"', head)
    if not m:
        sys.stderr.write("missing envelope header: %s\n" % path)
        sys.exit(1)
    if not rest.endswith(b"</memory:chunk>\n"):
        sys.stderr.write("missing envelope footer: %s\n" % path)
        sys.exit(1)
    parts.append((int(m.group(1)), rest[: -len(b"</memory:chunk>\n")]))
parts.sort()
sys.stdout.buffer.write(b"".join(body for _, body in parts))
PY
}

# --- sandbox helpers -------------------------------------------------------

new_sandbox() {
    # Print a fresh temp dir path. Caller is responsible for cleanup (or trap).
    mktemp -d 2>/dev/null || mktemp -d -t memtest
}

seed_template() {
    # seed_template <memdir> — create projects/_template scaffold.
    local m="$1" t="$1/projects/_template"
    mkdir -p "$t/plans" "$t/archive/plans" "$t/archive/todos" "$t/archive/working"
    : > "$t/plans/.gitkeep"
    : > "$t/archive/plans/.gitkeep"
    : > "$t/archive/todos/.gitkeep"
    : > "$t/archive/working/.gitkeep"
    : > "$t/working.md"
    printf '# Todo\n' > "$t/todo.md"
    cat > "$t/memory.md" <<'EOF'
---
topic: <name>
scope: project
summary: <one-line description for the index — replace before use>
---

# Project: <name>

## What It Is
One-line description.

## Current State
State.

## Architecture Decisions
Decisions.

## Known Constraints / Gotchas
Gotchas.

## Current Goal
Goal.
EOF
}

seed_domain() {
    # seed_domain <memdir> <topic> — create a valid domain file.
    local m="$1" topic="$2"
    mkdir -p "$m/domain"
    cat > "$m/domain/$topic.md" <<EOF
---
topic: $topic
triggers: [$topic, ${topic}-alias]
summary: Test summary for $topic
---

## Knowledge

**[2026-01-01]** seed entry — for tests.
EOF
}

seed_min_tree() {
    # seed_min_tree <memdir> — identity + template + one domain + AUTOGEN index stub.
    local m="$1"
    mkdir -p "$m/domain" "$m/projects"
    printf '# Identity\n\nHard rules.\n' > "$m/identity.md"
    seed_template "$m"
    seed_domain "$m" "terraform"
    printf '# Index\n\n<!-- BEGIN AUTOGEN -->\n<!-- END AUTOGEN -->\n' > "$m/index.md"
}
