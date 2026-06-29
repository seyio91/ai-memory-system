#!/usr/bin/env bash
#
# skill-boundary-check.sh — enforce a skill's write boundary (subsystem #11) by
# comparing git state before/after a skill runs. Harness-agnostic and *detective*
# (it reports a violation after the fact; the codex execpolicy prevents the
# destructive class up front). Targets bash 3.2.
#
# The check has two halves (see plans/skill-subsystem.md → Design):
#   * target tree  — a `target-read-only` skill must not modify the repo it
#                    operates on. Any change to --target = violation.
#   * memory repo  — writes must stay inside the skill's own folder
#                    (skills/<skill>/). Scope `full` forbids any other memory
#                    write; `others-only` forbids only *other* skills' dirs
#                    (the in-session narrowing — the orchestrator legitimately
#                    co-edits memory.md/todo.md/plans in the same turn).
#
# Two subcommands — the caller snapshots before the skill runs, checks after:
#
#   skill-boundary-check.sh snapshot --repo <path>
#       Print an opaque baseline (HEAD + porcelain status) to stdout. Save it.
#
#   skill-boundary-check.sh check --skill <name> --tier <tier> \
#       --memory <dir> --memory-baseline <file> [--memory-scope full|others-only] \
#       [--target <path> --target-baseline <file>]
#       Compare current state to the baselines; print VIOLATION: lines.
#
# Exit: 0 clean, 1 violation(s), 2 usage/setup error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# _lib.sh only for MEMORY_DIR default; tolerate being run outside the tree.
[ -f "$SCRIPT_DIR/_lib.sh" ] && . "$SCRIPT_DIR/_lib.sh" 2>/dev/null || true

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# repo_snapshot <repo> — emit "HEAD <sha|NONE>" then `git status --porcelain`.
# A non-repo or missing path yields HEAD NONE and no porcelain (treated as "no
# tracked changes possible" — the caller's --target/--memory must be real repos).
repo_snapshot() {
    local repo="$1" head
    if [ -d "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || printf 'NONE')"
        printf 'HEAD %s\n' "$head"
        # -uall: list untracked files individually (git otherwise collapses an
        # entirely-untracked dir to "?? dir/", which defeats path-prefix checks).
        git -C "$repo" status --porcelain -uall
    else
        printf 'HEAD NONE\n'
    fi
}

# porcelain_path <porcelain-line> — extract the path (handle "R  old -> new").
porcelain_path() {
    local line="$1" p
    p="${line#???}"               # strip "XY " status prefix (3 chars)
    case "$p" in *' -> '*) p="${p##* -> }" ;; esac
    # strip surrounding quotes git adds for paths with odd chars
    p="${p%\"}"; p="${p#\"}"
    printf '%s\n' "$p"
}

# changed_paths <repo> <baseline-file> — print the set of paths changed since the
# baseline (committed diffs if HEAD moved, plus porcelain lines not in baseline).
changed_paths() {
    local repo="$1" base="$2" base_head cur_head line p
    base_head="$(awk 'NR==1{print $2; exit}' "$base")"
    cur_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || printf 'NONE')"

    # 1. Committed changes (HEAD moved).
    if [ "$base_head" != "NONE" ] && [ "$cur_head" != "NONE" ] && [ "$base_head" != "$cur_head" ]; then
        git -C "$repo" diff --name-only "$base_head" "$cur_head" 2>/dev/null
    fi

    # 2. Working-tree changes new since baseline (porcelain line absent before).
    #    Compare full porcelain lines so a status transition counts as new.
    local baseline_pc; baseline_pc="$(awk 'NR>1' "$base")"
    git -C "$repo" status --porcelain -uall 2>/dev/null | while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "
$baseline_pc
" in
            *"
$line
"*) : ;;                       # unchanged since baseline — skip
            *) porcelain_path "$line" ;;
        esac
    done
}

cmd_snapshot() {
    local repo=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) repo="${2:-}"; shift 2 ;;
            *) printf 'snapshot: unknown arg: %s\n' "$1" >&2; exit 2 ;;
        esac
    done
    [ -n "$repo" ] || { printf 'snapshot: --repo required\n' >&2; exit 2; }
    repo_snapshot "$repo"
}

cmd_check() {
    local skill="" tier="" memory="${MEMORY_DIR:-}" mem_base="" mem_scope="full"
    local target="" tgt_base="" violations=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --skill)           skill="${2:-}"; shift 2 ;;
            --tier)            tier="${2:-}"; shift 2 ;;
            --memory)          memory="${2:-}"; shift 2 ;;
            --memory-baseline) mem_base="${2:-}"; shift 2 ;;
            --memory-scope)    mem_scope="${2:-}"; shift 2 ;;
            --target)          target="${2:-}"; shift 2 ;;
            --target-baseline) tgt_base="${2:-}"; shift 2 ;;
            *) printf 'check: unknown arg: %s\n' "$1" >&2; exit 2 ;;
        esac
    done
    [ -n "$skill" ] || { printf 'check: --skill required\n' >&2; exit 2; }
    case "$tier" in
        target-read-only|target-write) : ;;
        *) printf 'check: --tier must be target-read-only | target-write\n' >&2; exit 2 ;;
    esac
    case "$mem_scope" in full|others-only) : ;; *) printf 'check: --memory-scope must be full | others-only\n' >&2; exit 2 ;; esac

    # --- memory repo: writes must stay inside skills/<skill>/ -------------------
    if [ -n "$memory" ] && [ -n "$mem_base" ]; then
        [ -f "$mem_base" ] || { printf 'check: memory baseline not found: %s\n' "$mem_base" >&2; exit 2; }
        local own="skills/$skill/" p
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            case "$p" in
                "$own"*) continue ;;                      # own folder — always allowed
            esac
            if [ "$mem_scope" = full ]; then
                printf 'VIOLATION: %s wrote outside its own folder in memory repo: %s\n' "$skill" "$p"
                violations=$((violations + 1))
            else
                case "$p" in
                    skills/*) printf 'VIOLATION: %s wrote into another skill'\''s folder: %s\n' "$skill" "$p"
                              violations=$((violations + 1)) ;;
                esac
            fi
        done <<EOF
$(changed_paths "$memory" "$mem_base")
EOF
    fi

    # --- target repo: a read-only skill must not touch it ----------------------
    if [ "$tier" = target-read-only ] && [ -n "$target" ] && [ -n "$tgt_base" ]; then
        [ -f "$tgt_base" ] || { printf 'check: target baseline not found: %s\n' "$tgt_base" >&2; exit 2; }
        local tp
        while IFS= read -r tp; do
            [ -n "$tp" ] || continue
            printf 'VIOLATION: %s (target-read-only) modified the target repo: %s\n' "$skill" "$tp"
            violations=$((violations + 1))
        done <<EOF
$(changed_paths "$target" "$tgt_base")
EOF
    fi

    if [ "$violations" -gt 0 ]; then
        printf 'skill-boundary-check: %d violation(s) for %s\n' "$violations" "$skill" >&2
        exit 1
    fi
    printf 'skill-boundary-check: %s OK\n' "$skill"
    exit 0
}

case "${1:-}" in
    snapshot) shift; cmd_snapshot "$@" ;;
    check)    shift; cmd_check "$@" ;;
    -h|--help|"") usage ;;
    *) printf 'unknown subcommand: %s\n' "$1" >&2; usage ;;
esac
