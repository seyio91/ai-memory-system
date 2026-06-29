#!/usr/bin/env bash
#
# link-agents.sh — symlink canonical agent definitions from the memory system
# into an agent harness's agents directory. LLM/harness-agnostic: point it at
# any runtime's agents dir and every agent in memory/agents/ gets linked in.
#
# Canonical store (source of truth): ~/.claude-memory/agents/
# Each entry is a flat <name>.md file with YAML frontmatter (name/description/...).
#
# Usage:
#   link-agents.sh [TARGET_DIR]        # default: ~/.claude/agents
#   link-agents.sh --list              # list canonical agents and exit
#   link-agents.sh --dry-run [TARGET]  # show what would change, do nothing
#
# Examples:
#   link-agents.sh                                  # Claude Code
#   link-agents.sh ~/.config/opencode/agent         # another harness
#
# Idempotent. Only creates/repairs symlinks that point into the canonical
# store; never touches real files or foreign symlinks it didn't create.
#
# v1 is symlink-only: the system-prompt body is portable and the frontmatter
# schema is currently Claude-Code-shaped. When a harness with a divergent agent
# schema becomes a real consumer, add a transform-and-copy branch here for that
# target (emit a translated file instead of a symlink) — no store change needed.

set -euo pipefail

AGENTS_SRC="${AGENTS_SRC:-$(cd "$(dirname "$0")/.." && pwd)/agents}"
DRY_RUN=0
TARGET=""

# A store file is a valid agent iff it is non-empty and begins with a YAML
# frontmatter block (first line is exactly '---'). This drops empty stubs and
# stray non-agent files.
is_valid_agent() {
  local f="$1"
  [ -s "$f" ] || return 1
  IFS= read -r first < "$f" || return 1
  [ "$first" = "---" ]
}

for arg in "$@"; do
  case "$arg" in
    --list)
      [ -d "$AGENTS_SRC" ] || { echo "no canonical store at $AGENTS_SRC" >&2; exit 1; }
      for f in "$AGENTS_SRC"/*.md; do
        [ -e "$f" ] || continue
        name="$(basename "$f")"
        if is_valid_agent "$f"; then echo "$name"; else echo "$name (no frontmatter — skipped)"; fi
      done
      exit 0
      ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

TARGET="${TARGET:-$HOME/.claude/agents}"

[ -d "$AGENTS_SRC" ] || { echo "no canonical store at $AGENTS_SRC" >&2; exit 1; }
mkdir -p "$TARGET"

linked=0 skipped=0 repaired=0
for f in "$AGENTS_SRC"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  is_valid_agent "$f" || { echo "skip (no frontmatter): $name"; continue; }
  src="$AGENTS_SRC/$name"
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
