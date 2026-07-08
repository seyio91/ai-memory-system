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
run "$NEW" --name myrev --description "Review things."
assert_exit 0 "$code" "new-skill creates a skill"
assert_file "$MEM/skills/myrev/SKILL.md" "SKILL.md written"
assert_not_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "tier:" "no tier in frontmatter"
assert_contains "$out" "validated: myrev OK" "scaffold passes validate-skills"
assert_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "Brief a skilled colleague" "template body guidance"

# scaffold is genuinely valid per the store validator
run "$SCRIPTS_DIR/validate-skills.sh"
assert_exit 0 "$code" "store with scaffolded skill validates clean"

# workflow skill gets the self-rating block
run "$NEW" --name mygen --kind workflow
assert_exit 0 "$code" "new-skill creates a workflow skill"
assert_contains "$(cat "$MEM/skills/mygen/SKILL.md")" "kind: workflow" "optional kind written"
assert_contains "$(cat "$MEM/skills/mygen/SKILL.md")" "partial:self-rating START" "workflow skill gets self-rating block"
# a non-workflow (reference/default) skill does NOT get the self-rating block
assert_not_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "partial:self-rating START" "non-workflow skill has no self-rating block"

# guards
run "$NEW" --name myrev --description "dup"
assert_exit 1 "$code" "refuses to overwrite without --force"
run "$NEW" --name myloc --local
assert_exit 2 "$code" "new-skill rejects retired --local"
assert_contains "$out" "unknown arg: --local" "new-skill --local refusal is explicit"
run "$NEW" --name "../evil"
assert_exit 2 "$code" "rejects bad name"

# === installer =============================================================
# source A: has a metadata block (preserved verbatim on intake)
mkdir -p "$SRC/withmeta"
cat > "$SRC/withmeta/SKILL.md" <<'EOF'
---
name: withmeta
description: imported, has a metadata block.
metadata:
  domain: platform
---
# withmeta
body.
EOF
run "$INS" --from "$SRC/withmeta"
assert_exit 0 "$code" "install seeds an authored skill from a dir"
assert_contains "$(cat "$MEM/skills/withmeta/SKILL.md")" "domain: platform" "existing metadata preserved"
assert_not_contains "$(cat "$MEM/skills/withmeta/SKILL.md")" "tier:" "no tier injected on intake"
assert_contains "$out" "validated: withmeta OK" "installed skill validates"
# does NOT inject self-rating into imported skills
assert_not_contains "$(cat "$MEM/skills/withmeta/SKILL.md")" "self-rating" "no self-rating injected on intake"

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
run "$INS" --from "$SRC/nometa"
assert_exit 0 "$code" "install seeds a skill with no metadata block"
assert_file "$MEM/skills/nometa/references/notes.md" "references/ preserved on intake"
# name derived from frontmatter when --name omitted
assert_file "$MEM/skills/nometa/SKILL.md" "name derived from frontmatter"

# single SKILL.md (file, not dir) as --from
run "$INS" --from "$SRC/nometa/SKILL.md" --name singlefile
assert_exit 0 "$code" "single SKILL.md (file) install works"
assert_file "$MEM/skills/singlefile/SKILL.md" "single-file install placed"

# guards
run "$INS"
assert_exit 2 "$code" "install requires --from or --remote"
run "$INS" --from "$SRC/withmeta" --local
assert_exit 2 "$code" "install rejects retired --local"
assert_contains "$out" "unknown arg: --local" "install --local refusal is explicit"
run "$INS" --from "$SRC/missing"
assert_exit 2 "$code" "install rejects missing --from"
run "$INS" --from "$SRC/withmeta"
assert_exit 1 "$code" "install refuses existing target without --force"

# in-place re-import (source == target)
run "$INS" --from "$MEM/skills/withmeta" --force
assert_exit 2 "$code" "refuses in-place re-import (source == target)"
assert_file "$MEM/skills/withmeta/SKILL.md" "source survives refused re-import"

run "$INS" --from "$SRC/withmeta" --name ..
assert_exit 2 "$code" "rejects '..' as a name"

# a source without frontmatter is copied but fails validation -> exit 1
mkdir -p "$SRC/nofm"; printf '# no frontmatter here\n' > "$SRC/nofm/SKILL.md"
run "$INS" --from "$SRC/nofm"
assert_exit 1 "$code" "rejects a source without frontmatter"

# new-skill --force actually overwrites
run "$NEW" --name myrev --force --description "fresh"
assert_exit 0 "$code" "new-skill --force overwrites"
assert_contains "$(cat "$MEM/skills/myrev/SKILL.md")" "fresh" "overwritten description"

finish
