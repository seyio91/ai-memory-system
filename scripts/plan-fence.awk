# Shared plan-file line scanner for check-plan-drift.sh and lint-memory.sh
# rule 20: ONE definition of "which lines are live plan text". Function
# library only (BSD awk + gawk); load with `awk -f plan-fence.awk -f <prog>`.
#
# pf_skip(line) — call first on every input line. Returns 1 when the line is
# not live text (leading frontmatter block, a fence opener/body/closer), else 0.
# Side effects: PF_RAW = line without a trailing CR; PF_T = PF_RAW minus up to
# 3 leading spaces (the form fence markers are matched on).
# Fences follow CommonMark: opener = ``` plus an info string with no backtick,
# or ~~~ plus anything; closer = same char, length >= opener, then whitespace only.
function pf_skip(line,   s, c, n) {
    PF_RAW = line; sub(/\r$/, "", PF_RAW)
    PF_T = PF_RAW; sub(/^ ? ? ?/, "", PF_T)
    if (FNR == 1) {
        pf_fm = 0; pf_fence = 0
        if (PF_RAW ~ /^---[ \t]*$/) { pf_fm = 1; return 1 }
    }
    if (pf_fm) {
        if (PF_RAW ~ /^---[ \t]*$/) pf_fm = 0
        return 1
    }
    if (pf_fence) {
        s = PF_T; sub(/[ \t]+$/, "", s)
        if (substr(s, 1, 1) == pf_ch && s ~ /^(`+|~+)$/ && length(s) >= pf_len) pf_fence = 0
        return 1
    }
    if (PF_T ~ /^```+[^`]*$/ || PF_T ~ /^~~~+/) {
        pf_ch = substr(PF_T, 1, 1); n = 0
        while (substr(PF_T, n + 1, 1) == pf_ch) n++
        pf_len = n; pf_fence = 1
        return 1
    }
    return 0
}
