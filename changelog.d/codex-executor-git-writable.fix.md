Codex executor can commit again: `codex-mem.sh --executor` adds the repo's git dir to
`sandbox_workspace_write.writable_roots`. codex's `workspace-write` sandbox remounts `.git`
read-only, so `git add`/`git commit` failed with `Unable to create .git/index.lock:
Operation not permitted` while working-tree edits succeeded. No-op outside a git repo.
