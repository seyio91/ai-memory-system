# Decision-stream grammar shared by lint-memory.sh, initiative-status.sh and
# migrations/1.7.0-decision-status-field.sh. Functions only: no BEGIN/END or
# pattern rules, so it can be concatenated ahead of any caller program (BSD
# awk, gawk, mawk). Callers must not define names starting `ds_` or `DS_`.
#
# Per line (CR already stripped): `if (ds_track(L)) { ...stream body line... }`.
# After a true return, `ds_head(L)` classifies an entry head.
#
# Entry metadata (added for the initiative Now view)
#   Forward pointer: `→ D<n>` (U+2192), optionally a list `→ D75, D80`, sits on
#   the head AFTER the date (or after the status when no date) and BEFORE the
#   ` — ` that opens the decision text:
#       - D45 confirmed 2026-10-01 → D75 — text
#   ds_head strips a well-formed pointer before classifying, so a head without
#   one classifies exactly as before. Sets DS_PTR (ids, space-joined; "" when
#   none). A pointer AFTER the dash is not a pointer: the head classifies ok and
#   the arrow is decision text (DS_PTR ""). A malformed pointer (`→ see D3`,
#   `→ D3.`) or one before the date leaves the head "bad".
#   Continuation lines (indented under an entry, fences excluded by ds_track):
#       topic: <name>              the entry's topic (first non-blank one wins)
#       SUPERSEDES <ids>           upper-case keyword, optional colon after it
#       AMENDS <ids>
#   Id parser (keywords and prose): tokens split on whitespace, "," and "/"; the
#   word "and" is skipped; from each token leading `*`, `_`, `(`, `[` are
#   dropped and the leading D<n>[a-z]? is taken when the next byte is not
#   [A-Za-z0-9] (so `**D55**`, `D55)`, `D1's.`, `D50’s` all yield the id). The
#   list stops at the first token that is not an id, or after one whose remainder
#   contains `.`, `;`, `!`, `?` or `)`. A keyword line yielding no id is never
#   dropped silently: see ds_bad_keywords.
#
# Collector API (stateful; call ds_reset() once, ds_feed() per stream line, then
# query in END). Entries are addressed by 1-based index i in stream order, so
# repeated ids (superseded copies) stay distinct.
#   ds_reset()            forget all entries
#   ds_feed(L)            L is a stream body line (ds_track true). Runs ds_head;
#                         an "ok" head opens a new entry, an indented line is
#                         parsed as a continuation of the current entry and its
#                         text kept. A blank line, a non-indented non-head line,
#                         or a column-0 fence opener (closed inside ds_track, or
#                         call ds_close() yourself) ends the entry, as in lint.
#                         A head that classifies "bad" but has an id is kept as
#                         a candidate-only entry (never in the live set, counts
#                         or pointer checks). Returns the ds_head class.
#   ds_close()            end the current entry (continuations stop attaching)
#   ds_count()            number of ok entries
#   ds_id(i) ds_status(i) ds_date(i) ds_topic(i) ds_ptr(i)   fields ("" if none)
#   ds_supersedes(i) ds_amends(i)   id lists, space-joined
#   ds_text(i)            head + continuation lines, newline-joined
#   ds_live(i)            1 (byte-exact status match) when status is confirmed or proposed (superseded,
#                         rejected, retired and unknown drop out)
#   ds_live_ids()         live ids in stream order, space-joined, de-duplicated
#   ds_exists(id)         1 when an ok entry has this id
#   ds_amended_by(id)     ids of LIVE entries whose AMENDS names id, stream
#                         order, space-joined ("" when none or id is "")
#   ds_missing_pointers() newline-separated "<target> <by> <KEYWORD>" lines for
#                         every EXISTING entry id that a different LIVE entry
#                         AMENDS or SUPERSEDES but where no entry with that id
#                         carries a pointer naming <by>. "" when complete.
#   ds_unknown_targets()  newline-separated "<by> <target> <KEYWORD>" lines for
#                         AMENDS/SUPERSEDES keywords naming an id absent from
#                         the stream. "" when none.
#   ds_bad_keywords()     newline-separated "<entry-id> <line text>" for every
#                         AMENDS/SUPERSEDES continuation that yields no id
#   ds_dangling_pointers() newline-separated "<entry-id> <ptr-id>" for a `→ Dn`
#                         naming an id absent from the stream
#   ds_candidates()       newline-separated "<amender> <target>" lines for prose
#                         amendments: text of live entries (ok heads, plus bad
#                         heads with an id whose status is not superseded /
#                         rejected / retired) matching, case-insensitively,
#                         "amends[:] <ids>" or "amended by[:] <ids>" (any run of
#                         spaces/tabs between words; id parser above), each id
#                         its own line, with no matching AMENDS keyword on the
#                         amender. Distinct pairs. "" if none.
# All separator/dash comparisons are byte-exact (index/substr), never `==` on
# non-ASCII: BSD awk in a UTF-8 locale collates the arrow, em dash and en dash as
# equal under `==`.

function ds_dash() { return "\342\200\224" }

# Byte-exact string equality (never `==` on possibly non-ASCII text: BSD awk in
# a UTF-8 locale collates distinct strings as equal).
function ds_streq(a, b) { return (length(a) == length(b) && index(a, b) == 1) || (a == "" && b == "") }

function ds_status_ok(s) {
    return (ds_streq(s, "proposed") || ds_streq(s, "confirmed") || ds_streq(s, "rejected") || ds_streq(s, "superseded") || ds_streq(s, "retired"))
}

# YYYY-MM-DD shape only.
function ds_dateshape(d) {
    return (d ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/)
}

# YYYY-MM-DD that is a real calendar day (month lengths, leap years).
function ds_isdate(d,   y, m, dd, mx) {
    if (!ds_dateshape(d)) return 0
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    if (m < 1 || m > 12 || dd < 1) return 0
    mx = 31
    if (m == 4 || m == 6 || m == 9 || m == 11) mx = 30
    else if (m == 2) mx = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
    return (dd <= mx)
}

# Legacy: plain D<n> (no letter) with n <= lt (lt < 0: no legacy mark).
function ds_legacy(id, lt,   n) {
    if (id !~ /^D[0-9]+$/ || lt < 0) return 0
    n = substr(id, 2) + 0
    return (n <= lt + 0)
}

function ds_run(t, ch,   n) {
    n = 0
    while (substr(t, n + 1, 1) == ch) n++
    return n
}

# Fence tracking. Returns 1 when the line is a fence delimiter or inside a
# fence (callers skip it). A fence opens with 3+ backticks or tildes (a
# backtick fence's info string holds no backtick, so inline ```x``` is not one)
# and closes only on the same character, at least as long, followed by nothing
# but whitespace. Sets DS_FOPEN=1 on the line that opens a fence.
function ds_fence(L,   t, n, ch) {
    DS_FOPEN = 0
    t = L; sub(/^[ \t]+/, "", t)
    ch = substr(t, 1, 1)
    if (ds_fch != "") {
        if (ch == ds_fch) {
            n = ds_run(t, ch)
            if (n >= ds_flen && substr(t, n + 1) ~ /^[ \t]*$/) ds_fch = ""
        }
        return 1
    }
    if (ch != "`" && ch != "~") return 0
    n = ds_run(t, ch)
    if (n < 3) return 0
    if (ch == "`" && index(substr(t, n + 1), "`") > 0) return 0
    ds_fch = ch; ds_flen = n; DS_FOPEN = 1
    return 1
}

# 1 while a fence is still open (call at end of input).
function ds_fence_open() { return (ds_fch != "") }

# Stream tracking, fences included. Returns 1 for a body line of the first
# `## Decision stream` section (case-insensitive heading), else 0. Sets DS_END=1
# on the line that ends the stream (a `## ` line outside a fence); the stream is
# never re-entered. Fence lines and fenced text return 0.
function ds_track(L) {
    DS_END = 0
    if (ds_fence(L)) {
        if (DS_FOPEN && ds_in && L ~ /^[^ \t]/) ds_close()
        return 0
    }
    if (!ds_done && !ds_in && tolower(L) ~ /^## decision stream[ \t]*$/) { ds_in = 1; return 0 }
    if (ds_in && L ~ /^## /) { ds_in = 0; ds_done = 1; DS_END = 1; return 0 }
    return ds_in
}

# Classify a stream line. Returns:
#   ""       not an entry head (does not start `-<ws>D`)
#   "unmig"  old suffix shape (`- D<n>-proposed`, `- D<n>-rejected`, `- D<n>:`, `- D<n> (`)
#   "ok"     `- D<n>[a-z]? <status> [<date-token>] — ...`, single spaces; the
#            status is not checked against the set, the date token is not
#            required, but a YYYY-MM-DD token must be a real day
#   "bad"    any other line starting `- D`
# Sets DS_ID (when an id parsed), DS_NUM, DS_STATUS, DS_DATE (token as written).
function ds_head(L,   rest, d, a, b) {
    DS_ID = ""; DS_NUM = ""; DS_STATUS = ""; DS_DATE = ""; DS_PTR = ""
    if (L !~ /^-[ \t]+D/) return ""
    L = ds_ptrsplit(L)
    if (!match(L, /^- D[0-9]+[a-z]?/)) return "bad"
    DS_ID = substr(L, 3, RLENGTH - 2)
    rest = substr(L, RLENGTH + 1)
    DS_NUM = DS_ID; sub(/^D/, "", DS_NUM); sub(/[^0-9].*$/, "", DS_NUM)
    if (rest ~ /^-(proposed|rejected)([^A-Za-z0-9]|$)/ || rest ~ /^:/ || rest ~ /^[ \t]+\(/) return "unmig"
    d = " " ds_dash() " "
    if (rest !~ /^ [^ \t]+/) return "bad"
    a = substr(rest, 2); b = index(a, " ")
    if (b == 0) return "bad"
    DS_STATUS = substr(a, 1, b - 1)
    a = substr(a, b)
    if (index(a, d) == 1) return "ok"
    if (a !~ /^ [^ \t]+/) return "bad"
    a = substr(a, 2); b = index(a, " ")
    if (b == 0) return "bad"
    DS_DATE = substr(a, 1, b - 1)
    if (index(substr(a, b), d) != 1) return "bad"
    if (ds_dateshape(DS_DATE) && !ds_isdate(DS_DATE)) return "bad"
    return "ok"
}

function ds_arrow() { return "\342\206\222" }

# Split a forward pointer ` → D<n>[, D<m>...]` out of a head. The pointer must
# sit before the first ` — `. Sets DS_PTR and returns the head with the pointer
# removed; returns L unchanged (DS_PTR "") when there is no well-formed one.
function ds_ptrsplit(L,   dpos, h, a, p, n, parts, i, out) {
    DS_PTR = ""
    dpos = index(L, " " ds_dash() " ")
    if (dpos == 0) return L
    h = substr(L, 1, dpos - 1)
    p = " " ds_arrow() " "
    a = index(h, p)
    if (a == 0) return L
    n = split(substr(h, a + length(p)), parts, /, */)
    out = ""
    for (i = 1; i <= n; i++) {
        if (parts[i] !~ /^D[0-9]+[a-z]?$/) return L
        out = out (out == "" ? "" : " ") parts[i]
    }
    DS_PTR = out
    return substr(h, 1, a - 1) substr(L, dpos)
}

# Id list from the text after a keyword (see header for the grammar).
# ci=1: accept lower-case d and normalise to D.
function ds_idlist(t, ci,   n, parts, i, out, w, rem) {
    gsub(/[,\/]/, " ", t)
    n = split(t, parts, /[ \t]+/)
    out = ""
    for (i = 1; i <= n; i++) {
        w = parts[i]
        sub(/^[*_(\[]+/, "", w)
        if (w == "") continue
        if (w == "and" || (ci && tolower(w) == "and")) continue
        if (!match(w, ci ? "^[Dd][0-9]+[a-z]?" : "^D[0-9]+[a-z]?")) break
        rem = substr(w, RLENGTH + 1)
        if (rem ~ /^[A-Za-z0-9]/) break
        out = out (out == "" ? "" : " ") "D" substr(w, 2, RLENGTH - 1)
        if (rem ~ /[.;!?)]/) break
    }
    return out
}

function ds_reset() {
    split("", ds_e_id); split("", ds_e_st); split("", ds_e_date); split("", ds_e_topic)
    split("", ds_e_ptr); split("", ds_e_sup); split("", ds_e_am); split("", ds_e_text)
    split("", ds_b_id); split("", ds_b_am); split("", ds_b_text); split("", ds_b_st)
    split("", ds_k_id); split("", ds_k_text)
    ds_n = 0; ds_nb = 0; ds_nk = 0; ds_cur = 0; ds_curb = 0
}

function ds_close() { ds_cur = 0; ds_curb = 0 }

function ds_feed(L,   c) {
    c = ds_head(L)
    if (c == "ok") {
        ds_n++; ds_cur = ds_n; ds_curb = 0
        ds_e_id[ds_n] = DS_ID; ds_e_st[ds_n] = DS_STATUS; ds_e_date[ds_n] = DS_DATE
        ds_e_ptr[ds_n] = DS_PTR; ds_e_topic[ds_n] = ""; ds_e_sup[ds_n] = ""; ds_e_am[ds_n] = ""
        ds_e_text[ds_n] = L
        return c
    }
    if (c != "") {
        ds_close()
        if (c == "bad" && DS_ID != "") {
            ds_nb++; ds_curb = ds_nb
            ds_b_id[ds_nb] = DS_ID; ds_b_st[ds_nb] = DS_STATUS; ds_b_am[ds_nb] = ""; ds_b_text[ds_nb] = L
        }
        return c
    }
    if (L ~ /^[ \t]*$/ || L !~ /^[ \t]/) { ds_close(); return c }
    ds_cont(L)
    return c
}

# Keyword continuation: returns the ids after `KW` (optional colon), or sets
# ds_kwbad=1 when the line names none.
function ds_kwids(t, klen,   r, ids) {
    r = substr(t, klen + 1)
    sub(/^[ \t]*:?/, "", r)
    ids = ds_idlist(r, 0)
    ds_kwbad = (ids == "")
    return ids
}

# Attach an indented continuation line to the current entry.
function ds_cont(L,   t, k, ids, eid) {
    t = L; sub(/^[ \t]+/, "", t)
    if (ds_curb) {
        ds_b_text[ds_curb] = ds_b_text[ds_curb] "\n" L
        eid = ds_b_id[ds_curb]
    } else if (ds_cur) {
        ds_e_text[ds_cur] = ds_e_text[ds_cur] "\n" L
        eid = ds_e_id[ds_cur]
    } else return
    if (!ds_curb && t ~ /^topic:/) {
        k = substr(t, 7); sub(/^[ \t]+/, "", k); sub(/[ \t]+$/, "", k)
        if (k != "" && ds_e_topic[ds_cur] == "") ds_e_topic[ds_cur] = k
    } else if (t ~ /^SUPERSEDES([ \t:]|$)/ || t ~ /^AMENDS([ \t:]|$)/) {
        if (t ~ /^AMENDS/) ids = ds_kwids(t, 6); else ids = ds_kwids(t, 10)
        if (ds_kwbad) { ds_nk++; ds_k_id[ds_nk] = eid; ds_k_text[ds_nk] = t; return }
        if (ds_curb) { if (t ~ /^AMENDS/) ds_b_am[ds_curb] = ds_b_am[ds_curb] " " ids; return }
        if (t ~ /^AMENDS/) ds_e_am[ds_cur] = ds_e_am[ds_cur] (ds_e_am[ds_cur] == "" ? "" : " ") ids
        else ds_e_sup[ds_cur] = ds_e_sup[ds_cur] (ds_e_sup[ds_cur] == "" ? "" : " ") ids
    }
}

function ds_count() { return ds_n + 0 }
function ds_id(i) { return ds_e_id[i] }
function ds_status(i) { return ds_e_st[i] }
function ds_date(i) { return ds_e_date[i] }
function ds_topic(i) { return ds_e_topic[i] }
function ds_ptr(i) { return ds_e_ptr[i] }
function ds_supersedes(i) { return ds_e_sup[i] }
function ds_amends(i) { return ds_e_am[i] }
function ds_text(i) { return ds_e_text[i] }
function ds_live(i) { return (ds_streq(ds_e_st[i], "confirmed") || ds_streq(ds_e_st[i], "proposed")) }

# 1 when the space-joined list contains id.
function ds_has(list, id) { return (index(" " list " ", " " id " ") > 0) }

function ds_exists(id,   i) {
    for (i = 1; i <= ds_n; i++) if (ds_e_id[i] == id) return 1
    return 0
}

function ds_live_ids(   i, out, seen) {
    out = ""; split("", seen)
    for (i = 1; i <= ds_n; i++) {
        if (!ds_live(i) || (ds_e_id[i] in seen)) continue
        seen[ds_e_id[i]] = 1
        out = out (out == "" ? "" : " ") ds_e_id[i]
    }
    return out
}

function ds_amended_by(id,   i, out) {
    out = ""
    if (id == "") return out
    for (i = 1; i <= ds_n; i++)
        if (ds_live(i) && ds_e_id[i] != id && ds_has(ds_e_am[i], id) && !ds_has(out, ds_e_id[i]))
            out = out (out == "" ? "" : " ") ds_e_id[i]
    return out
}

# Does any entry with this id carry a pointer naming `by`?
function ds_points(id, by,   i) {
    for (i = 1; i <= ds_n; i++)
        if (ds_e_id[i] == id && ds_has(ds_e_ptr[i], by)) return 1
    return 0
}

function ds_missing_pointers(   j, k, n, ids, out, t, kw, seen, key) {
    out = ""; split("", seen)
    for (j = 1; j <= ds_n; j++) {
        if (!ds_live(j)) continue
        for (k = 1; k <= 2; k++) {
            kw = (k == 1) ? "AMENDS" : "SUPERSEDES"
            n = split((k == 1) ? ds_e_am[j] : ds_e_sup[j], ids, " ")
            for (t = 1; t <= n; t++) {
                if (ids[t] == ds_e_id[j] || !ds_exists(ids[t])) continue
                key = ids[t] " " ds_e_id[j] " " kw
                if ((key in seen) || ds_points(ids[t], ds_e_id[j])) continue
                seen[key] = 1
                out = out (out == "" ? "" : "\n") key
            }
        }
    }
    return out
}

function ds_unknown_targets(   j, k, n, ids, out, t, kw, seen, key) {
    out = ""; split("", seen)
    for (j = 1; j <= ds_n; j++) {
        for (k = 1; k <= 2; k++) {
            kw = (k == 1) ? "AMENDS" : "SUPERSEDES"
            n = split((k == 1) ? ds_e_am[j] : ds_e_sup[j], ids, " ")
            for (t = 1; t <= n; t++) {
                if (ds_exists(ids[t])) continue
                key = ds_e_id[j] " " ids[t] " " kw
                if (key in seen) continue
                seen[key] = 1
                out = out (out == "" ? "" : "\n") key
            }
        }
    }
    return out
}

function ds_bad_keywords(   i, out) {
    out = ""
    for (i = 1; i <= ds_nk; i++) out = out (out == "" ? "" : "\n") ds_k_id[i] " " ds_k_text[i]
    return out
}

function ds_dangling_pointers(   i, n, ids, t, out) {
    out = ""
    for (i = 1; i <= ds_n; i++) {
        n = split(ds_e_ptr[i], ids, " ")
        for (t = 1; t <= n; t++)
            if (!ds_exists(ids[t])) out = out (out == "" ? "" : "\n") ds_e_id[i] " " ids[t]
    }
    return out
}

function ds_cand_add(amender, target,   key) {
    key = amender " " target
    if (amender == target || (key in ds_cseen)) return
    ds_cseen[key] = 1
    ds_cout = ds_cout (ds_cout == "" ? "" : "\n") key
}

# Does some entry (ok or bad head) with this id carry AMENDS <target>?
function ds_amends_kw(amender, target,   i) {
    for (i = 1; i <= ds_n; i++)
        if (ds_e_id[i] == amender && ds_has(ds_e_am[i], target)) return 1
    for (i = 1; i <= ds_nb; i++)
        if (ds_b_id[i] == amender && ds_has(ds_b_am[i], target)) return 1
    return 0
}

# Scan one entry's text for prose amendments.
function ds_cand_scan(id, text,   t, parts, n, q, j, pre, kind, re, tail, p, rest) {
    t = tolower(text)
    for (kind = 1; kind <= 2; kind++) {
        re = (kind == 1) ? "amends:?[ \t]+" : "amended[ \t]+by:?[ \t]+"
        p = 1
        while (match(substr(t, p), re)) {
            q = p + RSTART - 1
            pre = (q > 1) ? substr(t, q - 1, 1) : " "
            p = q + RLENGTH
            if (pre ~ /[a-z0-9]/) continue
            tail = substr(text, p)
            sub(/\n.*$/, "", tail)
            n = split(ds_idlist(tail, 1), parts, " ")
            for (j = 1; j <= n; j++) {
                if (kind == 1) { if (!ds_amends_kw(id, parts[j])) ds_cand_add(id, parts[j]) }
                else if (!ds_amends_kw(parts[j], id)) ds_cand_add(parts[j], id)
            }
        }
    }
}

function ds_candidates(   i) {
    ds_cout = ""; split("", ds_cseen)
    for (i = 1; i <= ds_n; i++) if (ds_live(i)) ds_cand_scan(ds_e_id[i], ds_e_text[i])
    for (i = 1; i <= ds_nb; i++) {
        if (ds_streq(ds_b_st[i], "superseded") || ds_streq(ds_b_st[i], "rejected") || ds_streq(ds_b_st[i], "retired")) continue
        ds_cand_scan(ds_b_id[i], ds_b_text[i])
    }
    return ds_cout
}
