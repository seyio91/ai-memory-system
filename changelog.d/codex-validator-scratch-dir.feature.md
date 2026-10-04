Codex validator can run code without writing the repo: `codex-mem.sh --validator` runs
`codex --sandbox workspace-write` in a fresh scratch dir (network off, Go caches in scratch,
repo and `.git` never writable, scratch deleted on exit). New manifest key `exec_validate`
resolves the validate role, falling back to `exec_readonly`; explore still uses `exec_readonly`
only. The validator prompt uses a `git worktree`, or a `git clone --shared` on sandboxed planes.
