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
    git -C "$REPO" check-ignore --no-index skills/skill-audit/SKILL.md >/dev/null 2>&1
    audit_md_rc=$?
    git -C "$REPO" check-ignore --no-index skills/skill-audit/scripts/lint_skill.py >/dev/null 2>&1
    audit_py_rc=$?
    git -C "$REPO" check-ignore --no-index skills/skill-audit/scripts/__pycache__/lint_skill.cpython-39.pyc >/dev/null 2>&1
    audit_pyc_rc=$?
    git -C "$REPO" check-ignore --no-index skills/skill-audit/evals/.DS_Store >/dev/null 2>&1
    dsstore_rc=$?
    git -C "$REPO" check-ignore --no-index skills/design-brainstorm/self-rating.md >/dev/null 2>&1
    rating_rc=$?
    set -e
    assert_exit 1 "$brain_rc" "skills/design-brainstorm/SKILL.md is not ignored"
    assert_exit 1 "$audit_md_rc" "skills/skill-audit/SKILL.md is not ignored"
    assert_exit 1 "$audit_py_rc" "skills/skill-audit/scripts/lint_skill.py is not ignored"
    assert_exit 0 "$audit_pyc_rc" "skill-audit __pycache__ output stays ignored"
    assert_exit 0 "$dsstore_rc" "Finder .DS_Store inside a tracked skill stays ignored"
    assert_exit 0 "$rating_rc" "per-instance self-rating.md inside a tracked skill stays ignored"
    assert_exit 0 "$other_rc" "other per-instance skills stay ignored"
else
    printf '  SKIP git absent; skill gitignore tracking checks not run\n'
fi

assert_file "$REPO/skills/design-brainstorm/SKILL.md" "design-brainstorm skill ships in skills/"
assert_file "$REPO/skills/skill-audit/SKILL.md" "skill-audit skill ships in skills/"
assert_not_contains "$(cat "$REPO/templates/skills.toml.example")" "design-brainstorm" \
    "templates/skills.toml.example has no design-brainstorm remote entry"

finish
