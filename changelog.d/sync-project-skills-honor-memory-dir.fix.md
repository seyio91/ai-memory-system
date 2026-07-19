- **`sync-project-skills.sh` now honours `MEMORY_DIR` — it was silently ignoring it.** The script resolved
  the tree into its own `MEMORY_ROOT` and then assigned `MEMORY_DIR="$MEM"` *before* sourcing `_lib.sh`, so a
  user-set `MEMORY_DIR` was discarded and the self-located tree was synced instead. It was the one script in
  the tree that ignored the system's universal tree override, and it did so without a word: pointed at a
  sandbox with `MEMORY_DIR=…`, it happily wrote skill symlinks into the real repos named by the *other*
  tree's `repo_path`s. Tree resolution is now delegated to `_lib.sh`, the same `${MEMORY_DIR:-self-locate}`
  path every other script uses, so `config.local.sh` is also read from the tree actually being synced.
- **`MEMORY_ROOT` is deprecated.** It is still read and still takes precedence, but prints a deprecation
  notice to stderr. Honouring it is deliberate: silently ignoring it would reintroduce the identical
  wrong-tree failure for anyone who had set it. It is removed at the next major.
