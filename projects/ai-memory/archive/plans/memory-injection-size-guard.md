---
plan: memory-injection-size-guard
status: done
created: 2026-07-18
completed: 2026-07-18
owner: claude (orchestrator)
task_provider: notion
task_ref: 3a1f6850-c619-810d-a840-c5c812e4bb77
---

# Memory injection size guard, and get the payload back under budget

## Goal

The `SessionStart` injection reached 88.9KB, exceeded Claude Code's inline cap for `additionalContext`,
and was spilled to a file — leaving a 2KB preview of `identity.md` as the only memory in context. The
hook exited 0. Nothing reported the degradation. Fix *both* halves: make an oversized payload **loud**
rather than silent, and bring the payload itself back under a budget so the warning stays quiet in
normal operation. Full diagnosis in [memory-injection-size-guard](../investigations/memory-injection-size-guard.md).

## Resolution (2026-07-18) — the guard was already built; the bug was a missing config key

This plan was written on a wrong diagnosis. It assumed the payload was too large and needed a new
size guard plus aggressive compression. The actual root cause: `harnesses/claude/manifest` had no
`session_chunks` / `inject_chunks` keys, so the count defaulted to 1, `emit_hook_chunk` took its
`1/1` fast path (`lib.sh:134-137`, returns unmeasured), and the whole base went out as one message
against a 10,000-char per-entry cap.

Codex hit the same class of bug on 2026-07-16 and the fix already existed, tested and documented:
fan the base across N ordered chunk entries of ≤9,000B slices. Only Claude's manifest lacked the keys.

**Criteria 1-4 and 8 are superseded, not met.** They specified a `<memory:warning>` block and an
`AI_MEMORY_INJECT_WARN_BYTES` budget. Both are now redundant:

- the **overflow marker** in `emit_hook_chunk` (`lib.sh:151`) already fires loudly when the payload
  outgrows N chunks — that is the guard, and it predates this plan
- it is already covered by tests (`test_shared_hooks.sh:177-179`)
- a byte-budget warning would be a second, weaker mechanism policing a threshold the chunker already
  enforces structurally

Building it would have added a parallel implementation of an existing control. Phases 1b, 2 and 3 are
closed as superseded.

**Criteria 5-7 stand and were met by the compression work**, which remains worthwhile on its own terms
(doctrine compliance, not delivery): `memory.md` 55,338 → 17,802 B, `working.md` 14,219 → 3,735 B,
payload 91,797 → ~46,000 chars, now 6 of 12 chunks with the largest message at 8,711 chars.
Criterion 5's ≤6KB target was missed (Architecture Decisions landed at 7,451 B) — recorded as a miss,
not renegotiated; the byte target came from the refuted budget and no longer binds anything.

## Close-out (2026-07-18) — criterion 7 verified by live observation

Criterion 7 was the last item left open **in this plan file** (`todo.md` was already ahead of it). It is
now **met**, verified in a real post-`/clear` session rather than by simulation: the `SessionStart` hook
delivered the base as 6 chunks, all five sections present inline (`identity`, `orchestrator`, `project`,
`index`, `working`), no truncation marker, and correct reassembly despite out-of-order arrival (indices
landed 3,2,5,4,1,6). This is the second confirmation — the first, on 2026-07-18, proved per-entry
budgeting but surfaced the ordering bug; this one is the first clean run *after* that fix shipped, so it
validates the envelope end to end as well.

Criterion 6 is met on the same evidence. `render_full` for `ai-memory` measures 44,144 chars against
a 12 × ~9,000 = ~108,000 capacity — better than 2× headroom, and the live session showed no overflow
marker. Note the number must come from the *harness* path: invoking `scripts/hooks/inject.sh` directly
does not carry the manifest's `inject_chunks`, so it falls to the `1/1` default and emits one 45KB
message — a stand-in that measures the unconfigured path, not the shipped one.

**Final criteria state:** 1-4 and 8 superseded (the overflow marker is the guard); 5 **missed** and
left recorded as a miss — `## Architecture Decisions` is 7,595 B against a ≤6KB target drawn from the
refuted budget; 6 and 7 met.

**Not delivered:** Phase 7's changelog entry. The docs half is moot (`AI_MEMORY_INJECT_WARN_BYTES` was
never built), but the chunking fix shipped without a CHANGELOG entry. Carried out of this plan rather
than ticked — see `todo.md`.

## Success criteria

1. `emit_hook_chunk` measures the assembled payload on **every** path, including the `1/1` default —
   the fast path at `lib.sh:134-137` no longer returns unmeasured.
2. When the payload exceeds the budget, a `<memory:warning>` block is prepended naming the total size,
   the budget, the **largest file**, and the **largest section within that file**. The full payload is
   still emitted — the guard **never drops content**.
3. When the payload is under budget the output is **byte-identical** to today's — no warning, no
   marker, no behavior change.
4. The budget is env-configurable (`AI_MEMORY_INJECT_WARN_BYTES`) with a documented default, and the
   default is justified against the empirically measured real inline cap, not guessed.
5. `## Architecture Decisions` in `projects/ai-memory/memory.md` is **≤6KB** and every one of its 37
   decisions survives as a one-line record — count before equals count after. No decision is lost, only
   its rationale prose.
6. The assembled `render_full` payload for project `ai-memory` measures **under the budget**, verified
   by running the hook, not by summing files by hand.
7. A real session start injects the memory base **inline** — `orchestrator.md`, `memory.md`, `index.md`,
   and `working.md` are all present in context, confirmed by inspection rather than assumed.
8. The guard is covered by tests in the existing suite, including the over-budget and the exactly-at-budget
   boundary, and `/test-system` passes.

## Design

The guard is **not new machinery**. `scripts/hooks/lib.sh` already has `emit_hook_chunk()` (lines
131-193) with a byte cap (`MAX = 9000`), line-buffered slicing, and a truncation marker it appends when
content overflows. The defect is narrow: the chunk spec defaults to `1/1`, and lines 134-137 special-case
`1/1` as a fast path that returns the payload **untouched** — no measurement, no cap, no marker. Claude's
manifest uses the single-chunk shape, so on this harness that entire truncation path is dead code. The
fix is to measure on the fast path too and prepend a warning, keeping the existing marker vocabulary.

Warning shape, prepended ahead of `<memory:identity>`:

```
<memory:warning>
Injection is 88.9KB, over the 40KB budget.
Largest: projects/ai-memory/memory.md (55.3KB)
  -> ## Architecture Decisions (34.2KB, 37 entries)
</memory:warning>
```

Warn-and-inject-fully is deliberate. Truncating would drop `working.md` and `index.md` precisely when a
session is context-hungry, and the harness *already* has its own spill-to-file fallback — so the failure
mode we are fixing is not data loss, it is **silence**. The guard's job is to make the harness's spill
visible in the 2KB preview the model does still see, which means the warning must come **first** in the
payload.

The compression half is ordinary editing, but it is 37 entries of judgment and must not be batched blind
— each entry keeps its decision and drops its rationale. Rationale is recoverable from git (`memory.md`
is tracked, 50 commits), which is what makes discarding it acceptable rather than destructive.

Reaching budget needs more than the decisions section. Projected: fixed cost is
`identity + orchestrator + index` = 22.1KB. Trimming decisions alone lands the total near 51KB — still
over. Gotchas (15.5KB / 24 entries) and `working.md`'s `## Checkpoints` (11.3KB, handled by the existing
`/checkpoint-archive`) are both in scope to reach ~40KB. `index.md` at 8.8KB is left alone this pass.

Rejected:
- *Truncate lowest-priority files* — guarantees inline delivery but silently drops working/index; trades a
  visible failure for a quieter one.
- *Fail the hook non-zero* — maximum visibility, but a bloated memory file would block session start
  entirely, turning a degradation into an outage.
- *Move evicted rationale to `wikis/` pages* — 37 new files to preserve prose that git already preserves.

## Decisions (locked)

- Guard behavior: warn inline, inject fully. Never drop content.
- Warning position: first in the payload, so it survives into the harness's truncated preview.
- Evicted rationale: discarded, not relocated. Git history is the recovery path.
- Budget default: `AI_MEMORY_INJECT_WARN_BYTES` = **~7000–8000, pending live confirmation.**
  ~~20000~~ was refuted by validation: it sits *above* the real cap, so a 10,000–20,000 payload would
  spill silently while the guard stayed quiet — the original bug at a smaller size.
- **The governing cap is hook `additionalContext` ≈ 10,000 chars** (`jLt`/`mou = 1e4` in
  `@anthropic-ai/claude-code@2.1.214`), *not* the 30,000 `maxResultSizeChars` of the Bash tool. The two
  share persist/preview plumbing and emit an identical message, which is what made the earlier proxy
  measurement look sound. It was wrong by ~3x.
- The cap is a **character count** (`string.length`, UTF-16 units), not a byte count. Equivalent for
  ASCII markdown; divergent for emoji/CJK.
- **`render_full` is not a per-turn cost.** It fires on SessionStart, on the recompact sentinel, and on
  an explicit `@memory` prompt. Ordinary prompts emit a 546-byte breadcrumb.
- Under-budget output must be byte-identical to today's — the guard is inert in the normal case.
- Out of scope: the `resolve_session_key` / `working..git.md` bug (see investigation, filed separately).

## Phases

- [ ] **Phase 1 — Measure the real cap, then set the budget.** Determine empirically where Claude Code
      starts spilling `additionalContext` to a file by emitting payloads of increasing size. Record the
      threshold in the investigation and pick a default budget with headroom beneath it. Everything
      downstream depends on this number being real rather than assumed.
- [ ] **Phase 2 — Guard in `lib.sh`.** Close the `1/1` fast path so it measures; add per-file and
      per-section size accounting to `render_full` so the warning can name the largest offender; prepend
      the `<memory:warning>` block when over budget. Preserve byte-identical output under budget.
- [ ] **Phase 3 — Tests.** Cover over-budget (warning present, content intact), under-budget
      (byte-identical, no warning), and the boundary. Extend the existing hook test file rather than
      adding a new suite.
- [ ] **Phase 4 — Compress `## Architecture Decisions`.** 37 entries to one-line records, ≤6KB total.
      Entry count must be identical before and after. Review as a diff — this is the irreversible-looking
      step, even though git holds the rationale.
- [ ] **Phase 5 — Trim gotchas and roll checkpoints.** Compress `## Known Constraints / Gotchas`
      (15.5KB / 24 entries) on the same principle, and run `/checkpoint-archive` to move `working.md`'s
      11.3KB `## Checkpoints` into `archive/working/`.
- [x] **Phase 6 — Verify end to end.** First confirmed by a `/clear` on 2026-07-18 (5 chunks, no
      truncation marker, no spill preview), which also exposed the ordering bug split out to
      `plans/hook-chunk-ordering.md`. Re-confirmed after that fix shipped — see Close-out.
- [x] **Phase 7 — Docs.** Folded into the ordering plan's Phase 4 and delivered there
      (`docs/harnesses/claude.md` + codex caveat, manifest comment, project-memory gotcha).
      `AI_MEMORY_INJECT_WARN_BYTES` is superseded, never built, nothing to document.
      **Changelog entry remains outstanding** — carried to `todo.md`, not ticked here.

## Risks / open questions

- ~~The real inline cap is unknown.~~ **Resolved in Phase 1:** cap is between 24,576 and 32,764 bytes.
- ~~The cap may be token-based.~~ **Resolved in Phase 1:** byte-based; real prose and a repeated-character
  run at 24,576 bytes behaved identically.
- **BLOCKING — against a ~10,000-char cap, `orchestrator.md` (11,403) overflows the budget by itself,**
  before `identity`, `index`, `memory`, or `working` load at all. Compressing `memory.md` is not just
  insufficient, it barely touches the binding constraint. Selective injection (identity + project
  always; orchestrator/index on demand) is effectively the only option that can work — trimming cannot
  close a gap this size. Phases 4-5 remain worth doing for their own sake but must not be relied on to
  reach criterion 6.
  *Earlier framing of this risk cited a 22.1KB per-prompt fixed cost against a ~24.5KB ceiling. Both
  numbers were wrong: the cost is per-session, not per-turn, and the ceiling is ~10,000. The conclusion
  survives in stronger form.*
- **The ~10,000 figure is static analysis, not live observation.** Extracted from the shipped minified
  binary; concrete but unconfirmed against a running hook. Phase 1b exists to settle it. Do not hardcode
  a budget until it does.
- **Compression is judgment, not mechanical.** 37 entries rewritten in one pass risks flattening
  decisions that genuinely need two lines. The ≤6KB target is a goal, not a hard constraint — a decision
  that loses its meaning when compressed should keep the extra line.
- **This plan fixes today's payload but not the growth rate.** Decisions accrete; without a recurring
  check the section rebuilds. A `lint-memory` size rule would make it self-policing — deferred, but the
  reason the problem recurred silently is worth not repeating.
- **`orchestrator.md` (11.4KB) and `index.md` (8.8KB) are untouched** and are now a large share of a
  smaller budget. Fine at 40KB; revisit if Phase 1 forces the budget lower.
