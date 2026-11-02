#!/usr/bin/env bash
# path-match.sh: guarded writes to guard config and plans are denied; everything else passes.
. "$(dirname "$0")/_assert.sh"
. "$SCRIPTS_DIR/path-match.sh"

ROOT="$(cd "$SCRIPTS_DIR/.." && pwd -P)"
TMP="$(new_sandbox)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.codex"
unset AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE
export HOME="$FAKE_HOME"

file_in() { # <tool> <path> [cwd] [agent_id]
    local extra=""
    [ -z "${4:-}" ] || extra=",\"agent_id\":\"$4\""
    printf '{"tool_name":"%s","tool_input":{"file_path":%s},"cwd":%s%s}' \
        "$1" "$(json_escape "$2")" "$(json_escape "${3:-$ROOT}")" "$extra"
}

bash_in() { # <command> [cwd] [agent_id]
    local extra=""
    [ -z "${3:-}" ] || extra=",\"agent_id\":\"$3\""
    printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":%s%s}' \
        "$(json_escape "$1")" "$(json_escape "${2:-$ROOT}")" "$extra"
}

pg() { # <want DENY|ALLOW> <label> <json> [matcher-sourcing dir]
    local want="$1" label="$2" json="$3" got reason
    reason="$(AI_MEMORY_ROLE=task path_guard_match "$json")" && got=DENY || got=ALLOW
    assert_eq "$want" "$got" "$want: $label"
    PG_REASON="$reason"
}

# R2: every protected entry denied, near misses allowed
for rel in scripts/deny-list.txt scripts/deny-list.local.txt scripts/hooks/guard.sh \
    scripts/hooks/sub/deep.sh scripts/deny-match.sh scripts/jsonutil.sh scripts/path-match.sh \
    scripts/protected-paths.txt config.local.sh projects/ai-memory/plans/x.md \
    projects/newproj/plans/not-yet-created.md; do
    pg DENY "Write $rel" "$(file_in Write "$ROOT/$rel")"
done
pg DENY "Edit ~/.claude/settings.json" "$(file_in Edit "$HOME/.claude/settings.json")"
pg DENY "Write ~/.codex/hooks.json" "$(file_in Write "$HOME/.codex/hooks.json")"
pg ALLOW "NotebookEdit unprotected notebook_path" \
    "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$ROOT/docs/n.ipynb\"},\"cwd\":\"$ROOT\"}"
pg DENY "NotebookEdit notebook_path" \
    "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$ROOT/scripts/hooks/n.ipynb\"},\"cwd\":\"$ROOT\"}"
for rel in scripts/run-tests.sh scripts/tests/test_path_match.sh docs/workflow.md identity.md \
    projects/ai-memory/todo.md projects/ai-memory/memory.md projects/ai-memory/archive/plans/old.md \
    scripts/deny-lists.sh; do
    pg ALLOW "Write $rel" "$(file_in Write "$ROOT/$rel")"
done
pg ALLOW "Write ~/.claude/other.json" "$(file_in Write "$HOME/.claude/other.json")"
pg ALLOW "Read of a protected path" "$(file_in Read "$ROOT/scripts/deny-list.txt")"

# R3: live root only; target realpath'd
pg ALLOW "worktree copy" "$(file_in Write "$ROOT/.claude/worktrees/x/scripts/hooks/guard.sh")"
pg ALLOW "worktree copy of a plan" "$(file_in Write "$ROOT/.claude/worktrees/x/projects/p/plans/a.md")"
pg ALLOW "other clone" "$(file_in Write "$TMP/clone/scripts/deny-list.txt")"
pg ALLOW "relative path, cwd in another clone" "$(file_in Write scripts/deny-list.txt "$TMP/clone")"
pg DENY "relative path, cwd in live root" "$(file_in Write scripts/deny-list.txt "$ROOT")"
pg DENY "relative .. from cwd" "$(file_in Write ../scripts/hooks/x.sh "$ROOT/docs")"
pg DENY ".. into protected file" "$(file_in Write "$ROOT/docs/../scripts/deny-list.txt")"
pg DENY ".. out of worktree into live" "$(file_in Write "$ROOT/.claude/worktrees/x/../../../scripts/deny-list.txt")"
ln -s "$ROOT/scripts/deny-list.txt" "$TMP/filelink"
ln -s "$ROOT/scripts/hooks" "$TMP/dirlink"
pg DENY "symlink to protected file" "$(file_in Write "$TMP/filelink")"
pg DENY "symlinked dir to protected tree" "$(file_in Write "$TMP/dirlink/guard.sh")"
pg DENY "symlinked dir, new file" "$(file_in Write "$TMP/dirlink/new.sh")"
ln -s "$ROOT/projects" "$TMP/projlink"
pg DENY "symlinked projects, plan" "$(file_in Write "$TMP/projlink/p/plans/a.md")"
ln -s "$ROOT/docs/workflow.md" "$TMP/oklink"
pg ALLOW "symlink to unprotected file" "$(file_in Write "$TMP/oklink")"

# R3: root comes from the matcher's own location, symlinks resolved
FAKE="$TMP/fake"
mkdir -p "$FAKE/scripts"
cp "$SCRIPTS_DIR/path-match.sh" "$SCRIPTS_DIR/jsonutil.sh" "$SCRIPTS_DIR/deny-match.sh" \
    "$SCRIPTS_DIR/protected-paths.txt" "$FAKE/scripts/"
ln -s "$FAKE" "$TMP/fakelink"
fake_pg() { # <matcher-path> <json>
    ( . "$1"; AI_MEMORY_ROLE=task path_guard_match "$2" )
}
fake_pg "$FAKE/scripts/path-match.sh" "$(file_in Write "$FAKE/scripts/deny-list.txt")" >/dev/null
assert_exit 0 $? "DENY: copy's own root protected"
fake_pg "$FAKE/scripts/path-match.sh" "$(file_in Write "$ROOT/scripts/deny-list.txt")" >/dev/null
assert_exit 1 $? "ALLOW: live root unprotected from the copy's matcher"
fake_pg "$TMP/fakelink/scripts/path-match.sh" "$(file_in Write "$FAKE/scripts/hooks/g.sh")" >/dev/null
assert_exit 0 $? "DENY: matcher sourced through a symlink resolves its real root"
(cd "$TMP" && AI_MEMORY_ROLE=task bash "$FAKE/scripts/path-match.sh" "$(file_in Write "$FAKE/scripts/hooks/g.sh")") >/dev/null
assert_exit 0 $? "DENY: runnable form"
rm "$FAKE/scripts/protected-paths.txt"
out="$(fake_pg "$FAKE/scripts/path-match.sh" "$(file_in Write "$TMP/anything")")"
assert_exit 0 $? "DENY: missing protected-paths.txt fails closed"
assert_contains "$out" "orchestrator" "missing-list reason names the route"
( unset AI_MEMORY_ROLE; . "$FAKE/scripts/path-match.sh"; path_guard_match "$(file_in Write "$TMP/anything")" ) >/dev/null
assert_exit 1 $? "ALLOW: missing list never denies the main session"

# R4: guarded context
J="$(file_in Write "$ROOT/scripts/deny-list.txt")"
JA="$(file_in Write "$ROOT/scripts/deny-list.txt" "$ROOT" agent-1)"
for scope in unset executor all; do
    if [ "$scope" = unset ]; then unset AI_MEMORY_GUARD_SCOPE; else export AI_MEMORY_GUARD_SCOPE="$scope"; fi
    path_guard_match "$J" >/dev/null
    assert_exit 1 $? "ALLOW: main session (scope=$scope)"
    AI_MEMORY_ROLE=task path_guard_match "$J" >/dev/null
    assert_exit 0 $? "DENY: AI_MEMORY_ROLE set (scope=$scope)"
    path_guard_match "$JA" >/dev/null
    assert_exit 0 $? "DENY: agent_id present (scope=$scope)"
done
unset AI_MEMORY_GUARD_SCOPE
J_CONTENT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$ROOT/scripts/hooks/guard.sh\",\"content\":\"\\\"agent_id\\\"\"},\"cwd\":\"$ROOT\"}"
path_guard_match "$J_CONTENT" >/dev/null
assert_exit 1 $? "ALLOW: main session whose edit text mentions agent_id"
path_guard_match '{"tool_name":"Write","tool_input":{"file_path":"'"$ROOT"'/scripts/deny-list.txt","agent_id":"x"}}' >/dev/null
assert_exit 1 $? "ALLOW: main session with a nested agent_id key"
path_guard_match "$(bash_in 'rm scripts/deny-list.txt')" >/dev/null
assert_exit 1 $? "ALLOW: main session Bash write"
path_guard_match "$(bash_in 'rm scripts/deny-list.txt' "$ROOT" agent-1)" >/dev/null
assert_exit 0 $? "DENY: subagent Bash write"

# unextractable target on a write tool
pg DENY "Write without file_path" '{"tool_name":"Write","tool_input":{},"cwd":"/tmp"}'
assert_contains "$PG_REASON" "orchestrator" "unextractable reason names the route"
pg DENY "Edit with empty file_path" '{"tool_name":"Edit","tool_input":{"file_path":""}}'
pg DENY "NotebookEdit without a path" '{"tool_name":"NotebookEdit","tool_input":{}}'
pg ALLOW "unknown tool without a path" '{"tool_name":"Grep","tool_input":{}}'

# R5: Bash obvious writes
for c in 'cat scripts/deny-list.txt' 'ls -la && git log --oneline' 'grep -n x scripts/hooks/guard.sh' \
    'sed -n 1,5p scripts/deny-list.txt' 'cp scripts/deny-list.txt /tmp/copy' 'echo x > /tmp/out' \
    'echo cp scripts/deny-list.txt' 'git commit -m "a > scripts/deny-list.txt"' 'ls projects/ai-memory/plans' \
    'echo x > scripts/run-tests.sh.bak' 'cat scripts/deny-list.txt 2>&1 | head' 'rm /tmp/scratch'; do
    pg ALLOW "bash: $c" "$(bash_in "$c")"
done
for c in "sed -i 's/a/b/' scripts/deny-list.txt" "sed -i.bak 's/a/b/' scripts/deny-list.txt" \
    "sed -ni 's/a/b/p' scripts/hooks/guard.sh" "sed --in-place 's/a/b/' scripts/deny-match.sh" \
    'echo x > scripts/deny-list.txt' 'echo x >> scripts/deny-list.txt' 'echo x>scripts/deny-list.txt' \
    "echo x >$ROOT/scripts/hooks/guard.sh" 'echo x 2>/dev/null > scripts/jsonutil.sh' ': > scripts/protected-paths.txt' \
    'echo x | tee scripts/deny-list.txt' 'echo x | tee -a scripts/deny-list.txt' \
    'cp /tmp/x scripts/deny-list.txt' 'cp -f /tmp/x projects/ai-memory/plans/p.md' \
    'mv /tmp/x scripts/hooks/guard.sh' 'mv scripts/deny-list.txt /tmp/y' \
    'rm scripts/deny-list.txt' 'rm -rf projects/ai-memory/plans' 'rm -f scripts/hooks/*' \
    'truncate -s 0 scripts/deny-list.txt' 'timeout 5 rm scripts/deny-list.txt' 'nice -n 10 mv /tmp/x scripts/deny-list.txt' 'sudo rm scripts/deny-list.txt' 'ls && rm scripts/deny-list.txt' \
    'echo {} > ~/.codex/hooks.json' 'rm ~/.claude/settings.json' 'echo {} > $HOME/.claude/settings.json' \
    "echo {} >$HOME/.claude/settings.json"; do
    pg DENY "bash: $c" "$(bash_in "$c")"
done
pg DENY "bash relative to cwd (rm)" "$(bash_in 'rm deny-list.txt' "$ROOT/scripts")"
pg DENY "bash relative to cwd (sed -i)" "$(bash_in "sed -i 's/a/b/' guard.sh" "$ROOT/scripts/hooks")"
pg DENY "bash relative to cwd (redirect, ..)" "$(bash_in 'echo x > ../scripts/hooks/g.sh' "$ROOT/docs")"
pg ALLOW "bash same relative name, other cwd" "$(bash_in 'rm deny-list.txt' "$TMP")"
pg ALLOW "bash write in worktree copy" "$(bash_in "rm $ROOT/.claude/worktrees/x/scripts/deny-list.txt")"
pg ALLOW "bash write via symlink-free clone" "$(bash_in "echo x > $TMP/clone/scripts/deny-list.txt")"
pg DENY "bash write through symlink" "$(bash_in "echo x > $TMP/filelink")"

# R5: directory destinations and quoted redirect text
mkdir -p "$TMP/probe" "$TMP/outdir"
for c in "cp $TMP/probe/deny-list.txt scripts/" "mv $TMP/probe/deny-list.txt scripts/" \
    "cp $TMP/probe/deny-list.txt scripts" "cp $TMP/probe/x.sh scripts/hooks/" \
    "cp -r $TMP/probe/a $TMP/probe/deny-list.txt scripts/" "mv $TMP/probe/new.sh scripts/hooks/" \
    'echo x >"scripts/deny-list.txt"' 'echo x >scripts/deny-list.txt' 'echo x >>scripts/deny-list.txt' \
    'echo "a b" > scripts/deny-list.txt'; do
    pg DENY "bash: $c" "$(bash_in "$c")"
done
for c in "cp $TMP/probe/deny-list.txt $TMP/outdir/" "mv $TMP/probe/deny-list.txt $TMP/outdir" \
    "cp scripts/deny-list.txt $TMP/outdir/" 'printf "%s\n" ">scripts/deny-list.txt"' \
    'echo "example >scripts/deny-list.txt"' "echo 'x > scripts/deny-list.txt'"; do
    pg ALLOW "bash: $c" "$(bash_in "$c")"
done

# R5: redirect tokens are not operands; cd carries across a chain; truncate -r source is read
mkdir -p "$TMP/cdbase"
for c in 'cp /tmp/new scripts/deny-list.txt 2>/dev/null' 'mv x scripts/deny-list.txt 2>&1' \
    'rm scripts/deny-list.txt >/dev/null 2>&1' 'cd scripts && rm deny-list.txt' \
    'cd scripts/hooks; rm guard.sh' 'cd projects/p && echo x > plans/a.md' \
    'cd scripts && cd hooks && rm guard.sh' 'cd /tmp && cd - && rm scripts/deny-list.txt' \
    'cd /tmp && cd $X && rm scripts/deny-list.txt' 'cd -- scripts && rm deny-list.txt'; do
    pg DENY "bash: $c" "$(bash_in "$c")"
done
for c in 'cd /tmp && rm scripts/deny-list.txt' 'truncate -r scripts/deny-list.txt /tmp/sized-file' \
    'truncate --reference=scripts/deny-list.txt /tmp/sized-file' 'cp scripts/deny-list.txt /tmp/x 2>/dev/null' \
    'cd scripts && cd /tmp && rm deny-list.txt'; do
    pg ALLOW "bash: $c" "$(bash_in "$c")"
done

# R6: reason names the route
pg DENY "reason check (file tool)" "$(file_in Write "$ROOT/scripts/deny-list.txt")"
assert_contains "$PG_REASON" "only via the orchestrator" "file-tool reason: orchestrator route"
assert_contains "$PG_REASON" "report this deny" "file-tool reason: report in return"
assert_eq 1 "$(printf '%s\n' "$PG_REASON" | wc -l | tr -d ' ')" "reason is one line"
pg DENY "reason check (bash)" "$(bash_in 'rm scripts/deny-list.txt')"
assert_contains "$PG_REASON" "only via the orchestrator" "bash reason: orchestrator route"

# apply_patch: driven from the captured Codex payload
FIX="$SCRIPTS_DIR/tests/fixtures/codex/pre_tool_use_apply_patch.json"
patch_in() { # <patch text> [cwd] [agent_id]
    jq -c --arg p "$1" --arg c "${2:-$ROOT}" --arg a "${3:-}" \
        '.tool_input.command = $p | .cwd = $c | if $a != "" then .agent_id = $a else . end' "$FIX"
}
hdr() { printf '*** Begin Patch\n%s\n*** End Patch' "$1"; }
fx_patch="$(jq -r .tool_input.command "$FIX")"
pg ALLOW "apply_patch captured fixture, unprotected targets" "$(patch_in "$fx_patch" "$TMP")"
pg DENY "apply_patch fixture, cwd in scripts/hooks (relative Add)" "$(patch_in "$fx_patch" "$ROOT/scripts/hooks")"
assert_contains "$PG_REASON" "only via the orchestrator" "apply_patch reason: orchestrator route"
pg DENY "apply_patch Add protected" "$(patch_in "$(hdr "*** Add File: $ROOT/scripts/deny-list.txt
+x")")"
pg DENY "apply_patch Update protected" "$(patch_in "$(hdr "*** Update File: scripts/deny-list.txt
@@
-a
+b")")"
pg DENY "apply_patch Add protected beside benign target" "$(patch_in "$(hdr "*** Delete File: $TMP/z.txt
*** Add File: $ROOT/scripts/deny-list.txt
+x")")"
pg DENY "apply_patch Update protected beside benign target" "$(patch_in "$(hdr "*** Delete File: $TMP/z.txt
*** Update File: $ROOT/scripts/deny-list.txt
@@
-a
+b")")"
pg DENY "apply_patch Delete plan file" "$(patch_in "$(hdr "*** Delete File: projects/ai-memory/plans/x.md")")"
pg DENY "apply_patch Update plan file" "$(patch_in "$(hdr "*** Update File: $ROOT/projects/ai-memory/plans/executor-protected-paths.md
@@
-a
+b")")"
pg DENY "apply_patch Move to protected" "$(patch_in "$(hdr "*** Update File: $TMP/a.txt
*** Move to: $ROOT/scripts/deny-list.txt
@@
-a
+b")")"
pg DENY "apply_patch multi-file, last target protected" "$(patch_in "$(hdr "*** Add File: $TMP/a.txt
+a
*** Update File: $TMP/b.txt
@@
-a
+b
*** Delete File: $ROOT/scripts/deny-list.txt")")"
pg ALLOW "apply_patch multi-file unprotected" "$(patch_in "$(hdr "*** Add File: $TMP/a.txt
+a
*** Delete File: $TMP/b.txt")")"
pg DENY "apply_patch no Begin Patch" "$(patch_in "*** Add File: $TMP/a.txt
+a
*** End Patch")"
pg DENY "apply_patch no End Patch" "$(patch_in "*** Begin Patch
*** Add File: $TMP/a.txt
+a")"
pg DENY "apply_patch no headers" "$(patch_in "$(hdr "+a")")"
pg DENY "apply_patch empty text" "$(patch_in "")"
pg DENY "apply_patch empty header path" "$(patch_in "$(hdr "*** Add File: 
+a")")"
pg DENY "apply_patch unknown header" "$(patch_in "$(hdr "*** Add File: $TMP/a.txt
+a
*** Rename File: $TMP/b.txt")")"
assert_contains "$PG_REASON" "cannot parse" "apply_patch unparseable reason"
pg DENY "apply_patch missing command field" "$(jq -c 'del(.tool_input.command)' "$FIX")"
reason="$(path_guard_match "$(patch_in "$(hdr "*** Add File: $ROOT/scripts/deny-list.txt
+x")")")" && got=DENY || got=ALLOW
assert_eq ALLOW "$got" "apply_patch main session allowed"
reason="$(path_guard_match "$(patch_in "$(hdr "*** Add File: $ROOT/scripts/deny-list.txt
+x")" "$ROOT" sub1)")" && got=DENY || got=ALLOW
assert_eq DENY "$got" "apply_patch agent_id guarded"

finish
