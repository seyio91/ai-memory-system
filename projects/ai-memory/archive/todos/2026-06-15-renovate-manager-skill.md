# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### renovate-manager skill (helm + terraform reviewers) → [plan](plans/renovate-manager-skill.md)
- [x] Phase 1 — rename → `renovate-manager`, dispatcher SKILL.md (body-table parse + Type routing) + reference scaffolds
- [x] Phase 2 — skill-dir memory split by manager (`renovate-reviews/{helm,terraform}/`), re-key by project — spec in `references/memory.md`
- [x] Phase 3 — `references/helm.md` finalized: helm/helmv3 (de-hardcoded) + helm_release (set/values/var-defaults, templatefile deferred)
- [x] Phase 4 — `references/terraform.md` finalized: module/provider upgrade analysis + `terraform validate` (worktree, -backend=false) on examples/
- [x] Phase 5 — provider inference + per-provider body+diff fetch finalized (gh/bkt/az + Azure base/head git diff), execpolicy-clean
- [x] Phase 6 — validated live: PR #84 (helm_release, APPROVE WITH NOTES) + PR #78 (module, `terraform validate` PASS). Live fix: discover `example/` singular. GitHub Chart.yaml + provider surfaces dry-inspected (no live PR).

## Done
_(checked items stay above until the file is rolled)_
