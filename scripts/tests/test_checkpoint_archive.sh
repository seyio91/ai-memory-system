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

# === --section rolls the learnings section, and ONLY it =====================
# This is what /promote-memory calls. Its Step 6 used to `mv` the whole
# working.md and start a fresh empty one, destroying Checkpoints and Open
# threads along with it. The heading also carries parentheses — matched as a
# literal, since an awk regex would read them as grouping, miss the section,
# and still exit 0 having rolled nothing.
LEARN="Cross-project learnings (pending promotion)"
PDIR_L="$(mkproject "$MEM" learn)"
cat > "$PDIR_L/working.md" <<'EOF'
# Working — learn

## Cross-project learnings (pending promotion)

- rtk ls returns empty on a non-en_US locale — bisect the env, not the story.

## Checkpoints

### 2026-07-05 — in-flight, must survive

**Next:**
- unfinished work

## Open threads (not blocking)

- keep this too
EOF
before_cp="$(section "$PDIR_L/working.md" "## Checkpoints")"
before_ot="$(section "$PDIR_L/working.md" "## Open threads (not blocking)")"

run "$ARCHIVE" --section "$LEARN" "$PDIR_L/working.md"
assert_exit 0 "$code" "--section roll exits 0"
learn_snap="$(snapshot_path)"
assert_file "$learn_snap" "--section writes a snapshot"
assert_contains "$(cat "$learn_snap")" "rtk ls returns empty" "snapshot carries the learning body"
assert_contains "$(cat "$learn_snap")" "# Archived cross-project learnings (pending promotion) — learn —" \
    "snapshot header names the rolled section"
assert_contains "$out" "rolled $LEARN for learn" "report names the rolled section"

learned_after="$(section "$PDIR_L/working.md" "## Cross-project learnings (pending promotion)")"
assert_contains "$learned_after" "_(none yet — rolled " "learnings body reset to placeholder"
assert_not_contains "$learned_after" "rtk ls returns empty" "promoted learning removed from working file"

# The whole point: siblings are byte-identical, including an in-flight checkpoint.
assert_eq "$before_cp" "$(section "$PDIR_L/working.md" "## Checkpoints")" \
    "Checkpoints untouched — /checkpoint-archive still owns that section"
assert_eq "$before_ot" "$(section "$PDIR_L/working.md" "## Open threads (not blocking)")" \
    "Open threads untouched — owned by neither command"

# A section that is absent must no-op, not roll a neighbour by accident.
PDIR_ABS="$(mkproject "$MEM" absent)"
cat > "$PDIR_ABS/working.md" <<'EOF'
# Working — absent

## Checkpoints

### 2026-07-05 — DONE
EOF
before_abs="$(cat "$PDIR_ABS/working.md")"
run "$ARCHIVE" --section "$LEARN" "$PDIR_ABS/working.md"
assert_exit 0 "$code" "missing --section no-ops with exit 0"
assert_contains "$out" "nothing to roll" "missing --section reports nothing to roll"
assert_eq "$before_abs" "$(cat "$PDIR_ABS/working.md")" "missing --section leaves the file byte-identical"

# Bad invocations fail loudly rather than defaulting to Checkpoints.
run "$ARCHIVE" --section
assert_exit 2 "$code" "--section with no value exits 2"
run "$ARCHIVE" --bogus "$PDIR_L/working.md"
assert_exit 2 "$code" "unknown flag exits 2"

# === two rolls in one minute must not clobber each other ====================
# The stamp is minute-resolution. Rolling learnings and then checkpoints — what
# /promote-memory followed by /checkpoint-archive does — produced the SAME
# filename, and the second snapshot silently overwrote the first, destroying
# audit trail. Caught by live exercise, not by any assertion that existed then.
PDIR_C="$(mkproject "$MEM" collide)"
cat > "$PDIR_C/working.md" <<'EOF'
# Working — collide

## Cross-project learnings (pending promotion)

- learning body, must reach its own snapshot

## Checkpoints

### 2026-07-05 — DONE checkpoint body, must reach a different snapshot
EOF
run "$ARCHIVE" --section "$LEARN" "$PDIR_C/working.md"
assert_exit 0 "$code" "first roll exits 0"
first_snap="$(snapshot_path)"
run "$ARCHIVE" "$PDIR_C/working.md"
assert_exit 0 "$code" "second roll in the same minute exits 0"
second_snap="$(snapshot_path)"

assert_not_contains "$first_snap" "-2.md" "first snapshot has no collision suffix"
assert_file "$first_snap" "first snapshot still exists after the second roll"
assert_contains "$(cat "$first_snap")" "learning body" "first snapshot keeps the learnings it captured"
assert_contains "$(cat "$second_snap")" "checkpoint body" "second snapshot holds the checkpoints"
assert_contains "$second_snap" "-2.md" "collision suffix appended to the second snapshot"

finish
