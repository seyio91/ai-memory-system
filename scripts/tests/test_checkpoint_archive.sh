#!/usr/bin/env bash
# checkpoint-archive.sh — section-scoped working.md archive.
. "$(dirname "$0")/_assert.sh"

ARCHIVE="$SCRIPTS_DIR/checkpoint-archive.sh"

run() { set +e; out="$(bash "$@" 2>&1)"; code=$?; set -e; }

snapshot_path() {
    printf '%s\n' "$out" | awk '/^checkpoint-archive: snapshot / { sub(/^checkpoint-archive: snapshot /, ""); print; exit }'
}

section() {
    awk -v wanted="$2" '
        $0 == wanted { in_section = 1; print; next }
        in_section && /^## / { exit }
        in_section { print }
    ' "$1"
}

mkproject() {
    local root="$1" name="$2"
    mkdir -p "$root/projects/$name"
    printf '%s\n' "$root/projects/$name"
}

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT

# === roll preserves sibling sections and snapshots original content =========
PDIR="$(mkproject "$MEM" alpha)"
cat > "$PDIR/working.md" <<'EOF'
# Working — alpha

## Cross-project learnings (pending promotion)

Keep this byte-identical.

```
## Not a real section
```

## Checkpoints

### 2026-07-01 — CLOSED old work

**Task:** old work

**Done:**
- shipped

## Open threads (not blocking)

- keep this too
EOF
before_learnings="$(section "$PDIR/working.md" "## Cross-project learnings (pending promotion)")"
before_open="$(section "$PDIR/working.md" "## Open threads (not blocking)")"

run "$ARCHIVE" "$PDIR/working.md"
assert_exit 0 "$code" "roll exits 0"
snap="$(snapshot_path)"
assert_file "$snap" "snapshot file created"
assert_eq "$before_learnings" "$(section "$PDIR/working.md" "## Cross-project learnings (pending promotion)")" "learnings section preserved byte-identical"
assert_eq "$before_open" "$(section "$PDIR/working.md" "## Open threads (not blocking)")" "open threads section preserved byte-identical"
checkpoints_after="$(section "$PDIR/working.md" "## Checkpoints")"
assert_contains "$checkpoints_after" "## Checkpoints" "checkpoint heading kept"
assert_contains "$checkpoints_after" "_(none yet — rolled " "checkpoint body reset to placeholder"
assert_contains "$checkpoints_after" "archive/working/" "placeholder names archive location"
assert_contains "$(cat "$snap")" "# Archived checkpoints — alpha —" "snapshot has archive header"
assert_contains "$(cat "$snap")" "### 2026-07-01 — CLOSED old work" "snapshot includes original checkpoint entry"
assert_contains "$(cat "$snap")" "**Done:**" "snapshot includes checkpoint body"

# === no-op guard leaves file byte-identical and writes no snapshot ===========
PDIR_EMPTY="$(mkproject "$MEM" empty)"
cat > "$PDIR_EMPTY/working.md" <<'EOF'
# Working — empty

## Cross-project learnings (pending promotion)

_(none yet)_

## Checkpoints

_(none yet — rolled 2026-07-01 to archive/working/old.md)_

## Open threads

- still here
EOF
before_empty="$(cat "$PDIR_EMPTY/working.md")"
run "$ARCHIVE" "$PDIR_EMPTY/working.md"
assert_exit 0 "$code" "placeholder no-op exits 0"
assert_contains "$out" "nothing to roll" "placeholder no-op reports nothing to roll"
after_empty="$(cat "$PDIR_EMPTY/working.md")"
assert_eq "$before_empty" "$after_empty" "placeholder no-op leaves file byte-identical"
if [ -d "$PDIR_EMPTY/archive/working" ]; then
    snap_count="$(find "$PDIR_EMPTY/archive/working" -type f ! -name .gitkeep | wc -l | tr -d ' ')"
else
    snap_count="0"
fi
assert_eq "0" "$snap_count" "placeholder no-op writes no snapshot"

PDIR_NOCP="$(mkproject "$MEM" nocp)"
printf '# Working — nocp\n\n## Open threads\n\n- only this\n' > "$PDIR_NOCP/working.md"
before_nocp="$(cat "$PDIR_NOCP/working.md")"
run "$ARCHIVE" "$PDIR_NOCP/working.md"
assert_exit 0 "$code" "missing Checkpoints no-op exits 0"
assert_eq "$before_nocp" "$(cat "$PDIR_NOCP/working.md")" "missing Checkpoints leaves file byte-identical"

# === slug in filename =======================================================
PDIR_SLUG="$(mkproject "$MEM" sluggy)"
cat > "$PDIR_SLUG/working.md" <<'EOF'
# Working — sluggy

## Checkpoints

### 2026-07-02 — DONE slug work
EOF
run "$ARCHIVE" "$PDIR_SLUG/working.md" "batch-name"
assert_exit 0 "$code" "slug roll exits 0"
slug_snap="$(basename "$(snapshot_path)")"
assert_contains "$slug_snap" "-batch-name.md" "slug appears in snapshot filename"

# === per-worktree overlay path archives under project archive/working =======
PDIR_OVERLAY="$(mkproject "$MEM" overlay)"
cat > "$PDIR_OVERLAY/working.myfeature.md" <<'EOF'
# Working — overlay

## Checkpoints

### 2026-07-03 — DONE overlay work
EOF
run "$ARCHIVE" "$PDIR_OVERLAY/working.myfeature.md"
assert_exit 0 "$code" "overlay roll exits 0"
overlay_snap="$(snapshot_path)"
case "$overlay_snap" in
    "$PDIR_OVERLAY/archive/working/"*) _ok "overlay writes to project archive/working" ;;
    *) _bad "overlay writes to project archive/working"; printf '       snapshot: %s\n' "$overlay_snap" ;;
esac
assert_contains "$(cat "$PDIR_OVERLAY/working.myfeature.md")" "archive/working/$(basename "$overlay_snap")" "overlay placeholder names snapshot basename"

# === fence safety: h2 inside checkpoint fence does not split section =========
PDIR_FENCE="$(mkproject "$MEM" fence)"
cat > "$PDIR_FENCE/working.md" <<'EOF'
# Working — fence

## Checkpoints

### 2026-07-04 — DONE fenced body

```
## This is code, not a section
still checkpoint content
```

after fence

## Open threads

- after section
EOF
run "$ARCHIVE" "$PDIR_FENCE/working.md"
assert_exit 0 "$code" "fenced h2 roll exits 0"
fence_snap="$(snapshot_path)"
assert_contains "$(cat "$fence_snap")" "## This is code, not a section" "fenced h2 remains in snapshot"
assert_contains "$(cat "$fence_snap")" "after fence" "content after fenced h2 remains in checkpoint snapshot"
assert_contains "$(section "$PDIR_FENCE/working.md" "## Open threads")" "- after section" "section after checkpoint preserved with fenced h2"

# === ordering: Checkpoints can be last ======================================
PDIR_LAST="$(mkproject "$MEM" last)"
cat > "$PDIR_LAST/working.md" <<'EOF'
# Working — last

## Cross-project learnings (pending promotion)

_(none yet)_

## Checkpoints

### 2026-07-05 — DONE last section
EOF
run "$ARCHIVE" "$PDIR_LAST/working.md"
assert_exit 0 "$code" "last-section roll exits 0"
assert_contains "$(cat "$PDIR_LAST/working.md")" "## Checkpoints" "last-section heading kept"
assert_contains "$(cat "$PDIR_LAST/working.md")" "_(none yet — rolled " "last-section reset written"
assert_not_contains "$(cat "$PDIR_LAST/working.md")" "### 2026-07-05" "last-section old checkpoint removed from working file"

finish
