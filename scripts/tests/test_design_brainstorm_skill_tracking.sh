#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"

if command -v git >/dev/null 2>&1; then
    set +e
    # --no-index is load-bearing: plain `check-ignore` short-circuits on TRACKED
    # paths and returns "not ignored" without consulting .gitignore at all. Since
    # this file is always tracked, the assertion below passed for free — breaking
    # the `!/skills/design-brainstorm/` negation did not fail it (mutation-tested
    # 2026-09-08). --no-index evaluates the rules, so the control can actually fail.
    git -C "$REPO" check-ignore --no-index skills/design-brainstorm/SKILL.md >/dev/null 2>&1
    brain_rc=$?
    git -C "$REPO" check-ignore --no-index skills/somethingelse/SKILL.md >/dev/null 2>&1
    other_rc=$?
    set -e
    assert_exit 1 "$brain_rc" "skills/design-brainstorm/SKILL.md is not ignored"
    assert_exit 0 "$other_rc" "other per-instance skills stay ignored"
else
    printf '  SKIP git absent; skill gitignore tracking checks not run\n'
fi

assert_file "$REPO/skills/design-brainstorm/SKILL.md" "design-brainstorm skill ships in skills/"
assert_not_contains "$(cat "$REPO/templates/skills.toml.example")" "design-brainstorm" \
    "templates/skills.toml.example has no design-brainstorm remote entry"

finish
