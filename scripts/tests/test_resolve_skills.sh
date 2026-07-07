#!/usr/bin/env bash
# resolve-skills.sh — remote-skill manifest -> gitignored .skill-cache/ resolver.
# Uses a local file:// git repo as the "remote", so it runs fully offline.
. "$(dirname "$0")/_assert.sh"

RS="$SCRIPTS_DIR/resolve-skills.sh"
command -v git >/dev/null 2>&1 || { printf 'SKIP: git unavailable\n'; finish; }
command -v python3 >/dev/null 2>&1 || command -v jq >/dev/null 2>&1 || { printf 'SKIP: need python3 or jq\n'; finish; }

MEM="$(new_sandbox)"; REPO="$(new_sandbox)"
trap 'rm -rf "$MEM" "$REPO"' EXIT
export MEMORY_DIR="$MEM"
mkdir -p "$MEM/skills" "$MEM/skills-local"

run() { set +e; out=$(bash "$@" 2>&1); code=$?; set -e; }
gen_manifest() { cat > "$MEM/skills/skills.json"; }
loc_manifest() { cat > "$MEM/skills-local/skills.json"; }

# --- build a "remote" git repo: skill at a subpath + one at the repo root -----
mkdir -p "$REPO/pkg/remote-sub"
printf -- '---\nname: remote-sub\ndescription: remote skill at a subpath.\nmetadata:\n  tier: target-read-only\n---\n# remote-sub\n' > "$REPO/pkg/remote-sub/SKILL.md"
printf -- '---\nname: remote-root\ndescription: skill at repo root (no path).\nmetadata:\n  tier: target-write\n---\n# remote-root\n' > "$REPO/SKILL.md"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.co; git -C "$REPO" config user.name t
git -C "$REPO" add -A; git -C "$REPO" commit -qm init
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

# --- no manifests -> nothing to do (exit 0) -----------------------------------
run "$RS"
assert_exit 0 "$code" "no manifests -> exit 0"
assert_contains "$out" "no remote skills declared" "reports nothing declared"

# --- resolve a subpath skill from the tracked (generic) manifest --------------
gen_manifest <<EOF
{ "skills": [ { "name": "remote-sub", "url": "file://$REPO", "ref": "$BRANCH", "path": "pkg/remote-sub" } ] }
EOF
run "$RS"
assert_exit 0 "$code" "resolve generic subpath skill -> exit 0"
assert_file "$MEM/.skill-cache/remote-sub/SKILL.md" "subpath skill materialized into cache"
set +e; [ -e "$MEM/.skill-cache/remote-sub/.git" ]; e=$?; set -e
assert_exit 1 "$e" "cache copy carries no nested .git"
assert_contains "$(cat "$MEM/.skill-cache/skills.lock")" "$HEAD_SHA" "lockfile pins the resolved sha"

# it enumerates as a skill (list_skill_dirs third root)
. "$SCRIPTS_DIR/_lib.sh"
assert_contains "$(list_skill_dirs)" "$MEM/.skill-cache/remote-sub" "cached remote skill enumerated"
run "$SCRIPTS_DIR/validate-skills.sh"
assert_exit 0 "$code" "cached remote skill validates clean"

# --- cache hit: a plain re-resolve needs no network ---------------------------
# Move the repo away so any fetch would fail; the lockfile+cache must still satisfy.
mv "$REPO" "$REPO.hidden"
run "$RS"
assert_exit 0 "$code" "re-resolve is a cache hit (offline) -> exit 0"
assert_contains "$out" "cached" "reports cache hit, no fetch"
mv "$REPO.hidden" "$REPO"

# --- --update re-fetches (repo present again) ---------------------------------
run "$RS" --update
assert_exit 0 "$code" "--update re-resolves -> exit 0"
assert_contains "$out" "resolved" "--update actually fetches"

# --- local manifest: skill at repo root (no path) -----------------------------
loc_manifest <<EOF
{ "skills": [ { "name": "remote-root", "url": "file://$REPO", "ref": "$BRANCH" } ] }
EOF
run "$RS"
assert_exit 0 "$code" "resolve local root skill -> exit 0"
assert_file "$MEM/.skill-cache/remote-root/SKILL.md" "root skill materialized"

# --list shows both, with scope + resolved sha
run "$RS" --list
assert_contains "$out" "remote-sub" "--list shows generic remote"
assert_contains "$out" "remote-root" "--list shows local remote"
assert_contains "$out" "generic" "--list tags scope generic"
assert_contains "$out" "local" "--list tags scope local"

# --- hard-fail: bad ref is a fetch error (exit 1), strict --------------------
loc_manifest <<EOF
{ "skills": [ { "name": "remote-root", "url": "file://$REPO", "ref": "no-such-ref" } ] }
EOF
run "$RS" --update
assert_exit 1 "$code" "bad ref hard-fails -> exit 1"
assert_contains "$out" "no-such-ref" "error names the unresolvable ref"

# --- validation: SKILL.md missing at the declared path -> exit 1 --------------
loc_manifest <<EOF
{ "skills": [ { "name": "remote-root", "url": "file://$REPO", "ref": "$BRANCH", "path": "pkg/does-not-exist" } ] }
EOF
run "$RS" --update
assert_exit 1 "$code" "missing SKILL.md at path -> exit 1"
assert_contains "$out" "no SKILL.md" "names the missing SKILL.md"

# --- guards: missing url / ref are rejected -----------------------------------
loc_manifest <<'EOF'
{ "skills": [ { "name": "noref", "url": "file:///x" } ] }
EOF
run "$RS"
assert_exit 1 "$code" "missing ref -> exit 1"
assert_contains "$out" "missing ref" "flags missing ref"

# --dry-run never fetches
rm -rf "$MEM/.skill-cache"
gen_manifest <<EOF
{ "skills": [ { "name": "remote-sub", "url": "file://$REPO", "ref": "$BRANCH", "path": "pkg/remote-sub" } ] }
EOF
loc_manifest <<'EOF'
{ "skills": [] }
EOF
run "$RS" --dry-run
assert_exit 0 "$code" "--dry-run exits 0"
assert_contains "$out" "would-fetch" "--dry-run reports intent"
set +e; [ -e "$MEM/.skill-cache/remote-sub" ]; e=$?; set -e
assert_exit 1 "$e" "--dry-run wrote nothing to the cache"

finish
