#!/usr/bin/env bash
set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
NAME="${1:-}"

if [ -z "$NAME" ]; then
    echo "usage: new-project.sh <name>" >&2
    exit 1
fi

# The name becomes a directory and is substituted into the template with sed,
# so keep it to a charset that is safe in both.
case "$NAME" in
    *[!A-Za-z0-9._-]*|.*)
        echo "invalid project name '$NAME': use letters, digits, '.', '_' or '-' (not leading '.')" >&2
        exit 1
        ;;
esac

TARGET="$MEMORY_DIR/projects/$NAME"

if [ -d "$TARGET" ]; then
    echo "project '$NAME' already exists at $TARGET" >&2
    exit 1
fi

cp -r "$MEMORY_DIR/projects/_template" "$TARGET"
find "$TARGET" -type f -name '*.md' -exec sed -i.bak "s/<name>/$NAME/g" {} \;
find "$TARGET" -type f -name '*.md.bak' -exec rm -f {} \;
echo "created: $TARGET"
echo "activate by pinning a repo:"
echo "  cd <repo> && memory-pin.sh $NAME    # writes .agents/memory-project + reverse map"
