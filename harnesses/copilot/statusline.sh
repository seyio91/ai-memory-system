#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
    {
        read -r MODEL
        read -r DIR
        read -r PCT
    } <<EOF
$(printf '%s' "$input" | jq -r '
    (.model.display_name // "?"),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.current_context_used_percentage // .context_window.used_percentage // 0)
' 2>/dev/null || printf '?\n\n0\n')
EOF
else
    MODEL="?"
    DIR="$PWD"
    PCT=0
fi

[ -n "$DIR" ] || DIR="$PWD"
PCT="${PCT%.*}"
case "$PCT" in ''|*[!0-9]*) PCT=0 ;; esac

MEM_LIB="${MEMORY_DIR:-$HOME/.claude-memory}/scripts/_lib.sh"
PROJECT=""
OPEN_TODOS=""
if [ -f "$MEM_LIB" ]; then
    if . "$MEM_LIB" 2>/dev/null; then
        PROJECT="$(detect_active_project "$DIR" 2>/dev/null || true)"
        if [ -n "$PROJECT" ] && type count_open_todos >/dev/null 2>&1; then
            OPEN_TODOS="$(count_open_todos "${MEMORY_DIR:-$HOME/.claude-memory}/projects/$PROJECT/todo.md" 2>/dev/null || true)"
        fi
    fi
fi

BRANCH=""
if [ -n "$DIR" ] && command -v git >/dev/null 2>&1; then
    BRANCH="$(git -C "$DIR" branch --show-current 2>/dev/null || true)"
fi

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
MAGENTA='\033[35m'; DIM='\033[2m'; RESET='\033[0m'

if [ "$PCT" -ge 90 ]; then
    BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then
    BAR_COLOR="$YELLOW"
else
    BAR_COLOR="$GREEN"
fi
FILLED=$((PCT / 10)); [ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

line1="${CYAN}[${MODEL}]${RESET} 📁 ${DIR##*/}"
[ -n "$BRANCH" ] && line1="${line1} 🌿 ${BRANCH}"
if [ -n "$PROJECT" ]; then
    line1="${line1} ${MAGENTA}🧠 ${PROJECT}${RESET}"
    [ -n "$OPEN_TODOS" ] && line1="${line1} 📋 ${OPEN_TODOS} open"
else
    line1="${line1} ${DIM}🧠 (no project)${RESET}"
fi

line2="${BAR_COLOR}${BAR}${RESET} ${PCT}% ctx"

printf '%b\n' "$line1"
printf '%b\n' "$line2"
