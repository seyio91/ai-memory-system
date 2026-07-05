#!/usr/bin/env bash
# gen-commands-doc.sh — materialize a "Memory Commands" reference from the
# canonical slash-command bodies: one bullet per command with its first-line
# summary. The `commands=doc` fallback of the Phase-4 command surface, for a
# harness with neither a native command dir nor a skills surface (a context-only
# harness). The generated file is meant to sit alongside / inside the harness's
# materialized context so the model knows the commands exist.
#
#   gen-commands-doc.sh <commands-src> <out-file>
set -euo pipefail

SRC="${1:?usage: gen-commands-doc.sh <commands-src> <out-file>}"
OUT="${2:?usage: gen-commands-doc.sh <commands-src> <out-file>}"
[ -d "$SRC" ] || { echo "gen-commands-doc: no commands source at $SRC" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

{
    echo "# Memory Commands"
    echo
    echo "Reference for the memory-system commands available in this environment."
    echo "Each is an action you can perform on request; run the described step."
    echo
    for f in "$SRC"/*.md; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .md)"
        desc="$(awk 'NF{print; exit}' "$f")"
        printf -- '- **/%s** — %s\n' "$name" "$desc"
    done
} > "$OUT"

echo "wrote commands doc: $OUT"
