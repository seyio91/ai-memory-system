#!/usr/bin/env bash
# Claude Code status line.
# Line 1: model · dir · git branch · active memory project
# Line 2: context-window usage bar + percentage + session cost
#
# The "memory project" is resolved the SAME way the memory hook does (walk up
# for .agents/memory-project, then the legacy .claude/memory-project) by sourcing
# the ai-memory _lib.sh helper.
set -uo pipefail

input="$(cat)"

# --- fields from Claude Code stdin JSON ---
MODEL="$(printf '%s' "$input" | jq -r '.model.display_name // "?"')"
DIR="$(printf '%s' "$input"  | jq -r '.workspace.current_dir // .cwd // ""')"
PCT="$(printf '%s' "$input"  | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)"
COST="$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0')"

# --- active memory project ---
MEM_LIB="${MEMORY_DIR:-$HOME/.claude-memory}/scripts/_lib.sh"
PROJECT=""
if [ -f "$MEM_LIB" ]; then
  # shellcheck disable=SC1090
  . "$MEM_LIB"
  PROJECT="$(detect_active_project "$DIR" 2>/dev/null || true)"
fi

# --- git branch (scoped to DIR so it's correct regardless of script cwd) ---
BRANCH=""
[ -n "$DIR" ] && BRANCH="$(git -C "$DIR" branch --show-current 2>/dev/null || true)"

# --- colors ---
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
MAGENTA='\033[35m'; DIM='\033[2m'; RESET='\033[0m'

# --- context usage bar (color by threshold) ---
[ "$PCT" -ge 0 ] 2>/dev/null || PCT=0
if   [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else                         BAR_COLOR="$GREEN"; fi
FILLED=$((PCT / 10)); [ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

COST_FMT="$(printf '$%.2f' "$COST")"

# --- line 1: model · dir · branch · memory project ---
line1="${CYAN}[${MODEL}]${RESET} 📁 ${DIR##*/}"
[ -n "$BRANCH" ]  && line1="${line1} 🌿 ${BRANCH}"
if [ -n "$PROJECT" ]; then
  line1="${line1} ${MAGENTA}🧠 ${PROJECT}${RESET}"
else
  line1="${line1} ${DIM}🧠 (no project)${RESET}"
fi

# --- line 2: context bar ---
line2="${BAR_COLOR}${BAR}${RESET} ${PCT}% ctx ${DIM}|${RESET} ${YELLOW}${COST_FMT}${RESET}"

printf '%b\n' "$line1"
printf '%b\n' "$line2"
