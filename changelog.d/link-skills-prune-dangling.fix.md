- **`link-skills.sh` now prunes dangling store-shaped symlinks.** The link pass only ever walked
  skills that still exist, so a link stranded by a skill rename or by a move of the memory tree was
  never revisited and survived indefinitely — two such links (`dashboarding`, `tempo`) persisted
  across both a rename and a full tree relocation without any check noticing. A link is now removed
  only when it is dangling **and** its target sits directly under a `skills/` or `.skill-cache/`
  directory **and** the target basename matches the link name; anything else is reported as a `WARN`
  and left untouched. The match is deliberately on *shape* rather than on the currently-configured
  store roots, because a moved tree leaves links pointing at a root that is no longer configured —
  the exact case that would otherwise slip through. `--dry-run` reports prunes without removing, and
  the summary line gains a `N pruned` count.
