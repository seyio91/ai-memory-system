#!/usr/bin/env bash
# statusline.sh — memory-aware custom statusline for the Antigravity CLI (`agy`).
# Registered in ~/.gemini/antigravity-cli/settings.json ("statusLine") by
# install.sh --harness antigravity. agy pipes a JSON payload on stdin each render;
# this prints the formatted (ANSI) statusline to stdout.
#
# Surfaces, left→right: the active MEMORY PROJECT (🧠), the FOLDER (📁), git branch,
# model, a context-window % bar, and agent state (+subagent/task counts). The memory
# project + folder come from AI_MEMORY_PROJECT / AI_MEMORY_CWD (exported by agy.sh),
# falling back to walking up $PWD for a .agents/memory-project marker.
#
# Glyphs: emoji by default (same set Claude's statusline uses — renders in any
# terminal). Set USE_NERD_FONTS=true to use Nerd Font icons instead (needs a Nerd
# Font installed, else glyphs show as boxes).
# Never aborts (a statusline must not crash the CLI): jq-optional, defaults on error.
set -uo pipefail

USE_NERD_FONTS="${USE_NERD_FONTS:-false}"

# ─── ANSI (standard 16-color) ────────────────────────────────────────────────
R="\033[0m"; B="\033[1m"; I="\033[3m"
FG_GRAY="\033[90m"; FG_RED="\033[91m"; FG_GREEN="\033[92m"; FG_YELLOW="\033[93m"
FG_BLUE="\033[94m"; FG_MAGENTA="\033[95m"; FG_CYAN="\033[96m"; FG_WHITE="\033[97m"
NUM="${FG_WHITE}${B}"

# ─── Glyphs (Nerd Font ⟷ emoji/text fallback) ────────────────────────────────
if [ "$USE_NERD_FONTS" = "true" ]; then
    G_MEM=$'\uf1c0'; G_DIR=$'\uf07b'; G_BR=$'\uf126'; G_MODEL=$'\uf2db'
else
    G_MEM="🧠"; G_DIR="📁"; G_BR="🌿"; G_MODEL="🤖"
fi

# ─── Parse agy's stdin payload (single jq pass; defaults if jq/parse fails) ───
if command -v jq >/dev/null 2>&1; then
    { read -r STATE; read -r USED_PCT; read -r VCS_BRANCH; read -r VCS_DIRTY
      read -r SANDBOX; read -r SUBAGENTS; read -r BG_TASKS; read -r MODEL; read -r COLS
    } <<EOF
$(jq -r '
    (.agent_state // "idle"),
    (.context_window.used_percentage // 0),
    (.vcs.branch // ""),
    (.vcs.dirty // false),
    (.sandbox.enabled // false),
    (if .subagents | type == "array" then (.subagents | length) else 0 end),
    (.task_count // 0),
    (.model.display_name // ""),
    (.terminal_width // 80)
  ' 2>/dev/null || printf 'idle\n0\n\nfalse\nfalse\n0\n0\n\n80\n')
EOF
else
    cat >/dev/null 2>&1   # drain stdin so agy's pipe closes cleanly
    STATE=idle; USED_PCT=0; VCS_BRANCH=""; VCS_DIRTY=false
    SANDBOX=false; SUBAGENTS=0; BG_TASKS=0; MODEL=""; COLS=80
fi
COLS="${COLS:-80}"; case "$COLS" in ''|*[!0-9]*) COLS=80 ;; esac

# ─── Memory project + folder (env from agy.sh, else walk up for the marker) ───
mem_project() {
    if [ -n "${AI_MEMORY_PROJECT:-}" ]; then printf '%s' "$AI_MEMORY_PROJECT"; return; fi
    local dir="${AI_MEMORY_CWD:-$PWD}"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        [ -f "$dir/.agents/memory-project" ] && { tr -d '[:space:]' < "$dir/.agents/memory-project"; return; }
        [ -f "$dir/.claude/memory-project" ] && { tr -d '[:space:]' < "$dir/.claude/memory-project"; return; }
        dir=$(dirname "$dir")
    done
}
PROJECT="$(mem_project)"
FOLDER="$(basename "${AI_MEMORY_CWD:-$PWD}")"

# ─── Segments ────────────────────────────────────────────────────────────────
# Memory project (brain): highlighted when resolved, dim "dormant" otherwise.
if [ -n "$PROJECT" ]; then
    MEM="${FG_CYAN}${B}${G_MEM} ${PROJECT}${R}"
else
    MEM="${FG_GRAY}${G_MEM} dormant${R}"
fi
DIR="${FG_GRAY}${G_DIR} ${FG_WHITE}${FOLDER}${R}"

# Agent state.
case "$STATE" in
    idle)     S="${FG_GREEN}${B}● READY${R}" ;;
    thinking) S="${FG_YELLOW}${B}◆ THINKING${R}" ;;
    working)  S="${FG_CYAN}${B}⚙ WORKING${R}" ;;
    tool_use) S="${FG_MAGENTA}${B}🔧 TOOL${R}" ;;
    *)        S="${FG_WHITE}${B}⏳ $(printf '%s' "$STATE" | tr '[:lower:]' '[:upper:]')${R}" ;;
esac

# VCS branch (+dirty).
V=""
if [ -n "$VCS_BRANCH" ]; then
    if [ "$VCS_DIRTY" = "true" ]; then
        V="${FG_GRAY} ${G_BR} ${FG_RED}${VCS_BRANCH}${FG_YELLOW}*${R}"
    else
        V="${FG_GRAY} ${G_BR} ${FG_BLUE}${VCS_BRANCH}${R}"
    fi
fi

# Model.
M=""; [ -n "$MODEL" ] && M="${FG_GRAY} ${G_MODEL} ${FG_MAGENTA}${I}${MODEL}${R}"

# Context-window bar (15 cells, partial last block, color by fill).
PCT_INT="${USED_PCT%.*}"; case "$PCT_INT" in ''|*[!0-9]*) PCT_INT=0 ;; esac
PCT_FMT="$(LC_ALL=C printf '%.1f' "$USED_PCT" 2>/dev/null || printf '%s' "$PCT_INT")"
BAR_LEN=15; FILLED=$((PCT_INT * BAR_LEN / 100)); REM=$(((PCT_INT * BAR_LEN) % 100))
if   [ "$PCT_INT" -ge 90 ]; then BAR_COLOR="$FG_RED"
elif [ "$PCT_INT" -ge 60 ]; then BAR_COLOR="$FG_YELLOW"
else BAR_COLOR="$FG_WHITE"; fi
BAR=""
for ((i = 0; i < BAR_LEN; i++)); do
    if   [ "$i" -lt "$FILLED" ]; then BAR="${BAR}█"
    elif [ "$i" -eq "$FILLED" ]; then
        if   [ "$REM" -ge 75 ]; then BAR="${BAR}▓"
        elif [ "$REM" -ge 50 ]; then BAR="${BAR}▒"
        elif [ "$REM" -ge 25 ]; then BAR="${BAR}░"
        else BAR="${BAR}·"; fi
    else BAR="${BAR}·"; fi
done
CTX="${FG_GRAY}ctx ${BAR_COLOR}${BAR} ${NUM}${PCT_FMT}%${R}"
SUB="${FG_GRAY}subagents ${NUM}${SUBAGENTS}${R}"
TSK="${FG_GRAY}tasks ${NUM}${BG_TASKS}${R}"
[ "$SANDBOX" = "true" ] && SB="${FG_GRAY}sandbox ${FG_GREEN}${B}ON${R}" || SB="${FG_GRAY}sandbox off${R}"
DOT="${FG_GRAY} · ${R}"

# ─── Responsive layout ───────────────────────────────────────────────────────
LINE1="${MEM}${DOT}${DIR}${V}${M}"
LINE2=" ${S}${DOT}${CTX}${DOT}${SUB}${DOT}${TSK}${DOT}${SB}"
if [ "$COLS" -ge 120 ]; then
    echo -e "${LINE1}${FG_GRAY}  │  ${R}${S}${DOT}${CTX}"
elif [ "$COLS" -ge 80 ]; then
    echo -e "${FG_GRAY}╭─${R} ${LINE1}"
    echo -e "${FG_GRAY}╰─${R}${LINE2}"
else
    echo -e "${MEM}${DOT}${S}"
    echo -e "${CTX}"
fi
