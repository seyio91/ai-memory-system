#!/usr/bin/env bash
# scripts/hooks/lib.sh _initiative_targets_project on the 3.0.0 initiative
# format: the cheap project-prefix predicate must keep matching `@env` Targets,
# and a project whose only Targets are `### Closed` table rows must not match
# (a closed Target raises no alert).
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
mkdir -p "$MEM/initiatives"

cat > "$MEM/initiatives/fmt.md" <<'EOF'
---
kind: initiative
slug: fmt
status: active
created: 2026-11-17
---
# Fmt
## Targets
### envproj/thing@staging
- execution_mode: interactive
- scope: staging rollout
- depends_on: none
- status: open · next: exec — roll out · blocked_by: none
### plainproj/thing
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — build · blocked_by: none
### Closed
| id | closed | jira | outcome |
|---|---|---|---|
| closedonly/old | 2026-10-01 | ABC-1 | shipped |
| envproj2/old@prod | 2026-10-02 | ABC-2 | see log |
## Closure
Open.
EOF

matches() { # project
    MEMORY_DIR="$MEM" bash -c '. "$1/scripts/hooks/lib.sh"; _initiative_targets_project "$2" "$3"' _ "$REPO" "$MEM/initiatives/fmt.md" "$1" >/dev/null 2>&1
    echo $?
}

assert_eq 0 "$(matches envproj)" "an @env Target matches by project prefix"
assert_eq 0 "$(matches plainproj)" "a plain Target still matches by project prefix"
assert_eq 1 "$(matches closedonly)" "a project whose only Targets are Closed rows does not match"
assert_eq 1 "$(matches envproj2)" "a Closed row carrying an @env id does not match"
assert_eq 1 "$(matches absent)" "an unrelated project does not match"
assert_eq 1 "$(matches env)" "the prefix match needs the full project name before the slash"

finish
