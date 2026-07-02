#!/usr/bin/env bash
# Pin the current git checkout to a memory project, writing BOTH directions:
#   forward — <repo-root>/.claude/memory-project names the project
#   reverse — the project memory.md frontmatter records repo + repo_path
# Run from inside the checkout:  memory-pin.sh <project>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

PROJECT=""
CATEGORY=""
HAVE_CATEGORY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --category)
            shift
            [ $# -gt 0 ] || { echo "memory-pin: --category requires a value" >&2; exit 2; }
            CATEGORY="$1"; HAVE_CATEGORY=1 ;;
        --category=*)
            CATEGORY="${1#--category=}"; HAVE_CATEGORY=1 ;;
        --) shift; break ;;
        -*) echo "memory-pin: unknown option: $1" >&2; exit 2 ;;
        *)
            if [ -z "$PROJECT" ]; then PROJECT="$1"
            else echo "memory-pin: unexpected argument: $1" >&2; exit 2; fi ;;
    esac
    shift
done
# Any trailing args after `--` fill the project slot if still empty.
if [ -z "$PROJECT" ] && [ $# -gt 0 ]; then PROJECT="$1"; fi
if [ -z "$PROJECT" ]; then
    echo "usage: memory-pin.sh <project> [--category <client>]   (run from inside a git checkout)" >&2
    exit 2
fi

MF="$MEMORY_DIR/projects/$PROJECT/memory.md"
if [ ! -f "$MF" ]; then
    echo "memory-pin: no memory for project '$PROJECT' at $MF" >&2
    echo "  scaffold it first: $SCRIPT_DIR/new-project.sh $PROJECT" >&2
    exit 1
fi

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "memory-pin: not inside a git repository" >&2
    exit 1
}

# --- forward map ---
mkdir -p "$TOP/.claude"
printf '%s\n' "$PROJECT" > "$TOP/.claude/memory-project"

# --- reverse map values ---
REPO=$(git -C "$TOP" remote get-url origin 2>/dev/null || git -C "$TOP" config --get remote.origin.url 2>/dev/null || true)
REPO="${REPO:-}"

ROOT="$(projects_root)"
REPO_PATH=""
if [ -d "$ROOT" ]; then
    # Canonicalize the root so a symlinked root (macOS /var -> /private/var)
    # matches git's physical --show-toplevel before we strip the prefix.
    ROOT_PHYS="$(cd "$ROOT" && pwd -P)"
    case "$TOP/" in
        "$ROOT_PHYS"/*) REPO_PATH="${TOP#"$ROOT_PHYS"/}" ;;
        *)
            REPO_PATH="$TOP"
            echo "memory-pin: $TOP is not under projects root $ROOT_PHYS — storing absolute repo_path" >&2
            ;;
    esac
else
    REPO_PATH="$TOP"
    echo "memory-pin: projects root $ROOT does not exist — storing absolute repo_path" >&2
fi

# Upsert a single key into the leading ---…--- frontmatter block. Touches only
# the frontmatter; the body is left byte-for-byte intact. awk is bash-3.2-safe;
# values pass via -v so URLs/colons stay literal.
upsert_fm() {
    local file="$1" key="$2" val="$3" tmp
    tmp="$file.pin.$$"
    awk -v key="$key" -v val="$val" '
        BEGIN { infm = 0; seen = 0 }
        NR == 1 && /^---[[:space:]]*$/ { infm = 1; print; next }
        infm && /^---[[:space:]]*$/ {
            if (!seen) { print key ": " val }
            infm = 0; print; next
        }
        infm && $0 ~ ("^" key ":") {
            if (!seen) { print key ": " val; seen = 1 }
            next
        }
        { print }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

[ -n "$REPO" ] && upsert_fm "$MF" repo "$REPO"
upsert_fm "$MF" repo_path "$REPO_PATH"
# Category is optional, personal, per-instance — set only when --category was given.
if [ "$HAVE_CATEGORY" -eq 1 ]; then
    upsert_fm "$MF" category "$CATEGORY"
fi

echo "Pinned $TOP -> $PROJECT"
echo "  repo:      ${REPO:-<none>}"
echo "  repo_path: $REPO_PATH"
if [ "$HAVE_CATEGORY" -eq 1 ]; then
    echo "  category:  $CATEGORY"
fi
