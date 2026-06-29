#!/usr/bin/env bash
#
# link-skills.sh — symlink canonical skills from the memory system into an
# agent harness's skills directory. LLM/harness-agnostic: point it at any
# runtime's skills dir and every skill in memory/skills/ gets linked in.
#
# Canonical store (source of truth): ~/.claude-memory/skills/
# Each entry is a skill dir containing a SKILL.md.
#
# Usage:
#   link-skills.sh [TARGET_DIR]        # default: ~/.claude/skills
#   link-skills.sh --list              # list canonical skills and exit
#   link-skills.sh --dry-run [TARGET]  # show what would change, do nothing
#
# Examples:
#   link-skills.sh                                  # Claude Code
#   link-skills.sh ~/.config/opencode/skills        # another harness
#
# Idempotent. Only creates/repairs symlinks that point into the canonical
# store; never touches real dirs or foreign symlinks it didn't create.

set -euo pipefail

SKILLS_SRC="${SKILLS_SRC:-$(cd "$(dirname "$0")/.." && pwd)/skills}"
DRY_RUN=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --list)
      [ -d "$SKILLS_SRC" ] || { echo "no canonical store at $SKILLS_SRC" >&2; exit 1; }
      for d in "$SKILLS_SRC"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ -f "$d/SKILL.md" ] && echo "$name" || echo "$name (no SKILL.md — skipped)"
      done
      exit 0
      ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

TARGET="${TARGET:-$HOME/.claude/skills}"

[ -d "$SKILLS_SRC" ] || { echo "no canonical store at $SKILLS_SRC" >&2; exit 1; }
mkdir -p "$TARGET"

linked=0 skipped=0 repaired=0
for d in "$SKILLS_SRC"/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  [ -f "$d/SKILL.md" ] || { echo "skip (no SKILL.md): $name"; continue; }
  src="$SKILLS_SRC/$name"
  dst="$TARGET/$name"

  if [ -L "$dst" ]; then
    cur="$(readlink "$dst")"
    if [ "$cur" = "$src" ]; then skipped=$((skipped+1)); continue; fi
    echo "repair: $name ($cur -> $src)"
    [ "$DRY_RUN" = 1 ] || { rm "$dst"; ln -s "$src" "$dst"; }
    repaired=$((repaired+1))
    continue
  fi
  if [ -e "$dst" ]; then
    echo "WARN: $dst exists and is not a symlink — leaving untouched" >&2
    continue
  fi
  echo "link: $name"
  [ "$DRY_RUN" = 1 ] || ln -s "$src" "$dst"
  linked=$((linked+1))
done

tag=""; [ "$DRY_RUN" = 1 ] && tag=" [dry-run]"
echo "done: ${linked} linked, ${repaired} repaired, ${skipped} already-current (target: $TARGET)${tag}"
