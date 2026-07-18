---
plan: hook-chunk-ordering
status: done
completed: 2026-07-18
created: 2026-07-18
owner: claude (orchestrator)
---

# Plan — Hook chunk ordering envelope

## Goal
`742f083` fanned the memory base across N registered hook entries to defeat the per-entry
`additionalContext` cap. It assumed the harness delivers those entries in **registration order**,
by analogy with codex (verified 2026-07-16, `domain/codex.md`). Claude does **not** guarantee it:
on the 2026-07-18 `/clear`, five non-empty chunks registered 1..12 in `settings.json` arrived in
context as **2, 3, 4, 1, 5** — chunk 1 (`<memory:identity>` + orchestrator head) spliced into the
middle of the `<memory:index>` Domain table. Because `emit_hook_chunk` slices at arbitrary line
boundaries, an out-of-order chunk splits a `<memory:*>` block mid-table. No content is lost; the
block structure is scrambled.

Fix: stop depending on arrival order. Wrap each emitted slice in a self-describing ordering
envelope so a reader can reassemble by index regardless of delivery order.

## Success criteria
- `emit_hook_chunk` wraps every non-empty multi-chunk slice in `<memory:chunk index="i" of="N">` … `</memory:chunk>`.
- `of="N"` is the **actual** slice count (5 today), not the registered chunk total (12); on overflow it is the registered total.
- Chunk 1 additionally carries a `note=` attribute stating that delivery order is not guaranteed and fragments concatenate by index.
- The `1/1` and unset-spec fast paths remain **byte-identical passthrough** — no envelope (existing test must still pass unmodified).
- Chunks past the natural slice count still emit **nothing at all** — no empty envelope.
- The overflow truncation marker is preserved and still the final line **inside** the envelope.
- Stripping envelopes from all chunks and concatenating by index reproduces `render_full` **byte-for-byte**.
- Worst-case emitted chunk (9000B slice + longest envelope) stays under the 10,000-char cap; measured and asserted.
- `bash scripts/run-tests.sh` passes.
- Mutation check: reverting the envelope in `lib.sh` makes the new ordering tests fail (control watched failing before its green is trusted).

## Design
- **Chosen:** ordering envelope emitted by `emit_hook_chunk` in `scripts/hooks/lib.sh`. Harness-agnostic — codex inherits it for free, and it is inert there (codex already delivers in order).
- Envelope is a **transport frame**, deliberately not balanced against the `<memory:*>` content tags it may bisect. Naming it `memory:chunk` with `index`/`of` makes that legible.
- `note=` on chunk 1 only: all chunks are in context simultaneously, so one note is visible regardless of which arrives first — zero per-chunk repetition cost.
- **Rejected — section-aligned slicing** (one `<memory:*>` block per chunk): does not remove the need for the envelope, since `projects/ai-memory/memory.md` alone exceeds the 9000B slice budget, so intra-section splits remain unavoidable. Possible later refinement, not a substitute.
- **Rejected — file spill + pointer**: abandons in-band injection, which is the point of the hook archetype.
- **Rejected — shrink slices so everything fits one entry**: the base is ~43KB against a 10,000-char cap; not reachable.

## Decisions (locked)
- `MAX` stays 9000. Envelope adds ≤ ~140B, so worst case ≈ 9140 < 10,000.
- Empty chunks stay completely silent (no envelope) — preserves the existing "beyond natural slice count is empty" contract.
- Single-chunk (`1/1` / unset) stays raw passthrough — nothing to order.

## Phases
### Phase 1 — envelope in `emit_hook_chunk`
- Wrap non-empty slices; compute `of` from the actual slice count.
- `note=` on index 1; overflow path wraps the marker too.

### Phase 2 — tests in `test_shared_hooks.sh`
- Update the reassembly test to strip envelopes before the byte-identity compare.
- New: envelope shape, `of` = actual slice count, no envelope on empty chunk, no envelope on `1/1`, overflow marker still final line inside the envelope, worst-case chunk under 10,000 chars.
- New: out-of-order concatenation reassembles correctly when sorted by index.

### Phase 3 — verify + mutation-check
- `bash scripts/run-tests.sh`.
- Live hook run: render all 12 chunks, confirm envelopes and sizes.
- Revert the envelope temporarily and confirm the new tests fail.

### Phase 5 — restore the install gate (added after validation)
- `test_install_harness.sh` expected un-chunked hook commands, matching 0 entries since `742f083`.
- Expectations now derive the chunk count from the **manifest** (claude + codex), so the check asserts
  "registration matches the manifest" rather than a literal — a hardcoded count is what silently rotted.
- Both python checks wrapped in `set +e` / `rc=$?; set -e`: under `set -e` the script exited at the
  python call, so a failure produced a bare rc=1 with no reason and no summary line.
- Impact: the file died at assertion 37 of 143 — **106 assertions were entirely ungated**.
- Mutation-checked: collapsing `_hook_chunked_commands` to a single entry now fails loudly with named
  assertions (`SessionStart entries=1, manifest says 12`) and still reaches the summary.

### Phase 4 — docs + memory
- `docs/harnesses/claude.md`: the ordering caveat alongside the existing cap note (folds in the open Phase 7 of the `memory-injection-size-guard` plan).
- Correct the stale `harnesses/claude/manifest` comment ("Live payload 91,797B = 11 slices" → ~43KB = 5 slices).
- Record the gotcha in project memory: registration order is not delivery order on Claude.

## Validation (2026-07-18, `validate` role → subagent)
**All criteria now PASS** — `scripts/run-tests.sh`: 48 passed, 0 failed.

At first validation, 9 of 10 passed; criterion "`bash scripts/run-tests.sh` passes" FAILED because
`test_install_harness.sh` failed. That has since been fixed (Phase 5 below).

The validator traced that failure to its root cause, which **corrects the orchestrator's earlier
"pre-existing and unrelated" framing**: `test_install_harness.sh` asserts install idempotency by
*exact string match* against registered hook commands, and its expected string never included
`AI_MEMORY_HOOK_CHUNK=i/12`. So it has been failing since **`742f083`** — the chunking commit this
plan continues — not since some unrelated older change. It is pre-existing relative to the envelope
diff, but it belongs to this thread. `grep` confirms the file never references `emit_hook_chunk` or
the envelope; last touched in `cac1399`, before chunked registration existed.

Consequence: **install hook-registration is currently ungated** — the test dies before printing a
summary (rc=1, 37 oks, no FAIL line), the exact "silently ungated" failure class already in Gotchas.

Live production confirmation (this session's post-edit prompt): chunks arrived **4, 3, 5, 2, 1**,
each correctly enveloped, `of="5"`, note on chunk 1 only — the reordering is real and recurring, and
the envelope handles it.

## Risks / open questions
- **Single observation of the reordering.** One `/clear` proved order is not *guaranteed*, which is all the fix needs — the envelope is correct under both ordered and unordered delivery. Not worth blocking on a second sample.
- Envelope tags appear inside injected context and cost ~60B/chunk (~300B total today). Acceptable.
- The bisected-`<memory:*>`-tag ugliness is reduced but not eliminated; section-aligned slicing remains a possible follow-up.
