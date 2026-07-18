---
doc: memory-injection-size-guard
kind: investigation
status: open — diagnosis complete, feeds plan memory-injection-size-guard
created: 2026-07-18
owner: claude (orchestrator)
---

# Investigation — memory injection exceeded the inline cap and silently degraded

## The failure

On 2026-07-18 a session started with **only a 2KB preview of `identity.md` in context**. The
`SessionStart` hook ran and succeeded — it emitted an 88.9KB payload, which exceeded Claude Code's
inline cap for `additionalContext`. The harness spilled the whole thing to a file and left a preview:

```
Output too large (88.9KB). Full output saved to:
  .../tool-results/hook-e3e2795b-...-additionalContext.txt
```

Nothing errored. `orchestrator.md`, `projects/ai-memory/memory.md`, `index.md`, and `working.md` were
simply **not in context**, and neither the hook nor the session said so. The memory system was off, and
looked on.

## Payload breakdown (measured, 2026-07-18)

| File | Size | Share |
|---|---|---|
| `projects/ai-memory/memory.md` | 55.3 KB | 60% |
| `projects/ai-memory/working.md` | 14.2 KB | 16% |
| `orchestrator.md` | 11.4 KB | 12% |
| `index.md` | 8.8 KB | 10% |
| `identity.md` | 1.9 KB | 2% |
| **total on disk** | **91.6 KB** | (88.9 KB after XML assembly) |

Within `memory.md`:

| Section | Size | Entries |
|---|---|---|
| `## Architecture Decisions` | **34.2 KB** | 37 |
| `## Known Constraints / Gotchas` | 15.5 KB | 24 |
| everything else combined | 5.2 KB | — |

`## Architecture Decisions` alone is ~38% of the entire injection. Entries average ~925 B; the largest
run 1.2–2.4 KB each:

- 2448 B — *Hook layer — declarative, manifest-driven, shared where isomorphic*
- 2226 B — *Task `summary` is a capped thin record; long-form lives in the task*
- 2036 B — *Versioned release channel — a git tag IS the release*
- 1975 B — *An investigation is an artifact; a brainstorm is an activity*
- 1621 B — *Doc-vs-code gate — the `docs/scripts.md` env-var table is machine-checked*

These carry full rationale and implementation detail inline. That is the drift the
`feedback_decisions_not_changelog` rule warns against: Architecture Decisions records **system-level
decisions only** — not migration logs, dates, counts, or per-component specifics.

## Why no guard caught it

Truncation machinery **already exists** — `scripts/hooks/lib.sh`, `emit_hook_chunk()` (lines 131-193):

- line 150 — `MAX = 9000` bytes per chunk
- line 151 — `MARKER = b"[ai-memory: memory base truncated — raise session_chunks in the harness manifest]\n"`
- lines 158-169 — line-buffered slicing into ≤9000-byte slices
- lines 174-185 — on overflow, the last chunk drops trailing lines until the marker fits, then appends it

The hole: the chunk spec comes from `AI_MEMORY_HOOK_CHUNK` (`<idx>/<total>`, **default `1/1`**), and
**lines 134-137 make `1/1` a fast path that returns the payload untouched — no cap, no marker, no
warning.** Claude's manifest uses the default single-chunk shape, so on this harness the truncation
path is dead code. `session_start_memory.sh` and `inject.sh` add no size logic of their own.

So the guard is not new machinery. It is closing a hole in machinery that already exists and already
knows how to signal truncation.

## Decisions taken (user, 2026-07-18)

1. **Guard behavior = warn inline, inject fully.** Emit a visible warning block at the top of the
   payload naming the largest offending file and section; still emit everything. Never loses data;
   makes silent degradation visible. Rejected: truncate-lowest-priority (loses working/index exactly
   when a session needs them) and fail-the-hook-loudly (a bloated file would block session start).
2. **Evicted decision detail is discarded, not relocated.** Rewrite each oversized entry to a one-line
   decision record; drop the rationale prose. Safe because `projects/ai-memory/memory.md` is git-tracked
   with 50 commits of history — the rationale stays recoverable via `git log -p`, so this is reversible
   in practice despite reading as destructive. Rejected: per-decision `wikis/` pages (37 new files for
   detail that is already in git) and a single decisions-detail grab-bag file.

## Phase 1 result — the measured cap (2026-07-18)

Probed by emitting payloads of known size and observing whether the harness inlined them or spilled
them to a file. Bash tool output and hook `additionalContext` use the same spill mechanism and the same
`Output too large (NKB)` message, so the former is a valid proxy.

| Payload | Bytes | Result |
|---|---|---|
| repeated `'a'` | 24,576 | **inline** |
| real prose (`orchestrator.md` head) | 24,576 | **inline** |
| repeated `'a'` | 32,764 | spilled |
| repeated `'a'` | 40,960 | spilled |
| original injection | 91,033 | spilled |

**Cap is between 24,576 and 32,764 bytes.** Not narrowed further — the bracket is enough to choose a
budget, and each additional probe costs context.

**The cap is byte-based, not token-based.** 24,576 bytes of real prose and 24,576 bytes of a single
repeated character behaved identically, despite differing by more than an order of magnitude in token
count. This closes the "may be token-based" risk in the plan: a byte budget is a true measure, not a
proxy, and no token-estimation headroom is required.

### Consequence: compressing `memory.md` alone cannot reach budget

With a confirmed-safe ceiling of ~24.5KB, the **fixed** cost of the always-injected files is already
fatal:

| File | Size | |
|---|---|---|
| `orchestrator.md` | 11.4 KB | not previously in scope |
| `index.md` | 8.8 KB | not previously in scope |
| `identity.md` | 1.9 KB | |
| **fixed subtotal** | **22.1 KB** | **90% of the safe ceiling, before `memory.md` or `working.md` load at all** |

The original plan assumed a 40KB budget and explicitly left `orchestrator.md` and `index.md` alone.
Both assumptions are now wrong — 40KB spills, and the fixed set leaves ~2.5KB for the two project files
combined. Perfect compression of `## Architecture Decisions` and `## Known Constraints / Gotchas` still
overshoots.

Reaching budget therefore requires a structural change, not just editing. Candidates, not yet decided:

- **Trim `index.md`** (8.8KB) — it is generated by `/reindex` from frontmatter, so it is the cheapest to
  shrink and the least lossy; a leaner emitted form needs no hand-editing.
- **Trim `orchestrator.md`** (11.4KB) — doctrine prose, hand-maintained, the least safe to cut blind.
- **Make injection selective** — inject `identity` + `project` always, and load `orchestrator` / `index`
  on demand. The largest change, but the only one that stops the fixed cost growing back.

## Unrelated latent bug found while investigating

`scripts/content-core.sh`, `resolve_session_key()` (lines 43-73): the `.agents/memory-session` marker
path is sanitized via `_sanitize_session_key` (line 50), but the **linked-worktree fallback at line 58,
`basename "$git_dir"`, is not**. If `git_dir` ever resolves to `.git`, the key becomes `.git` and the
working overlay resolves to `working..git.md` — a file that does not exist, so working memory silently
loads as empty.

This is **not hypothetical**: the `UserPromptSubmit` breadcrumb on 2026-07-18 emitted

```
working: /Users/seyi/.../projects/ai-memory/working..git.md
```

after the session cwd moved into `projects/ai-memory/`. No such file exists anywhere in the repo.
Same silent-degradation class as the headline bug. **Out of scope for this plan — file separately.**
