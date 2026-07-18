- **Memory injection reached the model whole again on Claude — it had been silently truncated to a
  2KB preview.** `harnesses/claude/manifest` declared no `session_chunks` / `inject_chunks`, so the
  count defaulted to `1` and `emit_hook_chunk` took a `1/1` fast path that returned the payload
  unmeasured. The entire memory base then went out as a single hook message against Claude Code's
  ~10,000-character `additionalContext` cap, so the harness spilled it to a file and only a 2KB
  preview of `identity.md` survived into context. The hook exited `0` and nothing reported the
  degradation — a session looked normal while running with almost no memory. The base is now fanned
  across 12 ordered entries of ≤9,000-byte slices, the same shape Codex already used.
- **Chunked injection no longer depends on hook delivery order.** Claude runs same-event hook entries
  **concurrently** and concatenates them by completion, so registration order is not delivery order
  (entries registered 1..12 were observed arriving 2,3,4,1,5). Because slicing happens on line
  boundaries, an out-of-order chunk bisects a content block and the reassembled payload is corrupt.
  Every slice now carries a self-describing `<memory:chunk index="N" of="M">` envelope so the model
  can reassemble regardless of arrival order. Codex delivers in registration order and was never
  affected — the behaviour was verified per-harness rather than assumed from one.
- **An oversized base is now loud instead of silent.** When the payload outgrows its chunk budget the
  existing overflow marker fires — `[ai-memory: memory base truncated — raise session_chunks in the
  harness manifest]` — rather than the harness quietly spilling to a file. Raising `session_chunks` /
  `inject_chunks` in the harness manifest is the fix when you see it.
