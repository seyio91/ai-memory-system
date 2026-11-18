- **The initiative Now view leads with what needs you.** `## Now` now has five sections in
  order: Decisions needed, Waiting on you, Sessions to start, Blocked, Open proposals. A
  Target whose `next:` starts with `user —` is under Waiting on you; other ready Targets are
  under Sessions to start. Decisions needed lists each `proposed` D-id cited in a Target's
  `blocked_by:` with the Targets it holds up, and those ids are marked `(blocking)` in Open
  proposals. Blocked rows are sorted by how much they hold up, and dependencies read
  `(blocked)`, `(closed)`, `(needs <stage>)`, `(not found)`, `(stage unknown)` or
  `(not done)`.
- **New lint WARN.** `lint-memory.sh` warns when a Target is `status: open` but its
  `depends_on` is unsatisfied; set `status: blocked`. It uses the same verdict as the Now
  view, so a `closed` dependency never satisfies.
- **Authoring rules** (in `docs/initiatives.md` and `initiatives/_template.md`): start
  `next:` with `user —` when the user acts first, put only non-Target blockers in
  `blocked_by:` and cite decisions by D-id, and set `status: blocked` on a Target with
  unfinished `depends_on`.
- **Existing initiatives report a stale Now fence** until you run
  `bash scripts/initiative-render.sh <slug> --write` for each one.
