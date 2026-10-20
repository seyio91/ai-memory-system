# Decision-stream grammar shared by lint-memory.sh, initiative-status.sh and
# migrations/1.7.0-decision-status-field.sh. Functions only: no BEGIN/END or
# pattern rules, so it can be concatenated ahead of any caller program (BSD
# awk, gawk, mawk). Callers must not define names starting `ds_` or `DS_`.
#
# Per line (CR already stripped): `if (ds_track(L)) { ...stream body line... }`.
# After a true return, `ds_head(L)` classifies an entry head.

function ds_dash() { return "\342\200\224" }

function ds_status_ok(s) {
    return (s == "proposed" || s == "confirmed" || s == "rejected" || s == "superseded" || s == "retired")
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
    if (ds_fence(L)) return 0
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
    DS_ID = ""; DS_NUM = ""; DS_STATUS = ""; DS_DATE = ""
    if (L !~ /^-[ \t]+D/) return ""
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
    if (substr(a, 1, length(d)) == d) return "ok"
    if (a !~ /^ [^ \t]+/) return "bad"
    a = substr(a, 2); b = index(a, " ")
    if (b == 0) return "bad"
    DS_DATE = substr(a, 1, b - 1)
    if (substr(a, b, length(d)) != d) return "bad"
    if (ds_dateshape(DS_DATE) && !ds_isdate(DS_DATE)) return "bad"
    return "ok"
}
