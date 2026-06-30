#!/usr/bin/env bash
# apply-partial.sh (#5 partial inject/sync) + skill-ratings.sh (#6 aggregation).
. "$(dirname "$0")/_assert.sh"

AP="$SCRIPTS_DIR/apply-partial.sh"
SR="$SCRIPTS_DIR/skill-ratings.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"

seed_skill() { # <name> <tier>
    mkdir -p "$MEM/skills/$1"
    printf -- '---\nname: %s\ndescription: seed skill for tests.\nmetadata:\n  tier: %s\n---\n# %s\nbody.\n' "$1" "$2" "$1" > "$MEM/skills/$1/SKILL.md"
}

run() { set +e; out=$(bash "$@" 2>&1); code=$?; set -e; }

seed_skill renovate-manager target-read-only
seed_skill observability-check target-read-only
seed_skill fiter-infrastructure-analyzer target-write
seed_skill brainstorming target-read-only
seed_skill teach target-read-only

# === apply-partial (marker-derived membership) =============================
# First injection is an explicit act -> refused without --force, file untouched.
cp "$MEM/skills/brainstorming/SKILL.md" "$MEM/bs-before"
run "$AP" --skill brainstorming
assert_exit 1 "$code" "first injection without --force is refused"
assert_contains "$out" "requires --force" "refusal points at --force"
set +e; cmp -s "$MEM/bs-before" "$MEM/skills/brainstorming/SKILL.md"; un=$?; set -e
assert_exit 0 "$un" "refused skill left untouched"

# First injection with --force applies.
run "$AP" --skill brainstorming --force
assert_exit 0 "$code" "first injection with --force applies"
md="$(cat "$MEM/skills/brainstorming/SKILL.md")"
assert_contains "$md" "partial:self-rating START" "START marker injected"
assert_contains "$md" "partial:self-rating END" "END marker injected"
assert_contains "$md" "Self-rating (first-party)" "block body injected"
assert_contains "$md" "only when the user asks" "block carries the on-request rule"
assert_contains "$out" "applied: self-rating" "reports applied"

# Re-sync needs NO flag once the block is present, and is idempotent.
cp "$MEM/skills/brainstorming/SKILL.md" "$MEM/before"
run "$AP" --skill brainstorming
assert_exit 0 "$code" "re-sync without --force succeeds (block present)"
set +e; cmp -s "$MEM/before" "$MEM/skills/brainstorming/SKILL.md"; ident=$?; set -e
assert_exit 0 "$ident" "re-sync is idempotent (byte-identical)"
n_start=$(grep -c 'partial:self-rating START' "$MEM/skills/brainstorming/SKILL.md")
assert_eq "1" "$n_start" "no duplicate marker blocks"

# Membership is marker-derived, not name-based: ANY skill can enter via --force.
run "$AP" --skill teach --force
assert_exit 0 "$code" "--force injects into any skill (membership = marker)"
assert_contains "$(cat "$MEM/skills/teach/SKILL.md")" "partial:self-rating START" "forced block injected"

# --all re-syncs every carrier, and ONLY carriers.
seed_skill observability-check target-read-only   # reset -> a non-carrier
run "$AP" --all
assert_exit 0 "$code" "--all re-syncs carriers"
assert_contains "$(cat "$MEM/skills/brainstorming/SKILL.md")" "partial:self-rating START" "--all kept carrier brainstorming"
assert_contains "$(cat "$MEM/skills/teach/SKILL.md")" "partial:self-rating START" "--all kept carrier teach"
assert_not_contains "$(cat "$MEM/skills/observability-check/SKILL.md")" "partial:self-rating START" "--all skipped the non-carrier"

# guards
run "$AP" --skill ../evil --force
assert_exit 2 "$code" "rejects a bad skill name"
run "$AP" --skill nope --force
assert_exit 2 "$code" "missing skill -> exit 2"
run "$AP" --skill brainstorming --partial does-not-exist
assert_exit 2 "$code" "missing partial source -> exit 2"
run "$AP"
assert_exit 2 "$code" "no --skill / --all -> exit 2"

# === skill-ratings ==========================================================
# empty store (no logs) -> friendly message, exit 0
run "$SR"
assert_exit 0 "$code" "aggregator runs with no ratings"
assert_contains "$out" "no ratings recorded yet" "reports empty"

# seed two logs
printf '## d1\n- score: 4\n- friction: x\n- improve: name the path\n## d2\n- score: 2\n- friction: y\n- improve: add a row\n' \
    > "$MEM/skills/renovate-manager/self-rating.md"
printf '## d1\n- score: 5\n- improve: none\n' \
    > "$MEM/skills/observability-check/self-rating.md"

run "$SR"
assert_exit 0 "$code" "aggregator runs with ratings"
line_rm="$(printf '%s\n' "$out" | awk '$1=="renovate-manager"')"
assert_contains "$line_rm" " 2 " "renovate-manager N=2"
assert_contains "$line_rm" "3.0" "renovate-manager avg=3.0 (period decimal, not locale comma)"
assert_contains "$line_rm" "add a row" "latest improve note shown"
line_oc="$(printf '%s\n' "$out" | awk '$1=="observability-check"')"
assert_contains "$line_oc" "5.0" "single-entry avg=5.0"

# a log with no parseable score is skipped (without --all)
printf '## notes\njust prose, no score line\n' > "$MEM/skills/brainstorming/self-rating.md"
run "$SR"
assert_not_contains "$out" "brainstorming " "scoreless log skipped in default view"

# a carrier whose ONLY scores are out-of-range is treated as unrated, not vanished
seed_skill outofrange target-read-only
run "$AP" --skill outofrange --force >/dev/null
printf '## bad\n- score: 99\n- improve: x\n' > "$MEM/skills/outofrange/self-rating.md"
run "$SR"
assert_not_contains "$out" "outofrange " "out-of-range-only log skipped in default view"
run "$SR" --all
assert_contains "$out" "outofrange" "out-of-range-only carrier still surfaces as unrated in --all"

# --all surfaces first-party skills with no ratings
run "$SR" --all
assert_exit 0 "$code" "--all runs"
assert_contains "$out" "no ratings yet" "--all lists in-loop skills (carrying the block) with no ratings"

finish
