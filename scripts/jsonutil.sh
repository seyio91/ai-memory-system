#!/usr/bin/env bash
# jsonutil.sh — minimal JSON helpers for hook I/O (the Antigravity PreInvocation
# injector, and later the PreToolUse guard). Kept separate so hook scripts can
# share JSON behavior without depending on the full memory loader.
# Strategy: jq -> python3 -> (escape-only) sed/awk fallback, so hooks work even
# without jq installed.

# json_escape <string> — print the argument as a JSON string literal (quoted).
json_escape() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -Rs .
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
    else
        printf '%s' "$1" \
            | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
            | awk 'BEGIN{printf "\""} {if(NR>1) printf "\\n"; printf "%s",$0} END{printf "\""}'
    fi
}

json_parser_available() {
    command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1
}

# json_get <key> — read a JSON object from stdin, print the top-level <key> as a
# scalar (empty if absent or on parse error). jq -> python3; no plain-shell
# fallback (parsing arbitrary JSON in sed is not worth it — callers default
# sensibly on empty).
json_get() {
    local key="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    v = d.get(sys.argv[1], "")
    print("" if v is None else v)
except Exception:
    print("")' "$key" 2>/dev/null
    else
        echo ""
    fi
}

# json_get_path <key1> <key2> ... — read a NESTED scalar from JSON on stdin
# (e.g. `json_get_path toolCall args CommandLine`). Empty on any missing level or
# parse error. python3 -> jq (python3 first: nested walking is cleaner there).
json_get_path() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1:]:
        d = d.get(k) if isinstance(d, dict) else None
        if d is None: break
    print("" if d is None else d)
except Exception:
    print("")' "$@" 2>/dev/null
    elif command -v jq >/dev/null 2>&1; then
        local expr="." k
        for k in "$@"; do expr="${expr}[\"$k\"]"; done
        jq -r "${expr} // empty" 2>/dev/null
    else
        echo ""
    fi
}
