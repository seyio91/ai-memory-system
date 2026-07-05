#!/usr/bin/env bash
set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NAME="${1:-}"

if [ -z "$NAME" ]; then
    echo "usage: new-project.sh <name>" >&2
    exit 1
fi

TARGET="$MEMORY_DIR/projects/$NAME"

if [ -d "$TARGET" ]; then
    echo "project '$NAME' already exists at $TARGET" >&2
    exit 1
fi

cp -r "$MEMORY_DIR/projects/_template" "$TARGET"
echo "created: $TARGET"
echo "activate by pinning a repo:"
echo "  cd <repo> && memory-pin.sh $NAME    # writes .agents/memory-project + reverse map"
