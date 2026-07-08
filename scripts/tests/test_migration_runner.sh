#!/usr/bin/env bash
# sync-system.sh migration runner.
. "$(dirname "$0")/_assert.sh"

ROOT="$(new_sandbox)"
trap 'rm -rf "$ROOT"' EXIT

write_fixture_scripts() {
    local repo="$1"
    mkdir -p "$repo/scripts"
    cp "$SCRIPTS_DIR/sync-system.sh" "$repo/scripts/sync-system.sh"
    cp "$SCRIPTS_DIR/_lib.sh" "$repo/scripts/_lib.sh"
    cat > "$repo/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'install\n' >> install-ran.txt
EOF
    chmod +x "$repo/install.sh" "$repo/scripts/sync-system.sh"
}

make_fixture() {
    local name="$1" repo migrations marker
    repo="$ROOT/$name/repo"
    migrations="$ROOT/$name/migrations"
    marker="$ROOT/$name/.applied-version"
    mkdir -p "$repo" "$migrations"
    write_fixture_scripts "$repo"
    printf '# Migrations\n' > "$migrations/README.md"
    printf '%s\t%s\t%s\n' "$repo" "$migrations" "$marker"
}

fixture_repo() {
    printf '%s\n' "$1" | awk -F '	' '{print $1}'
}

fixture_migrations() {
    printf '%s\n' "$1" | awk -F '	' '{print $2}'
}

fixture_marker() {
    printf '%s\n' "$1" | awk -F '	' '{print $3}'
}

add_log_migration() {
    local dir="$1" version="$2" slug="$3"
    cat > "$dir/$version-$slug.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$version" >> "\$MEMORY_DIR/order.log"
EOF
}

run_sync_fixture() {
    local fixture="$1" repo migrations marker
    shift
    repo="$(fixture_repo "$fixture")"
    migrations="$(fixture_migrations "$fixture")"
    marker="$(fixture_marker "$fixture")"
    ( cd "$repo" && MEMORY_DIR="$repo" AI_MEMORY_MIGRATIONS_DIR="$migrations" AI_MEMORY_APPLIED_VERSION_FILE="$marker" bash scripts/sync-system.sh "$@" )
}

capture_sync_fixture() {
    local fixture="$1" repo migrations marker
    shift
    repo="$(fixture_repo "$fixture")"
    migrations="$(fixture_migrations "$fixture")"
    marker="$(fixture_marker "$fixture")"
    ( cd "$repo" && MEMORY_DIR="$repo" AI_MEMORY_MIGRATIONS_DIR="$migrations" AI_MEMORY_APPLIED_VERSION_FILE="$marker" bash scripts/sync-system.sh "$@" ) 2>&1
}

capture_sync_fixture_no_sort_v() {
    local fixture="$1" repo migrations marker
    shift
    repo="$(fixture_repo "$fixture")"
    migrations="$(fixture_migrations "$fixture")"
    marker="$(fixture_marker "$fixture")"
    ( cd "$repo" && MEMORY_DIR="$repo" AI_MEMORY_MIGRATIONS_DIR="$migrations" AI_MEMORY_APPLIED_VERSION_FILE="$marker" AI_MEMORY_TEST_NO_SORT_V=1 bash scripts/sync-system.sh "$@" ) 2>&1
}

# --- absent marker runs all migrations in ascending semver order ---
F1="$(make_fixture absent-marker)"
R1="$(fixture_repo "$F1")"
M1="$(fixture_migrations "$F1")"
MARK1="$(fixture_marker "$F1")"
add_log_migration "$M1" "1.10.0" "ten"
add_log_migration "$M1" "1.0.0" "one"
add_log_migration "$M1" "1.2.0" "two"
run_sync_fixture "$F1" --no-pull >/dev/null 2>&1
assert_eq "$(printf '1.0.0\n1.2.0\n1.10.0')" "$(cat "$R1/order.log")" "absent marker runs every migration ascending"
assert_eq "1.10.0" "$(cat "$MARK1")" "absent marker records highest migration version"

# --- marker is strict greater-than threshold ---
F2="$(make_fixture strict-marker)"
R2="$(fixture_repo "$F2")"
M2="$(fixture_migrations "$F2")"
MARK2="$(fixture_marker "$F2")"
printf '1.1.0\n' > "$MARK2"
add_log_migration "$M2" "1.1.0" "same"
add_log_migration "$M2" "1.1.1" "patch"
add_log_migration "$M2" "1.2.0" "minor"
run_sync_fixture "$F2" --no-pull >/dev/null 2>&1
assert_eq "$(printf '1.1.1\n1.2.0')" "$(cat "$R2/order.log")" "marker excludes the same version and runs only greater versions"
assert_eq "1.2.0" "$(cat "$MARK2")" "strict marker records final greater version"

# --- marker is written after each success; failure aborts before install ---
F3="$(make_fixture failure-marker)"
R3="$(fixture_repo "$F3")"
M3="$(fixture_migrations "$F3")"
MARK3="$(fixture_marker "$F3")"
add_log_migration "$M3" "1.0.0" "ok"
cat > "$M3/1.1.0-fail.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '1.1.0\n' >> "$MEMORY_DIR/order.log"
exit 1
EOF
add_log_migration "$M3" "1.2.0" "never"
set +e
fail_out="$(capture_sync_fixture "$F3" --no-pull)"
fail_rc=$?
set -u
assert_exit 1 "$fail_rc" "failing migration aborts sync"
assert_eq "1.0.0" "$(cat "$MARK3")" "failure leaves marker at previous successful migration"
assert_eq "$(printf '1.0.0\n1.1.0')" "$(cat "$R3/order.log")" "failure stops before later migrations"
if [ ! -f "$R3/install-ran.txt" ]; then _ok "failing migration prevents install.sh"; else _bad "failing migration prevents install.sh"; fi
assert_contains "$fail_out" "migration failed: $M3/1.1.0-fail.sh" "failure message names migration file"
assert_contains "$fail_out" "marker was left at 1.0.0" "failure message reports retained marker"

# --- re-run after success is a migration no-op ---
F4="$(make_fixture rerun-noop)"
R4="$(fixture_repo "$F4")"
M4="$(fixture_migrations "$F4")"
MARK4="$(fixture_marker "$F4")"
add_log_migration "$M4" "1.0.0" "one"
add_log_migration "$M4" "1.1.0" "two"
run_sync_fixture "$F4" --no-pull >/dev/null 2>&1
before_order="$(cat "$R4/order.log")"
before_marker="$(cat "$MARK4")"
run_sync_fixture "$F4" --no-pull >/dev/null 2>&1
assert_eq "$before_order" "$(cat "$R4/order.log")" "re-run after success runs no migrations"
assert_eq "$before_marker" "$(cat "$MARK4")" "re-run after success leaves marker unchanged"

# --- downgrade/high marker is a no-op, not an error ---
F5="$(make_fixture downgrade)"
R5="$(fixture_repo "$F5")"
M5="$(fixture_migrations "$F5")"
MARK5="$(fixture_marker "$F5")"
printf '9.9.9\n' > "$MARK5"
add_log_migration "$M5" "1.0.0" "old"
add_log_migration "$M5" "2.0.0" "older"
run_sync_fixture "$F5" --no-pull >/dev/null 2>&1
if [ ! -f "$R5/order.log" ]; then _ok "downgrade marker ahead runs nothing"; else _bad "downgrade marker ahead runs nothing"; fi
assert_eq "9.9.9" "$(cat "$MARK5")" "downgrade marker remains ahead"

# --- malformed migration names hard-fail; README.md is ignored ---
F6="$(make_fixture malformed)"
R6="$(fixture_repo "$F6")"
M6="$(fixture_migrations "$F6")"
printf 'bad\n' > "$M6/1.0-bad.sh"
set +e
malformed_out="$(capture_sync_fixture "$F6" --no-pull)"
malformed_rc=$?
set -u
assert_exit 1 "$malformed_rc" "malformed migration filename aborts"
assert_contains "$malformed_out" "malformed migration filename: 1.0-bad.sh" "malformed filename message names offending file"
if [ ! -f "$R6/install-ran.txt" ]; then _ok "malformed migration prevents install.sh"; else _bad "malformed migration prevents install.sh"; fi

F7="$(make_fixture readme-only)"
R7="$(fixture_repo "$F7")"
MARK7="$(fixture_marker "$F7")"
run_sync_fixture "$F7" --no-pull >/dev/null 2>&1
assert_file "$R7/install-ran.txt" "README.md-only migrations dir still installs"
if [ ! -f "$MARK7" ]; then _ok "README.md-only migrations dir does not create marker"; else _bad "README.md-only migrations dir does not create marker"; fi

# --- sort -V and fallback ordering match ---
F8="$(make_fixture sort-default)"
R8="$(fixture_repo "$F8")"
M8="$(fixture_migrations "$F8")"
add_log_migration "$M8" "1.10.0" "ten"
add_log_migration "$M8" "1.2.0" "two"
run_sync_fixture "$F8" --no-pull >/dev/null 2>&1
default_order="$(cat "$R8/order.log")"

F9="$(make_fixture sort-fallback)"
R9="$(fixture_repo "$F9")"
M9="$(fixture_migrations "$F9")"
add_log_migration "$M9" "1.10.0" "ten"
add_log_migration "$M9" "1.2.0" "two"
capture_sync_fixture_no_sort_v "$F9" --no-pull >/dev/null
fallback_order="$(cat "$R9/order.log")"
assert_eq "$(printf '1.2.0\n1.10.0')" "$default_order" "sort -V path orders 1.2.0 before 1.10.0"
assert_eq "$default_order" "$fallback_order" "fallback semver sort matches sort -V ordering"

# --- dry-run lists pending migrations and changes nothing ---
F10="$(make_fixture dry-run)"
R10="$(fixture_repo "$F10")"
M10="$(fixture_migrations "$F10")"
MARK10="$(fixture_marker "$F10")"
printf '1.0.0\n' > "$MARK10"
add_log_migration "$M10" "0.9.0" "old"
add_log_migration "$M10" "1.1.0" "next"
dry_out="$(capture_sync_fixture "$F10" --no-pull --dry-run)"
assert_contains "$dry_out" "applied marker: 1.0.0" "dry-run reports current marker"
assert_contains "$dry_out" "1.1.0  1.1.0-next.sh" "dry-run lists pending migration"
assert_not_contains "$dry_out" "0.9.0-old.sh" "dry-run omits already-applied migration"
if [ ! -f "$R10/order.log" ]; then _ok "dry-run runs no migrations"; else _bad "dry-run runs no migrations"; fi
assert_eq "1.0.0" "$(cat "$MARK10")" "dry-run leaves marker unchanged"
if [ ! -f "$R10/install-ran.txt" ]; then _ok "dry-run does not install"; else _bad "dry-run does not install"; fi

# --- migrations receive MEMORY_DIR and REPO_ROOT ---
F11="$(make_fixture env-vars)"
R11="$(fixture_repo "$F11")"
M11="$(fixture_migrations "$F11")"
cat > "$M11/1.0.0-env.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'MEMORY_DIR=%s\nREPO_ROOT=%s\n' "$MEMORY_DIR" "$REPO_ROOT" > "$MEMORY_DIR/env.log"
EOF
run_sync_fixture "$F11" --no-pull >/dev/null 2>&1
assert_contains "$(cat "$R11/env.log")" "MEMORY_DIR=$R11" "migration receives MEMORY_DIR"
assert_contains "$(cat "$R11/env.log")" "REPO_ROOT=$R11" "migration receives REPO_ROOT"

finish
