#!/usr/bin/env bash
# new-skill.sh (creator #12) + install-skill.sh (intake #13).
. "$(dirname "$0")/_assert.sh"

NEW="$SCRIPTS_DIR/new-skill.sh"
INS="$SCRIPTS_DIR/install-skill.sh"
command -v python3 >/dev/null 2>&1 || { printf 'SKIP: python3 unavailable\n'; finish; }

MEM="$(new_sandbox)"; SRC="$(new_sandbox)"
trap 'rm -rf "$MEM" "$SRC"' EXIT
export MEMORY_DIR="$MEM"

run() { set +e; out=$(bash "$@" 2>&1); code=$?; set -e; }

# === creator ===============================================================
run "$NEW" --name myrev --tier target-read-only --description "Review things."
assert_exit 0 "$code" "new-skill creates a read-only skill"
assert_file "$MEM/skills/myrev/SKILL.md" "SKILL.md written"
assert_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "tier: target-read-only" "tier in frontmatter"
assert_contains "$out" "validated: myrev OK" "scaffold passes validate-skills"
assert_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "MUST NOT modify the target" "read-only body guidance"

# scaffold is genuinely valid per the store validator
run "$SCRIPTS_DIR/validate-skills.sh"
assert_exit 0 "$code" "store with scaffolded skill validates clean"

# write skill body differs
run "$NEW" --name mygen --tier target-write --kind workflow
assert_exit 0 "$code" "new-skill creates a write skill"
assert_contains "$(cat "$MEM/skills/mygen/SKILL.md")" "tier: target-write" "write tier"
assert_contains "$(cat "$MEM/skills/mygen/SKILL.md")" "kind: workflow" "optional kind written"
assert_contains "$(cat "$MEM/skills/mygen/SKILL.md")" "partial:self-rating START" "workflow skill gets self-rating block"
# a non-workflow (reference/default) skill does NOT get the self-rating block
assert_not_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "partial:self-rating START" "non-workflow skill has no self-rating block"

# --local scaffolds into skills-local/, not skills/, and still validates + self-rates
run "$NEW" --name myloc --tier target-write --kind workflow --local
assert_exit 0 "$code" "new-skill --local creates a local skill"
assert_file "$MEM/skills-local/myloc/SKILL.md" "local skill written under skills-local/"
set +e; [ -e "$MEM/skills/myloc" ]; e=$?; set -e
assert_exit 1 "$e" "--local skill is NOT under skills/"
assert_contains "$(cat "$MEM/skills-local/myloc/SKILL.md")" "partial:self-rating START" "local workflow skill gets self-rating (apply-partial resolves across roots)"
assert_contains "$out" "validated: myloc OK" "local scaffold passes validate-skills (multi-root)"
# a read-only local skill points its own-folder guidance at skills-local/
run "$NEW" --name mylocro --tier target-read-only --local
assert_contains "$(cat "$MEM/skills-local/mylocro/SKILL.md")" "(skills-local/mylocro/)" "read-only body names the local own-folder"

# install --local forks an imported skill into skills-local/
mkdir -p "$SRC/imp-loc"
printf -- '---\nname: imp-loc\ndescription: imported local.\n---\n# body\n' > "$SRC/imp-loc/SKILL.md"
run "$INS" --from "$SRC/imp-loc" --tier target-write --local
assert_exit 0 "$code" "install --local imports into skills-local/"
assert_file "$MEM/skills-local/imp-loc/SKILL.md" "imported local skill under skills-local/"

# guards
run "$NEW" --name myrev --tier target-read-only
assert_exit 1 "$code" "refuses to overwrite without --force"
run "$NEW" --name bad --tier nonsense
assert_exit 2 "$code" "rejects invalid tier"
run "$NEW" --name "../evil" --tier target-write
assert_exit 2 "$code" "rejects bad name"

# === installer =============================================================
# source A: has a metadata block but no tier
mkdir -p "$SRC/withmeta"
cat > "$SRC/withmeta/SKILL.md" <<'EOF'
---
name: withmeta
description: imported, has metadata but no tier.
metadata:
  domain: platform
---
# withmeta
body.
EOF
run "$INS" --from "$SRC/withmeta" --tier target-read-only
assert_exit 0 "$code" "install adds tier to an existing metadata block"
assert_contains "$(cat "$MEM/skills/withmeta/SKILL.md")" "tier: target-read-only" "tier inserted under metadata"
assert_contains "$(cat "$MEM/skills/withmeta/SKILL.md")" "domain: platform" "existing metadata preserved"
assert_contains "$out" "validated: withmeta OK" "installed skill validates"

# source B: no metadata block at all + a references/ file to preserve
mkdir -p "$SRC/nometa/references"
cat > "$SRC/nometa/SKILL.md" <<'EOF'
---
name: nometa
description: imported, no metadata block.
---
# nometa
EOF
printf 'ref\n' > "$SRC/nometa/references/notes.md"
run "$INS" --from "$SRC/nometa" --tier target-write
assert_exit 0 "$code" "install adds a metadata block when none exists"
assert_contains "$(cat "$MEM/skills/nometa/SKILL.md")" "tier: target-write" "metadata block added with tier"
assert_file "$MEM/skills/nometa/references/notes.md" "references/ preserved on intake"

# source C: already has a (different) tier -> --tier is authoritative
cat > "$SRC/nometa/SKILL.md" <<'EOF'
---
name: nometa
description: now claims read-only.
metadata:
  tier: target-read-only
---
# nometa
EOF
run "$INS" --from "$SRC/nometa" --tier target-write --force
assert_exit 0 "$code" "install overrides an existing tier with --tier (+--force)"
assert_contains "$(cat "$MEM/skills/nometa/SKILL.md")" "tier: target-write" "tier overridden"
assert_not_contains "$(cat "$MEM/skills/nometa/SKILL.md")" "tier: target-read-only" "old tier gone"

# name derived from frontmatter when --name omitted (source B name=nometa)
assert_file "$MEM/skills/nometa/SKILL.md" "name derived from frontmatter"

# does NOT inject self-rating into imported skills
assert_not_contains "$(cat "$MEM/skills/withmeta/SKILL.md")" "self-rating" "no self-rating injected on intake"

# guards
run "$INS" --from "$SRC/withmeta"
assert_exit 2 "$code" "install requires --tier"
run "$INS" --from "$SRC/missing" --tier target-write
assert_exit 2 "$code" "install rejects missing --from"
run "$INS" --from "$SRC/withmeta" --tier target-read-only
assert_exit 1 "$code" "install refuses existing target without --force"

# === installer: frontmatter-shape robustness ===============================
# C: non-2-space metadata indent + existing tier -> replaced at the block indent
mkdir -p "$SRC/indent4"
printf -- '---\nname: indent4\ndescription: 4-space metadata.\nmetadata:\n    domain: x\n    tier: target-read-only\n---\n# indent4\n' > "$SRC/indent4/SKILL.md"
run "$INS" --from "$SRC/indent4" --tier target-write
assert_exit 0 "$code" "C: non-2-space metadata installs"
md="$(cat "$MEM/skills/indent4/SKILL.md")"
assert_contains "$md" "  tier: target-write" "C: tier normalized to our 2-space convention"
assert_contains "$md" "  domain: x" "C: sibling re-indented to 2-space (valid YAML)"
run "$SCRIPTS_DIR/validate-skills.sh"; assert_exit 0 "$code" "C: normalized skill passes our validator"

# A: a block-scalar body line reading 'tier:' must NOT be clobbered
mkdir -p "$SRC/blockscalar"
printf -- '---\nname: blockscalar\ndescription: block scalar.\nmetadata:\n  notes: |\n    tier: not-a-key\n  domain: x\n---\n# bs\n' > "$SRC/blockscalar/SKILL.md"
run "$INS" --from "$SRC/blockscalar" --tier target-read-only
assert_exit 0 "$code" "A: block-scalar source installs"
md="$(cat "$MEM/skills/blockscalar/SKILL.md")"
assert_contains "$md" "tier: not-a-key" "A: block-scalar body preserved"
assert_contains "$md" "tier: target-read-only" "A: real tier added"
assert_contains "$md" "domain: x" "A: sibling key preserved"

# B: a nested-mapping 'tier:' two levels deep is untouched
mkdir -p "$SRC/nested"
printf -- '---\nname: nested\ndescription: nested map.\nmetadata:\n  config:\n    tier: keep-this\n  domain: y\n---\n# n\n' > "$SRC/nested/SKILL.md"
run "$INS" --from "$SRC/nested" --tier target-write
assert_exit 0 "$code" "B: nested-mapping source installs"
md="$(cat "$MEM/skills/nested/SKILL.md")"
assert_contains "$md" "tier: keep-this" "B: nested tier untouched"
assert_contains "$md" "tier: target-write" "B: real tier added at top level"

# single SKILL.md (file, not dir) as --from
run "$INS" --from "$SRC/nested/SKILL.md" --tier target-write --name singlefile
assert_exit 0 "$code" "single SKILL.md (file) install works"
assert_file "$MEM/skills/singlefile/SKILL.md" "single-file install placed"

# --- guards: in-place re-import, bad name, no-frontmatter cleanup -----------
run "$INS" --from "$MEM/skills/withmeta" --tier target-write --force
assert_exit 2 "$code" "refuses in-place re-import (source == target)"
assert_file "$MEM/skills/withmeta/SKILL.md" "source survives refused re-import"

run "$INS" --from "$SRC/withmeta" --tier target-write --name ..
assert_exit 2 "$code" "rejects '..' as a name"

mkdir -p "$SRC/nofm"; printf '# no frontmatter here\n' > "$SRC/nofm/SKILL.md"
run "$INS" --from "$SRC/nofm" --tier target-write
assert_exit 1 "$code" "rejects a source without frontmatter"
set +e; [ -d "$MEM/skills/nofm" ]; e=$?; set -e
assert_exit 1 "$e" "half-installed target cleaned up on normalize failure"

# new-skill --force actually overwrites
run "$NEW" --name myrev --tier target-write --force
assert_exit 0 "$code" "new-skill --force overwrites"
assert_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "tier: target-write" "overwritten tier"

finish
