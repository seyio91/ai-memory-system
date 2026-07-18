---
plan: memory-injection-size-guard
status: active
created: 2026-07-18
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
- Budget default: `AI_MEMORY_INJECT_WARN_BYTES` = **20000**. Measured 2026-07-18: the cap sits between
  24,576 (inline) and 32,764 (spills); 20000 leaves headroom under the confirmed-safe figure. The
  original 40000 guess was itself over the cap.
- The cap is **byte-based, not token-based** — verified by identical behavior for real prose and a
  repeated-character run at the same byte count. A byte budget is exact, not a proxy.
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
- [ ] **Phase 6 — Verify end to end.** Run the hook for real and confirm the payload is under budget, the
      warning is absent, and a fresh session carries all five sections inline. Criteria 6 and 7 are
      verified by observation, not by arithmetic over file sizes.
- [ ] **Phase 7 — Docs + changelog.** Document `AI_MEMORY_INJECT_WARN_BYTES` in `docs/scripts.md` (the
      env-var table is machine-checked by the doc-vs-code gate) and add a changelog entry.

## Risks / open questions

- ~~The real inline cap is unknown.~~ **Resolved in Phase 1:** cap is between 24,576 and 32,764 bytes.
- ~~The cap may be token-based.~~ **Resolved in Phase 1:** byte-based; real prose and a repeated-character
  run at 24,576 bytes behaved identically.
- **BLOCKING — compressing `memory.md` cannot reach budget on its own.** The fixed always-injected set
  (`orchestrator` 11.4KB + `index` 8.8KB + `identity` 1.9KB = 22.1KB) already consumes 90% of the safe
  ceiling before either project file loads, leaving ~2.5KB for `memory.md` + `working.md` combined.
  Phases 4-5 are necessary but not sufficient, and criterion 6 is unreachable as the plan currently
  stands. Needs a decision — trim the generated `index.md`, trim `orchestrator.md`, or make injection
  selective (identity + project always, orchestrator/index on demand) — before Phase 2 hardcodes a
  budget the system cannot meet.
- **Compression is judgment, not mechanical.** 37 entries rewritten in one pass risks flattening
  decisions that genuinely need two lines. The ≤6KB target is a goal, not a hard constraint — a decision
  that loses its meaning when compressed should keep the extra line.
- **This plan fixes today's payload but not the growth rate.** Decisions accrete; without a recurring
  check the section rebuilds. A `lint-memory` size rule would make it self-policing — deferred, but the
  reason the problem recurred silently is worth not repeating.
- **`orchestrator.md` (11.4KB) and `index.md` (8.8KB) are untouched** and are now a large share of a
  smaller budget. Fine at 40KB; revisit if Phase 1 forces the budget lower.
