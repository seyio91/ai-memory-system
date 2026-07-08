#!/usr/bin/env bash
# Phase 4: install-skill --remote (manifest write-back + resolve) + list-skills.
# Uses a local file:// git repo as the "remote", so it runs fully offline.
. "$(dirname "$0")/_assert.sh"

INS="$SCRIPTS_DIR/install-skill.sh"
LS="$SCRIPTS_DIR/list-skills.sh"
command -v git >/dev/null 2>&1 || { printf 'SKIP: git unavailable\n'; finish; }
python3 -c 'import tomllib' >/dev/null 2>&1 || { printf 'SKIP: need python3.11+ (tomllib)\n'; finish; }

MEM="$(new_sandbox)"; REPO="$(new_sandbox)"
trap 'rm -rf "$MEM" "$REPO"' EXIT
export MEMORY_DIR="$MEM"
mkdir -p "$MEM/skills" "$MEM/skills-local"

run() { set +e; out=$(bash "$@" 2>&1); code=$?; set -e; }

# remote repo with a skill at a subpath
mkdir -p "$REPO/packs/widget"
printf -- '---\nname: widget\ndescription: remote widget skill.\nmetadata:\n  tier: target-read-only\n---\n# widget\n' > "$REPO/packs/widget/SKILL.md"
git -C "$REPO" init -q; git -C "$REPO" config user.email t@t.co; git -C "$REPO" config user.name t
git -C "$REPO" add -A; git -C "$REPO" commit -qm init
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"

ROOT_MF="$MEM/skills.toml"

# === install-skill --remote: write-back + resolve =============================
run "$INS" --remote "file://$REPO" --ref "$BRANCH" --path packs/widget
assert_exit 0 "$code" "install --remote resolves + saves (exit 0)"
assert_contains "$out" "saved: widget ->" "wrote a root manifest entry"
assert_contains "$out" "installed (remote): widget" "reports remote install"
assert_file "$ROOT_MF" "root manifest created"
assert_contains "$(cat "$ROOT_MF")" 'name = "widget"' "manifest entry has the name"
assert_contains "$(cat "$ROOT_MF")" 'path = "packs/widget"' "manifest entry has the path"
assert_file "$MEM/.skill-cache/widget/SKILL.md" "skill materialized into the cache"

# name derived from path when --name omitted (already 'widget'); explicit --name honored.
# --local is ignored for remote manifest routing; remote declarations have one root file.
run "$INS" --remote "file://$REPO" --ref "$BRANCH" --path packs/widget --name aliased --local
assert_exit 0 "$code" "install --remote --local --name resolves"
assert_contains "$out" "saved: aliased ->" "wrote a root manifest entry under --name"
assert_contains "$(cat "$ROOT_MF")" 'name = "aliased"' "aliased entry lives in root manifest"
assert_file "$MEM/.skill-cache/aliased/SKILL.md" "aliased skill in cache"

# === duplicate guard ==========================================================
run "$INS" --remote "file://$REPO" --ref "$BRANCH" --path packs/widget
assert_exit 1 "$code" "duplicate name refused (exit 1)"
assert_contains "$out" "already in" "duplicate guard names the conflict"
# manifest untouched by the refused install
n_before="$(grep -c '^\[\[skills\]\]' "$ROOT_MF")"
run "$INS" --remote "file://$REPO" --ref "$BRANCH" --path packs/widget
n_after="$(grep -c '^\[\[skills\]\]' "$ROOT_MF")"
assert_eq "$n_before" "$n_after" "refused duplicate did not append to the manifest"
# --force appends anyway (explicit override)
run "$INS" --remote "file://$REPO" --ref "$BRANCH" --path packs/widget --force
assert_exit 0 "$code" "--force appends a duplicate (exit 0)"
n_forced="$(grep -c '^\[\[skills\]\]' "$ROOT_MF")"
assert_eq "$((n_before + 1))" "$n_forced" "--force added one [[skills]] entry"

# === guards ===================================================================
run "$INS" --remote "file://$REPO" --path packs/widget --name noref
assert_exit 2 "$code" "--remote without --ref -> exit 2"
assert_contains "$out" "ref required" "flags the missing ref"

run "$INS" --from "$REPO/packs/widget" --remote "file://$REPO" --ref "$BRANCH"
assert_exit 2 "$code" "--from + --remote are mutually exclusive"

run "$INS" --remote "file://$REPO" --ref "$BRANCH" --path "../escape" --name x
assert_exit 2 "$code" "--path with .. rejected"

# --no-save declares nothing (no manifest write, nothing resolved)
cp "$ROOT_MF" "$MEM/root.before"
run "$INS" --remote "file://$REPO" --ref "$BRANCH" --path packs/widget --name skipme --no-save
assert_exit 0 "$code" "--no-save exits 0"
assert_eq "$(cat "$MEM/root.before")" "$(cat "$ROOT_MF")" "--no-save left the manifest untouched"
set +e; [ -e "$MEM/.skill-cache/skipme" ]; e=$?; set -e
assert_exit 1 "$e" "--no-save resolved nothing"

# === list-skills: unified provenance ==========================================
# add authored skills in both scopes alongside the resolved remotes
mkdir -p "$MEM/skills/auth-gen" "$MEM/skills-local/auth-loc"
printf -- '---\nname: auth-gen\nmetadata:\n  tier: target-write\n---\n# g\n' > "$MEM/skills/auth-gen/SKILL.md"
printf -- '---\nname: auth-loc\nmetadata:\n  tier: target-write\n---\n# l\n' > "$MEM/skills-local/auth-loc/SKILL.md"

run "$LS"
assert_exit 0 "$code" "list-skills runs"
gen_row="$(printf '%s\n' "$out" | awk '$1=="auth-gen"')"
assert_contains "$gen_row" "generic" "authored generic tagged generic"
assert_contains "$gen_row" "authored" "authored generic tagged authored"
assert_contains "$gen_row" "yes" "generic is synced=yes"
loc_row="$(printf '%s\n' "$out" | awk '$1=="auth-loc"')"
assert_contains "$loc_row" "local" "authored local tagged local"
assert_contains "$loc_row" "no" "local is synced=no"
rem_row="$(printf '%s\n' "$out" | awk '$1=="widget"')"
assert_contains "$rem_row" "remote" "cached skill tagged remote"
assert_contains "$rem_row" "instance" "widget's scope derived from the root manifest"
alias_row="$(printf '%s\n' "$out" | awk '$1=="aliased"')"
assert_contains "$alias_row" "instance" "aliased's scope derived from the root manifest"

# filters
run "$LS" --remote
assert_contains "$out" "widget" "--remote includes the remote skill"
assert_not_contains "$out" "auth-gen" "--remote excludes authored skills"
run "$LS" --local
assert_contains "$out" "auth-loc" "--local includes a local authored skill"
assert_not_contains "$out" "auth-gen" "--local excludes generic skills"

finish
