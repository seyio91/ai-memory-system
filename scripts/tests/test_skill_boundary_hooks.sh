#!/usr/bin/env bash
# skill boundary hooks: PostToolUse marker (arms read-only skills) + Stop check.
. "$(dirname "$0")/_assert.sh"

REPO_HOOKS="$(cd "$SCRIPTS_DIR/../harnesses/claude/hooks" && pwd)"
MARKER="$REPO_HOOKS/skill_boundary_marker.sh"
STOP="$REPO_HOOKS/skill_boundary_check.sh"

command -v python3 >/dev/null 2>&1 || { printf 'SKIP: python3 unavailable\n'; finish; }

git_q() { git -C "$1" -c user.email=t@t -c user.name=t -c init.defaultBranch=main "${@:2}"; }

MEM="$(new_sandbox)"; trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"

# sandbox memory tree: the real boundary-check engine + a read-only & a write skill.
# _lib.sh is copied too so the hooks' skill_dir_for resolves across all skill roots.
mkdir -p "$MEM/scripts" "$MEM/skills/ro-skill" "$MEM/skills/wr-skill" "$MEM/skills/other" \
    "$MEM/.skill-cache/ro-remote" "$MEM/projects/p"
cp "$SCRIPTS_DIR/skill-boundary-check.sh" "$MEM/scripts/"; chmod +x "$MEM/scripts/skill-boundary-check.sh"
cp "$SCRIPTS_DIR/_lib.sh" "$MEM/scripts/"
printf -- '---\nname: ro-skill\ndescription: r.\nmetadata:\n  tier: target-read-only\n---\n# ro\n' > "$MEM/skills/ro-skill/SKILL.md"
printf -- '---\nname: wr-skill\ndescription: w.\nmetadata:\n  tier: target-write\n---\n# wr\n' > "$MEM/skills/wr-skill/SKILL.md"
# a cached remote read-only skill — its tier must be read + armed too
printf -- '---\nname: ro-remote\ndescription: rr.\nmetadata:\n  tier: target-read-only\n---\n# rr\n' > "$MEM/.skill-cache/ro-remote/SKILL.md"
touch "$MEM/skills/other/.gitkeep" "$MEM/projects/p/.gitkeep"
printf '.sessions/\n' > "$MEM/.gitignore"   # model production: baselines live in gitignored .sessions/
git_q "$MEM" init -q; git_q "$MEM" add -A >/dev/null 2>&1; git_q "$MEM" commit -q -m init >/dev/null 2>&1

arm() { printf '{"session_id":"%s","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$1" "$2" | bash "$MARKER"; }
stop() { printf '{"session_id":"%s"}' "$1" | bash "$STOP" 2>"$MEM/.stoperr"; }

SDIR="$MEM/.sessions/skill-boundary"

# --- marker: read-only skill is armed ---------------------------------------
arm S1 ro-skill
assert_file "$SDIR/S1/ro-skill.marker" "read-only skill armed (marker written)"
assert_file "$SDIR/S1/ro-skill.mem-base" "memory baseline captured"

# --- marker: write skill is NOT armed ---------------------------------------
arm S2 wr-skill
set +e; [ -e "$SDIR/S2/wr-skill.marker" ]; e=$?; set -e
assert_exit 1 "$e" "target-write skill not armed"

# --- marker: a cached remote read-only skill is armed (multi-root) -----------
# Regression guard: the marker used to read tier only from skills/<name>/SKILL.md,
# so remote skills were silently never armed (their tier ignored).
arm SR ro-remote
assert_file "$SDIR/SR/ro-remote.marker" "remote read-only skill armed (tier read across roots)"
assert_file "$SDIR/SR/ro-remote.mem-base" "remote skill baseline captured"

# --- marker: non-Skill tool is a no-op --------------------------------------
printf '{"session_id":"S3","tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$MARKER"
set +e; [ -d "$SDIR/S3" ]; e=$?; set -e
assert_exit 1 "$e" "non-Skill tool does not arm anything"

# --- Stop: clean session passes, marker cleared -----------------------------
set +e; stop S1; code=$?; set -e
assert_exit 0 "$code" "clean read-only run passes"
set +e; [ -e "$SDIR/S1/ro-skill.marker" ]; e=$?; set -e
assert_exit 1 "$e" "marker cleared after Stop"

# --- Stop: write into another skill's folder is a violation -----------------
arm S4 ro-skill
printf 'leak\n' > "$MEM/skills/other/leak.md"      # ro-skill wrote another skill's dir
set +e; stop S4; code=$?; set -e
assert_exit 2 "$code" "other-skill write fails the Stop check (exit 2)"
assert_contains "$(cat "$MEM/.stoperr")" "another skill's folder: skills/other/leak.md" "violation names the path"
rm -f "$MEM/skills/other/leak.md"

# --- Stop: orchestrator's own memory edit is allowed (others-only scope) -----
arm S5 ro-skill
printf 'note\n' >> "$MEM/projects/p/memory.md"     # legitimate orchestrator co-edit
set +e; stop S5; code=$?; set -e
assert_exit 0 "$code" "projects/ co-edit allowed under others-only scope"
git_q "$MEM" checkout -- projects/p/memory.md 2>/dev/null || true

# --- Stop: registered target modified by a read-only skill is a violation ----
TGT="$(new_sandbox)"
git_q "$TGT" init -q; mkdir -p "$TGT/src"; printf 'orig\n' > "$TGT/src/a.txt"
git_q "$TGT" add -A >/dev/null 2>&1; git_q "$TGT" commit -q -m init >/dev/null 2>&1
arm S6 ro-skill
# skill registers its resolved target + baseline (the documented convention)
bash "$MEM/scripts/skill-boundary-check.sh" snapshot --repo "$TGT" > "$MEM/skills/ro-skill/.tbase"
printf '%s\n%s\n' "$TGT" "$MEM/skills/ro-skill/.tbase" > "$MEM/skills/ro-skill/.boundary-target"
printf 'tampered\n' >> "$TGT/src/a.txt"
set +e; stop S6; code=$?; set -e
assert_exit 2 "$code" "read-only skill modifying a registered target fails"
assert_contains "$(cat "$MEM/.stoperr")" "modified the target repo: src/a.txt" "names the target path"
rm -rf "$TGT"
rm -f "$MEM/skills/ro-skill/.boundary-target" "$MEM/skills/ro-skill/.tbase"

# --- marker: path-traversal / odd skill name is rejected --------------------
printf '{"session_id":"S7","tool_name":"Skill","tool_input":{"skill":"../evil"}}' | bash "$MARKER"
set +e; [ -d "$SDIR/S7" ]; e=$?; set -e
assert_exit 1 "$e" "traversal skill name is not armed"

# --- marker: non-executable engine still arms (bash fallback), never 0-byte --
chmod -x "$MEM/scripts/skill-boundary-check.sh"
arm S9 ro-skill
assert_file "$SDIR/S9/ro-skill.marker" "armed even when engine lacks +x (bash fallback)"
set +e; [ -s "$SDIR/S9/ro-skill.mem-base" ]; e=$?; set -e
assert_exit 0 "$e" "baseline is non-empty via the bash fallback"
chmod +x "$MEM/scripts/skill-boundary-check.sh"
stop S9 >/dev/null 2>&1 || true   # drain the marker

# --- Stop: a 0-byte baseline is dropped, not treated as a violation ---------
mkdir -p "$SDIR/S8"
printf 'ro-skill\n' > "$SDIR/S8/ro-skill.marker"
: > "$SDIR/S8/ro-skill.mem-base"
set +e; stop S8; code=$?; set -e
assert_exit 0 "$code" "empty baseline dropped gracefully (no false violation)"
set +e; [ -e "$SDIR/S8/ro-skill.marker" ]; e=$?; set -e
assert_exit 1 "$e" "stale marker with bad baseline cleared"

finish
