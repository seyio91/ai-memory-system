#!/usr/bin/env bash
# UPGRADING.md must narrate every migration. The real migrations/ directory is
# README-only today, so the repo check passes vacuously; the fixture below proves
# a future migration without a matching section fails.
. "$(dirname "$0")/_assert.sh"
set -euo pipefail

ROOT="$(new_sandbox)"
trap 'rm -rf "$ROOT"' EXIT

REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
MIGRATIONS_DIR="${AI_MEMORY_MIGRATIONS_DIR:-$REPO_ROOT/migrations}"
UPGRADING_DOC="${AI_MEMORY_UPGRADING_DOC:-$REPO_ROOT/UPGRADING.md}"
MIGRATION_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[A-Za-z0-9._-]+\.sh$'

abort() {
    printf 'ABORT: %s\n' "$1" >&2
    exit 1
}

has_upgrade_section() {
    local version="$1" doc="$2"
    awk -v version="$version" '
        { sub(/\r$/, "", $0) }
        $0 == "## " version { found=1 }
        END { exit found ? 0 : 1 }
    ' "$doc"
}

check_upgrading_doc() {
    local migrations_dir="$1" doc="$2" f base version missing

    [ -f "$doc" ] || abort "upgrade doc not found: $doc"
    [ -d "$migrations_dir" ] || return 0

    missing=""
    for f in "$migrations_dir"/* "$migrations_dir"/.gitkeep; do
        [ -e "$f" ] || continue
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        case "$base" in
            README.md|.gitkeep) continue ;;
        esac
        if ! printf '%s\n' "$base" | grep -Eq "$MIGRATION_RE"; then
            abort "malformed migration filename: $base"
        fi
        version="${base%%-*}"
        if ! has_upgrade_section "$version" "$doc"; then
            missing="${missing}${missing:+
}$version ($base)"
        fi
    done

    if [ -n "$missing" ]; then
        printf 'ABORT: missing UPGRADING.md section for migration version(s):\n%s\n' "$missing" >&2
        exit 1
    fi
}

capture_check() {
    local migrations_dir="$1" doc="$2"
    ( AI_MEMORY_MIGRATIONS_DIR="$migrations_dir" AI_MEMORY_UPGRADING_DOC="$doc" bash "$0" --check-only ) 2>&1
}

if [ "${1:-}" = "--check-only" ]; then
    check_upgrading_doc "$MIGRATIONS_DIR" "$UPGRADING_DOC"
    exit 0
fi

check_upgrading_doc "$MIGRATIONS_DIR" "$UPGRADING_DOC"
_ok "repo migrations all have upgrade notes"

SANDBOX_MIGRATIONS="$ROOT/migrations"
SANDBOX_DOC="$ROOT/UPGRADING.md"
mkdir -p "$SANDBOX_MIGRATIONS"
printf '# Migrations\n' > "$SANDBOX_MIGRATIONS/README.md"
printf '# Upgrading\n\n## 1.0.0\n' > "$SANDBOX_DOC"
cat > "$SANDBOX_MIGRATIONS/1.1.0-needs-note.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

set +e
missing_out="$(capture_check "$SANDBOX_MIGRATIONS" "$SANDBOX_DOC")"
missing_rc=$?
set -u
assert_exit 1 "$missing_rc" "fixture migration without matching section fails"
assert_contains "$missing_out" "1.1.0 (1.1.0-needs-note.sh)" "failure names the missing migration version and file"

printf '\n## 1.1.0\n' >> "$SANDBOX_DOC"
capture_check "$SANDBOX_MIGRATIONS" "$SANDBOX_DOC" >/dev/null
assert_exit 0 "$?" "fixture migration with matching section passes"

finish
