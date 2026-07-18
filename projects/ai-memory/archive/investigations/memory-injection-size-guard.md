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

## Phase 1 result — SUPERSEDED, see "Phase 1 corrected" below

> **The measurement in this section is wrong by ~3x.** It measured the *Bash tool* cap and assumed it
> also governed hook `additionalContext`. Independent validation refuted that. Kept for the record;
> use the corrected section that follows.

Probed by emitting payloads of known size and observing whether the harness inlined them or spilled
them to a file. Bash tool output and hook `additionalContext` use the same spill mechanism and the same
`Output too large (NKB)` message, so the former is a valid proxy. **← this inference is the error.**

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

## Phase 1 corrected — independent validation (2026-07-18)

A read-only validator re-derived every Phase 1 claim, then settled the decisive one by extracting
`strings` from the installed CLI (`@anthropic-ai/claude-code@2.1.214`, `bin/claude.exe`) rather than
inferring thresholds from observed behavior.

### The two caps are different

| Path | Constant | Value |
|---|---|---|
| Bash / shell tool result | `maxResultSizeChars` on the shell tool definition | **30,000** chars |
| Hook `additionalContext` | `jLt(e,t,r,n=mou)`, `mou = 1e4`; all call sites pass 3 args | **10,000** chars |

Both funnel into the same persist/preview helper (same `Output too large … Preview (first NKB)`
template, preview size `SXt = 2000`), which is precisely why they look identical from outside. **Shared
plumbing is not a shared threshold.** The original reasoning — "same mechanism, same message, therefore
valid proxy" — is a non-sequitur, and it is wrong here by a factor of three.

The 10,000 default is not user-tunable: no override for hook content exists anywhere in the binary, and
the surrounding flag (`tengu_velvet_ibis`) is a Statsig-style internal, not a setting.

### Corrected numbers

- **Hook `additionalContext` cap: ~10,000 chars.** Everything the guard cares about is measured against
  this, not 30,000.
- **Bash tool cap: ~30,000 chars**, empirically narrowed to inline ≤29,696 / spill ≥29,952 — consistent
  with `maxResultSizeChars: 30000`. Correct, but about a path the memory system never uses.
- **It is a character count, not a byte count** — the guard compares `string.length` (UTF-16 code units).
  Identical to bytes for ASCII markdown, divergent for emoji/CJK. "Byte-based" was imprecise; the
  practical conclusion still holds for this repo's content.
- **Budget 20,000 is refuted.** It sits *above* the real cap: a payload between 10,000 and 20,000 would
  be silently spilled by the harness while the guard stayed quiet — the original bug, reproduced at a
  smaller size. Needs recomputation with headroom under 10,000 (~7,000–8,000 pending live confirmation).

### Corrected scope — `render_full` is not a per-turn cost

`inject.sh` pays the full render on only three paths:

1. `SessionStart`, non-compact source (`session_start_memory.sh`, unconditional)
2. `UserPromptSubmit` when a recompact sentinel exists (one-shot, post-compaction)
3. `UserPromptSubmit` when the prompt contains `@memory`

Every other prompt calls `render_breadcrumb` — **measured at 546 bytes** for this project. There is no
continuous per-turn 22.1KB tax. The earlier Risks-section phrasing ("fixed always-injected set")
conflated "every session" with "every turn" and overstated the problem.

Fixed-set byte sizes confirmed exactly: `orchestrator.md` 11,403 + `index.md` 8,755 + `identity.md`
1,884 = **22,042 B**. Live `render_full` for `ai-memory` reproduced at **91,797 B**.

### What this changes

Against a ~10,000-char ceiling, **`orchestrator.md` alone (11,403) overflows the entire budget before
any other file loads.** Compression of `memory.md` is not merely insufficient — it is close to
irrelevant to the binding constraint. Selective injection stops being one option among three and
becomes effectively mandatory: the full set cannot fit, at any realistic level of editing.

The good news is the corrected scope makes this cheaper than feared — the cost lands at session start,
recompact, and explicit `@memory`, not on every turn, so deferring `orchestrator`/`index` to on-demand
loading costs a fetch on rare paths rather than degrading normal operation.

### Open — needs a live test

The validator's evidence is static analysis of minified shipped code: concrete (literal constants, exact
call sites) but not a live observation, and it could not drive the orchestrating session to test the
hook path directly. **Confirm with one live test before Phase 2 hardcodes a budget:** emit a
`render_full` payload sized just under and just over ~10,000 chars through the actual hook and observe
inline vs. spill. Until then treat 10,000 as high-confidence, not settled.

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
