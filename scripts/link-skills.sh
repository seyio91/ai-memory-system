#!/usr/bin/env bash
#
# link-skills.sh — symlink canonical skills from the memory system into an
# agent harness's skills directory. LLM/harness-agnostic: point it at any
# runtime's skills dir and every skill in memory/skills/ gets linked in.
#
# Skill stores: ~/.claude-memory/skills/ plus ~/.claude-memory/.skill-cache/.
# Enumeration is centralized in _lib.sh:list_skill_dirs (override the roots via
# AI_MEMORY_SKILL_ROOTS); the legacy SKILLS_SRC env still pins it to a single
# dir. Each entry is a skill dir containing a SKILL.md.
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
#
# Also prunes dangling store-shaped symlinks: a link left behind when its skill
# was renamed or the memory tree moved is never revisited by the link loop
# (which only walks skills that still exist), so it would otherwise survive
# indefinitely. A link is pruned only when it is dangling AND its target sits
# directly under a skills/ or .skill-cache/ dir AND the target basename matches
# the link name — deliberately matching on shape rather than on the *current*
# store roots, since a moved tree leaves links pointing at the old root.

set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/_lib.sh"

# Legacy single-source override: SKILLS_SRC pins enumeration to one dir.
[ -n "${SKILLS_SRC:-}" ] && export AI_MEMORY_SKILL_ROOTS="$SKILLS_SRC"

DRY_RUN=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --list)
      list_skill_dirs | while IFS= read -r d; do basename "$d"; done
      exit 0
      ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

TARGET="${TARGET:-$HOME/.claude/skills}"

mkdir -p "$TARGET"

linked=0 skipped=0 repaired=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  name="$(basename "$d")"
  src="$d"
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
done < <(list_skill_dirs)

pruned=0
for dst in "$TARGET"/*; do
  [ -L "$dst" ] || continue
  [ -e "$dst" ] && continue

  name="$(basename "$dst")"
  tgt="$(readlink "$dst")"
  parent="$(basename "$(dirname "$tgt")")"

  case "$parent" in
    skills|.skill-cache) ;;
    *)
      echo "WARN: $name dangles outside a skill store ($tgt) — leaving untouched" >&2
      continue
      ;;
  esac

  if [ "$(basename "$tgt")" != "$name" ]; then
    echo "WARN: $name dangles to a differently-named target ($tgt) — leaving untouched" >&2
    continue
  fi

  echo "prune: $name (dangling -> $tgt)"
  [ "$DRY_RUN" = 1 ] || rm "$dst"
  pruned=$((pruned+1))
done

tag=""; [ "$DRY_RUN" = 1 ] && tag=" [dry-run]"
echo "done: ${linked} linked, ${repaired} repaired, ${pruned} pruned, ${skipped} already-current (target: $TARGET)${tag}"
