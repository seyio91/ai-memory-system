#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"

if command -v git >/dev/null 2>&1; then
    set +e
    git -C "$REPO" check-ignore skills/brainstorming/SKILL.md >/dev/null 2>&1
    brain_rc=$?
    git -C "$REPO" check-ignore skills/somethingelse/SKILL.md >/dev/null 2>&1
    other_rc=$?
    set -e
    assert_exit 1 "$brain_rc" "skills/brainstorming/SKILL.md is not ignored"
    assert_exit 0 "$other_rc" "other per-instance skills stay ignored"
else
    printf '  SKIP git absent; skill gitignore tracking checks not run\n'
fi

assert_file "$REPO/skills/brainstorming/SKILL.md" "brainstorming skill ships in skills/"
assert_not_contains "$(cat "$REPO/skills.toml.example")" "brainstorming" \
    "skills.toml.example has no brainstorming remote entry"

finish
