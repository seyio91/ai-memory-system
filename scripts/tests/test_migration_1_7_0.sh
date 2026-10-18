#!/usr/bin/env bash
# Sandbox test for migrations/1.7.0-decision-status-field.sh. MIGRATION_1_7_0
# points the test at a mutated copy for mutation proofs.
. "$(dirname "$0")/_assert.sh"
set -euo pipefail

REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
MIG="${MIGRATION_1_7_0:-$REPO_ROOT/migrations/1.7.0-decision-status-field.sh}"
ROOT="$(new_sandbox)"
trap 'rm -rf "$ROOT"' EXIT

M="$ROOT/mem"
mkdir -p "$M/initiatives/archive" "$M/initiatives/.state"

assert_same() { if cmp -s "$1" "$2"; then _ok "$3"; else _bad "$3"; fi; }
run_mig() { MEMORY_DIR="$M" REPO_ROOT="$REPO_ROOT" bash "$MIG"; }

cat > "$M/initiatives/fix.md" <<'IN'
---
kind: initiative
slug: fix
status: active
created: 2026-08-01
---

# Fix

## Decision Stream

- D1: bare becomes confirmed.
  evidence: continuation stays
- D2-proposed: proposed suffix.
- D3-rejected: rejected suffix.
- D4-proposed (2026-09-10): dated proposal.
- D5-proposed *(raised by `x`, 2026-08-15)*: starred qualifier.
- D6 (settled 2026-08-30, closed 2026-09-10): paren qualifier on bare id.
- D7-proposed (2026-09-12) *(original)*: date and qualifier.
- D8a: lettered bare.
- D9 shipped 2026-09-18 — shipped becomes confirmed.
- D10 confirmed [2026-09-23] — bracketed date.
- D11 proposed [2026-09-25; via D12] — bracket with semicolon text.
- D12 confirmed [2026-10-01, user said so] — bracket with comma text.
- D13 confirmed 2026-09-20 — already field shaped.
- D14 proposed — undated field shaped.
- D15 confirmed/proposed — mixed value.
- D16 confirmed 2026-09-21 / proposed — mixed with date.
- D17-superseded: unknown suffix.
- D18-proposed no colon here
- D19-proposed:
- D20 Evidence: not a head status
- D22-proposed (2026-09-01) *(original)*: twin original.
- D22: twin confirmed.
- D23-proposed: only a lettered sibling.
- D23a: lettered confirmed.
Prose line mentioning D2-proposed and [2026-01-01] stays.

```
- D30: inside a fence stays
## Decision stream
```

- D21: after fence still in stream.

## Other

- D40: outside the stream stays.
IN

cp "$M/initiatives/fix.md" "$ROOT/fix.orig"
cp "$M/initiatives/fix.md" "$M/initiatives/_template.md"
cp "$M/initiatives/fix.md" "$M/initiatives/archive/old.md"
cp "$M/initiatives/fix.md" "$M/initiatives/.state/s.md"
sed 's/kind: initiative/kind: note/' "$ROOT/fix.orig" > "$M/initiatives/notinit.md"
cp "$M/initiatives/notinit.md" "$ROOT/notinit.orig"

out="$(run_mig)"
got="$M/initiatives/fix.md"

head_of() { grep -F -- "$1" "$got" | head -n 1; }
assert_eq "- D1 confirmed — bare becomes confirmed." "$(head_of '- D1 ')" "bare D<n>: -> confirmed"
assert_contains "$(cat "$got")" $'confirmed — bare becomes confirmed.\n  evidence: continuation stays' "continuation line untouched"
assert_eq "- D2 proposed — proposed suffix." "$(head_of '- D2 ')" "-proposed -> proposed"
assert_eq "- D3 rejected — rejected suffix." "$(head_of '- D3 ')" "-rejected -> rejected"
assert_eq "- D4 proposed 2026-09-10 — dated proposal." "$(head_of '- D4 ')" "parenthesised date carried bare"
assert_eq "- D5 proposed — (raised by \`x\`, 2026-08-15) starred qualifier." "$(head_of '- D5 ')" "*(qualifier)* moved after dash"
assert_eq "- D6 confirmed — (settled 2026-08-30, closed 2026-09-10) paren qualifier on bare id." "$(head_of '- D6 ')" "D<n> (qualifier): -> confirmed + moved qualifier"
assert_eq "- D7 proposed 2026-09-12 — (original) date and qualifier." "$(head_of '- D7 ')" "date plus qualifier"
assert_eq "- D22 superseded 2026-09-01 — (original) twin original." "$(head_of '- D22 superseded')" "-proposed with bare twin -> superseded"
assert_eq "- D22 confirmed — twin confirmed." "$(head_of '- D22 confirmed')" "bare twin -> confirmed"
assert_eq "- D23 proposed — only a lettered sibling." "$(head_of '- D23 ')" "-proposed with only lettered sibling stays proposed"
assert_eq "- D8a confirmed — lettered bare." "$(head_of '- D8a ')" "lettered id migrated"
assert_eq "- D9 confirmed 2026-09-18 — shipped becomes confirmed." "$(head_of '- D9 ')" "shipped -> confirmed"
assert_eq "- D10 confirmed 2026-09-23 — bracketed date." "$(head_of '- D10 ')" "[date] -> date"
assert_eq "- D11 proposed 2026-09-25 — (via D12) bracket with semicolon text." "$(head_of '- D11 ')" "[date; text] -> date, text after dash"
assert_eq "- D12 confirmed 2026-10-01 — (user said so) bracket with comma text." "$(head_of '- D12 ')" "[date, text] -> date, text after dash"
assert_eq "- D13 confirmed 2026-09-20 — already field shaped." "$(head_of '- D13 ')" "field-shaped dated entry untouched"
assert_eq "- D14 proposed — undated field shaped." "$(head_of '- D14 ')" "field-shaped undated entry untouched"

for pair in \
    '- D15 confirmed/proposed — mixed value.' \
    '- D16 confirmed 2026-09-21 / proposed — mixed with date.' \
    '- D17-superseded: unknown suffix.' \
    '- D18-proposed no colon here' \
    '- D19-proposed:' \
    '- D20 Evidence: not a head status'; do
    assert_contains "$(cat "$got")"$'\n' "$pair"$'\n' "unrecognised head byte-identical: ${pair%% —*}"
done
assert_contains "$out" "fix.md:" "unrecognised heads are reported with file"
for id in D15 D16 D17 D18 D19 D20; do
    assert_contains "$out" "- $id" "report names $id"
done
assert_not_contains "$out" "- D13 " "valid entries not reported"

assert_contains "$(cat "$got")" $'\nProse line mentioning D2-proposed and [2026-01-01] stays.\n' "prose line outside entry heads untouched"
assert_contains "$(cat "$got")" $'- D30: inside a fence stays\n' "fenced entry untouched"
assert_contains "$(cat "$got")" $'- D21 confirmed — after fence still in stream.' "stream continues after fence"
assert_contains "$(cat "$got")" $'- D40: outside the stream stays.' "entry outside the stream untouched"
assert_eq "legacy_through: D23" "$(grep '^legacy_through:' "$got")" "legacy_through = max plain id in the stream (fence/outside ignored)"
assert_eq "kind: initiative|slug: fix|status: active|created: 2026-08-01|legacy_through: D23|---" \
    "$(sed -n '2,7p' "$got" | tr '\n' '|' | sed 's/|$//')" "legacy_through inserted before closing frontmatter fence"
assert_contains "$out" "fix.md: 17 head(s) rewritten, legacy_through: D23" "summary line per changed file"

assert_same "$ROOT/fix.orig" "$M/initiatives/_template.md" "_template.md untouched"
assert_same "$ROOT/fix.orig" "$M/initiatives/archive/old.md" "archive/ untouched"
assert_same "$ROOT/fix.orig" "$M/initiatives/.state/s.md" ".state/ untouched"
assert_same "$ROOT/notinit.orig" "$M/initiatives/notinit.md" "non-initiative kind untouched"

# line count preserved except the frontmatter insertion; body diff is heads only
chg="$(diff "$ROOT/fix.orig" "$got" | grep -c '^>' || true)"
assert_eq "18" "$chg" "17 heads + 1 frontmatter line changed, nothing else"

# idempotency
cp "$got" "$ROOT/after1"
out2="$(run_mig)"
assert_same "$ROOT/after1" "$got" "second run: byte-identical"
assert_not_contains "$out2" "head(s) rewritten" "second run reports no rewrite"

# existing legacy_through is kept
mkdir -p "$ROOT/m2/initiatives"
printf -- '---\nkind: initiative\nslug: a\nstatus: active\ncreated: 2026-01-01\nlegacy_through: D1\n---\n\n## Decision stream\n\n- D1: x\n- D2: y\n' > "$ROOT/m2/initiatives/a.md"
MEMORY_DIR="$ROOT/m2" REPO_ROOT="$REPO_ROOT" bash "$MIG" >/dev/null
assert_eq "1" "$(grep -c '^legacy_through:' "$ROOT/m2/initiatives/a.md")" "existing legacy_through not duplicated"
assert_eq "legacy_through: D1" "$(grep '^legacy_through:' "$ROOT/m2/initiatives/a.md")" "existing legacy_through value kept"
assert_contains "$(cat "$ROOT/m2/initiatives/a.md")" "- D2 confirmed — y" "heads still migrated when legacy_through present"

# CRLF preserved; missing trailing newline preserved
mkdir -p "$ROOT/m3/initiatives"
printf -- '---\r\nkind: initiative\r\nslug: c\r\nstatus: active\r\ncreated: 2026-01-01\r\n---\r\n\r\n## DECISION STREAM\r\n\r\n- D1-proposed (2026-02-02): x\r\n  evidence: y\r\n- D2: z' > "$ROOT/m3/initiatives/c.md"
MEMORY_DIR="$ROOT/m3" REPO_ROOT="$REPO_ROOT" bash "$MIG" >/dev/null
printf -- '---\r\nkind: initiative\r\nslug: c\r\nstatus: active\r\ncreated: 2026-01-01\r\nlegacy_through: D2\r\n---\r\n\r\n## DECISION STREAM\r\n\r\n- D1 proposed 2026-02-02 — x\r\n  evidence: y\r\n- D2 confirmed — z' > "$ROOT/c.expected"
assert_same "$ROOT/c.expected" "$ROOT/m3/initiatives/c.md" "CRLF, case-insensitive heading and missing final newline preserved"

# no initiatives dir: silent no-op
mkdir -p "$ROOT/m4"
MEMORY_DIR="$ROOT/m4" REPO_ROOT="$REPO_ROOT" bash "$MIG" >/dev/null
assert_exit 0 "$?" "no initiatives/ dir exits 0"

finish
