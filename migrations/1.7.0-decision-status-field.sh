#!/usr/bin/env bash
# 1.7.0 -- decision status becomes a dated field.
#
# Rewrites suffix-shape entry heads in `## Decision stream` of kind: initiative
# files under $MEMORY_DIR/initiatives/*.md (the set lint-memory.sh reads;
# _template.md, .state/ and archive/ are skipped) to
#   - D<n>[a] <status>[ <YYYY-MM-DD>] -- <text>
# and stamps `legacy_through: D<max plain id>` in frontmatter when absent.
# A parenthesised or bracketed qualifier moves to the start of the text as
# `(<qualifier>) `. Lines it does not fully match are left byte-identical and
# reported. Idempotent; writes via temp file + mv.
set -euo pipefail

: "${MEMORY_DIR:?MEMORY_DIR is required}"
: "${REPO_ROOT:?REPO_ROOT is required}"

export LC_ALL=C

DIR="$MEMORY_DIR/initiatives"
[ -d "$DIR" ] || exit 0

AWK_PROG='
function isdate(s) { return s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
function inset(s) { return s ~ /^(proposed|confirmed|rejected|superseded|retired)$/ }
function closeparen(s, start,   i, d, c) {
    d = 0
    for (i = start; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") d++
        else if (c == ")") { d--; if (d == 0) return i }
    }
    return 0
}
# Sets NEWLINE (and returns 1) when the head is rewritten; returns 0 when left
# as is; sets UNREC when the head is not recognised.
function rewrite(L,   id, rest, st, st2, date, q, inner, c, n, g, sp, after, dtok, rem, text, tail, cl, sfx) {
    NEWLINE = ""; UNREC = 0
    if (!match(L, /^- D[0-9]+[a-z]?/)) { UNREC = 1; return 0 }
    id = substr(L, 3, RLENGTH - 2)
    rest = substr(L, RLENGTH + 1)
    sfx = 0
    if (rest ~ /^-(proposed|rejected)([ :]|$)/) {
        st = (substr(rest, 2, 1) == "p") ? "proposed" : "rejected"
        sub(/^-(proposed|rejected)/, "", rest); sfx = 1
    } else if (rest ~ /^:/ || rest ~ /^ \(/) {
        st = "confirmed"; sfx = 1
    }
    if (sfx) {
        date = ""; q = ""
        for (g = 0; g < 3; g++) {
            if (rest ~ /^ \*\(/) {
                c = closeparen(rest, 3)
                if (c == 0 || substr(rest, c + 1, 1) != "*") { UNREC = 1; return 0 }
                inner = substr(rest, 4, c - 4)
                rest = substr(rest, c + 2)
            } else if (rest ~ /^ \(/) {
                c = closeparen(rest, 2)
                if (c == 0) { UNREC = 1; return 0 }
                inner = substr(rest, 3, c - 3)
                rest = substr(rest, c + 1)
            } else break
            if (isdate(inner) && date == "") date = inner
            else if (q == "" && inner != "") q = inner
            else { UNREC = 1; return 0 }
        }
        if (rest !~ /^: ./) { UNREC = 1; return 0 }
        text = substr(rest, 3)
        NEWLINE = "- " id " " st (date != "" ? " " date : "") " \342\200\224 " (q != "" ? "(" q ") " : "") text
        return 1
    }
    if (rest !~ /^ [^ \t]/) { UNREC = 1; return 0 }
    rest = substr(rest, 2)
    sp = index(rest, " ")
    if (sp == 0) { UNREC = 1; return 0 }
    st = substr(rest, 1, sp - 1)
    after = substr(rest, sp)
    st2 = (st == "shipped") ? "confirmed" : st
    if (!inset(st2)) { UNREC = 1; return 0 }
    if (after ~ /^ \342\200\224 / || after ~ /^ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \342\200\224 /) {
        if (st == st2) return 0
        NEWLINE = "- " id " " st2 after
        return 1
    }
    if (after ~ /^ \[/) {
        cl = index(after, "] \342\200\224 ")
        if (cl == 0) { UNREC = 1; return 0 }
        inner = substr(after, 3, cl - 3)
        dtok = substr(inner, 1, 10)
        if (!isdate(dtok)) { UNREC = 1; return 0 }
        rem = substr(inner, 11)
        if (rem == "") text = ""
        else if (rem ~ /^[;,] ./) text = substr(rem, 3)
        else { UNREC = 1; return 0 }
        tail = substr(after, cl + length("] \342\200\224 "))
        NEWLINE = "- " id " " st2 " " dtok " \342\200\224 " (text != "" ? "(" text ") " : "") tail
        return 1
    }
    UNREC = 1; return 0
}
BEGIN { DASHSP = "" }
{
    cr = ($0 ~ /\r$/)
    L = $0; sub(/\r$/, "", L)
    orig[NR] = $0; crf[NR] = cr
    out[NR] = $0
    lines = NR
    if (NR == 1 && L == "---") { infm = 1; next }
    if (infm) {
        if (L == "---") { infm = 0; fm_end = NR; next }
        if (L ~ /^kind:[ \t]*["\047]?initiative["\047]?[ \t]*$/) isinit = 1
        if (L ~ /^legacy_through:/) haslegacy = 1
        next
    }
    if (!isinit) next
    if (L ~ /^[ \t]*```/) {
        t = L; sub(/^[ \t]*```/, "", t)
        if (t !~ /```/) { fence = !fence; next }
    }
    if (fence) next
    if (tolower(L) ~ /^## decision stream[ \t]*$/) { instream = 1; next }
    if (instream && L ~ /^## /) { instream = 0; next }
    if (!instream) next
    if (L ~ /^- D/) {
        if (match(L, /^- D[0-9]+/) && L !~ /^- D[0-9]+[a-z]/) {
            n = substr(L, 4, RLENGTH - 3) + 0
            if (n > maxnum) maxnum = n
        }
        if (rewrite(L)) {
            out[NR] = NEWLINE (cr ? "\r" : ""); nchanged++
        } else if (UNREC) {
            h = L
            p = index(h, " \342\200\224 "); if (p > 0) h = substr(h, 1, p - 1)
            else { p = index(h, ": "); if (p > 0) h = substr(h, 1, p) ; else h = substr(h, 1, 60) }
            print "U\t" NR "\t" h > ctl
        }
    }
}
END {
    ins = 0
    if (fm_end > 0 && isinit && !haslegacy && maxnum > 0) ins = 1
    if (ins) print "L\tD" maxnum > ctl
    print "H\t" nchanged + 0 > ctl
    for (i = 1; i <= lines; i++) {
        if (ins && i == fm_end) {
            s = "legacy_through: D" maxnum (crf[i] ? "\r" : "")
            printf "%s\n", s
        }
        if (i == lines && nonl) printf "%s", out[i]
        else printf "%s\n", out[i]
    }
}
'

for f in "$DIR"/*.md; do
    [ -f "$f" ] || continue
    case "$f" in */_template.md) continue ;; esac

    nonl=0
    if [ -s "$f" ] && [ "$(tail -c 1 "$f" | wc -l | tr -d ' ')" = "0" ]; then nonl=1; fi

    tmp="$(mktemp "$DIR/.mig-1.7.0.XXXXXX")"
    ctl="$(mktemp "$DIR/.mig-1.7.0.ctl.XXXXXX")"
    if ! awk -v ctl="$ctl" -v nonl="$nonl" "$AWK_PROG" "$f" > "$tmp"; then
        rm -f "$tmp" "$ctl"
        echo "1.7.0: failed to process $f" >&2
        exit 1
    fi

    while IFS="$(printf '\t')" read -r tag a b; do
        case "$tag" in
            U) printf '1.7.0: unrecognised decision head left unchanged (resolve by hand): %s:%s: %s\n' "$f" "$a" "$b" ;;
        esac
    done < "$ctl"

    heads="$(sed -n 's/^H\t//p' "$ctl" | head -n 1)"
    legacy="$(awk -F'\t' '$1=="L"{print $2}' "$ctl")"
    rm -f "$ctl"

    if cmp -s "$f" "$tmp"; then
        rm -f "$tmp"
        continue
    fi

    mode="$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")"
    chmod "$mode" "$tmp"
    mv "$tmp" "$f"
    printf '1.7.0: %s: %s head(s) rewritten%s\n' "$f" "${heads:-0}" "${legacy:+, legacy_through: $legacy}"
done
