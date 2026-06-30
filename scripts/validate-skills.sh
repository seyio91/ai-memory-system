#!/usr/bin/env bash
#
# validate-skills.sh — static checks for the skills store. One finding per line:
#   ERROR: <skill> <reason>   (fails the run)
#   WARN:  <skill> <reason>   (advisory; does not fail)
#
# Exit 0 if no ERROR (warnings allowed), 1 if any ERROR, 2 on usage/setup error.
# Targets bash 3.2 (macOS): no associative arrays, no mapfile.
#
# Checks per skill dir under $SKILLS_DIR (default $MEMORY_DIR/skills):
#   1. SKILL.md exists
#   2. frontmatter present (opening + closing ---)
#   3. required fields present: name, description
#   4. metadata.tier present and valid (target-read-only | target-write)
#   5. size flag (WARN) when SKILL.md exceeds $SKILL_MAX_LINES (default 500)
#   6. no unresolved {{PLACEHOLDER}} scaffolding tokens (UPPERCASE only — lowercase
#      {{...}} is legitimate content, e.g. Grafana legendFormat "{{status_code}}")
#
# Usage: validate-skills.sh [--list]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

SKILLS_DIR="${SKILLS_DIR:-$MEMORY_DIR/skills}"
MAX_LINES="${SKILL_MAX_LINES:-500}"
VALID_TIERS="target-read-only target-write"
ERRORS=0

err()  { printf 'ERROR: %s\n' "$*"; ERRORS=$((ERRORS + 1)); }
warn() { printf 'WARN:  %s\n' "$*"; }

# fm_has_key — is <key> present as a frontmatter line (any value, inline or block)?
#   fm_has_key <key> <file>  -> prints "yes" if found
fm_has_key() {
    awk -v k="$1" '
        NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
        fm && /^---[[:space:]]*$/ { exit }
        fm && $0 ~ "^" k ":" { print "yes"; exit }
    ' "$2"
}

# fm_has_close — print "yes" if the frontmatter block is closed by a second ---.
fm_has_close() {
    awk '
        NR == 1 && /^---[[:space:]]*$/ { o = 1; next }
        o && /^---[[:space:]]*$/ { print "yes"; exit }
    ' "$1"
}

# fm_tier — pull metadata.tier (nested under the metadata: block) from frontmatter.
fm_tier() {
    awk '
        NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
        fm && /^---[[:space:]]*$/ { exit }
        fm && /^metadata:[[:space:]]*$/ { meta = 1; next }
        fm && meta && /^  tier:[[:space:]]*/ {
            v = $0
            sub(/^  tier:[[:space:]]*/, "", v)
            sub(/[[:space:]]+$/, "", v)
            print v
            exit
        }
        fm && /^[^[:space:]]/ { meta = 0 }
    ' "$1"
}

[ -d "$SKILLS_DIR" ] || { printf 'validate-skills: no skills dir at %s\n' "$SKILLS_DIR" >&2; exit 2; }

if [ "${1:-}" = "--list" ]; then
    for d in "$SKILLS_DIR"/*/; do
        [ -d "$d" ] || continue
        printf '%s\n' "$(basename "$d")"
    done
    exit 0
fi

count=0
for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    f="$d/SKILL.md"

    # 1. SKILL.md exists
    if [ ! -f "$f" ]; then
        err "$name missing SKILL.md"
        continue
    fi
    count=$((count + 1))

    # 2. frontmatter present (opening + closing)
    if ! head -1 "$f" | grep -q '^---[[:space:]]*$'; then
        err "$name SKILL.md has no opening frontmatter (---)"
        continue
    fi
    if [ -z "$(fm_has_close "$f")" ]; then
        err "$name frontmatter not closed (missing second ---)"
        continue
    fi

    # 3. required fields
    [ -n "$(fm_has_key name "$f")" ]        || err "$name missing frontmatter field: name"
    [ -n "$(fm_has_key description "$f")" ] || err "$name missing frontmatter field: description"

    # 4. metadata.tier present + valid
    tier="$(fm_tier "$f")"
    if [ -z "$tier" ]; then
        err "$name missing metadata.tier (want: target-read-only | target-write)"
    else
        case " $VALID_TIERS " in
            *" $tier "*) : ;;
            *) err "$name invalid metadata.tier: '$tier' (want: target-read-only | target-write)" ;;
        esac
    fi

    # 5. size flag (advisory)
    lines=$(wc -l < "$f" | tr -d '[:space:]')
    if [ "${lines:-0}" -gt "$MAX_LINES" ]; then
        warn "$name SKILL.md is $lines lines (> $MAX_LINES; consider splitting)"
    fi

    # 6. no unresolved scaffolding placeholders (UPPERCASE tokens only; lowercase
    #    {{...}} is legitimate content such as Grafana legend templating)
    if grep -q '{{[A-Z][A-Z0-9_]*}}' "$f"; then
        toks=$(grep -oE '\{\{[A-Z][A-Z0-9_]*\}\}' "$f" | sort -u | tr '\n' ' ')
        err "$name has unresolved placeholder(s): $toks"
    fi
done

if [ "$ERRORS" -gt 0 ]; then
    printf 'validate-skills: %d error(s) across %d skill(s)\n' "$ERRORS" "$count" >&2
    exit 1
fi
printf 'validate-skills: %d skill(s) OK\n' "$count"
exit 0
