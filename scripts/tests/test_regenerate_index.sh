#!/usr/bin/env bash
# regenerate-index.sh: lean Projects roster (name + summary, no path/metadata),
# Working-memory section removed, Domain table unchanged (path + triggers kept),
# idempotent, excludes _template, preserves content outside the AUTOGEN fence.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"

seed_min_tree "$MEM"                 # identity + _template + domain/terraform (triggers: [terraform, terraform-alias]) + index stub
seed_domain "$MEM" "aws"
mkdir -p "$MEM/projects/realproj"
cat > "$MEM/projects/realproj/memory.md" <<'EOF'
---
topic: realproj
scope: project
summary: A real project summary
---
# Project: realproj
EOF
: > "$MEM/projects/realproj/working.md"

# Domain scaffold must be excluded like the project scaffold is.
cat > "$MEM/domain/_template.md" <<'EOF'
---
topic: <topic>
triggers: [<keyword>]
summary: <one-line description>
---
EOF

# Put a sentinel outside the fence to verify preservation.
printf '# Index\n\nSENTINEL-PRESERVE-ME\n\n<!-- BEGIN AUTOGEN -->\n<!-- END AUTOGEN -->\n' > "$MEM/index.md"

bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null
first="$(cat "$MEM/index.md")"

assert_contains     "$first" "SENTINEL-PRESERVE-ME"           "preserves content outside fence"
assert_contains     "$first" "realproj"                       "lists project by name"
assert_contains     "$first" "A real project summary"         "lists project summary"
assert_not_contains "$first" "projects/realproj/memory.md"    "project file path NOT in index"
assert_not_contains "$first" "Working memory"                 "Working-memory section removed"
assert_not_contains "$first" "/_template/"                    "excludes _template"
assert_not_contains "$first" "<topic>"                        "excludes domain/_template.md scaffold"
# Domain table is path-less now: topic + triggers + summary, but no file path.
assert_contains     "$first" "terraform"                      "lists domain topic"
assert_not_contains "$first" "domain/terraform.md"            "domain file path NOT in index (derive domain/<topic>.md)"
assert_contains     "$first" "terraform-alias"                "domain triggers kept in index"
assert_contains     "$first" "aws-alias"                      "domain triggers kept (aws)"

# --- idempotence: second run yields identical file ---
bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null
second="$(cat "$MEM/index.md")"
assert_eq "$first" "$second" "idempotent (second run identical)"

# --- creates fence when missing ---
M2="$(new_sandbox)"; export MEMORY_DIR="$M2"; seed_min_tree "$M2"
printf 'plain index no fence\n' > "$M2/index.md"
bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null
assert_contains "$(cat "$M2/index.md")" "BEGIN AUTOGEN" "adds fence when absent"
assert_contains "$(cat "$M2/index.md")" "plain index no fence" "keeps prior body when adding fence"
rm -rf "$M2"

# --- lean Projects: metadata stays in memory.md, never echoed into the index ---
M3="$(new_sandbox)"; export MEMORY_DIR="$M3"; seed_min_tree "$M3"
mkdir -p "$M3/projects/tagged"
cat > "$M3/projects/tagged/memory.md" <<'EOF'
---
topic: tagged
scope: project
summary: tagged project
tags: [terraform, aws, eks]
repo_path: some/where
repo: git@github.com:org/tagged.git
---
# body
EOF
: > "$M3/projects/tagged/working.md"
bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null
idx="$(cat "$M3/index.md")"
assert_contains     "$idx" "tagged"            "project listed by name"
assert_contains     "$idx" "tagged project"    "project listed by summary"
assert_not_contains "$idx" "eks"               "project tags NOT in index (eks only appears as a tag)"
assert_not_contains "$idx" "tagged.git"        "project repo/origin NOT in index"
assert_not_contains "$idx" "some/where"        "project repo_path NOT in index"
assert_not_contains "$idx" "projects/tagged/memory.md" "project file path NOT in index"
# idempotent
bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null
assert_eq "$idx" "$(cat "$M3/index.md")" "idempotent (lean index)"
rm -rf "$M3"

finish
