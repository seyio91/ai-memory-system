#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

[ "${1:-}" ] || { printf 'usage: %s <name>\n' "$(basename "$0")" >&2; exit 2; }

skill_data_dir "$1"
