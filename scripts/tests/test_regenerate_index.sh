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

# Initiatives are live work state, deliberately excluded from the lean catalog.
mkdir -p "$MEM/initiatives"
cat > "$MEM/initiatives/not-in-index.md" <<'EOF'
---
kind: initiative
slug: not-in-index
status: active
created: 2026-08-14
---
# INITIATIVE-MUST-NOT-APPEAR
EOF

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
assert_not_contains "$first" "INITIATIVE-MUST-NOT-APPEAR"      "excludes initiatives from index"
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

# --- MEMORY_DIR containing a space: path-safe enumeration ---
M4="$(new_sandbox)/with space"; mkdir -p "$M4"; export MEMORY_DIR="$M4"; seed_min_tree "$M4"
mkdir -p "$M4/projects/spaced"
printf -- '---\ntopic: spaced\nscope: project\nsummary: spaced summary\n---\n' > "$M4/projects/spaced/memory.md"
rc=0; bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "MEMORY_DIR with a space: exit 0"
sp="$(cat "$M4/index.md")"
assert_contains "$sp" "| spaced | spaced summary |" "space in MEMORY_DIR: project row present"
assert_contains "$sp" "terraform-alias"             "space in MEMORY_DIR: domain row present"
leftover="$(find "$M4" -maxdepth 1 -name '.index.*' | wc -l | tr -d ' ')"
assert_eq "0" "$leftover" "no .index.* temp files after successful run"
rm -f "$M4/index.md"
( umask 022; bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null 2>&1 )
mode="$(ls -l "$M4/index.md" | cut -c1-10)"
assert_eq "-rw-r--r--" "$mode" "regenerated index.md gets the umask (022) mode, not mktemp's 0600"
rm -rf "$(dirname "$M4")"

# --- mid-generation failure leaves prior index byte-identical, no temp litter ---
M5="$(new_sandbox)"; export MEMORY_DIR="$M5"; seed_min_tree "$M5"
printf '# Index\nKEEP\n<!-- BEGIN AUTOGEN -->\nold\n<!-- END AUTOGEN -->\n' > "$M5/index.md"
cp "$M5/index.md" "$M5/index.before"
STUB="$M5/stubbin"; mkdir -p "$STUB"
printf '#!/bin/sh\nexit 7\n' > "$STUB/awk"; chmod +x "$STUB/awk"
rc=0; PATH="$STUB:$PATH" bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null 2>&1 || rc=$?
nz=0; [ "$rc" -ne 0 ] && nz=1
assert_eq "1" "$nz" "forced mid-run failure exits non-zero"
same=0; cmp -s "$M5/index.md" "$M5/index.before" && same=1
assert_eq "1" "$same" "failed run leaves prior index.md byte-identical"
litter="$(find "$M5" -maxdepth 1 \( -name '.index.*' -o -name 'index.md.*' \) | wc -l | tr -d ' ')"
assert_eq "0" "$litter" "failed run leaves no temp files beside index.md"
rm -rf "$M5"

# --- failing enumeration (sort / find) must abort, not silently drop rows ---
for tool in sort find; do
    M6="$(new_sandbox)"; export MEMORY_DIR="$M6"; seed_min_tree "$M6"
    mkdir -p "$M6/projects/p1"
    printf -- '---\ntopic: p1\nscope: project\nsummary: p1 summary\n---\n' > "$M6/projects/p1/memory.md"
    printf '# Index\nKEEP\n<!-- BEGIN AUTOGEN -->\nold\n<!-- END AUTOGEN -->\n' > "$M6/index.md"
    cp "$M6/index.md" "$M6/index.before"
    STUB="$M6/stubbin"; mkdir -p "$STUB"
    printf '#!/bin/sh\nexit 7\n' > "$STUB/$tool"; chmod +x "$STUB/$tool"
    rc=0; PATH="$STUB:$PATH" bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null 2>&1 || rc=$?
    nz=0; [ "$rc" -ne 0 ] && nz=1
    assert_eq "1" "$nz" "failing $tool in enumeration exits non-zero"
    same=0; cmp -s "$M6/index.md" "$M6/index.before" && same=1
    assert_eq "1" "$same" "failing $tool leaves prior index.md byte-identical"
    litter="$(find "$M6" -maxdepth 1 \( -name '.index.*' -o -name 'index.md.*' \) | wc -l | tr -d ' ')"
    assert_eq "0" "$litter" "failing $tool leaves no temp files"
    rm -rf "$M6"
done

# --- missing projects/ dir still works (empty roster) ---
M7="$(new_sandbox)"; export MEMORY_DIR="$M7"; seed_min_tree "$M7"; rm -rf "$M7/projects"
rc=0; bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "missing projects/ dir: exit 0"
rm -rf "$M7"

finish
