#!/usr/bin/env bash
# Size + payload budget check for project memory.
#
# Project `memory.md` holds decisions and constraints: let it grow past a
# budget and every session pays for it at load time. A long line is usually a
# table or a wall of prose that would read better split up. Both are WARN —
# style, not breakage. A rendered session payload that needs more chunks than
# a harness's manifest declares is different: the harness truncates silently
# past the declared cap, so that one is ERROR.
#
# Usage:
#   check-memory-size.sh --file <memory.md> [<file>...]
#   check-memory-size.sh --payload <project> [--working <path>]
# Prints  <file>:<line>: <reason>   one per finding (WARN/ERROR named in the text).
# Exit    0 clean, 1 findings, 2 usage error.
#
# Two-Path: this is also the hand-runnable form of the rule. lint-memory.sh
# will call it across the tree and the memory-write hook will call it on one
# file/project at the moment it is edited (Phase 4) — one definition, so the
# two can never disagree.
set -uo pipefail

# --- thresholds, defined once ------------------------------------------------
# Both budgets are clean AT the threshold ("stays within", not "stays under") —
# pinned by tests at the exact boundary and one byte over.
FILE_BUDGET_BYTES=16384
LINE_BUDGET_BYTES=400

# --- engine location (this install) vs MEMORY_DIR (the tree being inspected) -
# Mirrors memory_write_guard.sh's hook_dir / check-changelog-drift split: the
# script's OWN location is always the engine (code + harness manifests, which
# ship with the install), regardless of what --payload's MEMORY_DIR points the
# PROJECT lookup at. Resolving harnesses from MEMORY_DIR would break the
# moment MEMORY_DIR pointed at a worktree or a test sandbox that carries no
# harnesses/ of its own.
_cms_resolve() {
    local p="$1" t
    while [ -L "$p" ]; do
        t="$(readlink "$p")"
        case "$t" in
            /*) p="$t" ;;
            *)  p="$(dirname "$p")/$t" ;;
        esac
    done
    ( cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")" )
}
_cms_self="$(_cms_resolve "$0")"
ENGINE_ROOT="$(cd "$(dirname "$_cms_self")/.." && pwd)"
# Test seam (same var executor.sh uses for the same reason): override to point
# at a fixture registry without standing up a whole fake install.
HARNESSES_DIR="${AI_MEMORY_HARNESSES_DIR:-$ENGINE_ROOT/harnesses}"
: "${MEMORY_DIR:=$ENGINE_ROOT}"
export MEMORY_DIR

RENDERER="$ENGINE_ROOT/scripts/hooks/render-session-payload.sh"
# Test seam, same reasoning as HARNESSES_DIR above: a fake slicer lets a test
# prove the pre-filter below actually SKIPPED the expensive render | slice
# pipe (nothing writes to the fixture's marker) rather than merely asserting
# on an output that would look the same whether the pipe ran or not.
SLICER="${AI_MEMORY_SLICER_OVERRIDE:-$ENGINE_ROOT/scripts/payload-slices.py}"

# manifest.sh is deliberately NOT sourced here: _cms_manifest_fields below
# reads the two scalar keys --payload needs without it, for performance (see
# that function's header). Nothing else in this script needs manifest.sh.

usage() {
    printf 'usage: %s --file <memory.md> [<file>...]\n' "$(basename "$0")" >&2
    printf '       %s --payload <project> [--working <path>]\n' "$(basename "$0")" >&2
    exit 2
}

[ "$#" -ge 1 ] || usage

found=0

# --- --file mode --------------------------------------------------------------
# check_file <path> — emits at most one budget finding and one long-line
# finding for this file. Absent files are silently skipped (parity with
# check-changelog-drift.sh, which globs can hand a dangling pattern to).
check_file() {
    local f="$1" size
    [ -f "$f" ] || return 0

    size=$(wc -c <"$f" | tr -d '[:space:]')
    if [ "$size" -gt "$FILE_BUDGET_BYTES" ]; then
        printf '%s:1: WARN budget — %s bytes exceeds the %s-byte memory.md budget\n' \
            "$f" "$size" "$FILE_BUDGET_BYTES"
        found=1
    fi

    # Long lines: ONE finding per file naming the count and the longest few
    # line numbers, not one WARN per line — a per-line report on a 160-line
    # offender would bury every other signal in the run.
    # LC_ALL=C makes awk's length() count BYTES, not locale characters, so a
    # multi-byte UTF-8 line is measured the same way `wc -c` measures the file.
    local longlines
    longlines="$(LC_ALL=C awk -v budget="$LINE_BUDGET_BYTES" \
        '{ if (length($0) > budget) print length($0)"\t"NR }' "$f")"
    if [ -n "$longlines" ]; then
        local count top_line top_list
        count=$(printf '%s\n' "$longlines" | wc -l | tr -d '[:space:]')
        top_line=$(printf '%s\n' "$longlines" | sort -t"$(printf '\t')" -k1,1rn | head -1 | cut -f2)
        top_list="$(printf '%s\n' "$longlines" | sort -t"$(printf '\t')" -k1,1rn | head -5 | cut -f2 | paste -sd, -)"
        printf '%s:%s: WARN long-line — %s line(s) exceed %s bytes (longest: %s)\n' \
            "$f" "$top_line" "$count" "$LINE_BUDGET_BYTES" "$top_list"
        found=1
    fi
}

# --- --payload mode ------------------------------------------------------------

# --- initiative-alert reuse (perf) -------------------------------------------
# render_initiative_alert's real cost is initiative-status.sh — ~0.9s per
# matching active initiative (P4 measured --payload at ~91s across 19 real
# projects before this existed). That cost is the SAME for every
# harness/working-file combination of one project: it depends only on the
# project and initiatives/, never on format or which working file is in play.
# check_payload can call render_slice_count a dozen times for one project (N
# harnesses x M working files); _cms_get_alert pays the scan once, lazily
# (only when the pre-filter below decides a combo needs an exact render at
# all), and every later call for the same project reuses it.
_cms_alert_project=""
_cms_alert_set=""
_cms_alert_lines=""

# _cms_get_alert <project> — populates _cms_alert_set / _cms_alert_lines,
# computing via one `--alert-lines` subprocess the first time this project is
# asked for and reusing the cached values after. Subprocess, fail-open: a
# crash or a missing marker (the renderer never even started) degrades to "no
# alert" — identical to render_initiative_alert's own `|| true` fail-open path.
_cms_get_alert() {
    local project="$1" out
    [ "$_cms_alert_project" = "$project" ] && [ -n "$_cms_alert_set" ] && return 0
    out="$(MEMORY_DIR="$MEMORY_DIR" bash "$RENDERER" --alert-lines "$project" 2>/dev/null)" || out=""
    case "$out" in
        *"$ALERT_LINES_MARKER") out="${out%"$ALERT_LINES_MARKER"}" ;;
        *) out="" ;;
    esac
    _cms_alert_project="$project"
    _cms_alert_set="1"
    _cms_alert_lines="$out"
}
# Must match render-session-payload.sh's ALERT_LINES_MARKER exactly — the two
# are never sourced from one place (Two-Path/subprocess contract, see the
# header), so this is the one constant duplicated by hand across that split.
ALERT_LINES_MARKER=$'\x01''AI_MEMORY_ALERT_END'$'\x01'

# --- cheap pre-filter (perf) --------------------------------------------------
# A pre-filter that skips the exact render must be SOUND: it may only skip a
# combination that cannot possibly overflow, under worst-case assumptions.
#
# The slicer (payload-slices.py) packs lines greedily into <=MAX-byte slices.
# That means every slice except (maybe) the last has length strictly greater
# than MAX - L, where L is the longest line in the rendered payload — if a
# slice's content were <= MAX - L, the NEXT line (<= L bytes) would still fit
# inside it and the greedy packer would have appended it instead of starting
# a new slice. So for RAW bytes of content and MAX-L > 0:
#
#     slices <= floor(raw / (MAX - L)) + 1
#
# (+1 covers the final, possibly-short slice.) When L >= MAX, a single line
# can already exceed a slice on its own, so no such bound exists — every line
# could in principle be its own slice, and the only sound answer is "render
# it exactly" (never skip).
#
# raw and L are both measured on the RAW markdown, but the rendered payload is
# raw PLUS section tags/headings the render step adds — rendering is always at
# least as big. The same 75% margin used before is kept, now applied as an
# over-estimate of the bound's INPUT rather than a threshold on raw bytes
# directly: raw is inflated by 100/75 (x4/3) before computing the bound, and L
# gets a small constant added for the render's own wrapper lines (section
# open/close tags; measured ~163 B for the longest chunk-framing line — see
# payload-slices.py's NOTE/head — rounded up for headroom). Skip only when
# L < MAX and the resulting bound is <= the harness's cap; anything else
# (including "no cap declared at all") falls through to the exact render.
#
# The bound MUST also cover the initiative-alert block render_full inserts
# ahead of <memory:working> (see render-session-payload.sh /
# session_start_memory.sh) — an alert is render content like any other and
# omitting it from raw/L makes the "skip" side of this filter unsound. Before
# applying the bound, _cms_project_targeted asks lib.sh's cheap
# _initiative_has_target predicate (the same "## Targets" awk scan
# _compute_initiative_alert_lines uses, without its initiative-status.sh
# cost) whether ANY active initiative targets this project. "no" proves the
# alert is empty for free — raw/L are used as-is. "yes" pays for the real
# alert text once via _cms_get_alert and folds its bytes/longest line into
# raw/L before the bound below ever runs.
#
# This is a pre-filter, not a replacement for the exact check: anything NOT
# skipped still goes through render_slice_count and is counted exactly.
PREFILTER_MARGIN_PCT=75
WRAPPER_LINE_MARGIN_BYTES=256

# SLICE_MAX_BYTES mirrors payload-slices.py's MAX by reading it from that file
# rather than redeclaring it, so the two constants can never drift apart; the
# fallback covers an install where the slicer's shape changes in a way this
# grep can't follow.
_cms_slice_max_bytes() {
    local v
    v="$(sed -n 's/^MAX[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$SLICER" 2>/dev/null | head -1)"
    case "$v" in ''|*[!0-9]*) v=9000 ;; esac
    printf '%s' "$v"
}

# PREFILTER_MIN_CAP / PREFILTER_SLICE_MAX are initialized lazily by
# _cms_init_prefilter(<min cap>), not at top-level and not by their own
# manifest scan: manifest.sh's reader is subprocess-heavy per line (measured
# ~0.3s per manifest), and check_payload already makes ONE pass over every
# harness manifest to collect the capped ones — it hands this function the
# minimum cap it found in that same pass. Using the MINIMUM cap (rather than
# the cap of the one harness being checked) keeps one skip decision sound for
# every harness check_payload will check afterward: if the bound clears the
# smallest cap, it clears every larger one too. A second scan here would
# silently double the manifest-read cost for nothing; --file mode
# (lint-memory.sh's per-project-memory.md sweep) never reaches check_payload
# at all, so it never pays for this either.
PREFILTER_MIN_CAP=""
PREFILTER_SLICE_MAX=""
_cms_prefilter_ready=""
_cms_init_prefilter() {
    local min_cap="${1:-}"
    [ -n "$_cms_prefilter_ready" ] && return 0
    _cms_prefilter_ready=1
    [ -n "$min_cap" ] || return 0
    PREFILTER_MIN_CAP="$min_cap"
    PREFILTER_SLICE_MAX="$(_cms_slice_max_bytes)"
}

# _cms_domain_bytes — bytes AND longest line of the domain section an
# md-format payload carries. md_render emits a frontmatter-derived index of
# domain/ (_md_render_domain), not the files' content, so summing
# domain/*.md's own bytes/lines overestimated the payload ~25x and forced an
# exact render for every project on every md harness. Rendered once per
# invocation (both numbers from the SAME render, one awk pass) and cached in
# _cms_domain_cache / _cms_domain_max_line; call it outside `$( )` so the
# cache survives.
_cms_domain_cache=""
_cms_domain_max_line=0
_cms_domain_ready=""
_cms_domain_bytes() {
    [ -n "$_cms_domain_ready" ] && return 0
    _cms_domain_ready=1
    local stats
    stats="$(
        MEMORY_DIR="$MEMORY_DIR" bash -c '. "$1/scripts/hooks/lib.sh" && [ -d "$MEMORY_DIR/domain" ] && _md_render_domain "$MEMORY_DIR/domain"' _ "$ENGINE_ROOT" 2>/dev/null \
        | LC_ALL=C awk '{ n = length($0); if (n > max) max = n; bytes += n + 1 } END { printf "%d\t%d", bytes+0, max+0 }'
    )"
    _cms_domain_cache="${stats%%$'\t'*}"
    _cms_domain_max_line="${stats#*$'\t'}"
    case "$_cms_domain_cache" in ''|*[!0-9]*) _cms_domain_cache=0 ;; esac
    case "$_cms_domain_max_line" in ''|*[!0-9]*) _cms_domain_max_line=0 ;; esac
}

# _cms_project_targeted <project> — true when ANY active initiative targets
# <project>, via lib.sh's _initiative_has_target predicate (the cheap "##
# Targets" awk scan _compute_initiative_alert_lines also uses, WITHOUT its
# initiative-status.sh cost). Sourced the same way _cms_domain_bytes sources
# _md_render_domain above — one subprocess, reusing lib.sh's match logic
# rather than duplicating the awk here, so the two can never drift apart.
# Cached across every harness/working-file combination this invocation
# checks: --payload takes exactly one project, so the answer is the same for
# all of them (same one-invocation-one-value reasoning as _cms_domain_bytes).
_cms_target_ready=""
_cms_target_present=""
_cms_project_targeted() {
    local project="$1"
    if [ -n "$_cms_target_ready" ]; then
        [ "$_cms_target_present" = "1" ]
        return
    fi
    _cms_target_ready=1
    _cms_target_present="0"
    if MEMORY_DIR="$MEMORY_DIR" bash -c '. "$1/scripts/hooks/lib.sh" 2>/dev/null && _initiative_has_target "$2"' _ "$ENGINE_ROOT" "$project" >/dev/null 2>&1; then
        _cms_target_present="1"
    fi
    [ "$_cms_target_present" = "1" ]
}

# _cms_alert_stats — bytes AND longest line of the cached initiative-alert
# text (_cms_alert_lines, populated by _cms_get_alert above). _cms_get_alert
# already pays the initiative-status.sh cost once per project and caches the
# raw text; this just avoids re-running the awk pass over that text for every
# harness/working-file combination.
_cms_alert_stats_ready=""
_cms_alert_bytes=0
_cms_alert_max_line=0
_cms_alert_stats() {
    [ -n "$_cms_alert_stats_ready" ] && return 0
    _cms_alert_stats_ready=1
    [ -n "$_cms_alert_lines" ] || return 0
    local stats
    stats="$(printf '%s\n' "$_cms_alert_lines" \
        | LC_ALL=C awk '{ n = length($0); if (n > max) max = n; bytes += n + 1 } END { printf "%d\t%d", bytes+0, max+0 }')"
    _cms_alert_bytes="${stats%%$'\t'*}"
    _cms_alert_max_line="${stats#*$'\t'}"
    case "$_cms_alert_bytes" in ''|*[!0-9]*) _cms_alert_bytes=0 ;; esac
    case "$_cms_alert_max_line" in ''|*[!0-9]*) _cms_alert_max_line=0 ;; esac
}

# _cms_under_prefilter <project> <format> <working> — true when the sound
# slice-count bound derived below clears PREFILTER_MIN_CAP (skip the exact
# render); false — including "no cap declared at all" or "longest line >=
# MAX" — always falls through to the exact render. See the header comment
# above for the derivation.
_cms_under_prefilter() {
    local project="$1" format="$2" working="$3"
    # Invariant: check_payload always calls _cms_init_prefilter (with the min
    # cap from its own manifest pass) before this runs. Not re-called here —
    # see _cms_init_prefilter's header for why a second scan is the thing
    # being avoided.
    [ -n "$PREFILTER_MIN_CAP" ] || return 1

    local stats raw max_line
    # ONE `cat | awk` pass (not a per-file wc+awk loop) gets BOTH raw bytes
    # and the longest line from the same read of the same files. Same
    # "absent file contributes nothing" semantics as the old `wc -c` version:
    # cat's stderr for a missing path is discarded and the rest of the sum
    # still comes through the one pipe.
    stats="$(cat "$MEMORY_DIR/identity.md" "$MEMORY_DIR/orchestrator.md" "$MEMORY_DIR/index.md" \
                 "$MEMORY_DIR/projects/$project/memory.md" "$working" 2>/dev/null \
             | LC_ALL=C awk '{ n = length($0); if (n > max) max = n; bytes += n + 1 } END { printf "%d\t%d", bytes+0, max+0 }')"
    raw="${stats%%$'\t'*}"
    max_line="${stats#*$'\t'}"
    case "$raw" in ''|*[!0-9]*) raw=0 ;; esac
    case "$max_line" in ''|*[!0-9]*) max_line=0 ;; esac

    if [ "$format" = "md" ]; then
        _cms_domain_bytes
        raw=$(( raw + _cms_domain_cache ))
        [ "$_cms_domain_max_line" -gt "$max_line" ] && max_line="$_cms_domain_max_line"
    fi

    # The initiative-alert block is render content too (see the header
    # comment above) and must be folded into raw/L before the bound runs, or
    # the "skip" side of this filter is unsound the moment a targeting
    # initiative has stale targets to report. _cms_project_targeted proves
    # "no active initiative targets this project" for free (cheap awk scan,
    # no initiative-status.sh); only a "yes" pays _cms_get_alert's real cost,
    # and only once per project (cached by both helpers).
    if _cms_project_targeted "$project"; then
        _cms_get_alert "$project"
        _cms_alert_stats
        raw=$(( raw + _cms_alert_bytes ))
        [ "$_cms_alert_max_line" -gt "$max_line" ] && max_line="$_cms_alert_max_line"
    fi

    max_line=$(( max_line + WRAPPER_LINE_MARGIN_BYTES ))
    # L >= MAX: a single line could be its own slice on its own merit — no
    # sound bound exists from this formula. Never skip.
    [ "$max_line" -lt "$PREFILTER_SLICE_MAX" ] || return 1

    local inflated_raw bound
    inflated_raw=$(( raw * 100 / PREFILTER_MARGIN_PCT ))
    bound=$(( inflated_raw / (PREFILTER_SLICE_MAX - max_line) + 1 ))
    [ "$bound" -le "$PREFILTER_MIN_CAP" ]
}

# render_slice_count <project> <format> <working> — the slice count a harness
# in <format> would need to deliver <project>'s payload with <working> as the
# one working file included. Subprocess, fail-open: a crash, an unsupported
# format, or a non-numeric result prints nothing (empty stdout), never a false
# ERROR and never a script abort.
render_slice_count() {
    local project="$1" format="$2" working="$3" out
    _cms_get_alert "$project"
    out="$(
        MEMORY_DIR="$MEMORY_DIR" \
        AI_MEMORY_HOOK_FORMAT="$format" \
        AI_MEMORY_WORKING_OVERRIDE="$working" \
        AI_MEMORY_PRECOMPUTED_ALERT_SET="$_cms_alert_set" \
        AI_MEMORY_PRECOMPUTED_ALERT="$_cms_alert_lines" \
            bash "$RENDERER" "$project" 2>/dev/null \
        | python3 "$SLICER" --count 2>/dev/null
    )"
    case "$out" in ''|*[!0-9]*) return 0 ;; esac
    printf '%s' "$out"
}

# check_one_payload <project> <harness> <format> <cap> <working>
check_one_payload() {
    local project="$1" harness="$2" format="$3" cap="$4" working="$5" slices
    _cms_under_prefilter "$project" "$format" "$working" && return 0
    slices="$(render_slice_count "$project" "$format" "$working")"
    [ -n "$slices" ] || return 0
    if [ "$slices" -gt "$cap" ]; then
        printf '%s:1: ERROR payload — %s needs %s chunk(s) to deliver this payload, over its session_chunks cap of %s (working=%s)\n' \
            "$working" "$harness" "$slices" "$cap" "$(basename "$working")"
        found=1
    fi
}

# _cms_manifest_fields <manifest> — prints "<session_chunks>\t<format>" (either
# half empty if absent), reading both top-level keys in ONE subprocess.
# manifest.sh's manifest_get is the canonical reader, but _mf_pairs re-walks
# the WHOLE file line by line through a `sed`-per-token trim on every call —
# calling it twice per manifest (once for session_chunks, once for format)
# across 4 harness manifests measured at ~2s per --payload invocation, which
# is what made --payload across 19 real projects take ~60s even with the
# alert-reuse and byte pre-filter fixes in place. This hand-rolled awk parse
# covers only the grammar those two keys need (top-level `key = value`,
# `#`-comment stripped, section lines skipped) — not a general manifest
# reader, and never used for a value that needs `~`/$HOME expansion.
_cms_manifest_fields() {
    awk -F'=' '
        { line = $0; sub(/#.*/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", line) }
        line ~ /^\[.*\]$/ { in_section = 1; next }
        in_section { next }
        line !~ /=/ { next }
        {
            eq = index(line, "=")
            key = substr(line, 1, eq - 1); gsub(/^[ \t]+|[ \t]+$/, "", key)
            val = substr(line, eq + 1); gsub(/^[ \t]+|[ \t]+$/, "", val)
            if (key == "session_chunks") chunks = val
            if (key == "format") fmt = val
        }
        END { printf "%s\t%s", chunks, fmt }
    ' "$1" 2>/dev/null
}

# check_payload <project> [<explicit-working>] — every harness that declares
# session_chunks, against either the one <explicit-working> file (--working)
# or every working file that exists for the project: the shared working.md
# plus each working.<key>.md overlay. A project with no working file at all
# (fresh project, or an empty sandbox) has nothing to check and is clean —
# render_full would emit no <memory:working> section in that case either.
check_payload() {
    local project="$1" explicit="${2:-}" proj_dir
    proj_dir="$MEMORY_DIR/projects/$project"
    [ -d "$proj_dir" ] || return 0

    local working_files="" w
    if [ -n "$explicit" ]; then
        working_files="$explicit"
    else
        [ -f "$proj_dir/working.md" ] && working_files="$proj_dir/working.md"
        for w in "$proj_dir"/working.*.md; do
            [ -f "$w" ] || continue
            if [ -z "$working_files" ]; then
                working_files="$w"
            else
                working_files="$working_files
$w"
            fi
        done
    fi
    [ -n "$working_files" ] || return 0

    # One pass over every harness manifest: collect the capped ones (harness,
    # format, cap) and track the global minimum cap as a side effect, so
    # _cms_init_prefilter never has to re-scan the manifests itself. Reads
    # both fields with ONE _cms_manifest_fields call per manifest (see its
    # header for why not two manifest_get calls) — with 4 manifests this was
    # measured at ~2s/project via manifest_get, which is what made --payload
    # across 19 real projects take ~60s even after the alert/pre-filter
    # fixes; this is the fix for that.
    local manifest harness fields cap format min_cap=""
    local harnesses=() formats=() caps=()
    for manifest in "$HARNESSES_DIR"/*/manifest; do
        [ -f "$manifest" ] || continue
        fields="$(_cms_manifest_fields "$manifest")"
        cap="${fields%%$'\t'*}"
        format="${fields#*$'\t'}"
        [ -n "$cap" ] || continue
        case "$cap" in *[!0-9]*) continue ;; esac
        harness="$(basename "$(dirname "$manifest")")"
        [ -n "$format" ] || format=xml
        harnesses[${#harnesses[@]}]="$harness"
        formats[${#formats[@]}]="$format"
        caps[${#caps[@]}]="$cap"
        if [ -z "$min_cap" ] || [ "$cap" -lt "$min_cap" ]; then
            min_cap="$cap"
        fi
    done
    _cms_init_prefilter "$min_cap"

    local i
    for i in "${!harnesses[@]}"; do
        while IFS= read -r w; do
            [ -n "$w" ] || continue
            check_one_payload "$project" "${harnesses[$i]}" "${formats[$i]}" "${caps[$i]}" "$w"
        done < <(printf '%s\n' "$working_files")
    done
}

# --- arg parsing ---------------------------------------------------------------
mode=""
files=""
project=""
explicit_working=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --file)
            [ -n "$mode" ] && [ "$mode" != "file" ] && usage
            mode="file"
            shift
            [ "$#" -ge 1 ] || usage
            while [ "$#" -gt 0 ]; do
                case "$1" in --*) break ;; esac
                if [ -z "$files" ]; then
                    files="$1"
                else
                    files="$files
$1"
                fi
                shift
            done
            ;;
        --payload)
            [ -n "$mode" ] && [ "$mode" != "payload" ] && usage
            mode="payload"
            shift
            [ "$#" -ge 1 ] || usage
            project="$1"
            shift
            ;;
        --working)
            shift
            [ "$#" -ge 1 ] || usage
            explicit_working="$1"
            shift
            ;;
        *) usage ;;
    esac
done

[ -n "$mode" ] || usage
case "$mode" in
    file)
        [ -n "$files" ] || usage
        [ -z "$explicit_working" ] || usage   # --working only makes sense with --payload
        ;;
    payload)
        [ -n "$project" ] || usage
        ;;
esac

# --- run -----------------------------------------------------------------------
if [ "$mode" = "file" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        check_file "$f"
    done < <(printf '%s\n' "$files")
else
    check_payload "$project" "$explicit_working"
fi

exit "$found"
