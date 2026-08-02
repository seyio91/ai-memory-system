- **`lint-memory.sh` no longer warns on two things that can never be acted on.** A `working.md`
  holding only section headings and `_(none yet)_` placeholders is no longer reported as stale —
  it has nothing to promote or checkpoint, so its mtime was never evidence of neglect (`[ -s ]`
  only caught a zero-byte file). And `domain/_template.md` is no longer reported as an index
  orphan: its placeholder `topic: <topic>` can never appear in the catalog, so `/reindex` could
  never clear it. The domain loop now skips the scaffold, mirroring the `*/_template/*` skip the
  project loop already had. Both narrowings are mutation-tested in both directions, so a stale
  file with real content is still flagged.
