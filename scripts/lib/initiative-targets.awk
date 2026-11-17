# Initiative Target grammar shared by initiative-status.sh and lint-memory.sh.
# Functions only: no BEGIN/END or pattern rules, so it can be concatenated
# ahead of any caller program (BSD awk, gawk, mawk). Callers must not define
# names starting `it_` or `IT_`. REQUIRES lib/decision-stream.awk concatenated
# first: fences are tracked with ds_fence and strings compared with ds_streq,
# so a `## Targets` / `### ` heading or `- status:` line inside a fenced code
# block is ignored. Feed every line through it_line from ONE program only:
# the fence state is shared with ds_track, so a caller that also runs ds_track
# on the same lines must be a separate awk invocation.
#
# Per line (CR already stripped): `it_line($0)`. At end: `it_emit(sep)` prints
# one record per Target, fields joined by `sep`:
#   T id mode stages depends_on task scope jira status state next blocked_by closed
# then one `E sep <kind> sep <message>` line per format error (kind `old` for a
# `next_actor:` line or an old `<state> — prose` status, which the 3.0.0
# migration converts; kind `grammar` for any other format error). A program
# that reads the IT_* arrays itself calls it_finish() instead of it_emit().
# Only the `## Targets` section is read. Under it:
#   ### <project>/<name>[@<env>]   a Target; the id is the heading text, so an
#                                  @env id is just a longer plain string.
#   ### Closed                     rows `| <id> | <closed date> | <jira> | <outcome> |`
#                                  are terminal (done) Targets (closed=1); the
#                                  row before the separator is the header and is skipped.
# Target fields: `- execution_mode:` `- stages:` `- depends_on:` `- task:`
# `- scope:` `- jira:` `- status:`. The status grammar is
#   <state> · next: <session — action> · blocked_by: <…|none>
# where terminal states (done, closed) may stand alone. States are
# open|blocked|done|closed; any other state is a format error. `- status:` is optional
# for software_adw Targets and required for interactive ones. Format errors:
# any `- next_actor:` line, a status not matching the grammar, and an
# interactive Target with no status.

function it_mid() { return " \302\267 " }

function it_trim(s) {
    sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
    return s
}

function it_err(kind, msg) { IT_E[++IT_NE] = msg; IT_EK[IT_NE] = kind }

function it_start(id, closed) {
    IT_N++
    IT_ID[IT_N] = id; IT_MODE[IT_N] = ""; IT_STAGES[IT_N] = ""; IT_DEPS[IT_N] = ""
    IT_TASK[IT_N] = ""; IT_SCOPE[IT_N] = ""; IT_JIRA[IT_N] = ""; IT_STATUS[IT_N] = ""
    IT_STATE[IT_N] = ""; IT_NEXT[IT_N] = ""; IT_BLOCK[IT_N] = ""; IT_CLOSED[IT_N] = closed
}

# Parse the status text of Target n into state/next/blocked_by, or record a
# format error. State vocabulary: open, blocked, done, closed. done/closed may
# stand alone; anything else needs the full ` · next: … · blocked_by: …` tail.
function it_status(n, s,   mid, w, rest, j, nx, bl) {
    mid = it_mid()
    IT_STATUS[n] = s
    w = s; sub(/[ \t].*$/, "", w)
    rest = substr(s, length(w) + 1)
    if (ds_streq(w, "open") || ds_streq(w, "blocked") || ds_streq(w, "done") || ds_streq(w, "closed")) {
        if (rest == "" && (ds_streq(w, "done") || ds_streq(w, "closed"))) { IT_STATE[n] = w; return }
        j = index(rest, mid "blocked_by: ")
        if (index(rest, mid "next: ") == 1 && j > 1) {
            nx = it_trim(substr(rest, length(mid "next: ") + 1, j - length(mid "next: ") - 1))
            bl = it_trim(substr(rest, j + length(mid "blocked_by: ")))
            if (nx != "" && bl != "") {
                IT_STATE[n] = w; IT_NEXT[n] = nx; IT_BLOCK[n] = bl
                return
            }
        }
    }
    if (ds_streq(w, "open") || ds_streq(w, "blocked") || ds_streq(w, "done") || ds_streq(w, "closed")) {
        if (index(rest, " " ds_dash() " ") == 1) {
            it_err("old", "Target '" IT_ID[n] "' line " IT_LN " has an old-format status '<state> " ds_dash() " prose': " s)
            return
        }
    }
    it_err("grammar", "Target '" IT_ID[n] "' line " IT_LN " has a status not matching '<open|blocked|done|closed>" mid "next: <session " ds_dash() " action>" mid "blocked_by: <...|none>' (done/closed may stand alone; single spaces around the middle dot): " s)
}

# Split a table row body into cells on unescaped `|`; `\|` yields a literal `|`.
function it_cells(t, c,   n, i, ch, cur) {
    n = 0; cur = ""
    for (i = 1; i <= length(t); i++) {
        ch = substr(t, i, 1)
        if (ch == "\\" && substr(t, i + 1, 1) == "|") { cur = cur "|"; i++ }
        else if (ch == "|") { c[++n] = it_trim(cur); cur = "" }
        else cur = cur ch
    }
    c[++n] = it_trim(cur)
    return n
}

function it_flush_row(   k, o) {
    if (!IT_PEND) return
    IT_PEND = 0
    if (IT_PC[1] == "") return
    it_start(IT_PC[1], 1)
    IT_JIRA[IT_N] = IT_PC[3]
    o = IT_PC[4]
    for (k = 5; k <= IT_PN; k++) o = o " | " IT_PC[k]
    IT_SCOPE[IT_N] = o
    IT_STATUS[IT_N] = "done"; IT_STATE[IT_N] = "done"
}

# A row is held until the next row shows it is not the header: the row
# immediately before the separator row is the header, whatever its text.
function it_closed_row(L,   t, c, n, k) {
    t = it_trim(L)
    if (t !~ /^\|/) return
    sub(/^\|/, "", t)
    if (t ~ /[^\\]\|$/) sub(/\|$/, "", t)
    n = it_cells(t, c)
    if (c[1] ~ /^:?-+:?$/) { IT_PEND = 0; return }
    it_flush_row()
    for (k = 1; k <= n; k++) IT_PC[k] = c[k]
    for (k = n + 1; k <= 4; k++) IT_PC[k] = ""
    IT_PN = n; IT_PEND = 1
}

function it_line(L,   v) {
    IT_LN++
    if (IT_DONE) return
    if (ds_fence(L)) return
    if (L ~ /^## Targets[ \t]*$/) { IT_IN = 1; return }
    if (!IT_IN) return
    if (L ~ /^## /) { it_flush_row(); IT_DONE = 1; return }
    if (L ~ /^### /) {
        it_flush_row()
        v = it_trim(substr(L, 5))
        IT_CLOSED_SEC = ds_streq(v, "Closed")
        if (IT_CLOSED_SEC) IT_CUR = 0
        else { it_start(v, 0); IT_CUR = IT_N }
        return
    }
    if (IT_CLOSED_SEC) { it_closed_row(L); return }
    if (!IT_CUR) return
    if (L ~ /^- next_actor:/) { it_err("old", "Target '" IT_ID[IT_CUR] "' line " IT_LN " has a next_actor: line"); return }
    if (L ~ /^- execution_mode: /) { v = L; sub(/^- execution_mode: /, "", v); IT_MODE[IT_CUR] = v; return }
    if (L ~ /^- stages: /) { v = L; sub(/^- stages: /, "", v); IT_STAGES[IT_CUR] = v; return }
    if (L ~ /^- depends_on: /) { v = L; sub(/^- depends_on: /, "", v); IT_DEPS[IT_CUR] = v; return }
    if (L ~ /^- task: /) { v = L; sub(/^- task: /, "", v); IT_TASK[IT_CUR] = v; return }
    if (L ~ /^- scope: /) { v = L; sub(/^- scope: /, "", v); IT_SCOPE[IT_CUR] = v; return }
    if (L ~ /^- jira: /) { v = L; sub(/^- jira: /, "", v); IT_JIRA[IT_CUR] = v; return }
    if (L ~ /^- status: /) { v = L; sub(/^- status: /, "", v); it_status(IT_CUR, it_trim(v)); return }
}

# Print every Target record, then every format error. Interactive Targets
# without a status are a format error, found once the whole section is read.
function it_finish(   i) {
    if (IT_FIN) return
    IT_FIN = 1
    it_flush_row()
    for (i = 1; i <= IT_N; i++)
        if (!IT_CLOSED[i] && ds_streq(IT_MODE[i], "interactive") && IT_STATUS[i] == "")
            it_err("grammar", "Target '" IT_ID[i] "' is interactive and has no status")
}

function it_emit(sep,   i) {
    it_finish()
    for (i = 1; i <= IT_N; i++) {
        print "T" sep IT_ID[i] sep IT_MODE[i] sep IT_STAGES[i] sep IT_DEPS[i] sep IT_TASK[i] sep IT_SCOPE[i] sep IT_JIRA[i] sep IT_STATUS[i] sep IT_STATE[i] sep IT_NEXT[i] sep IT_BLOCK[i] sep IT_CLOSED[i]
    }
    for (i = 1; i <= IT_NE; i++) print "E" sep IT_EK[i] sep IT_E[i]
}
