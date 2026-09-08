- **The Task Contract now has two levels: plan and phase.** `## Success criteria` still defines
  done for the whole plan, but each `### Phase N` now carries its own `**Verify:**` line, held to
  the same bar. The Validator can be invoked when a phase lands instead of only after everything
  is built — previously a six-phase plan got a single terminal check, so a defect in phase 2
  surfaced only once phases 3-6 sat on top of it. A phase whose `**Verify:**` cannot be written is
  defined as mis-drawn: redraw the boundary rather than write an aspirational line.
- **`/new-plan` gained a decomposition rule (Step 3.5).** The command scaffolded `## Phases` but
  never said how to fill it. It now defines a phase as *one executor delegation* and gives the
  rules: when to split (spans two subsystems, title needs an "and", more than ~3 verify
  conditions, files unnameable), when to merge (no `**Verify:**` of its own), how to order
  (foundations first, high-risk early), and where checkpoints go (before the human/CI gates
  executors may not cross, before anything irreversible, and as the pre-ship gate).
- **Phase dependencies are declared, not implied.** The plan scaffold emits a `**Depends:**` line
  per phase, and `/start` mirrors it onto the `todo.md` checkbox as `(needs: Pn)`. Order used to
  live only in the sequence of the list — invisible from `todo.md`, which is exactly what gets
  read on resume and after compaction. Phases with no annotation are independent and safe to fan
  out in parallel.
- **The `brainstorming` skill is renamed `design-brainstorm`.** It collided with the
  `superpowers:brainstorming` plugin skill, which the SessionStart injection names explicitly and
  whose handoff writes plans to `docs/superpowers/plans/` rather than the memory tree — so skill
  selection was underdetermined. Only the *skill name* moved: the activity is still
  "brainstorming" and the gate is still the "brainstorm gate", so prose using those words is
  unchanged. `link-skills.sh` prunes the old symlink automatically.
  **Existing instances:** `orchestrator.md` is per-instance and is not rewritten by an upgrade, so
  a tree installed before this release still routes to the old name. Update its one invocation
  line in the Brainstorm gate section to `design-brainstorm`, or re-seed from
  `templates/orchestrator.template.md`.
