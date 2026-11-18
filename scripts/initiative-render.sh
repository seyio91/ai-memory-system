#!/usr/bin/env bash
#
# initiative-render.sh — render an initiative's derived views into fenced,
# generated blocks of the initiative file itself.
#
# Usage: initiative-render.sh <slug> [--write | --check]
#   (default)  print the three fences (markers and bodies) to stdout
#   --write    replace each fence body in place (temp file + mv); a missing
#              section is inserted: `## Now` and `## Environment matrix`
#              directly before `## Targets`, `## Current rules` directly before
#              `## Decision stream`. Bytes outside fences are never touched.
#              Refuses a symlinked initiative file.
#   --check    exit 0 iff every fence that should exist exists and equals a
#              fresh render; else exit 1 naming the stale/missing fence(s).
#              Read-only.
#
# Fence markers, one pair per section, directly under its heading:
#   <!-- BEGIN AUTOGEN initiative-render:now -->     ## Now
#   <!-- BEGIN AUTOGEN initiative-render:matrix -->  ## Environment matrix
#   <!-- BEGIN AUTOGEN initiative-render:rules -->   ## Current rules
#   ... body ...
#   <!-- END AUTOGEN initiative-render:<key> -->
# Bodies carry no date or timestamp, so a render is deterministic.
#
# Now: from `initiative-status.sh --tsv`. Non-terminal Targets with all
# depends_on edges satisfied, no authored blocked_by and state not `blocked` are
# split on the first actor of `next:` (text before the first ` — `): exactly
# `user` -> Waiting on you; anything else, or no `next:`, -> Sessions to start.
# Blocked = the other non-terminal Targets; the cell merges the unsatisfied
# depends_on edges with the authored blocked_by, and rows are sorted by how many
# non-terminal Targets each holds up (directly or transitively), most first,
# ties in file order. Edge wording is rewritten here: `(at blocked)` ->
# `(blocked)`, `(at closed)` -> `(closed)`, `(at X, needs Y)` -> `(needs Y)`,
# other `(at X)` -> `(not done)`.
# Decisions needed = each proposed D-id cited as a whole `D<n>` token in the
# authored blocked_by of a non-terminal Target, with the citing Targets and
# every non-terminal Target they hold up transitively. Open proposals lists
# those ids first, suffixed `(blocking)`, then the rest in stream order. Every
# empty section renders `**<name>:** none`. done/closed/complete Targets are
# omitted. The hold-up graph is `--tsv`'s `unsatisfied` column; nothing is
# derived from raw depends_on, and ids/state come only from --tsv (its `state`
# column is the asserted state, which --tsv's stage column hides for
# software_adw Targets).
# Matrix: frontmatter `envs: [a, b]` gives the columns; rows are the base names
# of `@env` Targets; a cell is the derived stage of `<base>@<env>` or
# `not opened`. No `envs:` -> no matrix section; a matrix fence left behind is an
# orphan (`--check` exits 1 `orphan fence: matrix`; `--write` removes the heading,
# fence and the blank line after it).
# Current rules: frontmatter `topics: [x, y]` gives the row order; each row
# lists live (confirmed + proposed) decision-stream entries of that topic.
# Entries without a topic go to a final `(untagged)` row, off-enum topics to a
# final `(unknown topic)` row.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/_lib.sh"

usage() {
    echo "usage: initiative-render.sh <slug> [--write | --check]" >&2
    exit 2
}

MODE='print'
SLUG=""
for arg in "$@"; do
    case "$arg" in
        --write) [ "$MODE" = print ] || usage; MODE='write' ;;
        --check) [ "$MODE" = print ] || usage; MODE='check' ;;
        -*) usage ;;
        *) [ -z "$SLUG" ] || usage; SLUG="$arg" ;;
    esac
done
[ -n "$SLUG" ] || usage
INITIATIVE="$MEMORY_DIR/initiatives/$SLUG.md"
[ -f "$INITIATIVE" ] || { echo "initiative-render: initiative not found: $INITIATIVE" >&2; exit 1; }

DS_LIB="$(cat "$HERE/lib/decision-stream.awk" 2>/dev/null)"
[ -n "$DS_LIB" ] || { echo "initiative-render: missing $HERE/lib/decision-stream.awk" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/initiative-render.XXXXXX")" || exit 1
OUT=""
trap 'rm -rf "$TMP"; [ -z "$OUT" ] || rm -f "$OUT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Marker and heading strings, defined once; every awk program gets them by -v.
BEGIN_PFX='<!-- BEGIN AUTOGEN initiative-render:'
END_PFX='<!-- END AUTOGEN initiative-render:'
MARK_SFX=' -->'
H_NOW='## Now'
H_MATRIX='## Environment matrix'
H_RULES='## Current rules'
AWK_VARS=(-v "bp=$BEGIN_PFX" -v "ep=$END_PFX" -v "ms=$MARK_SFX" -v "hn=$H_NOW" -v "hm=$H_MATRIX" -v "hr=$H_RULES")

TSV="$TMP/tsv"
bash "$HERE/initiative-status.sh" --tsv "$SLUG" > "$TSV" 2> "$TMP/tsv.err" || {
    cat "$TMP/tsv.err" >&2
    echo "initiative-render: initiative-status.sh --tsv failed for $SLUG" >&2
    exit 1
}
grep '^WARNING:' "$TMP/tsv.err" >&2 || true

# fm_list <field> — a frontmatter list as one item per line: inline
# `[a, "b", 'c']` (or `a, b`) or a YAML block list (`field:` then `  - a` lines).
# Surrounding quotes are stripped.
fm_list() {
    awk -v f="$1" '
        function unq(x) {
            sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x)
            if (length(x) >= 2) {
                c = substr(x, 1, 1)
                if ((c == "\"" || c == "\047") && substr(x, length(x), 1) == c) x = substr(x, 2, length(x) - 2)
            }
            return x
        }
        { sub(/\r$/, "") }
        NR == 1 { if ($0 ~ /^---[ \t]*$/) { infm = 1; next } else exit }
        infm && /^---[ \t]*$/ { exit }
        !infm { exit }
        blk {
            if ($0 ~ /^[ \t]*-([ \t]|$)/) { v = $0; sub(/^[ \t]*-[ \t]*/, "", v); v = unq(v); if (v != "") print v; next }
            if ($0 ~ /^[ \t]*$/) next
            exit
        }
        index($0, f ":") == 1 {
            v = substr($0, length(f) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
            if (v == "") { blk = 1; next }
            sub(/^\[/, "", v); sub(/\]$/, "", v)
            m = split(v, p, ",")
            for (i = 1; i <= m; i++) { x = unq(p[i]); if (x != "") print x }
            exit
        }
    ' "$INITIATIVE"
}

# esc <text> — sets ESC to the text made safe for a markdown table cell: each
# unescaped `|` becomes `\|`; an already escaped `\|` is left alone.
esc() {
    local rest="$1" piece
    ESC=""
    while :; do
        case "$rest" in
            *'|'*)
                piece="${rest%%|*}"; rest="${rest#*|}"
                case "$piece" in
                    *\\) ESC="$ESC$piece|" ;;
                    *) ESC="$ESC$piece\\|" ;;
                esac
                ;;
            *) break ;;
        esac
    done
    ESC="$ESC$rest"
}

# --tsv rows (id, stage, deps-satisfied, next, blocked_by, unsatisfied, state)
# are the only source of Target ids and state.
tab=$(printf '\t')
t_id=(); t_stage=(); t_ok=(); t_next=(); t_block=(); t_unsat=(); t_state=()
n=0
while IFS="$tab" read -r tid tstage tok tnext tblock tunsat tstate; do
    t_id[$n]="$tid"; t_stage[$n]="$tstage"; t_ok[$n]="$tok"; t_next[$n]="$tnext"
    t_block[$n]="$tblock"; t_unsat[$n]="$tunsat"; t_state[$n]="$tstate"
    n=$((n + 1))
done < "$TSV"

idx_of() {
    local i=0
    while [ "$i" -lt "$n" ]; do
        [ "${t_id[$i]}" = "$1" ] && { IDX=$i; return 0; }
        i=$((i + 1))
    done
    return 1
}

# rules_awk <mode> — decision-stream views. mode=rules: table rows; mode=prop:
# proposed ids, one per line.
rules_awk() {
    TOPICS="$(fm_list topics)" MODE_="$1" awk "$DS_LIB"'
        function item(i,   id, am, s) {
            id = ds_id(i); s = id
            am = ds_amended_by(id)
            if (am != "") { gsub(/ /, ", ", am); s = s " (as amended by " am ")" }
            if (ds_streq(ds_status(i), "proposed")) s = s " (proposed)"
            return s
        }
        function row(label, sel,   i, id, out, k) {
            out = ""
            for (i = 1; i <= ds_count(); i++) {
                if (!ds_live(i)) continue
                if (!pick(i, sel)) continue
                id = ds_id(i)
                if (seen[label SUBSEP id]) continue
                seen[label SUBSEP id] = 1
                out = out (out == "" ? "" : ", ") item(i)
            }
            return out
        }
        # sel: topic index (1..nt), or 0 untagged, -1 unknown
        function pick(i, sel,   t, k) {
            t = ds_topic(i)
            if (sel > 0) return ds_streq(t, tp[sel])
            if (sel == 0) return ds_streq(t, "")
            if (ds_streq(t, "")) return 0
            for (k = 1; k <= nt; k++) if (ds_streq(t, tp[k])) return 0
            return 1
        }
        BEGIN {
            ds_reset()
            nt = split(ENVIRON["TOPICS"], tp, "\n")
            if (nt == 1 && tp[1] == "") nt = 0
        }
        { sub(/\r$/, "") }
        { inst = ds_track($0) }
        DS_END { exit }
        !inst { next }
        { ds_feed($0) }
        END {
            if (ENVIRON["MODE_"] == "prop") {
                for (i = 1; i <= ds_count(); i++)
                    if (ds_streq(ds_status(i), "proposed") && !pseen[ds_id(i)]) {
                        pseen[ds_id(i)] = 1; print ds_id(i)
                    }
                exit
            }
            for (k = 1; k <= nt; k++) {
                r = row(tp[k], k)
                printf "| %s | %s |\n", tp[k], (r == "" ? "none" : r)
            }
            r = row("(untagged)", 0)
            if (r != "") printf "| (untagged) | %s |\n", r
            r = row("(unknown topic)", -1)
            if (r != "") printf "| (unknown topic) | %s |\n", r
        }
    ' "$INITIATIVE"
}

unsat_entries() {
    local rest="$1" piece last
    UE=()
    while [ -n "$rest" ]; do
        case "$rest" in
            *", "*) piece="${rest%%, *}"; rest="${rest#*, }" ;;
            *) piece="$rest"; rest="" ;;
        esac
        case "$piece" in
            "needs "*)
                last=$((${#UE[@]} - 1))
                [ "$last" -ge 0 ] && { UE[$last]="${UE[$last]}, $piece"; continue; }
                ;;
        esac
        UE[${#UE[@]}]="$piece"
    done
    return 0
}

reword_unsat() {
    local e r pre
    REW=""
    unsat_entries "$1"
    for e in "${UE[@]+"${UE[@]}"}"; do
        r="${e##* (}"; r="${r%)}"; pre="${e%" ("*}"
        case "$r" in
            "at blocked") e="$pre (blocked)" ;;
            "at closed") e="$pre (closed)" ;;
            "at "*", needs "*) e="$pre (needs ${r#*, needs })" ;;
            "at "*) e="$pre (not done)" ;;
        esac
        REW="$REW${REW:+, }$e"
    done
    return 0
}

hold_closure() {
    local s x j changed=1
    CL=()
    for ((j = 0; j < n; j++)); do CL[$j]=0; done
    for s in "$@"; do CL[$s]=1; done
    while [ "$changed" -eq 1 ]; do
        changed=0
        for ((j = 0; j < n; j++)); do
            [ "${CL[$j]}" -eq 0 ] || continue
            for x in ${dep_of[$j]}; do
                if [ "${CL[$x]}" -eq 1 ]; then CL[$j]=1; changed=1; break; fi
            done
        done
    done
    return 0
}

now_section() {
    if [ -n "$3" ]; then
        printf '**%s**\n\n%s\n|---|---|\n%s\n' "$1" "$2" "$3"
    else
        printf '**%s:** none\n\n' "$1"
    fi
    return 0
}

render_now() {
    local i j w d e1 cell auth nx pid cnt c p props
    local maxc=0 nb=0 plist="" blocking=" "
    local waiting="" sessions="" blocked="" decisions=""
    local live=() dep_of=() btok=() cite=() brow_id=() brow_cell=() brow_cnt=()
    for ((i = 0; i < n; i++)); do
        live[$i]=1
        case "${t_state[$i]}" in done|closed) live[$i]=0 ;; esac
        case "${t_stage[$i]}" in done|closed|complete) live[$i]=0 ;; esac
        dep_of[$i]=""
        unsat_entries "${t_unsat[$i]}"
        for e1 in "${UE[@]+"${UE[@]}"}"; do
            [ "$e1" != "-" ] || continue
            w="${e1%%(*}"; w="${w%"${w##*[! ]}"}"
            if idx_of "$w"; then dep_of[$i]="${dep_of[$i]} $IDX"; fi
        done
        btok[$i]=""
        auth="${t_block[$i]}"
        auth="${auth//[^A-Za-z0-9]/ }"
        for w in $auth; do
            d="${w#D}"
            { [ "$d" != "$w" ] && [ -n "$d" ]; } || continue
            case "$d" in *[!0-9]*) ;; *) btok[$i]="${btok[$i]} $w" ;; esac
        done
    done
    for ((i = 0; i < n; i++)); do
        [ "${live[$i]}" -eq 1 ] || continue
        cell=""
        if [ "${t_unsat[$i]}" != "-" ]; then reword_unsat "${t_unsat[$i]}"; cell="$REW"; fi
        if [ "${t_stage[$i]}" = "unknown" ]; then
            cell="stage unknown${cell:+; $cell}"
        fi
        auth="${t_block[$i]}"
        case "$auth" in -|none|"") auth="" ;; esac
        if [ -n "$auth" ]; then
            [ -z "$cell" ] || cell="$cell; "
            cell="$cell$auth"
        fi
        if [ -n "$cell" ] || [ "${t_state[$i]}" = "blocked" ] || [ "${t_ok[$i]}" != "yes" ]; then
            [ -n "$cell" ] || cell="blocked (no reason given)"
            hold_closure "$i"
            cnt=0
            for ((j = 0; j < n; j++)); do
                if [ "$j" -ne "$i" ] && [ "${live[$j]}" -eq 1 ] && [ "${CL[$j]}" -eq 1 ]; then cnt=$((cnt + 1)); fi
            done
            brow_id[$nb]="${t_id[$i]}"; brow_cell[$nb]="$cell"; brow_cnt[$nb]="$cnt"
            nb=$((nb + 1))
            [ "$cnt" -le "$maxc" ] || maxc="$cnt"
        else
            nx="${t_next[$i]}"
            [ "$nx" != "-" ] || nx="(stage: ${t_stage[$i]})"
            esc "${t_id[$i]}"; e1="$ESC"; esc "$nx"
            if [ "${nx%% — *}" = "user" ]; then
                waiting="$waiting| $e1 | $ESC |
"
            else
                sessions="$sessions| $e1 | $ESC |
"
            fi
        fi
    done
    for ((c = maxc; c >= 0; c--)); do
        for ((i = 0; i < nb; i++)); do
            [ "${brow_cnt[$i]}" -eq "$c" ] || continue
            esc "${brow_id[$i]}"; e1="$ESC"; esc "${brow_cell[$i]}"
            blocked="$blocked| $e1 | $ESC |
"
        done
    done
    props="$(rules_awk prop)"
    for pid in $props; do
        cite=()
        for ((i = 0; i < n; i++)); do
            [ "${live[$i]}" -eq 1 ] || continue
            case "${btok[$i]} " in *" $pid "*) cite[${#cite[@]}]="$i" ;; esac
        done
        [ "${#cite[@]}" -gt 0 ] || continue
        hold_closure "${cite[@]}"
        cell=""
        for ((j = 0; j < n; j++)); do
            if [ "${live[$j]}" -eq 1 ] && [ "${CL[$j]}" -eq 1 ]; then
                esc "${t_id[$j]}"; cell="$cell${cell:+, }$ESC"
            fi
        done
        decisions="$decisions| $pid | $cell |
"
        blocking="$blocking$pid "
    done
    now_section "Decisions needed" "| Decision | Blocks |" "$decisions"
    now_section "Waiting on you" "| Target | Next |" "$waiting"
    now_section "Sessions to start" "| Target | Next |" "$sessions"
    now_section "Blocked" "| Target | Blocked by |" "$blocked"
    for p in $props; do
        case "$blocking" in *" $p "*) plist="$plist${plist:+, }$p (blocking)" ;; esac
    done
    for p in $props; do
        case "$blocking" in *" $p "*) ;; *) plist="$plist${plist:+, }$p" ;; esac
    done
    printf '**Open proposals:** %s\n' "${plist:-none}"
    return 0
}

render_matrix() {
    local envs=() e line bases=() b i row seen found cols ev
    while IFS= read -r e; do envs[${#envs[@]}]="$e"; done < <(fm_list envs)
    for ((i = 0; i < n; i++)); do
        case "${t_id[$i]}" in
            *@*)
                b="${t_id[$i]%@*}"; ev="${t_id[$i]##*@}"
                seen=0
                for e in "${bases[@]+"${bases[@]}"}"; do [ "$e" = "$b" ] && seen=1; done
                [ "$seen" -eq 1 ] || bases[${#bases[@]}]="$b"
                # an env not declared in envs: still gets a trailing column
                seen=0
                for e in "${envs[@]}"; do [ "$e" = "$ev" ] && seen=1; done
                [ "$seen" -eq 1 ] || envs[${#envs[@]}]="$ev"
                ;;
        esac
    done
    if [ "${#bases[@]}" -eq 0 ]; then
        printf '_No per-environment Targets._\n'
        return 0
    fi
    line="| Target |"; row="|---|"
    for e in "${envs[@]}"; do esc "$e"; line="$line $ESC |"; row="$row---|"; done
    printf '%s\n%s\n' "$line" "$row"
    for b in "${bases[@]}"; do
        esc "$b"; line="| $ESC |"
        for e in "${envs[@]}"; do
            if idx_of "$b@$e"; then found="${t_stage[$IDX]}"; else found="not opened"; fi
            esc "$found"; line="$line $ESC |"
        done
        printf '%s\n' "$line"
    done
}

render_rules() {
    local body
    body="$(rules_awk rules)"
    if [ -z "$body" ]; then
        printf '_No live decisions._\n'
        return 0
    fi
    printf '| Topic | Live decisions |\n|---|---|\n%s\n' "$body"
}

HAS_ENVS=0
[ -n "$(fm_list envs)" ] && HAS_ENVS=1

KEYS="now"
[ "$HAS_ENVS" -eq 0 ] || KEYS="$KEYS matrix"
KEYS="$KEYS rules"

render_now > "$TMP/now.body"
[ "$HAS_ENVS" -eq 0 ] || render_matrix > "$TMP/matrix.body"
render_rules > "$TMP/rules.body"

heading_of() {
    case "$1" in
        now) printf '%s' "$H_NOW" ;;
        matrix) printf '%s' "$H_MATRIX" ;;
        rules) printf '%s' "$H_RULES" ;;
    esac
}
begin_of() { printf '%s%s%s' "$BEGIN_PFX" "$1" "$MARK_SFX"; }
end_of() { printf '%s%s%s' "$END_PFX" "$1" "$MARK_SFX"; }

if [ "$MODE" = print ]; then
    for k in $KEYS; do
        printf '%s\n' "$(begin_of "$k")"
        cat "$TMP/$k.body"
        printf '%s\n' "$(end_of "$k")"
    done
    exit 0
fi

# Shared awk prelude: marker/heading names and the one line normaliser. Fence
# state comes from ds_fence (lib/decision-stream.awk), so headings and markers
# inside ``` / ~~~ code blocks are never seen.
AWK_PRE='
    function bm(k) { return bp k ms }
    function em(k) { return ep k ms }
    function heading(k) { return k == "now" ? hn : (k == "matrix" ? hm : hr) }
    # norm: sets c (the CR, if any), line (no CR, no trailing blanks), fenced
    function norm(   t) {
        c = ""; line = $0
        if (line ~ /\r$/) { c = "\r"; sub(/\r$/, "", line) }
        t = line
        fenced = ds_fence(t)
        sub(/[ \t]+$/, "", line)
    }
'

# One scan: marker counts/order per fence, which headings and anchors exist.
SCAN="
$(awk "${AWK_VARS[@]}" "$DS_LIB$AWK_PRE"'
    BEGIN { n = split("now matrix rules", ks, " ") }
    {
        norm()
        if (fenced) next
        for (j = 1; j <= n; j++) {
            k = ks[j]
            if (line == bm(k)) { b[k]++; sb[k] = NR }
            if (line == em(k)) { e[k]++; se[k] = NR }
            if (line == heading(k)) hd[k] = 1
        }
        if (line == "## Targets") tg = 1
        if (tolower(line) == "## decision stream") ds = 1
    }
    END {
        for (j = 1; j <= n; j++) {
            k = ks[j]
            if (b[k] + 0 == 0 && e[k] + 0 == 0) st = "missing"
            else if (b[k] == 1 && e[k] == 1 && sb[k] < se[k]) st = "ok"
            else st = "broken"
            print "fence " k " " st
            if (hd[k]) print "head " k
        }
        if (tg) print "anchor targets"
        if (ds) print "anchor decisions"
    }
' "$INITIATIVE")
"
scan_has() { case "$SCAN" in *"
$1
"*) return 0 ;; esac; return 1; }
fence_state() {
    local st
    for st in ok missing broken; do
        scan_has "fence $1 $st" && { echo "$st"; return 0; }
    done
}

# current_body <key> — the existing fence body, CRs removed.
current_body() {
    awk -v key="$1" "${AWK_VARS[@]}" "$DS_LIB$AWK_PRE"'
        { norm() }
        !fenced && line == em(key) { inside = 0 }
        inside { sub(/\r$/, ""); print }
        !fenced && line == bm(key) { inside = 1 }' "$INITIATIVE"
}

if [ "$MODE" = check ]; then
    bad=0
    for k in $KEYS; do
        st="$(fence_state "$k")"
        case "$st" in
            missing) echo "initiative-render: missing fence: $k ($(heading_of "$k"))" >&2; bad=1 ;;
            broken) echo "initiative-render: malformed fence markers: $k" >&2; bad=1 ;;
            ok)
                current_body "$k" > "$TMP/$k.cur"
                cmp -s "$TMP/$k.cur" "$TMP/$k.body" || { echo "initiative-render: stale fence: $k" >&2; bad=1; }
                ;;
        esac
    done
    if [ "$HAS_ENVS" -eq 0 ] && [ "$(fence_state matrix)" != missing ]; then
        echo "initiative-render: orphan fence: matrix (no envs: in frontmatter)" >&2
        bad=1
    fi
    exit "$bad"
fi

# --write
if [ -L "$INITIATIVE" ]; then
    echo "initiative-render: refusing symlink (render its target by hand): $INITIATIVE" >&2
    exit 1
fi
ORPHAN=""
[ "$HAS_ENVS" -eq 1 ] || [ "$(fence_state matrix)" = missing ] || ORPHAN="matrix"
[ "$ORPHAN" != matrix ] || [ "$(fence_state matrix)" != broken ] || { echo "initiative-render: malformed fence markers: matrix (fix by hand)" >&2; exit 1; }
have=""
heads=""
need_targets=0
need_ds=0
for k in $KEYS; do
    st="$(fence_state "$k")"
    [ "$st" != broken ] || { echo "initiative-render: malformed fence markers: $k (fix by hand)" >&2; exit 1; }
    [ "$st" != ok ] || have="$have $k"
    scan_has "head $k" && heads="$heads $k"
    # an insertion happens only for a section with neither fence nor heading
    if [ "$st" = missing ] && ! scan_has "head $k"; then
        if [ "$k" = rules ]; then need_ds=1; else need_targets=1; fi
    fi
done
if [ "$need_targets" -eq 1 ] && ! scan_has "anchor targets"; then
    echo "initiative-render: no '## Targets' heading to anchor insertion" >&2; exit 1
fi
if [ "$need_ds" -eq 1 ] && ! scan_has "anchor decisions"; then
    echo "initiative-render: no '## Decision stream' heading to anchor insertion" >&2; exit 1
fi

# A file with no final newline gains exactly one (awk terminates every line).
OUT="$INITIATIVE.tmp.$$"
awk -v keys="$KEYS" -v have="$have" -v heads="$heads" -v orphan="$ORPHAN" -v dir="$TMP" "${AWK_VARS[@]}" "$DS_LIB$AWK_PRE"'
    function body(k, c,   l, f) {
        f = dir "/" k ".body"
        while ((getline l < f) > 0) printf "%s%s\n", l, c
        close(f)
    }
    function fence(k, c) { printf "%s%s\n", bm(k), c; body(k, c); printf "%s%s\n", em(k), c }
    function section(k, c) { printf "%s%s\n", heading(k), c; fence(k, c); printf "%s\n", c }
    function want(k) { return index(" " keys " ", " " k " ") > 0 }
    function hh(k) { return index(" " heads " ", " " k " ") > 0 }
    function has(k) { return index(" " have " ", " " k " ") > 0 }
    BEGIN { n = split("now matrix rules", ks, " ") }
    END { if (held != "") { print held; if (heldb != "") print heldb } }
    { raw = $0; norm() }
    skipping { if (!fenced && line == em(skipk)) { skipping = 0; if (orphan == "matrix" && skipk == "matrix") dropblank = 1 } next }
    # orphan matrix fence (envs: removed): drop heading, an optional blank line,
    # the fence and one blank line after it
    held != "" {
        if (line == "" && heldb == "") { heldb = raw; next }
        if (!fenced && line == bm("matrix")) { held = ""; heldb = ""; skipping = 1; skipk = "matrix"; next }
        print held; if (heldb != "") print heldb
        held = ""; heldb = ""
    }
    fenced { print raw; next }
    dropblank { dropblank = 0; if (line == "") next }
    orphan == "matrix" && line == heading("matrix") { held = raw; next }
    orphan == "matrix" && line == bm("matrix") { skipping = 1; skipk = "matrix"; next }
    {
        for (j = 1; j <= n; j++) if (want(ks[j]) && has(ks[j]) && line == bm(ks[j])) {
            fence(ks[j], c); skipping = 1; skipk = ks[j]; next
        }
    }
    line == "## Targets" && !tdone {
        tdone = 1
        if (want("now") && !has("now") && !hh("now")) section("now", c)
        if (want("matrix") && !has("matrix") && !hh("matrix")) section("matrix", c)
    }
    tolower(line) == "## decision stream" && !ddone {
        ddone = 1
        if (want("rules") && !has("rules") && !hh("rules")) section("rules", c)
    }
    { print raw }
    {
        for (j = 1; j <= n; j++) if (want(ks[j]) && !has(ks[j]) && line == heading(ks[j]) && !hdone[ks[j]]) {
            fence(ks[j], c); hdone[ks[j]] = 1
        }
    }
' "$INITIATIVE" > "$OUT" || { rm -f "$OUT"; echo "initiative-render: render failed" >&2; exit 1; }

if cmp -s "$OUT" "$INITIATIVE"; then
    rm -f "$OUT"
else
    mode="$(stat -c %a "$INITIATIVE" 2>/dev/null || stat -f %Lp "$INITIATIVE")"
    chmod "$mode" "$OUT" 2>/dev/null
    mv "$OUT" "$INITIATIVE" || { rm -f "$OUT"; echo "initiative-render: cannot write $INITIATIVE" >&2; exit 1; }
fi
OUT=""
exit 0
