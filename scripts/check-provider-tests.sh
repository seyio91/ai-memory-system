#!/usr/bin/env bash
#
# check-provider-tests.sh — every taskprovider provider must ship a matching
# tests/test_<name>.py. A provider is either a flat module providers/<name>.py
# or a package directory providers/<name>/ (with __init__.py exposing PROVIDER).
#
# Adding a provider needs no factory edit (the registry resolves the module name
# from MEMORY_TASK_PROVIDER), which is the design — but it means nothing else in
# the system would ever notice a provider landing with no tests. This does.
#
# Usage: check-provider-tests.sh [taskprovider_dir]
#   taskprovider_dir  defaults to <scripts>/taskprovider
#
# Exit: 0 all providers paired, 1 one or more unpaired, 2 setup error.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="${1:-$HERE/taskprovider}"
PROVIDERS="$PKG/providers"
TESTS="$PKG/tests"

[ -d "$PROVIDERS" ] || { echo "check-provider-tests: no providers dir at $PROVIDERS" >&2; exit 2; }
[ -d "$TESTS" ] || { echo "check-provider-tests: no tests dir at $TESTS" >&2; exit 2; }

rc=0
found=0

check_provider() {
    local base="$1"
    [ "$base" = "__init__" ] && return 0
    [ "$base" = "__pycache__" ] && return 0
    found=$((found + 1))
    if [ ! -f "$TESTS/test_$base.py" ]; then
        printf 'ERROR provider %s has no tests/test_%s.py\n' "$base" "$base"
        rc=1
    fi
}

# Flat modules: providers/<name>.py
for p in "$PROVIDERS"/*.py; do
    [ -e "$p" ] || continue
    check_provider "$(basename "$p" .py)"
done

# Package providers: providers/<name>/__init__.py
for d in "$PROVIDERS"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}__init__.py" ] || continue
    check_provider "$(basename "$d")"
done

if [ "$found" -eq 0 ]; then
    echo "check-provider-tests: no providers found under $PROVIDERS" >&2
    exit 2
fi

exit $rc
