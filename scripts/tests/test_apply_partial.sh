#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"

AP="$SCRIPTS_DIR/apply-partial.sh"
MEM="$(new_sandbox)"
OUTSIDE="$(dirname "$MEM")/apply-partial-outside-$$"
trap 'rm -rf "$MEM" "$OUTSIDE"' EXIT
export MEMORY_DIR="$MEM"

TARGET="$MEM/commands/carrier.md"
mkdir -p "$MEM/commands"
mkdir -p "$OUTSIDE"
printf '# Carrier\n' > "$TARGET"
printf '# Outside\n' > "$OUTSIDE/outside.md"

run() { set +e; out=$(bash "$@" 2>&1); code=$?; set -e; }

cp "$TARGET" "$MEM/before"
run "$AP" --file "$TARGET"
assert_exit 1 "$code" "fresh --file requires --force"
set +e; cmp -s "$MEM/before" "$TARGET"; unchanged=$?; set -e
assert_exit 0 "$unchanged" "refused --file leaves target untouched"

run "$AP" --file "$TARGET" --force
assert_exit 0 "$code" "--file injects with --force"
assert_contains "$(cat "$TARGET")" "partial:self-rating START" "--file injected START marker"
assert_contains "$out" "commands/carrier.md" "--file reports carrier path"

cp "$TARGET" "$MEM/after-first"
run "$AP" --file "$TARGET"
assert_exit 0 "$code" "existing --file re-sync succeeds without --force"
set +e; cmp -s "$MEM/after-first" "$TARGET"; identical=$?; set -e
assert_exit 0 "$identical" "second --file run is byte-identical"

run "$AP" --skill fake --file "$TARGET"
assert_exit 2 "$code" "--skill and --file are mutually exclusive"

run "$AP" --file "$OUTSIDE/outside.md" --force
assert_exit 2 "$code" "outside --file path is refused"

run "$AP" --file "$MEM/commands/../../$(basename "$OUTSIDE")/outside.md" --force
assert_exit 2 "$code" "traversal outside --file path is refused"

ln -s "$OUTSIDE" "$MEM/outside-link"
run "$AP" --file "$MEM/outside-link/outside.md" --force
assert_exit 2 "$code" "symlinked outside --file path is refused"

run "$AP" --all
assert_exit 0 "$code" "--all re-syncs command carrier"
assert_contains "$out" "commands/carrier.md" "--all finds command carrier"

ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
TASK_LINK="$SCRIPTS_DIR/partials/task-link.md"
TASK_START="<!-- partial:task-link START (managed by scripts/apply-partial.sh — edit scripts/partials/task-link.md) -->"
TASK_END="<!-- partial:task-link END -->"
TASK_BLOCK="$(mktemp 2>/dev/null || mktemp -t task-link-block)"
trap 'rm -rf "$MEM" "$OUTSIDE" "$TASK_BLOCK"' EXIT

extract_task_link() {
    awk -v start="$TASK_START" -v end="$TASK_END" '
        $0 == start {
            if (found || in_block) exit 1
            found = 1
            in_block = 1
            next
        }
        in_block && $0 == end {
            in_block = 0
            closed = 1
            next
        }
        in_block { print; next }
        END { if (!found || !closed || in_block) exit 1 }
    ' "$1" > "$2"
}

set +e
task_carriers="$(grep -l -F "$TASK_START" "$ROOT"/commands/*.md)"
code=$?
set -e
assert_exit 0 "$code" "task-link carriers discovered by START marker"

task_carrier_count="$(printf '%s\n' "$task_carriers" | awk 'NF { count++ } END { print count + 0 }')"
# The literal 2 is load-bearing: marker discovery fails OPEN on deletion (a carrier
# that lost its block just drops out of the list). Bump it when adding a carrier;
# do not make it dynamic, or block-loss stops being detected at all.
assert_eq "2" "$task_carrier_count" "both task-link command carriers remain present"

while IFS= read -r carrier; do
    [ -n "$carrier" ] || continue
    set +e
    extract_task_link "$carrier" "$TASK_BLOCK"
    code=$?
    set -e
    assert_exit 0 "$code" "$(basename "$carrier") task-link block extracts"

    set +e
    cmp -s "$TASK_LINK" "$TASK_BLOCK"
    code=$?
    set -e
    assert_exit 0 "$code" "$(basename "$carrier") task-link block matches source bytes"
done <<EOF
$task_carriers
EOF


TWO="$MEM/commands/two.md"
printf '# Two\n' > "$TWO"
run "$AP" --file "$TWO" --partial task-link --force
assert_exit 0 "$code" "two-partial carrier: task-link injects"
run "$AP" --file "$TWO" --partial plan-scaffold --force
assert_exit 0 "$code" "two-partial carrier: plan-scaffold injects"
cp "$TWO" "$MEM/two-before"
for order in "task-link plan-scaffold" "plan-scaffold task-link"; do
    for part in $order; do
        run "$AP" --file "$TWO" --partial "$part"
        assert_exit 0 "$code" "two-partial carrier: re-sync $part"
    done
    set +e; cmp -s "$MEM/two-before" "$TWO"; identical=$?; set -e
    assert_exit 0 "$identical" "two-partial carrier byte-identical after re-sync ($order)"
done
first_marker="$(grep -o -E 'partial:(task-link|plan-scaffold) START' "$TWO" | head -1)"
assert_eq "partial:task-link START" "$first_marker" "re-sync keeps task-link block ahead of plan-scaffold"

BROKEN="$MEM/commands/broken.md"
grep -F 'partial:task-link START' "$TWO" | head -1 > "$MEM/start-line"
{ printf '# Broken\n'; cat "$MEM/start-line"; printf 'stale\n\n## Keep\n'; } > "$BROKEN"
cp "$BROKEN" "$MEM/broken-before"
run "$AP" --file "$BROKEN" --partial task-link
assert_exit 1 "$code" "START without END refuses re-sync"
set +e; cmp -s "$MEM/broken-before" "$BROKEN"; unchanged=$?; set -e
assert_exit 0 "$unchanged" "START without END leaves carrier untouched"

{ printf '# Dup\n'; cat "$MEM/start-line"; printf 'PRECIOUS\n'; cat "$MEM/start-line"; printf 'old\n'; grep -F 'partial:task-link END' "$TWO" | head -1; printf '## tail\n'; } > "$BROKEN"
cp "$BROKEN" "$MEM/broken-before"
run "$AP" --file "$BROKEN" --partial task-link
assert_exit 1 "$code" "duplicate START refuses re-sync"
set +e; cmp -s "$MEM/broken-before" "$BROKEN"; unchanged=$?; set -e
assert_exit 0 "$unchanged" "duplicate START leaves carrier untouched"

PLAN_SCAFFOLD="$SCRIPTS_DIR/partials/plan-scaffold.md"
PLAN_START="<!-- partial:plan-scaffold START (managed by scripts/apply-partial.sh — edit scripts/partials/plan-scaffold.md) -->"
PLAN_END="<!-- partial:plan-scaffold END -->"
PLAN_BLOCK="$(mktemp 2>/dev/null || mktemp -t plan-scaffold-block)"
trap 'rm -rf "$MEM" "$OUTSIDE" "$TASK_BLOCK" "$PLAN_BLOCK"' EXIT

set +e
plan_carriers="$(grep -l -F "$PLAN_START" "$ROOT"/commands/*.md)"
code=$?
set -e
assert_exit 0 "$code" "plan-scaffold carriers discovered by START marker"

plan_carrier_count="$(printf '%s\n' "$plan_carriers" | awk 'NF { count++ } END { print count + 0 }')"
# Literal 2, same reasoning as the task-link count above: never make it dynamic.
assert_eq "2" "$plan_carrier_count" "both plan-scaffold command carriers remain present"

while IFS= read -r carrier; do
    [ -n "$carrier" ] || continue
    set +e
    awk -v start="$PLAN_START" -v end="$PLAN_END" '
        $0 == start { if (found || in_block) exit 1; found = 1; in_block = 1; next }
        in_block && $0 == end { in_block = 0; closed = 1; next }
        in_block { print; next }
        END { if (!found || !closed || in_block) exit 1 }
    ' "$carrier" > "$PLAN_BLOCK"
    code=$?
    set -e
    assert_exit 0 "$code" "$(basename "$carrier") plan-scaffold block extracts"

    set +e
    cmp -s "$PLAN_SCAFFOLD" "$PLAN_BLOCK"
    code=$?
    set -e
    assert_exit 0 "$code" "$(basename "$carrier") plan-scaffold block matches source bytes"
done <<EOF
$plan_carriers
EOF

PF_SRC="$SCRIPTS_DIR/partials/plan-feasibility.md"
PF_START="<!-- partial:plan-feasibility START (managed by scripts/apply-partial.sh — edit scripts/partials/plan-feasibility.md) -->"
PF_END="<!-- partial:plan-feasibility END -->"
PF_BLOCK="$(mktemp 2>/dev/null || mktemp -t plan-feasibility-block)"
trap 'rm -rf "$MEM" "$OUTSIDE" "$TASK_BLOCK" "$PLAN_BLOCK" "$PF_BLOCK"' EXIT

set +e
pf_carriers="$(grep -l -F "$PF_START" "$ROOT"/commands/*.md)"
code=$?
set -e
assert_exit 0 "$code" "plan-feasibility carriers discovered by START marker"

pf_carrier_count="$(printf '%s\n' "$pf_carriers" | awk 'NF { count++ } END { print count + 0 }')"
# Literal 2, same reasoning as the task-link count above: never make it dynamic.
assert_eq "2" "$pf_carrier_count" "both plan-feasibility command carriers remain present"

while IFS= read -r carrier; do
    [ -n "$carrier" ] || continue
    set +e
    awk -v start="$PF_START" -v end="$PF_END" '
        $0 == start { if (found || in_block) exit 1; found = 1; in_block = 1; next }
        in_block && $0 == end { in_block = 0; closed = 1; next }
        in_block { print; next }
        END { if (!found || !closed || in_block) exit 1 }
    ' "$carrier" > "$PF_BLOCK"
    code=$?
    set -e
    assert_exit 0 "$code" "$(basename "$carrier") plan-feasibility block extracts"

    set +e
    cmp -s "$PF_SRC" "$PF_BLOCK"
    code=$?
    set -e
    assert_exit 0 "$code" "$(basename "$carrier") plan-feasibility block matches source bytes"
done <<EOF2
$pf_carriers
EOF2

finish
