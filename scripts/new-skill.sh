#!/usr/bin/env bash
# new-skill.sh — scaffold a NEW skill to the memory-system schema (#12).
# Writes skills/<name>/SKILL.md with the required frontmatter (name, description,
# metadata.tier, metadata.compatibility), then validates it. A skill may write
# its own skills/<name>/ folder at any time, regardless of tier.
#
# Usage:
#   new-skill.sh --name <name> --tier target-read-only|target-write \
#       [--description <text>] [--kind workflow|reference] \
#       [--compat <csv>] [--link] [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

NAME="" TIER="" DESC="" KIND="" COMPAT="claude-code, codex-cli" LINK=0 FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --name)        NAME="${2:-}"; shift 2 ;;
        --tier)        TIER="${2:-}"; shift 2 ;;
        --description) DESC="${2:-}"; shift 2 ;;
        --kind)        KIND="${2:-}"; shift 2 ;;
        --compat)      COMPAT="${2:-}"; shift 2 ;;
        --link)        LINK=1; shift ;;
        --force)       FORCE=1; shift ;;
        -h|--help)     sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'new-skill: unknown arg: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[ -n "$NAME" ] || { printf 'new-skill: --name required\n' >&2; exit 2; }
case "$NAME" in *[!A-Za-z0-9._-]*|.|..) printf 'new-skill: invalid name (allowed: A-Za-z0-9._-; not . or ..)\n' >&2; exit 2 ;; esac
case "$TIER" in target-read-only|target-write) : ;; *) printf 'new-skill: --tier must be target-read-only | target-write\n' >&2; exit 2 ;; esac
if [ -n "$KIND" ]; then
    case "$KIND" in workflow|reference) : ;; *) printf 'new-skill: --kind must be workflow | reference\n' >&2; exit 2 ;; esac
fi
[ -n "$DESC" ] || DESC="TODO: one-line description + trigger phrases (what this skill does and when to use it)."

TARGET="$MEMORY_DIR/skills/$NAME"
if [ -e "$TARGET" ] && [ "$FORCE" != 1 ]; then
    printf 'new-skill: %s already exists (use --force to overwrite)\n' "$TARGET" >&2; exit 1
fi
[ -e "$TARGET" ] && [ "$FORCE" = 1 ] && rm -rf "$TARGET"   # clean stale aux files
mkdir -p "$TARGET"

{
    printf -- '---\n'
    printf 'name: %s\n' "$NAME"
    printf 'description: %s\n' "$DESC"
    printf 'metadata:\n'
    printf '  tier: %s\n' "$TIER"
    [ -n "$KIND" ] && printf '  kind: %s\n' "$KIND"
    printf '  compatibility: %s\n' "$COMPAT"
    printf -- '---\n\n'
    printf '# %s\n\n' "$NAME"
    printf 'TODO: the instruction set. Brief a skilled colleague — what to do, in what\n'
    printf 'order, and what to produce. '
    if [ "$TIER" = target-read-only ]; then
        printf 'This skill MUST NOT modify the target it\noperates on; write any output (notes, reviews, self-rating) to its own folder\n(skills/%s/), never to the target repo or the system memory tree.\n' "$NAME"
    else
        printf 'This skill may modify the target it operates\non.\n'
    fi
} > "$TARGET/SKILL.md"

echo "created: $TARGET/SKILL.md"

# Validate just this skill (store-wide check may surface unrelated skills).
# Match by exact field (a name may contain '.', a regex metachar).
vout="$(bash "$SCRIPT_DIR/validate-skills.sh" 2>&1 || true)"
verr="$(printf '%s\n' "$vout" | awk -v n="$NAME" '$1=="ERROR:" && $2==n')"
if [ -n "$verr" ]; then
    printf '%s\n' "$verr" >&2
    printf 'new-skill: validation failed for %s\n' "$NAME" >&2
    exit 1
fi
echo "validated: $NAME OK"

if [ "$LINK" = 1 ]; then
    bash "$SCRIPT_DIR/link-skills.sh" >/dev/null && echo "linked: $NAME -> ~/.claude/skills"
fi

printf 'next: fill in SKILL.md (description + instructions) at %s\n' "$TARGET/SKILL.md"
