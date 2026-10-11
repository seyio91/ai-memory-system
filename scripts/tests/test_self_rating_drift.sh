#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"

# Every tracked skill carrying the self-rating block must match scripts/partials/self-rating.md
# byte for byte; an edit to the partial without `apply-partial.sh --all` must fail here.
REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
PARTIAL="$REPO/scripts/partials/self-rating.md"
START='<!-- partial:self-rating START'
END='<!-- partial:self-rating END -->'

carriers=""
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    carriers="$(git -C "$REPO" ls-files --cached --others --exclude-standard 'skills/*/SKILL.md' | while read -r f; do
        grep -Fq "$START" "$REPO/$f" && printf '%s\n' "$f"
    done)"
fi
[ -n "$carriers" ] || carriers="$(cd "$REPO" && grep -lF "$START" skills/design-brainstorm/SKILL.md skills/skill-audit/SKILL.md)"
assert_contains "$carriers" "skills/design-brainstorm/SKILL.md" "design-brainstorm is a self-rating carrier"
assert_contains "$carriers" "skills/skill-audit/SKILL.md" "skill-audit is a self-rating carrier"

for f in $carriers; do
    assert_contains "$(cat "$REPO/$f")" "$END" "$f closes the self-rating block"
    block="$(awk -v s="$START" -v e="$END" 'index($0, s) == 1 {inblk=1; next} $0 == e {inblk=0} inblk' "$REPO/$f")"
    assert_eq "$(cat "$PARTIAL")" "$block" "$f self-rating block matches scripts/partials/self-rating.md"
done

finish
