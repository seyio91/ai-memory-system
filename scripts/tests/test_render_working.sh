#!/usr/bin/env bash
# formatters/working.sh render_working — Checkpoints render window, via both
# formatters and via check-memory-size.sh --payload.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
CHECK="$SCRIPTS_DIR/check-memory-size.sh"
. "$SCRIPTS_DIR/formatters/xml.sh"
. "$SCRIPTS_DIR/formatters/md.sh"

T="$(new_sandbox)"
trap 'rm -rf "$T"' EXIT
unset AI_MEMORY_CHECKPOINT_WINDOW

# mkwork <path> <n> [preamble-line]
mkwork() {
    local f="$1" n="$2" pre="${3:-}" i
    {
        printf '# Working\n\n## Open threads\n- thread\n\n## Checkpoints\n'
        [ -n "$pre" ] && printf '%s\n\n' "$pre"
        i=1
        while [ "$i" -le "$n" ]; do
            printf '### cp%d\nbody%d\n\n' "$i" "$i"
            i=$((i + 1))
        done
    } > "$f"
}

MARK='older checkpoints not loaded'
W="$T/working.md"

# --- 0 / 1 / 2 checkpoints: raw ---------------------------------------------
for n in 0 1 2; do
    mkwork "$W" "$n"
    assert_eq "$(cat "$W")" "$(render_working "$W")" "$n checkpoints: unchanged"
done

# --- 7 checkpoints ----------------------------------------------------------
mkwork "$W" 7 '_(rolled 2026-01-01)_'
out="$(render_working "$W")"
assert_contains "$out" "_(5 older checkpoints not loaded — see working.md)_" "7 cp: omitted line says 5"
assert_contains "$out" "_(rolled 2026-01-01)_" "7 cp: preamble preserved"
assert_contains "$out" "### cp6" "7 cp: cp6 kept"
assert_contains "$out" "### cp7" "7 cp: cp7 kept"
assert_not_contains "$out" "### cp5" "7 cp: cp5 dropped"
assert_not_contains "$out" "body1" "7 cp: cp1 body dropped"
assert_contains "$out" "- thread" "7 cp: other section kept"
assert_eq "1" "$(printf '%s\n' "$out" | grep -c "$MARK")" "7 cp: exactly one omitted line"
pre_line=$(printf '%s\n' "$out" | grep -n 'rolled' | cut -d: -f1)
mark_line=$(printf '%s\n' "$out" | grep -n "$MARK" | cut -d: -f1)
cp6_line=$(printf '%s\n' "$out" | grep -n '### cp6' | cut -d: -f1)
assert_eq "yes" "$([ "$pre_line" -lt "$mark_line" ] && [ "$mark_line" -lt "$cp6_line" ] && echo yes)" "7 cp: order preamble < marker < kept"

# --- sections outside Checkpoints identical to the unfiltered render --------
before="$(printf '%s\n' "$(cat "$W")" | sed '/^## Checkpoints/,$d')"
after="$(printf '%s\n' "$out" | sed '/^## Checkpoints/,$d')"
assert_eq "$before" "$after" "7 cp: text before Checkpoints identical"

# --- section followed by another section ------------------------------------
{ cat "$W"; printf '## Cross-project learnings\n- keep me\n'; } > "$T/tail.md"
out="$(render_working "$T/tail.md")"
assert_contains "$out" "- keep me" "trailing section after Checkpoints kept"
assert_contains "$out" "## Cross-project learnings" "trailing heading kept"
assert_not_contains "$out" "### cp1" "trailing-section case: old entries still dropped"

# --- env override -----------------------------------------------------------
out="$(AI_MEMORY_CHECKPOINT_WINDOW=3 render_working "$W")"
assert_contains "$out" "_(4 older checkpoints not loaded — see working.md)_" "window=3: 4 omitted"
assert_contains "$out" "### cp5" "window=3: cp5 kept"
assert_not_contains "$out" "### cp4" "window=3: cp4 dropped"
for bad in 0 abc -1 ""; do
    out="$(AI_MEMORY_CHECKPOINT_WINDOW=$bad render_working "$W")"
    assert_contains "$out" "_(5 older checkpoints not loaded" "window='$bad': falls back to 2"
done

# --- missing Checkpoints section -------------------------------------------
printf '# Working\n\n## Open threads\n### a\n### b\n### c\n' > "$T/nosec.md"
assert_eq "$(cat "$T/nosec.md")" "$(render_working "$T/nosec.md")" "no Checkpoints section: unchanged"

# --- fences -----------------------------------------------------------------
cat > "$T/fence.md" <<'X'
# Working

```
## Checkpoints
### fake1
### fake2
### fake3
```

## Checkpoints
### real1
```
### inside-fence
```
### real2
~~~
### tilde-fence
~~~
### real3
last
X
out="$(render_working "$T/fence.md")"
assert_contains "$out" "_(1 older checkpoints not loaded" "fence: only fence-depth-0 headings count (1 dropped)"
assert_not_contains "$out" "real1" "fence: real1 dropped"
assert_not_contains "$out" "inside-fence" "fence: fenced ### stays inside its entry (dropped with real1)"
assert_contains "$out" "### fake3" "fence: fenced fake section untouched"
assert_contains "$out" "tilde-fence" "fence: tilde fence belongs to real2 (kept)"
assert_contains "$out" "### real3" "fence: real3 kept"

# --- fail-safe: awk failure prints the raw file ------------------------------
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 2\n' > "$T/bin/awk"; chmod +x "$T/bin/awk"
mkwork "$W" 7
assert_eq "$(cat "$W")" "$(PATH="$T/bin:$PATH" render_working "$W")" "awk failure: raw file"
printf '#!/bin/sh\nprintf junk\nexit 2\n' > "$T/bin/awk"
assert_eq "$(cat "$W")" "$(PATH="$T/bin:$PATH" render_working "$W")" "awk failure with partial output: raw file"
rm -rf "${T:?}/bin"

# --- never modifies the file ------------------------------------------------
h1="$(cksum < "$W")"; render_working "$W" >/dev/null; h2="$(cksum < "$W")"
assert_eq "$h1" "$h2" "working file untouched"

# --- both formatters --------------------------------------------------------
rec="$(printf 'working\t%s\tworking' "$W")"
xo="$(printf '%s\n' "$rec" | xml_render_full)"
mo="$(printf '%s\n' "$rec" | md_render)"
for pair in "xml:$xo" "md:$mo"; do
    f="${pair%%:*}"; o="${pair#*:}"
    assert_contains "$o" "_(5 older checkpoints not loaded — see working.md)_" "$f formatter: omitted line"
    assert_contains "$o" "### cp7" "$f formatter: newest kept"
    assert_not_contains "$o" "### cp5" "$f formatter: older dropped"
    assert_contains "$o" "- thread" "$f formatter: other section kept"
done
assert_contains "$xo" "<memory:working>" "xml formatter: wrapper kept"
assert_contains "$mo" "# === WORKING MEMORY ===" "md formatter: header kept"
xo3="$(printf '%s\n' "$rec" | AI_MEMORY_CHECKPOINT_WINDOW=3 xml_render_full)"
assert_contains "$xo3" "### cp5" "xml formatter: env override honoured"

# --- check-memory-size --payload counts the windowed render (R5) ------------
MEM="$T/mem"; HARN="$T/harn"
mkdir -p "$MEM/projects/proj" "$HARN/capped"
printf -- '---\ntopic: proj\nscope: project\nsummary: s\n---\n# Project: proj\n' > "$MEM/projects/proj/memory.md"
python3 - "$MEM/projects/proj/working.md" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    f.write("# Working\n\n## Checkpoints\n")
    for i in range(1, 8):
        f.write("### cp%d\n%s\n\n" % (i, ("w%d" % i) * 1000))
PY
printf 'name = capped\nformat = xml\nsession_chunks = 1\n' > "$HARN/capped/manifest"
runp() {
    set +e
    OUT="$(MEMORY_DIR="$MEM" AI_MEMORY_HARNESSES_DIR="$HARN" "$@" bash "$CHECK" --payload proj 2>&1)"
    RC=$?
    set -e
}
runp env
assert_exit 0 "$RC" "--payload: windowed render fits a 1-chunk cap"
runp env AI_MEMORY_CHECKPOINT_WINDOW=99
assert_exit 1 "$RC" "--payload: same file with a 99 window exceeds the cap (window is what keeps it under)"

finish
