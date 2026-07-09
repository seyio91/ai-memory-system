#!/usr/bin/env bash
#
# check-provider-tests.sh — every taskprovider providers/<name>.py must ship a
# matching tests/test_<name>.py.
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
for p in "$PROVIDERS"/*.py; do
    [ -e "$p" ] || continue
    base="$(basename "$p" .py)"
    if [ "$base" != "__init__" ] && [ ! -f "$TESTS/test_$base.py" ]; then
        printf 'ERROR provider %s has no tests/test_%s.py\n' "$base" "$base"
        rc=1
    fi
done

exit $rc
