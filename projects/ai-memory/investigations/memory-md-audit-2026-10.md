---
investigation: memory-md-audit-2026-10
project: ai-memory
status: open
created: 2026-10-07
owner: claude (orchestrator)
task_ref: trim-ai-memory-memory-md-to-the-include-leave-out-contract
---

# memory.md audit — 2026-10-07

Read-only audit of all 19 `projects/*/memory.md` against the contract in wiki
`memory-md-content-contract`, by five parallel subagents, each spot-checking claims against
`origin` of the project's repo. Consumed by initiative `memory-md-hygiene`: each project's trim
task reads its own section below. Every "stale" item was true of the repo on 2026-10-07 —
**re-verify before acting**, the tree moves.

Fleet: ~280 KB → ~90 KB estimated. Order inside every trim: **fix stale → cut → condense → move → add.**

## System findings (ai-memory system Targets)

1. No size check anywhere; platform-sandbox payload ~171 KB vs ~108 KB chunk ceiling → `working.md` tail truncated silently.
2. Write guard hand-wired in `~/.claude/settings.json`, absent from `harnesses/claude/manifest`/`install.sh`; Claude manifest has no `guard_script` (codex/copilot do).
3. Template + lint require `## Current State` / `## Current Goal` (`lint-memory.sh:74-80`); no Commands/Conventions section.
4. Base duplication: deny-list in `identity.md`, `orchestrator.md` ×2, `harnesses/claude/CLAUDE.md`, `scripts/deny-list.txt`; tiers/TaskCreate/archive rules ×2; `harnesses/claude/CLAUDE.md:66` "small items inline" contradicts the tier rule. "Reorganize memory" procedure, executor config detail and Task Contract are always-injected but rarely used. `orchestrator.md` drifted from `templates/orchestrator.template.md` undetected.
5. `check-changelog-drift.sh:39` `DATED_RE` misses `**[YYYY-MM-DD]**` written by `/promote-memory`.
6. No twice rule (`/promote-memory` promotes on first occurrence), no prune cadence.
7. Investigations `lint-memory-size-and-drift-gaps` and `on-demand-project-load` carried Notion task refs the local provider cannot resolve — re-pointed to this initiative's tasks.

## Per-project findings

### ai-memory (130 lines, 44.7 KB → ~12–15 KB)
- **Cut:** Current State release commentary; "Moving parts" inventory; architecture summaries covered by README/docs (Markdown over DB, Lean index, Codex/Antigravity adapters, Hook layer…); tests-badge incident (keep half-line); lint WARN baseline log (keep first sentence); rtk entry (fixed, duplicated in `domain/agent-tooling.md`); 1/1 no-chunking measurement; "Docs rot within hours"; lines repeating global CLAUDE.md (archive rule, git-tracked note).
- **Condense:** add_progress, design-brainstorm rename, Task Contract, plan-entry convergence, commit route (→ CONTRIBUTING.md), release automation, CI exemption, initiatives (~2 KB → stream-first rule), seven testing essays → ~4 bullets, branch-switch incident → one rule.
- **Move:** testing doctrine → new `domain/testing-discipline.md` or CONTRIBUTING; git tag/force-push facts → domain git file; Codex exec/execpolicy → `domain/codex.md`; link-skills prune rationale → code comment; Current Goal → backlog.
- **Add:** `bash scripts/run-tests.sh [--changed|--only PAT]`, `lint-memory.sh`, `check-docs.sh`, `assemble-changelog.sh`; conventional-commit scopes; commits via git-cli; CONTRIBUTING.md pointer.

### git-cli (77 lines, 24.9 KB → ~6–8 KB)
- **Stale:** L49 `-buildvcs=false` change no longer exists (restate as risk or drop); L32 "No test covers StripPlaceholders" — `internal/pr/render_test.go` covers it; `make test` lacks `-count=1`.
- **Cut:** Current State (counts, dates); package list, default models, prompt split, style list, L57–66 internals; `ghHint` wording; `Validator.Rules()` history; L48 correction log.
- **Condense:** error contract, verbatim-body rule, five prompt entries → one rule, no-merge invariant.
- **Move:** fake-`gh` capture procedure → `docs/development.md`; LiteLLM setup → `domain/git-cli.md`; Current Goal → backlog.
- **Add:** `make build` + copy to `~/.local/bin/git-cli` (`make install` targets `~/go/bin`, not on PATH); `go test -count=1 ./...`; `{type}/{slug}` branches.

### platform-sandbox (407 lines, 41 KB → ~12–15 KB)
- **Stale:** rtk `helm template` workaround (fixed; contradicts `domain/agent-tooling.md`); vmoperator ownerReferences (`enable_converter_ownership: true`); kyverno allow-list (bottlerocket etc. added); `terraform-yosama/vault.tf` deleted (`68043e2da`); crossplane label failures (addons disabled); Vault "NLB" heading vs ALB body, written as built; PR #8337 dependency; "no PR gate" imprecise.
- **Cut:** Current State; throwaway-commit advice; What-It-Is repeats; completed Kyverno observability and dashboard programme logs; 2026-09-14 diagnostic trap; SHAs/dates inside gotchas; costcenter sub-bullets.
- **Condense:** What It Is → 4–5 lines; three Kyverno-to-Grafana bullets + policy-reporter (~55 lines) → rules only; namespace-exclusion entries → one; Vault ops gotchas → ~12 lines; keep Operational handles.
- **Move:** Kyverno CEL metrics / Deny-has-no-PolicyReport / admission-only exclusions → `domain/kyverno.md`; kube-downscaler → already in `domain/kubernetes.md`, keep sandbox line only; drill-down dashboard rules → `platform-drilldown-dashboard` skill; serviceMonitor key trap → `vm-scrape-enablement` references; Vault design (~100 lines) → repo ADR / `UPSTREAM.md`; phase status → plan.
- **Add:** `type(scope):` commits, `fix/`/`feat/` branches, merge deploys live; `helm template` policy render + `kyverno-validate` pointer; `helm dependency build` note surfaced.

### platform-charts (317 lines, 21 KB → ~8–10 KB)
- **Stale:** "11 charts" + versions (12, `pxc-db` added); Current State/Goal PRs all resolved; `rabbitmq-monitors/_helpers.tpl:15` now defaults; README refactor table fixed; upgrade-doc pin is `-v2`; concurrency group shipped; tpe-migration numbers. (Side: repo `README.md:312`, `:251` stale.)
- **Cut:** ownership, extraction history, maturity list, stale branches, publish matrix, chart-releaser, role, completed work, deleted-CLAUDE.md history, refactor verification story, PR refs in 1-x section.
- **Condense:** 1-x track → ~4 lines; auto-commit race → one line; CHANGELOG-trust rule; account-ID maps → two rules; upgrade-doc skill rules.
- **Move:** live template defects + dead code + brittle regexes → GitHub issues; version-string ambiguity → `helm-chart-upgrade-document` skill; release-please `refactor:` semantics → `domain/helm.md`.
- **Keep:** release-please dry-run, dir basename = chart name, depth 2, onboarding bot commit, dismiss_stale_reviews, UPGRADE.md same PR, docs paths trigger nothing, tpe-migration collision, `networking.tp.ccv.eu/allow-*`, tunneler path, Related Projects.
- **Add:** "README.md is canonical"; `ct lint --validate-maintainers=false --charts <path>`; `helm template … -f values.example.yaml`; no test runner.

### rabbitmq-pas-service (210 lines, 37.5 KB → ~9–10 KB)
- **Stale (misleading):** "No CI" — chart-validation/release/prerelease workflows exist; `selfHeal: false` — now true; `environments/common/topology-values.yaml` gone, topology lives in `charts/pas-rabbitmq-topology` gated per env (gotcha 3 inverted); chart pins (infra 2.0.0, topology wrapper prod 0.5.0, monitors 1.1.1); "charts/ deleted"; `kpt` vhost missing; branch counts. Still true: staging broken, `policies: []`, `fail_if_no_peer_cert = false`.
- **Cut:** author line, commit count, Current State, recent stream, Current Goal, gotcha 23, eks-side gotchas 31/32/34, consumer list, supporting-k8s bullet, Open Questions → working.md.
- **Condense:** What It Is → 5 lines; decisions without counts/account IDs; keep gotchas 2,4,5,6,7,8,9,10,11,14,15,22 at 1–2 lines; producer landmines → ~4 lines linking `[[eks]]`; TLS → ~6 lines linking `wikis/tls-configuration.md`.
- **Move:** producer→consumer chain → eks / wiki; vhost/env table → `domain/environments-clusters.md` link; gotcha 7a → `domain/tagging-strategy.md`; audit-finding gotchas → TLS wiki/backlog.
- **Add:** topology release flow (values → feat/fix PR → release-please → bump `targetRevision` per env); `/prerelease charts/pas-rabbitmq-topology`; which changes need a release; local render command.

### datafactory (125 lines, 20 KB → ~7–8 KB)
- **Stale:** release tags; In-flight SHAs; local checkout on master, not dev. Still present: `push_image_to_ecr.yml` bracket bug, `sync_dev.yml` `needs.prepare` bug.
- **Cut:** scale counts, authors, provider/Glue/Aurora versions, Current State tags, In-flight 1–4, Markers, Current Goal narrative, duplicate no-ADR line.
- **Condense:** What It Is → 4 lines; CI/CD → 3 lines; hardcoded-values and table-lock gotchas to rules.
- **Keep:** branching model, env-suffix rule, upsert/UNIQUE KEY contract, backend.tf banner, non-idempotent ALTER, removed/import pair, max_concurrent_runs + bookmarks, field casing.
- **Move:** add-a-field checklist → project skill/docs; PoC teardown → working.md; workflow bugs → backlog.
- **Add:** default branch is `dev` → terraform/`kubernetes/*/envs/**` PRs need `--base master`; `feat(terraform): [TP-n]` commits; `feat|fix|chore/TP-<n>/<slug>` branches; env-prefixed release tags on master-ancestor merges; ruff 0.12.8 / black 26.1.0 / sqlfluff 3.4.2; no unit tests.

### k8s-addons (87 lines, 19 KB → ~6–7 KB)
- **Stale:** `overlay/` → `overlays/`; `generate_jobs.py` reads `parts[1]` only; no local overlay (`make deploy-local` no-ops); L38 vs L63 contradict on `MIGRATION.md` (gone); link into `archive/investigations/`; tag naming incomplete.
- **Cut:** CEL defect sweep, Datadog IaC abandonment, Prometheus→VM migration log, prod/cde audit baselines, zero-failures/outstanding/batch-1 status, PR narratives.
- **Condense:** OPA→Kyverno → 3 standing facts (end state; 5 Audit-only + `requireSSLRedirect: false` are accepted — don't propose flipping; decommission = promote tags); sandbox rows → 2 lines; L59 → 2 lines with delete-when-decommissioned marker.
- **Move:** Gatekeeper decommission runbook → plan/skill (keep namespace-deletion hazard); `kyverno apply` vs `test` mutations + toggle note → `domain/kyverno.md`.
- **Add:** `fix(<addon-dir>):` commits, `feat/`/`fix/` branches; CI test commands (`helm template … tests/values-test.yaml`, `kyverno test …/suites/<suite>/ --detailed-results`); every template needs a suite; push to master → `release.yml`, prod job moves `-cde` tag.

### tpe-kubernetes (68 lines)
- **Stale (misleading):** three gotchas copied from tpe-stacks — `*-components.yaml`/`*-gen-values.yaml`, `ap-fips`/fi30, `*-migration` RabbitMQ — false here.
- **Cut:** ~35-app list, env matrix, Current State, eks pin duplication (in eks + `domain/system-architecture.md`), "Verified <date>" stamps.
- **Add:** `kustomize build` as standard pre-edit check; "Release <date>" promotion convention + `pr-review-release` skill; yamllint/kube-linter pre-commit.

### network (30 lines)
- Unfilled template; placeholder summary pollutes `index.md`. Repo exists at `ccv-terraform/networking/network` (`CCV-Group/network`); seed from `ccv-terraform/networking/CLAUDE.md` (68 lines); sibling module `terraform-aws-ccv-network`. Or delete the project.

### inception (72 lines)
- **Cut:** Current State (in-flight list, PR numbers, RiskShield story), Current Goal (PR #2194), counts (26 roots, 157 users, ~250 import lines, KB sizes), biggest roots, provider list.
- **Add:** add-a-stack recipe; where the TFC speculative plan appears on a PR (auto-apply on merge); CCVSM branch rule as one line.

### eks (74 lines)
- **Stale:** `cluster_version` is 1.34, not 1.33.
- **Cut:** Current State (CVE, bumps, branches), module list/layout tree, ArgoCD pin gotcha (keep one copy in domain, link), "VERIFIED 2026-08-05".
- **Add:** IRSA SA numbered checklist; "check Application count after editing `argo.tf`/`*.app.yaml`".

### skill-hub (107 lines)
- **Stale:** master has 10 commits not 8; `helm-chart-upgrade-document-v2` tag exists.
- **Cut:** Current State, commit hashes in decisions, PII paragraph → one line, anything in repo `CLAUDE.md` (155 lines).
- **Add:** canonical eval schema rule; `<skill>-vN` tag procedure.

### tpe (73 lines)
- **Stale:** Current State says Keycloak migration complete; Current Goal says staging remains — resolve.
- **Cut:** dated themes/hashes, duplicate "manual per-env sync" landmine, pre-commit hook list.
- **Add:** lead rule "`terraform/{staging,tpe-staging,tpe-keycloak-staging}` edited on `staging` branch only"; `GNUmakefile` targets if used.

### myccv-terraform (48 lines)
- **Cut:** "currently untracked at session start", Current State, app/module lists, duplicated backend.tf line.
- **Add:** branch/PR convention for hand-written PRs vs auto-approved deploy PRs; `ccv-pod-identity` pin; validate-wrapper command.

### flexo (45 lines)
- **Stale:** prod `eb_env.tf:158` already passes `entra_client_id` — gotcha and Current Goal are done.
- **Cut:** branch counts, env inventory, provider pins, personal email in Lambda line.
- **Add:** Lambda layer Docker rebuild; keep-two-`main.py`-in-sync pre-PR check.

### services (55 lines)
- **Stale:** aws provider `~> 6.40.0`, not `~> 6.35`.
- **Cut:** "What it provisions" file-by-file list, provider pins, Current State.
- **Add:** promote ECR repo-path naming + prod/non-prod mirror rules; OIDC push-mapping steps.

### tpe-stacks (46 lines)
- **Stale:** `[NEEDS REVIEW]` "tracks master" false (pinned `tp-tenant-v0.1.2`); `cde` stage missing.
- **Cut:** Current State; content duplicated in repo `CLAUDE.md` (304 lines).
- **Add:** merge to master auto-applies; cross-repo ordering; link MAP tags in domain.

### modules-myccv-s3 (43 lines)
- **Cut:** upstream versions, `>= 0.14`, object-ownership default, Current State/Goal, KMS ordering stated 3×.
- **Add:** module release/tag process (TFC registry); verifying a consumer bump (diff tags, no CHANGELOG).

### account-baseline (36 lines)
- **Stale:** datadog `~> 4.12`, not `~> 3.68`; `wiz.tf` unmentioned.
- **Cut:** provider pins, PR-numbered state, Datadog/backup skip lists (in `locals.tf`).
- **Add:** link `[[landing-zone]]` for `.json.tpl`; "baseline `kms.tf` edits hit every account".

## Cross-cutting

- `backend.tf` is generated — stated in 6 project files; promote one line to `domain/terraform.md`.
- eks ArgoCD branch pins in 3 places; account-baseline KMS ordering in 3.
- Missing almost everywhere: local pre-PR check command, branch/PR convention, "merge applies" warning.
