#!/usr/bin/env bash
#
# link-commands.sh — symlink canonical slash commands from the memory system
# into an agent harness's commands directory. LLM/harness-agnostic: point it at
# any runtime's commands dir and every command in memory/claude/commands/ gets
# linked in.
#
# Canonical store (source of truth): ~/.claude-memory/claude/commands/
# Each entry is a flat <name>.md file (the command body).
#
# Usage:
#   link-commands.sh [TARGET_DIR]        # default: ~/.claude/commands
#   link-commands.sh --list              # list canonical commands and exit
#   link-commands.sh --dry-run [TARGET]  # show what would change, do nothing
#
# Examples:
#   link-commands.sh                                 # Claude Code
#   link-commands.sh ~/.config/some-harness/commands # another harness
#
# Idempotent. Only creates/repairs symlinks that point into the canonical
# store; never touches real files or foreign symlinks it didn't create.

set -euo pipefail

COMMANDS_SRC="${COMMANDS_SRC:-$(cd "$(dirname "$0")/.." && pwd)/claude/commands}"
DRY_RUN=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --list)
      [ -d "$COMMANDS_SRC" ] || { echo "no canonical store at $COMMANDS_SRC" >&2; exit 1; }
      for f in "$COMMANDS_SRC"/*.md; do
        [ -e "$f" ] || continue
        basename "$f"
      done
      exit 0
      ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

TARGET="${TARGET:-$HOME/.claude/commands}"

[ -d "$COMMANDS_SRC" ] || { echo "no canonical store at $COMMANDS_SRC" >&2; exit 1; }
mkdir -p "$TARGET"

linked=0 skipped=0 repaired=0
for f in "$COMMANDS_SRC"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  src="$COMMANDS_SRC/$name"
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
