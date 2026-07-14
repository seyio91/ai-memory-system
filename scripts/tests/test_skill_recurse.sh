#!/usr/bin/env bash
# resolve-skills.sh recurse=true fixture coverage. Uses only local file:// repos.
. "$(dirname "$0")/_assert.sh"

RS="$SCRIPTS_DIR/resolve-skills.sh"
command -v git >/dev/null 2>&1 || { printf 'SKIP: git unavailable\n'; finish; }
python3 -c 'import tomllib' >/dev/null 2>&1 || { printf 'SKIP: need python3.11+ (tomllib)\n'; finish; }

TOP="$(new_sandbox)"
trap 'rm -rf "$TOP"' EXIT

run_rs() { set +e; out=$(bash "$RS" "$@" 2>&1); code=$?; set -e; }
manifest() { cat > "$MEM/skills.toml"; }

case_env() {
    MEM="$TOP/$1/mem"
    REPO="$TOP/$1/repo"
    export MEMORY_DIR="$MEM"
    export AI_MEMORY_SKILL_CACHE="$MEM/.skill-cache"
    mkdir -p "$MEM/skills" "$REPO"
}

write_skill() {
    local dir="$1" name="$2"
    mkdir -p "$dir"
    if [ -n "$name" ]; then
        printf -- '---\nname: %s\ndescription: fixture skill.\n---\n# %s\n' "$name" "$name" > "$dir/SKILL.md"
    else
        printf -- '---\ndescription: fixture skill.\n---\n# %s\n' "$(basename "$dir")" > "$dir/SKILL.md"
    fi
}

commit_repo() {
    local msg="$1"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@t.co
    git -C "$REPO" config user.name t
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "$msg"
    BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
}

cache_names() {
    [ -d "$MEM/.skill-cache" ] || return 0
    find "$MEM/.skill-cache" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

lock_names() {
    [ -f "$MEM/.skill-cache/skills.lock" ] || return 0
    awk -F '\t' '/^#/{next} {print $1}' "$MEM/.skill-cache/skills.lock" | sort
}

# --- unresolved --list keeps a recurse row visible without fetching -----------
case_env unresolved
write_skill "$REPO/skills/only" ""
commit_repo init
manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true
EOF
run_rs --list
assert_exit 0 "$code" "--list before recurse resolve exits 0"
assert_contains "$out" "unresolved - run resolve-skills" "--list unresolved recurse row is informational"

# --- (a/e) N-from-1 + nested SKILL.md prune + frontmatter name + prefix --------
case_env nfrom1
write_skill "$REPO/skills/core/alpha" ""
write_skill "$REPO/skills/core/alpha/references" "nested-ignored"
write_skill "$REPO/skills/core/renamed-dir" "front-name"
write_skill "$REPO/skills/ops/keep" ""
commit_repo init
manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true
prefix  = "p-"
EOF
run_rs
assert_exit 0 "$code" "recurse N-from-1 exits 0"
assert_eq "$(printf 'p-alpha\np-front-name\np-keep')" "$(cache_names)" "recurse materializes exactly expected children"
assert_file "$MEM/.skill-cache/p-alpha/SKILL.md" "basename fallback child materialized"
assert_file "$MEM/.skill-cache/p-front-name/SKILL.md" "frontmatter-name child materialized"
assert_not_contains "$(cache_names)" "p-renamed-dir" "frontmatter name beats basename"
assert_not_contains "$(cache_names)" "p-nested-ignored" "nested references/SKILL.md is not materialized as a skill"
assert_file "$MEM/.skill-cache/p-alpha/references/SKILL.md" "nested references/SKILL.md still copied inside its parent skill"

run_rs --list
assert_exit 0 "$code" "--list after recurse resolve exits 0"
assert_contains "$out" "p-alpha" "--list shows expanded recurse child"
assert_contains "$out" "p-front-name" "--list shows frontmatter-named recurse child"
assert_not_contains "$out" "[recurse]" "--list does not show bare recurse placeholder after resolve"

# --- (b) offline replay from lock/cache, no network ---------------------------
before="$(cache_names)"
mv "$REPO" "$REPO.gone"
run_rs
assert_exit 0 "$code" "plain recurse resolve replays offline cache"
assert_contains "$out" "cached" "offline replay reports cached children"
assert_eq "$before" "$(cache_names)" "offline replay leaves cache set unchanged"
mv "$REPO.gone" "$REPO"

# --- (c) collision between two recurse origins, then prefix escape hatch -------
case_env collision
write_skill "$REPO/skills/a" "dup"
write_skill "$REPO/other/b" "dup"
commit_repo init
manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true

[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "other"
recurse = true
EOF
run_rs
assert_exit 1 "$code" "duplicate recurse child names fail"
assert_contains "$out" "file://$REPO#skills" "collision message names first recurse origin"
assert_contains "$out" "file://$REPO#other" "collision message names second recurse origin"

manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true

[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "other"
recurse = true
prefix  = "other-"
EOF
run_rs
assert_exit 0 "$code" "prefix resolves recurse collision"
assert_contains "$(cache_names)" "dup" "unprefixed colliding child remains"
assert_contains "$(cache_names)" "other-dup" "prefixed colliding child materialized"

# --- (c) authored collision variant ------------------------------------------
case_env authored
write_skill "$REPO/skills/remote" "localdup"
commit_repo init
write_skill "$MEM/skills/localdup" "localdup"
manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true
EOF
run_rs
assert_exit 1 "$code" "recurse child colliding with authored skill fails"
assert_contains "$out" "authored:$MEM/skills" "authored collision message names authored origin"
assert_contains "$out" "file://$REPO#skills" "authored collision message names recurse origin"

manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true
prefix  = "remote-"
EOF
run_rs
assert_exit 0 "$code" "prefix resolves authored collision"
assert_file "$MEM/.skill-cache/remote-localdup/SKILL.md" "prefixed authored-collision child materialized"

# --- (d) prune is update-only; dry-run previews without deleting --------------
case_env prune
write_skill "$REPO/skills/a" ""
write_skill "$REPO/skills/b" ""
commit_repo init
manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true
prefix  = "pr-"
EOF
run_rs
assert_exit 0 "$code" "prune fixture initial recurse resolve exits 0"
manifest <<'EOF'
EOF
run_rs
assert_exit 0 "$code" "plain resolve with source removed exits 0"
assert_contains "$(cache_names)" "pr-a" "plain resolve does not prune stale child"
run_rs --update --dry-run
assert_exit 0 "$code" "--update --dry-run with source removed exits 0"
assert_contains "$out" "would-prune pr-a" "dry-run previews stale recurse child prune"
assert_contains "$(cache_names)" "pr-a" "dry-run does not delete stale cache dir"
run_rs --update
assert_exit 0 "$code" "--update with source removed exits 0"
assert_eq "" "$(cache_names)" "--update prunes stale recurse cache dirs"
assert_eq "" "$(lock_names)" "--update prunes stale recurse lock rows"

# --- (f) exclude globs omit matching skills from cache and lock ---------------
case_env exclude
write_skill "$REPO/skills/keep" ""
write_skill "$REPO/skills/drop-me" ""
commit_repo init
manifest <<EOF
[[skills]]
url     = "file://$REPO"
ref     = "$BRANCH"
path    = "skills"
recurse = true
exclude = ["drop*"]
EOF
run_rs
assert_exit 0 "$code" "exclude recurse resolve exits 0"
assert_contains "$(cache_names)" "keep" "exclude keeps non-matching child in cache"
assert_not_contains "$(cache_names)" "drop-me" "exclude omits matching child from cache"
assert_contains "$(lock_names)" "keep" "exclude keeps non-matching child in lock"
assert_not_contains "$(lock_names)" "drop-me" "exclude omits matching child from lock"

finish
