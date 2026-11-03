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

# === --list / --keep: selective roll ========================================
snap_count_of() {
    if [ -d "$1/archive/working" ]; then
        find "$1/archive/working" -type f ! -name .gitkeep | wc -l | tr -d ' '
    else
        printf '0'
    fi
}

write_multi() {
    cat > "$1" <<'EOF'
# Working — multi

## Cross-project learnings (pending promotion)

Learnings stay.

## Checkpoints

_(none yet — rolled 2026-06-01 to archive/working/old.md)_

### 2026-07-01 — first (old)

**Done:**
- one

~~~
## fake h2 in tilde fence
### fake h3 in tilde fence
~~~

### 2026-07-02 — second (middle)

**Next:**
- two

### 2026-07-03 — third (newest)

**Next:**
- three

## Open threads (not blocking)

- sibling stays
EOF
}

PDIR_M="$(mkproject "$MEM" multi)"
write_multi "$PDIR_M/working.md"
before_multi_sum="$(cksum < "$PDIR_M/working.md")"

run "$ARCHIVE" --list "$PDIR_M/working.md"
assert_exit 0 "$code" "--list exits 0"
assert_eq "$(printf '1\t### 2026-07-01 — first (old)\n2\t### 2026-07-02 — second (middle)\n3\t### 2026-07-03 — third (newest)')" "$out" \
    "--list prints numbered fence-depth-0 entries only"
assert_eq "$before_multi_sum" "$(cksum < "$PDIR_M/working.md")" "--list leaves file byte-identical"
assert_eq "0" "$(snap_count_of "$PDIR_M")" "--list writes no snapshot"

run "$ARCHIVE" --list --section "$LEARN" "$PDIR_M/working.md"
assert_exit 0 "$code" "--list on entry-less section exits 0"
assert_eq "" "$out" "--list on entry-less section prints nothing"
run "$ARCHIVE" --list --section "No such section" "$PDIR_M/working.md"
assert_exit 2 "$code" "--list on absent section exits 2"
assert_contains "$out" "not found" "--list on absent section says not found"

run "$ARCHIVE" --list --keep 1 "$PDIR_M/working.md"
assert_exit 2 "$code" "--list with --keep is a usage error"
assert_eq "0" "$(snap_count_of "$PDIR_M")" "--list with --keep writes no snapshot"

# keep newest
write_multi "$PDIR_M/working.md"
before_open_m="$(section "$PDIR_M/working.md" "## Open threads (not blocking)")"
before_learn_m="$(section "$PDIR_M/working.md" "## Cross-project learnings (pending promotion)")"
run "$ARCHIVE" --keep 3 "$PDIR_M/working.md"
assert_exit 0 "$code" "--keep newest exits 0"
msnap="$(snapshot_path)"
live="$(section "$PDIR_M/working.md" "## Checkpoints")"
assert_contains "$out" "kept 1 of 3" "--keep reports kept count"
assert_contains "$(cat "$msnap")" "### 2026-07-01 — first (old)" "keep newest: snapshot has first"
assert_contains "$(cat "$msnap")" "### 2026-07-02 — second (middle)" "keep newest: snapshot has second"
assert_not_contains "$(cat "$msnap")" "third (newest)" "keep newest: snapshot lacks kept entry"
assert_contains "$(cat "$msnap")" "## Checkpoints" "snapshot carries section heading"
assert_contains "$(cat "$msnap")" "## fake h2 in tilde fence" "tilde-fenced h2 stays inside its entry in snapshot"
assert_contains "$(cat "$msnap")" "### fake h3 in tilde fence" "tilde-fenced h3 stays inside its entry in snapshot"
assert_not_contains "$live" "first (old)" "keep newest: live lacks rolled first"
assert_not_contains "$(cat "$PDIR_M/working.md")" "fake h2" "keep newest: live file lacks tilde-fenced lines of rolled entry"
assert_contains "$live" "### 2026-07-03 — third (newest)" "keep newest: live has kept entry"
assert_contains "$live" "- three" "keep newest: live keeps entry body"
assert_eq "## Checkpoints" "$(printf '%s\n' "$live" | sed -n 1p)" "live: heading first"
assert_eq "" "$(printf '%s\n' "$live" | sed -n 2p)" "live: blank after heading"
assert_contains "$(printf '%s\n' "$live" | sed -n 3p)" "_(none yet — rolled " "live: placeholder third"
assert_eq "" "$(printf '%s\n' "$live" | sed -n 4p)" "live: blank after placeholder"
assert_eq "### 2026-07-03 — third (newest)" "$(printf '%s\n' "$live" | sed -n 5p)" "live: kept entry follows placeholder"
assert_eq "$before_open_m" "$(section "$PDIR_M/working.md" "## Open threads (not blocking)")" "keep: sibling after section byte-identical"
assert_eq "$before_learn_m" "$(section "$PDIR_M/working.md" "## Cross-project learnings (pending promotion)")" "keep: sibling before section byte-identical"
assert_eq "# Working — multi" "$(sed -n 1p "$PDIR_M/working.md")" "keep: H1 untouched"
assert_not_contains "$live" "rolled 2026-06-01" "preamble (old placeholder) replaced in live file"
assert_contains "$(cat "$msnap")" "rolled 2026-06-01 to archive/working/old.md" "preamble (old placeholder) included in snapshot"
run "$ARCHIVE" --list "$PDIR_M/working.md"
assert_eq "$(printf '1\t### 2026-07-03 — third (newest)')" "$out" "--list after keep shows only kept entry"

# keep a middle entry
PDIR_M2="$(mkproject "$MEM" multi2)"
write_multi "$PDIR_M2/working.md"
run "$ARCHIVE" --keep=2 "$PDIR_M2/working.md"
assert_exit 0 "$code" "--keep=2 (middle) exits 0"
msnap2="$(snapshot_path)"
live2="$(section "$PDIR_M2/working.md" "## Checkpoints")"
assert_contains "$(cat "$msnap2")" "first (old)" "keep middle: snapshot has first"
assert_contains "$(cat "$msnap2")" "third (newest)" "keep middle: snapshot has third"
assert_not_contains "$(cat "$msnap2")" "second (middle)" "keep middle: snapshot lacks kept"
assert_contains "$live2" "second (middle)" "keep middle: live has kept"
assert_not_contains "$live2" "third (newest)" "keep middle: live lacks rolled third"
assert_eq "first (old)" "$(grep -o 'first (old)' "$msnap2" </dev/null)" "keep middle: snapshot order preserved (first)"
assert_eq "1" "$(awk '/first \(old\)/{a=NR} /third \(newest\)/{b=NR} END{print (a<b)}' "$msnap2" </dev/null)" "keep middle: rolled entries in original order"

# keep two non-adjacent
PDIR_M3="$(mkproject "$MEM" multi3)"
write_multi "$PDIR_M3/working.md"
run "$ARCHIVE" --keep 1 --keep 3 "$PDIR_M3/working.md"
assert_exit 0 "$code" "--keep 1 --keep 3 exits 0"
msnap3="$(snapshot_path)"
live3="$(section "$PDIR_M3/working.md" "## Checkpoints")"
assert_contains "$(cat "$msnap3")" "second (middle)" "keep non-adjacent: snapshot has the rolled one"
assert_not_contains "$(cat "$msnap3")" "first (old)" "keep non-adjacent: snapshot lacks kept first"
assert_not_contains "$(cat "$msnap3")" "third (newest)" "keep non-adjacent: snapshot lacks kept third"
assert_eq "1" "$(awk '/first \(old\)/{a=NR} /third \(newest\)/{b=NR} END{print (a>0 && b>a)}' "$PDIR_M3/working.md")" "keep non-adjacent: kept in original order"
assert_contains "$(cat "$PDIR_M3/working.md")" "fake h2 in tilde fence" "keep non-adjacent: kept entry's fenced lines byte-intact"
assert_not_contains "$live3" "second (middle)" "keep non-adjacent: live lacks rolled"
assert_eq "$before_open_m" "$(section "$PDIR_M3/working.md" "## Open threads (not blocking)")" "keep non-adjacent: sibling byte-identical"

# kept entry bytes are identical to the original
write_multi "$MEM/orig.md"
assert_eq "$(awk '/^### 2026-07-01/{p=1} /^### 2026-07-02/{p=0} p' "$MEM/orig.md")" \
    "$(awk '/^### 2026-07-01/{p=1} /^### 2026-07-03/{p=0} p' "$PDIR_M3/working.md" | awk '/^### 2026-07-02/{exit} {print}')" \
    "kept entry 1 byte-identical to original"

# fail closed on invalid keeps
PDIR_V="$(mkproject "$MEM" invalid)"
for bad in abc 0 4 -1 "" 1x; do
    write_multi "$PDIR_V/working.md"
    sum_v="$(cksum < "$PDIR_V/working.md")"
    run "$ARCHIVE" --keep "$bad" "$PDIR_V/working.md"
    assert_exit 2 "$code" "--keep '$bad' exits 2"
    assert_eq "$sum_v" "$(cksum < "$PDIR_V/working.md")" "--keep '$bad' leaves file byte-identical"
    assert_eq "0" "$(snap_count_of "$PDIR_V")" "--keep '$bad' writes no snapshot"
done
write_multi "$PDIR_V/working.md"
sum_v="$(cksum < "$PDIR_V/working.md")"
run "$ARCHIVE" --keep 1 --keep 9 "$PDIR_V/working.md"
assert_exit 2 "$code" "valid keep plus invalid keep exits 2"
assert_eq "$sum_v" "$(cksum < "$PDIR_V/working.md")" "valid+invalid keep leaves file byte-identical"
assert_eq "0" "$(snap_count_of "$PDIR_V")" "valid+invalid keep writes no snapshot"
run "$ARCHIVE" --keep
assert_exit 2 "$code" "--keep with no value exits 2"

# keep-all is a no-op
run "$ARCHIVE" --keep 1 --keep 2 --keep 3 "$PDIR_V/working.md"
assert_exit 0 "$code" "keep-all exits 0"
assert_contains "$out" "nothing to roll" "keep-all reports nothing to roll"
assert_eq "$sum_v" "$(cksum < "$PDIR_V/working.md")" "keep-all leaves file byte-identical"
assert_eq "0" "$(snap_count_of "$PDIR_V")" "keep-all writes no snapshot"

# keep-all with carried (non-placeholder) preamble must still be a no-op
PDIR_KP="$(mkproject "$MEM" keepall-preamble)"
cat > "$PDIR_KP/working.md" <<'EOF'
# Working — kp

## Checkpoints

Carried note, not a placeholder.

### 2026-07-01 — only

- x
EOF
sum_kp="$(cksum < "$PDIR_KP/working.md")"
run "$ARCHIVE" --keep 1 "$PDIR_KP/working.md"
assert_exit 0 "$code" "keep-all with real preamble exits 0"
assert_contains "$out" "nothing to roll" "keep-all with real preamble reports nothing to roll"
assert_eq "$sum_kp" "$(cksum < "$PDIR_KP/working.md")" "keep-all with real preamble leaves file byte-identical"
assert_eq "0" "$(snap_count_of "$PDIR_KP")" "keep-all with real preamble writes no snapshot"

# ~~~ fence with ## / ### lines inside an entry does not split under legacy roll
PDIR_T="$(mkproject "$MEM" tilde)"
write_multi "$PDIR_T/working.md"
run "$ARCHIVE" "$PDIR_T/working.md"
assert_exit 0 "$code" "legacy roll with tilde fence exits 0"
assert_contains "$(cat "$(snapshot_path)")" "### fake h3 in tilde fence" "legacy roll: tilde-fenced h3 in snapshot"
assert_eq "## Open threads (not blocking)" "$(grep '^## Open' "$PDIR_T/working.md")" "legacy roll: next section intact after tilde fence"
assert_not_contains "$(section "$PDIR_T/working.md" "## Checkpoints")" "fake h2" "legacy roll: tilde-fenced lines gone from live section"

# longer fence is closed only by an equal-or-longer fence
PDIR_F="$(mkproject "$MEM" longfence)"
cat > "$PDIR_F/working.md" <<'EOF'
# Working — longfence

## Checkpoints

### 2026-07-01 — a

````
```
### not an entry
````

### 2026-07-02 — b

## Open threads

- x
EOF
run "$ARCHIVE" --list "$PDIR_F/working.md"
assert_eq "$(printf '1\t### 2026-07-01 — a\n2\t### 2026-07-02 — b')" "$out" "longer fence not closed by shorter inner fence"

# === B1: --keep values are never glob-expanded or word-split ===============
PDIR_G="$(mkproject "$MEM" globby)"
GCWD="$MEM/globcwd"
mkdir -p "$GCWD"
: > "$GCWD/k1"; : > "$GCWD/k2"; : > "$GCWD/1"; : > "$GCWD/2"
for bad in '*' '?' '1 2' '[1-3]'; do
    write_multi "$PDIR_G/working.md"
    sum_g="$(cksum < "$PDIR_G/working.md")"
    set +e; out="$(cd "$GCWD" && bash "$ARCHIVE" --keep "$bad" "$PDIR_G/working.md" 2>&1)"; code=$?; set -e
    assert_exit 2 "$code" "--keep '$bad' with matching files in cwd exits 2"
    assert_eq "$sum_g" "$(cksum < "$PDIR_G/working.md")" "--keep '$bad' glob case leaves file byte-identical"
    assert_eq "0" "$(snap_count_of "$PDIR_G")" "--keep '$bad' glob case writes no snapshot"
done

# === B3: open fence at EOF fails closed =====================================
write_openfence() {
    cat > "$1" <<'EOF'
# Working — open

## Checkpoints

### 2026-07-01 — a

~~~
unterminated

### 2026-07-02 — b

## Open threads

- x
EOF
}
PDIR_O="$(mkproject "$MEM" openfence)"
write_openfence "$PDIR_O/working.md"
sum_o="$(cksum < "$PDIR_O/working.md")"
for mode in "" "--list" "--keep 1" ; do
    # shellcheck disable=SC2086
    run "$ARCHIVE" $mode "$PDIR_O/working.md"
    assert_exit 2 "$code" "open fence swallowing the section (mode '$mode') exits 2"
    assert_contains "$out" "unclosed code fence" "open fence (mode '$mode') names the problem"
    assert_eq "$sum_o" "$(cksum < "$PDIR_O/working.md")" "open fence (mode '$mode') leaves file byte-identical"
    assert_eq "0" "$(snap_count_of "$PDIR_O")" "open fence (mode '$mode') writes no snapshot"
done
cat > "$PDIR_O/working.md" <<'EOF'
# Working — open

## Checkpoints

### 2026-07-01 — a

- x

## Open threads

```
unterminated in a later sibling
EOF
run "$ARCHIVE" --list "$PDIR_O/working.md"
assert_exit 0 "$code" "open fence in a later sibling is harmless for --list"
assert_eq "$(printf '1\t### 2026-07-01 — a')" "$out" "open fence in a later sibling still lists entries"
run "$ARCHIVE" "$PDIR_O/working.md"
assert_exit 0 "$code" "open fence in a later sibling is harmless for a roll"
assert_file "$(snapshot_path)" "open fence in a later sibling still snapshots"

# === B4: duplicate target heading fails closed ==============================
PDIR_D="$(mkproject "$MEM" dupheading)"
cat > "$PDIR_D/working.md" <<'EOF'
# Working — dup

## Checkpoints

### 2026-07-01 — a

## Open threads

- x

## Checkpoints

### 2026-07-02 — b
EOF
sum_d="$(cksum < "$PDIR_D/working.md")"
for mode in "" "--list" "--keep 1"; do
    # shellcheck disable=SC2086
    run "$ARCHIVE" $mode "$PDIR_D/working.md"
    assert_exit 2 "$code" "duplicate target heading (mode '$mode') exits 2"
    assert_contains "$out" "more than once" "duplicate heading (mode '$mode') names the problem"
    assert_eq "$sum_d" "$(cksum < "$PDIR_D/working.md")" "duplicate heading (mode '$mode') leaves file byte-identical"
    assert_eq "0" "$(snap_count_of "$PDIR_D")" "duplicate heading (mode '$mode') writes no snapshot"
done
cat > "$PDIR_D/working.md" <<'EOF'
# Working — dup

## Checkpoints

### 2026-07-01 — a

```
## Checkpoints
```
EOF
run "$ARCHIVE" --list "$PDIR_D/working.md"
assert_exit 0 "$code" "target heading inside a fence is not a duplicate"

# === B2: --list creates no temp files =======================================
write_multi "$PDIR_M/working.md"
before_ls="$(ls -A "$PDIR_M" | sort)"
run "$ARCHIVE" --list "$PDIR_M/working.md"
assert_exit 0 "$code" "--list (temp-file check) exits 0"
assert_eq "$before_ls" "$(ls -A "$PDIR_M" | sort)" "--list creates no files in the working file's dir"

# === N1/N4 ==================================================================
write_multi "$PDIR_M/working.md"
sum_n="$(cksum < "$PDIR_M/working.md")"
run "$ARCHIVE" --section "No such section" --keep 1 "$PDIR_M/working.md"
assert_exit 2 "$code" "--keep with absent section exits 2"
assert_contains "$out" "not found" "--keep with absent section says not found"
assert_eq "$sum_n" "$(cksum < "$PDIR_M/working.md")" "--keep with absent section leaves file byte-identical"
run "$ARCHIVE" --list "$PDIR_M/working.md" extra-slug
assert_exit 2 "$code" "--list with a slug argument is a usage error"

# === slug is validated: trailing options are not slugs ======================
PDIR_S="$(mkproject "$MEM" slugcheck)"
for bad in --keep=2 --list --keep ../x -x "a/b" "" ".hidden" "a b"; do
    write_multi "$PDIR_S/working.md"
    sum_s="$(cksum < "$PDIR_S/working.md")"
    run "$ARCHIVE" "$PDIR_S/working.md" "$bad"
    assert_exit 2 "$code" "slug '$bad' exits 2"
    assert_eq "$sum_s" "$(cksum < "$PDIR_S/working.md")" "slug '$bad' leaves file byte-identical"
    assert_eq "0" "$(snap_count_of "$PDIR_S")" "slug '$bad' writes no snapshot"
done
write_multi "$PDIR_S/working.md"
run "$ARCHIVE" "$PDIR_S/working.md" "v1.2_fix-3"
assert_exit 0 "$code" "valid slug exits 0"
assert_contains "$(snapshot_path)" "-v1.2_fix-3.md" "valid slug used in snapshot name"

# === awk values are literal: backslashes are never interpreted ==============
PDIR_B="$(mkproject "$MEM" 'back\slash')"
cat > "$PDIR_B/working.md" <<'EOF'
# Working — bs

## Notes \t tab

### 2026-07-01 — one

- x

### 2026-07-02 — two

- y

## Other

- z
EOF
run "$ARCHIVE" --list --section 'Notes \t tab' "$PDIR_B/working.md"
assert_exit 0 "$code" "--section with backslash escape lists"
assert_eq "$(printf '1\t### 2026-07-01 — one\n2\t### 2026-07-02 — two')" "$out" "--section with backslash escape matches literally"
run "$ARCHIVE" --section 'Notes \t tab' --keep 2 "$PDIR_B/working.md"
assert_exit 0 "$code" "--section with backslash escape rolls in a backslash dir"
bsnap="$(snapshot_path)"
assert_contains "$(cat "$bsnap")" "## Notes \\t tab" "backslash heading in snapshot"
assert_contains "$(cat "$bsnap")" "### 2026-07-01 — one" "backslash section rolled entry 1"
assert_contains "$(cat "$PDIR_B/working.md")" "### 2026-07-02 — two" "backslash section kept entry 2"
assert_contains "$(cat "$PDIR_B/working.md")" "- z" "backslash section sibling intact"

# === --list on absent vs empty section ======================================
PDIR_E="$(mkproject "$MEM" listabsent)"
cat > "$PDIR_E/working.md" <<'EOF'
# Working — e

## Checkpoints

_(none yet)_
EOF
run "$ARCHIVE" --list "$PDIR_E/working.md"
assert_exit 0 "$code" "--list on empty-but-present section exits 0"
assert_eq "" "$out" "--list on empty-but-present section prints nothing"
run "$ARCHIVE" --list --section "Nope" "$PDIR_E/working.md"
assert_exit 2 "$code" "--list on absent section exits 2"
assert_contains "$out" "section '## Nope' not found" "--list absent message matches --keep's"
run "$ARCHIVE" --section "Nope" "$PDIR_E/working.md"
assert_exit 0 "$code" "legacy roll on absent section still exits 0"
assert_contains "$out" "nothing to roll" "legacy roll on absent section still says nothing to roll"

# === section last + last kept entry ends blank: no extra blank at EOF =======
PDIR_Z="$(mkproject "$MEM" eofblank)"
cat > "$PDIR_Z/working.md" <<'EOF'
# Working — z

## Checkpoints

### 2026-07-01 — old

- a

### 2026-07-02 — keep

- b

EOF
run "$ARCHIVE" --keep 2 "$PDIR_Z/working.md"
assert_exit 0 "$code" "keep with trailing blank at EOF exits 0"
assert_eq "- b" "$(tail -n 1 "$PDIR_Z/working.md")" "no trailing blank line left at EOF after keep"
write_multi "$MEM/z2.md"; cp "$MEM/z2.md" "$PDIR_Z/working.md"
run "$ARCHIVE" --section "Open threads (not blocking)" --keep 1 "$PDIR_Z/working.md"
assert_exit 2 "$code" "keep on section without entries exits 2"

# === relative path shaped like name=value is a file, not an awk assignment ===
EQDIR="$(mkproject "$MEM" eqpath)"
printf '%s\n' '# Working' '' '## Checkpoints' '' '### 2026-01-01 — a' '' '- a' > "$EQDIR/x=y"
set +e
lout="$(cd "$EQDIR" && bash "$ARCHIVE" --list x=y </dev/null 2>&1)"; lcode=$?
rout="$(cd "$EQDIR" && bash "$ARCHIVE" x=y </dev/null 2>&1)"; rcode=$?
set -e
assert_exit 0 "$lcode" "name=value path: --list exits 0"
assert_contains "$lout" "### 2026-01-01 — a" "name=value path: --list reads the file"
assert_exit 0 "$rcode" "name=value path: roll exits 0"
assert_contains "$rout" "checkpoint-archive: snapshot " "name=value path: roll writes a snapshot"
assert_not_contains "$(cat "$EQDIR/x=y")" "### 2026-01-01 — a" "name=value path: entry rolled out of live file"

finish
