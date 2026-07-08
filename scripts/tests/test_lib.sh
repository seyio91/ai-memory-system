#!/usr/bin/env bash
# _lib.sh: detect_active_project (pin / fallback / none) + extract_fm_field.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"

. "$SCRIPTS_DIR/_lib.sh"

# --- extract_fm_field ---
mkdir -p "$MEM/domain"
cat > "$MEM/d.md" <<'EOF'
---
topic: terraform
triggers: [tf, hcl]
summary: A one line summary
---
body
EOF
assert_eq "terraform" "$(extract_fm_field "$MEM/d.md" topic)" "extract_fm_field topic"
assert_eq "A one line summary" "$(extract_fm_field "$MEM/d.md" summary)" "extract_fm_field summary"
assert_eq "" "$(extract_fm_field "$MEM/d.md" nope)" "extract_fm_field missing -> empty"

printf 'no frontmatter here\n' > "$MEM/plain.md"
assert_eq "" "$(extract_fm_field "$MEM/plain.md" topic)" "extract_fm_field no-fm -> empty"

# --- detect_active_project: .active_project global is NOT a fallback ---
printf 'stale-global\n' > "$MEM/.active_project"
assert_eq "" "$(detect_active_project "$MEM/projects")" "global .active_project ignored (no fallback)"

# --- detect_active_project: neutral .agents marker resolved by walking up ---
REPO="$MEM/repo/sub"
mkdir -p "$REPO/.git" "$MEM/repo/.agents"
printf 'pinned-proj\n' > "$MEM/repo/.agents/memory-project"
assert_eq "pinned-proj" "$(detect_active_project "$REPO")" "neutral marker resolved (walks up)"

# --- legacy .claude marker still resolves (back-compat fallback) ---
LEG="$(new_sandbox)"; mkdir -p "$LEG/deep/.git" "$LEG/.claude"
printf 'legacy-proj\n' > "$LEG/.claude/memory-project"
assert_eq "legacy-proj" "$(detect_active_project "$LEG/deep")" "legacy .claude marker resolves (fallback)"
# --- when both exist at the same level, the neutral marker wins ---
mkdir -p "$LEG/.agents"; printf 'neutral-proj\n' > "$LEG/.agents/memory-project"
assert_eq "neutral-proj" "$(detect_active_project "$LEG/deep")" "neutral marker wins over legacy"
rm -rf "$LEG"

# --- detect_active_project: none ---
rm -f "$MEM/.active_project"
EMPTY="$(new_sandbox)"
assert_eq "" "$(detect_active_project "$EMPTY")" "no marker -> empty"
rm -rf "$EMPTY"

# --- projects_root: default + env override ---
unset AI_MEMORY_PROJECTS_ROOT
assert_eq "$HOME/Projects" "$(projects_root)" "projects_root default"
export AI_MEMORY_PROJECTS_ROOT="/tmp/some-root"
assert_eq "/tmp/some-root" "$(projects_root)" "projects_root env override"

# --- resolve_repo_path: primary hit (relative repo_path) ---
ROOT="$(new_sandbox)"
export AI_MEMORY_PROJECTS_ROOT="$ROOT"
mkdir -p "$ROOT/myrepo"
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: s
repo_path: myrepo
---
# body
EOF
out=$(resolve_repo_path proj); code=$?
assert_exit 0 "$code" "resolve_repo_path primary hit returns 0"
assert_eq "$ROOT/myrepo" "$out" "resolve_repo_path primary hit -> root/repo_path"

# --- resolve_repo_path: absolute repo_path ---
ABS="$(new_sandbox)"
mkdir -p "$MEM/projects/absproj"
cat > "$MEM/projects/absproj/memory.md" <<EOF
---
topic: absproj
scope: project
summary: s
repo_path: $ABS
---
EOF
assert_eq "$ABS" "$(resolve_repo_path absproj)" "resolve_repo_path absolute repo_path"
rm -rf "$ABS"

# --- resolve_repo_path: $MEMORY_DIR sentinel (self-referential meta-project) ---
mkdir -p "$MEM/projects/metaproj"
cat > "$MEM/projects/metaproj/memory.md" <<'EOF'
---
topic: metaproj
scope: project
summary: s
repo_path: $MEMORY_DIR
---
EOF
assert_eq "$MEM" "$(resolve_repo_path metaproj)" "resolve_repo_path \$MEMORY_DIR -> memory tree"

mkdir -p "$MEM/projects/metasub"
cat > "$MEM/projects/metasub/memory.md" <<'EOF'
---
topic: metasub
scope: project
summary: s
repo_path: $MEMORY_DIR/projects
---
EOF
assert_eq "$MEM/projects" "$(resolve_repo_path metasub)" "resolve_repo_path \$MEMORY_DIR/subpath"

# --- resolve_repo_path: git-remote fallback when repo_path dir is gone ---
URL="git@github.com:org/sibling.git"
SIB="$ROOT/sibling-checkout"
mkdir -p "$SIB"
( cd "$SIB" && git init -q && git remote add origin "$URL" )
mkdir -p "$MEM/projects/fbproj"
cat > "$MEM/projects/fbproj/memory.md" <<EOF
---
topic: fbproj
scope: project
summary: s
repo: $URL
repo_path: does-not-exist-here
---
EOF
out=$(resolve_repo_path fbproj); code=$?
assert_exit 0 "$code" "resolve_repo_path remote fallback returns 0"
assert_eq "$SIB" "$out" "resolve_repo_path remote fallback -> matching sibling"

# --- resolve_repo_path: miss -> empty + exit 1 ---
mkdir -p "$MEM/projects/missproj"
cat > "$MEM/projects/missproj/memory.md" <<'EOF'
---
topic: missproj
scope: project
summary: s
---
EOF
out=$(resolve_repo_path missproj); code=$?
assert_exit 1 "$code" "resolve_repo_path miss returns 1"
assert_eq "" "$out" "resolve_repo_path miss -> empty"
rm -rf "$ROOT"

# --- MEMORY_DIR self-locating default (no MEMORY_DIR set) ---
# With MEMORY_DIR unset, sourcing scripts/_lib.sh must resolve MEMORY_DIR to the
# memory root (parent of scripts/) via BASH_SOURCE. Copy _lib.sh into a sandbox
# scripts/ dir with no config.local.sh, so the test exercises the bare
# ${MEMORY_DIR:-$(...)} default and is NOT overridden by the installed tree's
# stamped MEMORY_DIR (install.sh writes one to the real config.local.sh).
# Runs under bash, where BASH_SOURCE is populated (it is empty under zsh).
SBLIB="$(new_sandbox)"
mkdir -p "$SBLIB/scripts"
cp "$SCRIPTS_DIR/_lib.sh" "$SBLIB/scripts/_lib.sh"
EXPECTED_ROOT="$(cd "$SBLIB" && pwd)"
got=$( unset MEMORY_DIR; . "$SBLIB/scripts/_lib.sh"; printf '%s' "$MEMORY_DIR" )
assert_eq "$EXPECTED_ROOT" "$got" "MEMORY_DIR default self-locates to memory root"
rm -rf "$SBLIB"

# --- skill_roots / list_skill_dirs ---
SK="$(new_sandbox)"
export MEMORY_DIR="$SK"
unset AI_MEMORY_SKILL_ROOTS
# generic store: one valid skill + one dir missing SKILL.md (a non-skill)
mkdir -p "$SK/skills/gen-a" "$SK/skills/nomd"
printf -- '---\nname: gen-a\n---\n' > "$SK/skills/gen-a/SKILL.md"
# local store: one valid skill
mkdir -p "$SK/skills-local/loc-a"
printf -- '---\nname: loc-a\n---\n' > "$SK/skills-local/loc-a/SKILL.md"

assert_eq "$SK/skills
$SK/skills-local
$SK/.skill-cache" "$(skill_roots)" "skill_roots default = generic + local + remote cache"
assert_eq "$SK/.skill-cache" "$(skill_cache_dir)" "skill_cache_dir default"
assert_eq "$SK/skills.toml" "$(skill_manifest)" "skill_manifest default -> root skills.toml"
assert_eq "$SK/skills.toml" "$(skill_manifest local)" "skill_manifest ignores legacy scope arg"
assert_eq "$SK/skills.toml.example" "$(skill_manifest_template)" "skill_manifest_template -> root catalog template"

dirs="$(list_skill_dirs)"
assert_contains "$dirs" "$SK/skills/gen-a" "list_skill_dirs yields generic skill"
assert_contains "$dirs" "$SK/skills-local/loc-a" "list_skill_dirs yields local skill (second root)"
assert_not_contains "$dirs" "nomd" "list_skill_dirs skips dir without SKILL.md"

# a materialized remote skill in .skill-cache/ is enumerated as a third root
mkdir -p "$SK/.skill-cache/rem-a"
printf -- '---\nname: rem-a\n---\n' > "$SK/.skill-cache/rem-a/SKILL.md"
assert_contains "$(list_skill_dirs)" "$SK/.skill-cache/rem-a" "list_skill_dirs yields cached remote skill"
assert_eq "$SK/.skill-cache/rem-a" "$(resolve_skill_dir rem-a)" "resolve_skill_dir -> cached remote dir"

# AI_MEMORY_SKILL_ROOTS override pins the roots
export AI_MEMORY_SKILL_ROOTS="$SK/skills"
assert_eq "$SK/skills" "$(skill_roots)" "AI_MEMORY_SKILL_ROOTS override -> single root"
assert_not_contains "$(list_skill_dirs)" "loc-a" "override excludes the local root"
unset AI_MEMORY_SKILL_ROOTS

# --- resolve_skill_dir: finds a skill in either root, fails on unknown ---
assert_eq "$SK/skills/gen-a" "$(resolve_skill_dir gen-a)" "resolve_skill_dir -> generic dir"
assert_eq "$SK/skills-local/loc-a" "$(resolve_skill_dir loc-a)" "resolve_skill_dir -> local dir"
out=$(resolve_skill_dir nope); code=$?
assert_exit 1 "$code" "resolve_skill_dir unknown -> exit 1"
assert_eq "" "$out" "resolve_skill_dir unknown -> empty"

# --- skills_with_partial: scans all roots by default ---
printf '\n<!-- partial:self-rating START x -->\n<!-- partial:self-rating END -->\n' >> "$SK/skills/gen-a/SKILL.md"
printf '\n<!-- partial:self-rating START x -->\n<!-- partial:self-rating END -->\n' >> "$SK/skills-local/loc-a/SKILL.md"
carriers="$(skills_with_partial self-rating)"
assert_contains "$carriers" "gen-a" "skills_with_partial (no dir) finds generic carrier"
assert_contains "$carriers" "loc-a" "skills_with_partial (no dir) finds local carrier"
# explicit-dir form still scans just that dir (back-compat)
assert_not_contains "$(skills_with_partial self-rating "$SK/skills")" "loc-a" "explicit dir scopes to that root"
rm -rf "$SK"

finish
