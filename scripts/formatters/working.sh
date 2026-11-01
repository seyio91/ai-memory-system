#!/usr/bin/env bash
# formatters/working.sh — render_working <path>: print working.md with the
# `## Checkpoints` section cut to its newest AI_MEMORY_CHECKPOINT_WINDOW (default 2)
# `### ` entries. Sourced by xml.sh and md.sh. Read-only; any filter failure or
# nothing-to-cut prints the file unchanged.

render_working() {
    local path="$1" w="${AI_MEMORY_CHECKPOINT_WINDOW:-2}" out rc body
    case "$w" in ''|*[!0-9]*) w=2 ;; esac
    [ "$((10#$w))" -gt 0 ] || w=2
    out=$(awk -v w="$((10#$w))" '
        function fenceline(s,   t, c, k) {
            t = s; sub(/^ ? ? ?/, "", t)
            if (fence) {
                sub(/[ \t]+$/, "", t)
                if (substr(t, 1, 1) == fch && t ~ /^(`+|~+)$/ && length(t) >= flen) fence = 0
                return 1
            }
            if (t !~ /^```+[^`]*$/ && t !~ /^~~~+/) return 0
            fch = substr(t, 1, 1); k = 0
            while (substr(t, k + 1, 1) == fch) k++
            flen = k; fence = 1
            return 1
        }
        {
            line[NR] = $0
            r = $0; sub(/\r$/, "", r)
            if (fenceline(r) || fence) { ent[NR] = insec ? n : 0; next }
            if (r ~ /^## /) { insec = (r ~ /^## Checkpoints[ \t]*$/); ent[NR] = 0; next }
            if (insec && r ~ /^### /) { n++; start[n] = NR }
            ent[NR] = insec ? n : 0
        }
        END {
            if (n <= w) exit 3
            first = n - w + 1
            for (i = 1; i <= NR; i++) {
                if (ent[i] > 0 && ent[i] < first) continue
                if (i == start[first]) printf "_(%d older checkpoints not loaded — see working.md)_\n", first - 1
                print line[i]
            }
        }
    ' "$path" 2>/dev/null; printf 'x%s' "$?")
    rc="${out##*x}"
    body="${out%x*}"
    if [ "$rc" = 0 ]; then printf '%s' "$body"; else cat "$path"; fi
}
