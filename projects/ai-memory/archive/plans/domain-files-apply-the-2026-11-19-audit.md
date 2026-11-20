---
plan: domain-files-apply-the-2026-11-19-audit
status: done
completed: 2026-11-19
created: 2026-11-19
owner: claude (orchestrator)
task_provider: local
task_ref: domain-files-apply-the-2026-11-19-audit-trim-deprecate-fix-stale
---

# Plan — Domain files: apply the 2026-11-19 audit

## Goal
Apply the domain-files audit: fix every stale claim, deprecate the two files that are status snapshots rather than reference, and trim the rest to durable patterns and traps, so a triggered domain load costs about half what it does today and stops feeding agents wrong facts.

**Before:** 19 domain files, ≈200 KB; the audit found wrong-today claims in 14 of them, two files that are a design snapshot and an unexecuted rollout plan, and widespread version pins, `file:line` refs, counts, dated status and content duplicated in skills, project memory or engine docs.
**After:** every stale item in investigation `domain-files-audit` is fixed or removed; secrets and agent-sandboxing are gone with their kept lines relocated; remaining files follow the volatile-specifics rule; personal domain total ≤ ~110 KB; the tracked files and the template are fixed by one merged PR.

## Non-goals
- Fixing the out-of-scope findings (k8s-addons folder annotation, shell token exports, stale checkouts) — reported to the user, not handled here.
- Re-auditing project `memory.md` files (investigation `memory-pruning-pass` covers that).
- Changing how triggers are matched or how the index is generated.

## Success criteria
- R1 [acceptance] Every STALE/WRONG item listed in investigation `domain-files-audit` is corrected or its line removed — checked item by item against the investigation table.
- R2 [acceptance] `domain/secrets.md` and `domain/agent-sandboxing.md` no longer exist as domain files (or agent-sandboxing is ≤ 5 KB of gotchas only, per the user's choice); each kept line named in the investigation is present in its stated new home.
- R3 [acceptance] Personal domain files (excluding the three tracked ones) carry no version pins, `file:line` refs, one-off counts, dated status or incident narratives: `grep -nE '~> ?[0-9]|\bv?[0-9]+\.[0-9]+\.[0-9]+\b|\.(tf|ya?ml|md|sh|go|py|toml):[0-9]+|in progress|still open|PR #[0-9]+ open' $(ls domain/*.md | grep -vE '/(_template|agent-tooling|codex)\.md$')` returns only lines individually justified in the phase report.
- R4 [acceptance] `bash scripts/regenerate-index.sh` then `bash scripts/lint-memory.sh` → 0 ERRORs; no trigger appears in two domain files.
- R5 [acceptance] `wc -c` over personal domain files (`domain/*.md` minus `_template`, `agent-tooling`, `codex`) ≤ 110 KB.
- R6 [acceptance] Every "keep" item in investigation `domain-files-audit` survives somewhere (domain file, skill, project memory), checked against the pre-plan backup of `domain/` kept outside the repo (personal content cannot be a tracked baseline).
- R7 [acceptance] One PR changes `domain/agent-tooling.md`, `domain/codex.md`, `domain/_template.md` (+ changelog fragment); CI green; merged by the user.

## Design
- Settled shape (no brainstorm): the investigation names each cut, move and fix; phases group files by theme so each phase validates independently.
- Personal files (P1–P5) are gitignored and edited in the main checkout; the tracked files (P6) go through a worktree branch and `git-cli ship`.
- Back up `domain/` outside the repo before P2 — the files have no git history.
- Relocations land in owners: VictoriaMetrics/KEDA/dashboard entries → the owning personal skills; repo-specific facts → that project's `memory.md`; ESO lines → external-secrets.
- Alternative: one pass over all 19 files → rejected, too large to validate in one round.

**Builds on:** investigation `domain-files-audit`; `orchestrator.local.md` § Domain files; `scripts/regenerate-index.sh`, `scripts/lint-memory.sh`.

## Decisions (locked)
- Domain files hold durable patterns and traps only (user, 2026-11-19).
- agent-sandboxing's unexecuted rollout moves to a local-only investigation (`.git/info/exclude`), not deleted (user, 2026-11-19).
- The audit investigation carries client data: it stays local (`.git/info/exclude`), never committed. This plan names no client specifics.
- Base: `30a34941a5520443676dae7bcf73e0a75e631cb0` (origin/main).

## Phases
### Phase 1 — Wrong-today fixes
- git-cli: closed commit types, path args ignored. datadog: Opsgenie paging scope, generic-monitor pin.

**Files touched:** `domain/git-cli.md`, `domain/datadog.md`
**Risk:** low
**Depends:** none
**Verify:** R1 — the git-cli and datadog rows' STALE items are corrected (done 2026-11-19).

### Phase 2 — Deprecate secrets and agent-sandboxing
- Back up `domain/` outside the repo.
- secrets: ESO interface lines → external-secrets; analysis → the owning initiative/investigation; reverse that investigation's pointer; delete the file.
- agent-sandboxing: rollout section moved or deleted per the user's choice; keep gotchas condensed (or fold into another file); fix `VAULT_TOKEN` and step-2 claims.
- Regenerate index.

**Files touched:** `domain/secrets.md`, `domain/agent-sandboxing.md`, `domain/external-secrets.md`, `index.md`
**Risk:** low
**Depends:** Phase 1
**Verify:** R2, R6 — both files gone or reduced; each kept line present in its new home.

### Phase 3 — Trim topology files
- system-architecture, environments-clusters, tagging-strategy, landing-zone: fix stale items, remove cross-file duplicates (keep each fact in one file), drop pins/line refs/dated status.

**Files touched:** `domain/system-architecture.md`, `domain/environments-clusters.md`, `domain/tagging-strategy.md`, `domain/landing-zone.md`
**Risk:** low
**Depends:** Phase 2
**Verify:** R1, R3, R6 — for these four files.

### Phase 4 — Trim Kubernetes-area files and relocate gotchas
- kubernetes: drop generic checklist; move VM scrape / KEDA / histogram entries to owning skills (reconcile the duplicate-scrape-target conflict); keep general k8s gotchas where they will still load.
- kyverno, helm, vault, external-secrets: per investigation.

**Files touched:** `domain/kubernetes.md`, `domain/kyverno.md`, `domain/helm.md`, `domain/vault.md`, `domain/external-secrets.md`, `skills/vm-scrape-enablement/**`, `skills/platform-drilldown-dashboard/**`
**Risk:** low
**Depends:** Phase 2
**Verify:** R1, R3, R6 — for these files; relocated entries present in the skills.

### Phase 5 — Trim tool files
- datadog, grafana, jira, zeppelin, terraform, git-cli: drop content duplicated in skills, CLI help, manuals, `orchestrator.local.md` or project memory; fix remaining stale items.

**Files touched:** `domain/datadog.md`, `domain/grafana.md`, `domain/jira.md`, `domain/zeppelin.md`, `domain/terraform.md`, `domain/git-cli.md`
**Risk:** low
**Depends:** Phase 2
**Verify:** R1, R3, R6 — for these files.

### Phase 6 — Tracked files PR
- Worktree branch from origin/main. agent-tooling: drop rtk entries and derivable linker mechanics, fix skill-store path, add opencode, remove dangling links. codex: drop retired AGENTS.md mechanism and doc duplicates, fix bare mode and `default.rules` role. `_template.md`: state the volatile-specifics rule; drop the dated-entry format. Changelog fragment. `git-cli ship --intent`.

**Files touched:** `domain/agent-tooling.md`, `domain/codex.md`, `domain/_template.md`, `changelog.d/domain-files-volatile-specifics.fix.md` (new)
**Risk:** low
**Depends:** none
**Verify:** R7 — PR open with only these files, full suite green, CI green.

### Phase 7 — Whole-tree checks
- Regenerate the index, lint, check trigger uniqueness and total size; walk the investigation's STALE and keep lists once more.

**Files touched:** `index.md`
**Risk:** low
**Depends:** Phase 3, Phase 4, Phase 5
**Verify:** R1, R4, R5, R6 — whole tree (tracked files as on main; rerun R4 after P6 merges).

## Risks / open questions
- Narrowed kubernetes triggers: general gotchas kept there may not load; P4 decides per gotcha whether it moves or the triggers widen.
- Several local checkouts are far behind origin; claims re-checked in P3–P5 must use `origin/<default>`.
