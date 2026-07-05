#!/usr/bin/env bash
# link-command-skills.sh — deliver slash-command bodies AS skills, for a harness
# whose custom-command mechanism IS skills (Codex: prompts deprecated, skills are
# the command surface). Each canonical command <name>.md (a bare prompt body) is
# wrapped into <target>/<name>/SKILL.md with synthesized frontmatter (name +
# description-from-first-line + tier), unifying commands and skills into one
# skills_dir. The `commands=skill` case of the Phase-4 command surface.
#
#   link-command-skills.sh <commands-src> [target-skills-dir] [--dry-run]
#
# Generated dirs carry a .from-command marker so re-runs refresh them and never
# clobber a canonical (symlinked) skill or a foreign dir of the same name.
set -euo pipefail

SRC="${1:?usage: link-command-skills.sh <commands-src> [target] [--dry-run]}"
TARGET="${2:-$HOME/.agents/skills}"
DRY_RUN=0
case "${2:-}" in --dry-run) TARGET="$HOME/.agents/skills"; DRY_RUN=1 ;; esac
[ "${3:-}" = "--dry-run" ] && DRY_RUN=1

[ -d "$SRC" ] || { echo "link-command-skills: no commands source at $SRC" >&2; exit 1; }
[ "$DRY_RUN" = 1 ] || mkdir -p "$TARGET"

# YAML-escape for a double-quoted scalar (backslash + double-quote).
yq() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

gen=0 skip=0
for f in "$SRC"/*.md; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .md)"
    dst="$TARGET/$name"

    if [ -L "$dst" ]; then
        echo "WARN: '$name' already a linked skill — command-skill skipped" >&2; skip=$((skip+1)); continue
    fi
    if [ -d "$dst" ] && [ ! -f "$dst/.from-command" ]; then
        echo "WARN: '$name' exists (not command-generated) — leaving untouched" >&2; skip=$((skip+1)); continue
    fi

    desc="$(awk 'NF{print; exit}' "$f")"   # first non-empty line
    if [ "$DRY_RUN" = 1 ]; then echo "gen: $name"; gen=$((gen+1)); continue; fi

    mkdir -p "$dst"
    : > "$dst/.from-command"
    {
        printf -- '---\n'
        printf 'name: %s\n' "$name"
        printf 'description: "%s"\n' "$(yq "$desc")"
        printf 'metadata:\n  tier: target-write\n'
        printf -- '---\n\n'
        cat "$f"
    } > "$dst/SKILL.md"
    gen=$((gen+1))
done

tag=""; [ "$DRY_RUN" = 1 ] && tag=" [dry-run]"
echo "done: ${gen} command-skills generated, ${skip} skipped (target: $TARGET)${tag}"
