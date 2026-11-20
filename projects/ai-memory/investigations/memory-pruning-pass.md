# Memory pruning pass — method and worked example

Source for task `add-a-rediscovery-cost-pruning-pass-to-the-memory-auditor`. Today the `auditor` agent (invoked by `/lint-memory`) checks whether each `memory.md` claim is *true*; it never asks whether a true claim is *worth its context cost*. This pass adds that question.

## Method (as run on platform-sandbox, 2026-11-09)

1. **Size by section** (`awk` on `^## ` headings) to find where the bytes are; the budget warning from `memory_write_guard.sh` names the file, not the culprit.
2. **Move cross-project entries to domain files.** An entry about a tool (ESO, Vault, Datadog, kubectl, Kyverno) rather than the repo belongs in `domain/<tool>.md`, loaded on demand by triggers. Append to an existing domain file when one fits; create one (frontmatter `topic`/`triggers`/`summary`, `## Knowledge`, dated entries) only when none does; run `regenerate-index.sh`.
3. **Judge every entry by cost of rediscovery**, including entries just moved to domain files:
   - KEEP: silent failure (wrong result, all statuses green), a fact that took a source read or a cross-repo read, a user decision `(user, <date>)`, anything living outside the repo (memory-only scripts, external org handles).
   - REMOVE: loud error with an obvious fix; one `grep`/`ls`/`kubectl get` away; already enforced in code or recorded in an ADR / decision log / D-entry; dated changelog of what happened.
   - CONDENSE: keep the rule, cut the incident story, PR numbers, dates and snapshots that go stale (e.g. "namespaces currently outside the allow-list").
4. **Remove duplication with what every session already loads**: identity, doctrine, `orchestrator.local.md`, `index.md` (lists every domain file with triggers), and the harness skill list. Pointer lines like "`domain/x.md` — …" or "`<skill>` skill — …" are redundant. Keep a pointer only when it carries a rule ("keep the two in step", "reasons go in ADR-0011") or names a file the index cannot (wikis, memory-only scripts, repo docs with maintenance rules).
5. **Remove duplication inside the file** (same fact under What It Is, Conventions and Architecture Decisions).
6. **Move long conventions to a wiki** with a one-line rule + pointer left behind (e.g. a multi-bullet doc-writing convention).
7. **Verify before removing anything flagged stale** — read the repo and the live system (the sandbox's Vault-node `do-not-disrupt` gotcha was wrong: D48 had removed the annotation; confirmed on the live pods).
8. **Keep format contracts**: `## Related Projects` stays a table (doctrine routes on it); frontmatter untouched.
9. Back up before rewriting; lint after.

A fresh read-only reviewer subagent (not the one that did the first pass) found a further 6 KB the first pass had kept — run the judgement twice, the second time cold.

## Worked example — platform-sandbox, 2026-11-09

24.4 KB → 7.7 KB (budget 16 KB).

- Moved to new domain files, then pruned by rediscovery cost: `external-secrets.md` (kept: PushSecret template merge, estate store models), `vault.md` (kept: orphan-token grant tests, `required_parameters` gating reads), `datadog.md` (kept: tag-flip carry-forward, sparse monitors). Dropped: ESO ≥ 2.4 caProvider (in D59), store Ready without auth, Vault `..` 307 (enforced + ADR-0011), TLS reload, audit stall (ADR-0003), per-org Datadog tags.
- Merged into existing domain files: atomic-list API defaults → `kubernetes.md`; Deny-on-UPDATE finalizer → `kyverno.md`.
- Wiki: docs reference chain → `wikis/vault-docs-reference-chain.md`.
- Removed as duplicated: domain and skill pointers, the initiative pointer (in Related Projects), What It Is restated in Architecture Decisions, the kyverno-validate rule (in the skill's description).
- Removed as derivable: commit/branch naming, EC2-vs-EKS, kube-state-metrics allowlist, pull-through registry prefixes, ADR-0007 status.
- Removed as stale: Vault-node `do-not-disrupt` gotcha. Corrected: rds-manager "Updated user" claim. Hand-kept list replaced by the rule: per-appset prune flags (the list was missing three appsets).

## Open design questions for the task

- Where it lives: a second pass in the `auditor` agent, a separate `pruner` agent, or a `/lint-memory --prune` mode.
- Output: verdict table only (user applies by number), as `skill-audit` does — never auto-delete.
- Whether domain files get the same pass on their own budget.
