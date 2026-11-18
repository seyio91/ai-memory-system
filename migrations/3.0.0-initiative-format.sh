#!/usr/bin/env bash
# 3.0.0 -- initiatives move to the one-line status, scope:, Closed rows and a
# progress log.
#
# Rewrites every `kind: initiative` file directly under $MEMORY_DIR/initiatives/
# (active and closed; _template.md, symlinks and subdirectories such as
# archive/, logs/ and .state/ are skipped). Grammar: scripts/lib/initiative-targets.awk
# (Targets, status) and scripts/lib/decision-stream.awk (stream, fences).
#
# A file is migrated only when it is old format: some Target under `## Targets`
# has a `- next_actor:` line or an old status (a known state, a ` — ` and no
# ` · `). A Target already in the new format is never touched. Per old Target:
#   - open/blocked `<state>[ <date>][ (…)] — <prose>` becomes
#       - scope: [<date/(…)> — ]<prose minus Progress:/Was: segments>
#       - status: <state> · next: <first next_actor value, or none> · blocked_by: none
#     A segment starts at `Progress:` or `Was:` (at the start of the prose or
#     after a space) and ends just before the next of: another `Progress:` /
#     `Was:`; a label opening a sentence, i.e. `. ` followed by a capitalised
#     word, at most three more lower-case words (each optionally after a comma)
#     and a colon, matching `[A-Z][a-z]+(,? [a-z]+){0,3}:` (`Remaining:`,
#     `Next, in repo:`, `Seed:`, `Earlier:`; not `P2 done 2026-11-16:`); or the
#     end. Segments go to the log; the rest of the prose (the pieces before,
#     between and after them, each trimmed, joined by one space) is scope.
#     Every `- next_actor:` line is removed; with more than one, all of them
#     also go to the log. Every other line stays as written.
#   - old `closed[ <date>][ (…)] — <prose>` (abandoned) is converted the same
#     way but keeps its heading and state: `- scope:` as above, then
#     `- status: closed` (terminal, standalone); every `- next_actor:` line
#     goes to the log. It is NOT collapsed: a Closed row reads as done and
#     would satisfy its dependents, which must stay unsatisfied.
#   - a status whose first token is done collapses into a row
#       | <id> | <date from `done <date>`, else -> | <jira: or -> | see log |
#     of the `### Closed` table at the end of `## Targets` (created when absent,
#     header `| id | closed | jira | outcome |`); the Closed table holds done
#     Targets only. The whole Target block (heading to its last non-blank line)
#     goes to the log verbatim. This includes a new-format done status with a
#     stray `- next_actor:` line.
#   - a Target with a new-format status (open, blocked or closed), or with none,
#     only loses its next_actor line(s), which go to the log.
#   - any other status (state outside open|blocked|done|closed, an unparsed
#     middle, more than one `- status:` line) leaves the whole Target
#     byte-identical and is reported.
#   In a migrated file a Target that is not old but whose status breaks the
#   grammar (e.g. `done (no dash)`) is reported too, and left as written.
#   A file with no old Target is not rewritten (no backup, no log), but each
#   status in it that breaks the new grammar is still reported:
#     <file>:<line>: status does not match the 3.0.0 grammar; fix by hand (lint ERRORs it)
#   Reported line numbers are those of the rewritten file.
# Then: `topics: []` is added to frontmatter when absent; for every
# `SUPERSEDES <id>` continuation under entry X, a `→ X` forward pointer is added
# to each head of <id> lacking it (after date/status, before ` — `). No other
# decision text is edited. Prose amendment candidates (ds_candidates) are
# reported, never written.
#
# Before the first write a byte-identical copy is saved to
# initiatives/.state/<slug>.pre-3.0.0.md (an existing copy is kept). Moved text
# is appended to initiatives/logs/<slug>.md as entries
#   ## <YYYY-MM-DD> — <target-id> (migrated by 3.0.0)
# The log is written before the main file. An entry whose text after the date
# (Target id, marker and body) is already in the log is not appended again, so
# a rerun after a failed main-file write does not duplicate entries. New backup
# and log files take the main file's mode.
# Writes go through temp file + mv. When initiative-status.sh --tsv accepts the
# result, scripts/initiative-render.sh <slug> --write inserts the generated
# fences; otherwise the file is left as rewritten and the refusal reported.
# The staleness snapshot (.state/<slug>.snapshot) is not touched: it is compared
# only against software_adw Targets still present, so a Target collapsed into a
# Closed row cannot raise a stale alert, and the stream entry count is unchanged.
#
# Idempotent: a second run finds no old Target and changes nothing (main file,
# log, backup). Exit 0 unless an I/O failure; unmatched content is reported.
# Test seam: MIGRATION_3_0_0_TODAY=YYYY-MM-DD.
set -euo pipefail

: "${MEMORY_DIR:?MEMORY_DIR is required}"
: "${REPO_ROOT:?REPO_ROOT is required}"

export LC_ALL=C

DIR="$MEMORY_DIR/initiatives"
[ -d "$DIR" ] || exit 0

DS_LIB="$(cat "$REPO_ROOT/scripts/lib/decision-stream.awk" 2>/dev/null)"
[ -n "$DS_LIB" ] || { echo "3.0.0: missing $REPO_ROOT/scripts/lib/decision-stream.awk" >&2; exit 1; }
IT_LIB="$(cat "$REPO_ROOT/scripts/lib/initiative-targets.awk" 2>/dev/null)"
[ -n "$IT_LIB" ] || { echo "3.0.0: missing $REPO_ROOT/scripts/lib/initiative-targets.awk" >&2; exit 1; }

TODAY="${MIGRATION_3_0_0_TODAY:-$(date +%Y-%m-%d)}"

AWK_PROG='
function trim(s) { return it_trim(s) }
function dash() { return " " ds_dash() " " }
function emit(s) { OUTN++; OUT[OUTN] = s }
function crs() { return FILECR ? "\r" : "" }
function ctl(s) { print s > CTL }
# One entry per record, records separated by \036 (the shell dedupes them).
function logent(id, body) {
    NLOG++
    printf "\n## %s %s %s (migrated by 3.0.0)\n\n%s\n\036", TODAY, ds_dash(), id, body > LOGF
}
function rep(s) { gsub(/\t/, " ", s); return s }
# Unmatched lines are reported after the rewrite, with their line number in
# the rewritten file (OUTLN; equal to the input line when nothing moved).
function unmatched(i, why) { NUM++; UMI[NUM] = i; UMW[NUM] = why }
function cell(s) { gsub(/\|/, "\\|", s); return (s == "") ? "-" : s }

# Middle between the state token and ` — `: "", <date>, (…), or <date> (…).
# Sets MDATE to the date when present. Returns 0 when not recognised.
function middle_ok(m,   d) {
    MDATE = ""
    if (m == "") return 1
    d = substr(m, 1, 10)
    if (ds_isdate(d) && (length(m) == 10 || substr(m, 11) ~ /^ \(.*\)$/)) { MDATE = d; return 1 }
    if (m ~ /^\(.*\)$/) return 1
    return 0
}

# Offset of the first `Progress:` / `Was:` at or after p that starts the text
# or follows a space; 0 when none.
function kwpos(t, p,   i) {
    for (i = p; i <= length(t); i++) {
        if (i > 1 && substr(t, i - 1, 1) != " ") continue
        if (substr(t, i, 9) == "Progress:" || substr(t, i, 4) == "Was:") return i
    }
    return 0
}

# Offset of the first sentence-opening label at or after p (see header); 0 when none.
function labelpos(t, p,   i) {
    for (i = (p > 3 ? p : 3); i <= length(t); i++) {
        if (substr(t, i - 2, 2) != ". ") continue
        if (substr(t, i) ~ /^[A-Z][a-z]+(,? [a-z]+)?(,? [a-z]+)?(,? [a-z]+)?:/) return i
    }
    return 0
}

function addpiece(acc, piece, sep) {
    piece = trim(piece)
    if (piece == "") return acc
    return acc (acc == "" ? "" : sep) piece
}

# Split prose into SC (scope) and SG (segments, blank-line separated).
function segsplit(t,   pos, p, e, a, b) {
    SC = ""; SG = ""; pos = 1
    while ((p = kwpos(t, pos))) {
        SC = addpiece(SC, substr(t, pos, p - pos), " ")
        a = kwpos(t, p + 1); b = labelpos(t, p + 1)
        e = (a && (!b || a < b)) ? a : b
        if (!e) { SG = addpiece(SG, substr(t, p), "\n\n"); pos = length(t) + 1; break }
        SG = addpiece(SG, substr(t, p, e - p), "\n\n"); pos = e
    }
    SC = addpiece(SC, substr(t, pos), " ")
}

{
    c = sub(/\r$/, "")
    L[NR] = $0; CRL[NR] = c; n = NR
    if (NR == 1) FILECR = c
}

END {
    CTL = ENVIRON["MIG_CTL"]; LOGF = ENVIRON["MIG_LOG"]; TODAY = ENVIRON["MIG_TODAY"]
    mid = it_mid()
    # Frontmatter.
    fm_end = 0; isinit = 0; hastopics = 0
    if (n >= 1 && L[1] == "---") {
        for (i = 2; i <= n; i++) {
            if (L[i] == "---") { fm_end = i; break }
            if (L[i] ~ /^kind:[ \t]*["\047]?initiative["\047]?[ \t]*$/) isinit = 1
            if (L[i] ~ /^topics:/) hastopics = 1
        }
    }
    if (!isinit || !fm_end) { ctl("S\tnot-initiative"); exit }

    # Fences and sections (first `## Targets`, first `## Decision stream`).
    t_beg = 0; t_end = n + 1; s_beg = 0; s_end = n + 1
    for (i = 1; i <= n; i++) {
        fz[i] = (i > fm_end) ? ds_fence(L[i]) : 0
        fo[i] = (i > fm_end) ? DS_FOPEN : 0
        if (fz[i] || i <= fm_end || L[i] !~ /^## /) continue
        if (t_beg && t_end > n && i > t_beg) t_end = i
        if (s_beg && s_end > n && i > s_beg) s_end = i
        if (!t_beg && L[i] ~ /^## Targets[ \t]*$/) t_beg = i
        else if (!s_beg && tolower(L[i]) ~ /^## decision stream[ \t]*$/) s_beg = i
    }

    # Decision stream collector; remember each ok head line.
    ds_reset()
    if (s_beg) for (i = s_beg + 1; i < s_end; i++) {
        if (fz[i]) { if (fo[i] && L[i] ~ /^[^ \t]/) ds_close(); continue }
        if (ds_feed(L[i]) == "ok") HL[ds_count()] = i
        else if (DS_ID != "") BADHEAD[DS_ID] = 1
    }

    # Target blocks.
    nb = 0; cs = 0
    if (t_beg) for (i = t_beg + 1; i < t_end; i++) {
        if (fz[i] || L[i] !~ /^### /) continue
        nb++; BS[nb] = i
        if (nb > 1) BE[nb - 1] = i - 1
        BID[nb] = trim(substr(L[i], 5))
    }
    if (nb) BE[nb] = t_end - 1
    old = 0
    for (k = 1; k <= nb; k++) {
        if (ds_streq(BID[k], "Closed")) { if (!cs) cs = k; BK[k] = "closedsec"; continue }
        na = 0; st = 0; jira = ""; mode = ""; scp = 0; nst = 0
        last = BS[k]
        for (i = BS[k] + 1; i <= BE[k]; i++) {
            if (L[i] !~ /^[ \t]*$/) last = i
            if (fz[i]) continue
            if (L[i] ~ /^- next_actor:/) { if (!na) na = i; NAL[k, ++NNA[k]] = i }
            else if (L[i] ~ /^- status: /) { if (!st) st = i; STL[k, ++nst] = i }
            else if (L[i] ~ /^- jira: /) { jira = L[i]; sub(/^- jira: /, "", jira); jira = trim(jira) }
            else if (L[i] ~ /^- execution_mode: /) { mode = L[i]; sub(/^- execution_mode: /, "", mode); mode = trim(mode) }
            else if (L[i] ~ /^- scope: /) scp = i
        }
        BL[k] = last; BNA[k] = na; BST[k] = st; BJ[k] = jira; BM[k] = mode; BSC[k] = scp
        BK[k] = "new"; skind = ""; valid = 1
        if (st) {
            s = L[st]; sub(/^- status: /, "", s); s = trim(s); BS_TXT[k] = s
            IT_ID[1] = BID[k]; IT_STATE[1] = ""; IT_LN = st; ne = IT_NE
            it_status(1, s)
            valid = (IT_STATE[1] != "")
            if (IT_NE > ne) skind = IT_EK[IT_NE]
        }
        if (nst > 1) {
            BNST[k] = nst
            if (na || skind == "old") { old = 1; BK[k] = "unmatched"; BWHY[k] = "Target has more than one status line"; continue }
            BK[k] = "badnew"; BWHY[k] = "Target has more than one status line"; continue
        }
        if (!na && skind != "old") {
            if (st && !valid) { BK[k] = "badnew"; BWHY[k] = "status does not match the new grammar (fix by hand)" }
            continue
        }
        old = 1
        w = st ? BS_TXT[k] : ""; sub(/[ \t].*$/, "", w)
        # Only a finished (done) Target collapses into a Closed row: a Closed row
        # reads as done and satisfies dependencies. An abandoned (closed) one
        # keeps its heading, so its dependents stay unsatisfied.
        if (st && w ~ /^done([^A-Za-z0-9_-]|$)/) {
            BK[k] = "collapse"
            r = BS_TXT[k]; sub(/^[a-z]+[ \t]*/, "", r)
            d = substr(r, 1, 10); if (substr(r, 1, 1) == "(") d = substr(r, 2, 10)
            BD[k] = ds_isdate(d) ? d : "-"
        } else if (st && valid) {
            BK[k] = "dropna"
        } else if (st && skind == "old") {
            rest = substr(BS_TXT[k], length(w) + 1)
            dp = index(rest, dash())
            m = trim(substr(rest, 1, dp - 1))
            if (!middle_ok(m)) { BK[k] = "unmatched"; BWHY[k] = "status middle `" m "` is not a date or (…)"; continue }
            BK[k] = "convert"; BW[k] = w
            prose = trim(substr(rest, dp + length(dash())))
            segsplit(prose)
            sc = SC
            if (m != "") sc = (sc == "" ? m : m dash() sc)
            BSCOPE[k] = sc; BSEG[k] = SG
        } else if (!st) {
            BK[k] = "dropna"
            if (ds_streq(mode, "interactive")) ctl("W\tTarget " BID[k] " (line " BS[k] ") is interactive and has no status: add one by hand")
        } else {
            BK[k] = "unmatched"; BWHY[k] = "status is not `<open|blocked|done|closed> — prose` or the new grammar"
        }
    }
    if (!old) {
        # Not rewritten, but a status that breaks the new grammar is reported
        # (input line numbers: the file is left byte-identical).
        for (k = 1; k <= nb; k++) if (BK[k] == "badnew") {
            if (BNST[k] > 1) { for (t = 1; t <= BNST[k]; t++) ctl("B\t" STL[k, t]) }
            else ctl("B\t" BST[k])
        }
        ctl("S\tnew-format"); exit
    }

    # Plan the rewrite.
    nconv = 0; ncol = 0; nrows = 0
    for (k = 1; k <= nb; k++) {
        if (BK[k] == "unmatched" || BK[k] == "badnew") {
            if (BNST[k] > 1) { for (t = 1; t <= BNST[k]; t++) unmatched(STL[k, t], BWHY[k]) }
            else unmatched(BST[k], BWHY[k])
            for (t = 1; t <= NNA[k]; t++) unmatched(NAL[k, t], "left with its Target, whose status was not converted")
            continue
        }
        nalines = ""
        for (t = 1; t <= NNA[k]; t++) { DROP[NAL[k, t]] = 1; nalines = nalines (t > 1 ? "\n" : "") L[NAL[k, t]] }
        if (BK[k] == "collapse") {
            body = ""
            for (i = BS[k]; i <= BL[k]; i++) body = body (i > BS[k] ? "\n" : "") L[i] (CRL[i] ? "\r" : "")
            logent(BID[k], body)
            for (i = BS[k]; i <= BE[k]; i++) DROP[i] = 1
            ROW[++nrows] = "| " cell(BID[k]) " | " BD[k] " | " cell(BJ[k]) " | see log |"
            ncol++
            continue
        }
        if (BK[k] == "dropna") {
            logent(BID[k], nalines)
            nconv++
            continue
        }
        if (BK[k] == "convert") {
            nx = ""
            if (BNA[k]) { nx = L[BNA[k]]; sub(/^- next_actor:/, "", nx); nx = trim(nx) }
            if (nx == "" || tolower(nx) == "none") nx = "none"
            # closed (abandoned) is terminal: it stands alone, and every
            # next_actor line goes to the log.
            if (BW[k] == "closed") ns = "- status: closed" (CRL[BST[k]] ? "\r" : "")
            else ns = "- status: " BW[k] mid "next: " nx mid "blocked_by: none" (CRL[BST[k]] ? "\r" : "")
            sc = BSCOPE[k]; segs = BSEG[k]
            if (sc != "" && BSC[k]) { segs = "scope (Target already had a scope: line): " sc (segs == "" ? "" : "\n\n" segs); sc = "" }
            if (NNA[k] > 1 || (NNA[k] && BW[k] == "closed")) segs = nalines (segs == "" ? "" : "\n\n" segs)
            if (sc != "") ns = "- scope: " sc (CRL[BST[k]] ? "\r" : "") "\n" ns
            REPL[BST[k]] = ns
            if (segs != "") logent(BID[k], segs)
            nconv++
        }
    }

    # Forward pointers from SUPERSEDES keywords.
    nptr = 0
    for (j = 1; j <= ds_count(); j++) {
        cnt = split(ds_supersedes(j), ids, " ")
        for (t = 1; t <= cnt; t++) {
            x = ds_id(j)
            if (ids[t] == x) continue
            if (!ds_exists(ids[t])) {
                if (ids[t] in BADHEAD) ctl("W\t" x " SUPERSEDES " ids[t] ", which names a malformed head (left unedited): no pointer added")
                else ctl("W\t" x " SUPERSEDES " ids[t] ", which is not in the stream: no pointer added")
                continue
            }
            for (i = 1; i <= ds_count(); i++) {
                if (ds_id(i) != ids[t] || ds_has(ds_ptr(i), x) || ((i, x) in PDONE)) continue
                PDONE[i, x] = 1
                h = HL[i]; line = L[h]
                dp = index(line, dash())
                hd = substr(line, 1, dp - 1)
                if (index(hd, " " ds_arrow() " ") > 0) hd = hd ", " x
                else hd = hd " " ds_arrow() " " x
                L[h] = hd substr(line, dp)
                PCH[h] = 1; nptr++
            }
        }
    }

    # Candidates.
    cand = ds_candidates()
    if (cand != "") { cnt = split(cand, cl, "\n"); for (t = 1; t <= cnt; t++) { split(cl[t], pr, " "); ctl("K\t" pr[1] "\t" pr[2]) } }

    # Closed rows: into the existing Closed table, else a new section.
    closed_after = 0
    if (nrows && cs) {
        closed_after = BS[cs]
        for (i = BS[cs] + 1; i <= BE[cs]; i++) if (!fz[i] && L[i] ~ /^[ \t]*\|/) closed_after = i
        if (closed_after == BS[cs]) NEEDHDR = 1
    }

    for (i = 1; i <= n; i++) {
        if (i == fm_end && !hastopics) emit("topics: []" crs())
        if (nrows && !cs && i == t_end) closed_block()
        if (DROP[i]) continue
        if (i in REPL) { cnt = split(REPL[i], rl, "\n"); for (t = 1; t <= cnt; t++) emit(rl[t]); continue }
        emit(L[i] (CRL[i] ? "\r" : "")); OUTLN[i] = OUTN
        if (i == closed_after) {
            if (NEEDHDR) { emit("" crs()); emit("| id | closed | jira | outcome |" crs()); emit("|---|---|---|---|" crs()) }
            for (t = 1; t <= nrows; t++) emit(ROW[t] crs())
        }
    }
    if (nrows && !cs && t_end > n) closed_block()

    for (t = 1; t <= NUM; t++) ctl("U\t" OUTLN[UMI[t]] "\t" rep(L[UMI[t]]) "\t" UMW[t])
    ctl("C\t" nconv); ctl("X\t" ncol); ctl("G\t" NLOG + 0); ctl("P\t" nptr)
    for (i = 1; i <= OUTN; i++) {
        if (i == OUTN && nonl) printf "%s", OUT[i]
        else printf "%s\n", OUT[i]
    }
}

function closed_block(   t) {
    if (OUTN && OUT[OUTN] !~ /^\r?$/) emit("" crs())
    emit("### Closed" crs()); emit("" crs())
    emit("| id | closed | jira | outcome |" crs()); emit("|---|---|---|---|" crs())
    for (t = 1; t <= nrows; t++) emit(ROW[t] crs())
    if (t_end <= n) emit("" crs())
}
'

LOG_HEADER='# Progress log — %s

Append-only. Dated entries tagged with a Target id; progress history that would
otherwise crowd the initiative file. Entries marked "migrated by 3.0.0" hold text
the 3.0.0 migration moved out of the initiative.
'

tmp="" ctl="" lg="" ltmp="" btmp=""
cleanup() { rm -f "$tmp" "$ctl" "$lg" "$ltmp" "$btmp"; }
trap cleanup EXIT

for f in "$DIR"/*.md; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    case "$f" in */_template.md) continue ;; esac
    if [ -L "$f" ]; then
        echo "3.0.0: skipped symlink (migrate its target by hand): $f"
        continue
    fi
    [ -f "$f" ] || continue
    slug="$(basename "$f" .md)"

    nonl=0
    if [ -s "$f" ] && [ "$(tail -c 1 "$f" | wc -l | tr -d ' ')" = "0" ]; then nonl=1; fi

    tmp="$(mktemp "$DIR/.mig-3.0.0.XXXXXX")"
    ctl="$(mktemp "$DIR/.mig-3.0.0.ctl.XXXXXX")"
    lg="$(mktemp "$DIR/.mig-3.0.0.log.XXXXXX")"
    if ! MIG_CTL="$ctl" MIG_LOG="$lg" MIG_TODAY="$TODAY" awk -v nonl="$nonl" "$DS_LIB
$IT_LIB
$AWK_PROG" "$f" > "$tmp"; then
        echo "3.0.0: failed to process $f" >&2
        exit 1
    fi

    if awk -F'\t' '$1 == "S" { f = 1 } END { exit !f }' "$ctl"; then
        awk -F'\t' -v f="$f" '$1 == "B" { printf "3.0.0: %s:%s: status does not match the 3.0.0 grammar; fix by hand (lint ERRORs it)\n", f, $2 }' "$ctl"
        rm -f "$tmp" "$ctl" "$lg"; tmp="" ctl="" lg=""
        continue
    fi

    conv="$(awk -F'\t' '$1 == "C" { print $2 }' "$ctl")"
    coll="$(awk -F'\t' '$1 == "X" { print $2 }' "$ctl")"
    nlog="$(awk -F'\t' '$1 == "G" { print $2 }' "$ctl")"
    nptr="$(awk -F'\t' '$1 == "P" { print $2 }' "$ctl")"
    printf '3.0.0: %s: %s Target(s) converted, %s collapsed into Closed rows, %s log entr(ies), %s forward pointer(s) added\n' \
        "$f" "${conv:-0}" "${coll:-0}" "${nlog:-0}" "${nptr:-0}"
    while IFS="$(printf '\t')" read -r tag a b c; do
        case "$tag" in
            K) printf '3.0.0: candidate: %s amends %s — add an AMENDS line by hand\n' "$a" "$b" ;;
            U) printf '3.0.0: unmatched line left unchanged (fix by hand): %s:%s: %s (%s)\n' "$f" "$a" "$b" "$c" ;;
            W) printf '3.0.0: note: %s: %s\n' "$f" "$a" ;;
        esac
    done < "$ctl"
    rm -f "$ctl"; ctl=""

    if cmp -s "$f" "$tmp"; then
        rm -f "$tmp" "$lg"; tmp="" lg=""
        echo "3.0.0: $f: nothing rewritten"
        continue
    fi

    mode="$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")"

    # Backup before the first write; an existing backup is kept.
    mkdir -p "$DIR/.state"
    backup="$DIR/.state/$slug.pre-3.0.0.md"
    if [ ! -e "$backup" ]; then
        btmp="$(mktemp "$DIR/.state/.mig-3.0.0.bak.XXXXXX")"
        cp "$f" "$btmp"
        chmod "$mode" "$btmp"
        mv "$btmp" "$backup"; btmp=""
        echo "3.0.0: backup: $backup"
    fi

    # Append moved text to the log before the main file (temp + mv; existing
    # bytes kept as is). Entries already present (same text after the date)
    # are skipped, so a rerun after a failed main-file write adds nothing.
    if [ -s "$lg" ]; then
        mkdir -p "$DIR/logs"
        logf="$DIR/logs/$slug.md"
        ltmp="$(mktemp "$DIR/logs/.mig-3.0.0.XXXXXX")"
        if [ -e "$logf" ]; then
            cat "$logf" > "$ltmp"
            chmod "$(stat -c %a "$logf" 2>/dev/null || stat -f %Lp "$logf")" "$ltmp"
        else
            # shellcheck disable=SC2059
            printf "$LOG_HEADER" "$slug" > "$ltmp"
            chmod "$mode" "$ltmp"
        fi
        counts="$(awk -v ex="$ltmp" -v RS='\036' '
            BEGIN { while ((getline l < ex) > 0) seen = seen l "\n"; close(ex) }
            $0 == "" || $0 == "\n" { next }
            {
                k = $0; sub(/^\n## [^ ]+ /, "", k)
                if (index(seen, k) > 0) { skip++; next }
                printf "%s", $0 >> ex
                seen = seen $0; add++
            }
            END { print add + 0, skip + 0 }
        ' "$lg")"
        mv "$ltmp" "$logf"; ltmp=""
        echo "3.0.0: log: $logf (${counts%% *} entr(ies) appended, ${counts##* } already present)"
    fi
    rm -f "$lg"; lg=""

    chmod "$mode" "$tmp"
    mv "$tmp" "$f" || { echo "3.0.0: cannot write $f (rerun the migration; the log will not be duplicated)" >&2; exit 1; }
    tmp=""

    if ! err="$(MEMORY_DIR="$MEMORY_DIR" bash "$REPO_ROOT/scripts/initiative-status.sh" --tsv "$slug" 2>&1 >/dev/null)"; then
        echo "3.0.0: $f: fences skipped: initiative-status.sh refuses the result (fix the reported lines, then run initiative-render.sh $slug --write):"
        printf '%s\n' "$err" | sed 's/^/3.0.0:   /'
        continue
    fi
    if ! err="$(MEMORY_DIR="$MEMORY_DIR" bash "$REPO_ROOT/scripts/initiative-render.sh" "$slug" --write 2>&1 >/dev/null)"; then
        echo "3.0.0: $f: fences skipped: initiative-render.sh --write failed:"
        printf '%s\n' "$err" | sed 's/^/3.0.0:   /'
        continue
    fi
    echo "3.0.0: $f: fences written (initiative-render.sh $slug --write)"
done
