#!/usr/bin/env bash
# validate-skills.sh: tier + structural static checks over a skills store.
. "$(dirname "$0")/_assert.sh"

VS="$SCRIPTS_DIR/validate-skills.sh"

# write_skill <memdir> <name> -- body read from stdin into skills/<name>/SKILL.md
write_skill() {
    local m="$1" n="$2"
    mkdir -p "$m/skills/$n"
    cat > "$m/skills/$n/SKILL.md"
}

# --- clean store: valid skills (inline desc, block desc, lowercase {{ }}) ------
MEM="$(new_sandbox)"; BAD=""; BIG=""
trap 'rm -rf "$MEM" "$BAD" "$BIG"' EXIT
export MEMORY_DIR="$MEM"

write_skill "$MEM" good-ro <<'EOF'
---
name: good-ro
description: A read-only skill.
metadata:
  tier: target-read-only
---
# Good RO
Body.
EOF

write_skill "$MEM" good-rw <<'EOF'
---
name: good-rw
description:
  A write skill whose description is a YAML block scalar
  spanning two lines.
metadata:
  tier: target-write
---
# Good RW
Body.
EOF

# lowercase {{ }} is legitimate content (Grafana legends etc.) — must NOT be flagged
write_skill "$MEM" good-content <<'EOF'
---
name: good-content
description: legitimate lowercase templating in body.
metadata:
  tier: target-write
---
# Good content
"legendFormat": "{{status_code}}", titled "{{service}} {{version}}".
EOF

set +e
out=$(bash "$VS" 2>&1); code=$?
set -e
assert_exit 0 "$code" "clean store exits 0"
assert_contains "$out" "3 skill(s) OK" "clean store reports 3 OK"
assert_not_contains "$out" "ERROR" "clean store has no errors"
assert_not_contains "$out" "placeholder" "lowercase {{ }} content not flagged"

# --list enumerates skills
set +e
lst=$(bash "$VS" --list 2>&1); code=$?
set -e
assert_exit 0 "$code" "--list exits 0"
assert_contains "$lst" "good-ro" "--list shows good-ro"

# --- bad store: one of each failure mode --------------------------------------
BAD="$(new_sandbox)"
export MEMORY_DIR="$BAD"

# top-level tier (outside metadata:) must NOT satisfy the metadata.tier check
write_skill "$BAD" toptier <<'EOF'
---
name: toptier
description: tier at top level, not under metadata.
tier: target-write
---
# x
EOF

# missing name key
write_skill "$BAD" noname <<'EOF'
---
description: no name field.
metadata:
  tier: target-read-only
---
# x
EOF

# opening --- absent entirely
mkdir -p "$BAD/skills/noopen"
printf 'name: noopen\nNo frontmatter fence here.\n' > "$BAD/skills/noopen/SKILL.md"

# opening --- present, closing --- absent
mkdir -p "$BAD/skills/noclose"
printf -- '---\nname: noclose\ndescription: unterminated.\nmetadata:\n  tier: target-write\n# body, never closed\n' > "$BAD/skills/noclose/SKILL.md"

# valid one survives alongside the bad ones
write_skill "$BAD" ok <<'EOF'
---
name: ok
description: fine.
metadata:
  tier: target-write
---
# ok
EOF

# dir with no SKILL.md
mkdir -p "$BAD/skills/nomd"

write_skill "$BAD" notier <<'EOF'
---
name: notier
description: missing tier.
---
# x
EOF

write_skill "$BAD" badtier <<'EOF'
---
name: badtier
description: bogus tier value.
metadata:
  tier: sometimes
---
# x
EOF

write_skill "$BAD" nodesc <<'EOF'
---
name: nodesc
metadata:
  tier: target-read-only
---
# x
EOF

write_skill "$BAD" ph <<'EOF'
---
name: ph
description: has a placeholder.
metadata:
  tier: target-write
---
Body with {{UNRESOLVED}} token.
EOF

set +e
out=$(bash "$VS" 2>&1); code=$?
set -e
assert_exit 1 "$code" "bad store exits 1"
assert_contains "$out" "nomd missing SKILL.md" "flags missing SKILL.md"
assert_contains "$out" "notier missing metadata.tier" "flags missing tier"
assert_contains "$out" "badtier invalid metadata.tier: 'sometimes'" "flags invalid tier"
assert_contains "$out" "nodesc missing frontmatter field: description" "flags missing description"
assert_contains "$out" "noname missing frontmatter field: name" "flags missing name"
assert_contains "$out" "ph has unresolved placeholder(s): {{UNRESOLVED}}" "flags placeholder"
assert_contains "$out" "toptier missing metadata.tier" "top-level tier doesn't satisfy metadata.tier"
assert_contains "$out" "noopen SKILL.md has no opening frontmatter" "flags missing opening ---"
assert_contains "$out" "noclose frontmatter not closed" "flags missing closing ---"

# --- size flag is a WARN, not a failure ---------------------------------------
BIG="$(new_sandbox)"
export MEMORY_DIR="$BIG"
mkdir -p "$BIG/skills/big"
{
    printf -- '---\nname: big\ndescription: big.\nmetadata:\n  tier: target-write\n---\n'
    i=1; while [ "$i" -le 520 ]; do printf 'line %d\n' "$i"; i=$((i + 1)); done
} > "$BIG/skills/big/SKILL.md"

set +e
out=$(bash "$VS" 2>&1); code=$?
set -e
assert_exit 0 "$code" "oversized-but-valid skill still exits 0 (WARN only)"
assert_contains "$out" "WARN" "size emits a WARN"
assert_contains "$out" "big SKILL.md is" "WARN names the oversized skill"

finish
