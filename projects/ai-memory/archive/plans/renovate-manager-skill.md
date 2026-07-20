---
plan: renovate-manager-skill
status: done
created: 2026-06-14
completed: 2026-06-14
owner: claude (orchestrator)
supersedes: reconcile-review-renovate-pr
---

# Plan — Restructure the renovate review skill into `renovate-manager` (helm + terraform reviewers, multi-provider)

## Goal
The `review-renovate-pr` skill was authored for an earlier memory system (a previous engagement), is GitHub-only, and assumed a single chart-source surface — a `Chart.yaml` dependency bump under the `deployments/<name>/` layout. In reality Renovate manages several dependency classes across the user's repos and providers: Helm charts via `helm`/`helmv3` (Chart.yaml) and `helm_release` (Terraform), and Terraform `module`/`provider` version bumps. The Renovate PR **body table** exposes a uniform `{Package, Type, current→target, upstream}` for every one of them (confirmed on Bitbucket PRs #84 helm_release and #78 terraform module), so a single dispatcher can route by `Type`. This plan restructures the skill into **`renovate-manager`**: a shared, provider-agnostic pipeline (parse → dispatch → verdict/report/memory) plus per-manager `references/{helm,terraform}.md` reviewers, with review memory stored inside the skill dir, split by manager. Read-only, orchestrator-invoked throughout.

## Success criteria
- Skill renamed `review-renovate-pr` → `renovate-manager` in the canonical store; harness symlinks re-pointed; `name`/`description`/frontmatter updated for the broader scope (helm + terraform). The old name no longer resolves.
- `SKILL.md` is a shared **dispatcher**: infer provider from the PR URL host → fetch PR body+diff → parse the Renovate body table for `{package, type, current→target, upstream}` (diff / `# renovate:` annotation fallback) → dispatch on `Type` → run the matching reference → shared verdict/report/memory. No manager-specific impact logic remains in `SKILL.md` itself.
- `references/helm.md` reviews `helm`/`helmv3` (Chart.yaml + sibling `values/*.yaml`) and `helm_release` (Terraform: surface `set`/`values` blocks + variable defaults; **templatefile resolution explicitly deferred**). Upstream = Helm chart GitHub releases.
- `references/terraform.md` reviews `module` and `provider` bumps: fetch the upstream upgrade guide/CHANGELOG (Registry source link → GitHub releases/UPGRADE.md), flag breaking input/output/attribute changes against the **inputs the caller actually sets** (module-block args / provider config in use), and provider version-constraint implications.
- The terraform reviewer's primary breaking-change check is **runnable**: at the PR's head (bumped version), run `terraform init` + `terraform validate` (+ `terraform fmt -check`) against the module's **`examples/` folder**, and surface the result in the verdict (validate failure → ACTION REQUIRED). Read-only — no `plan` against real state, no `apply`; execpolicy-allowed.
- Scope is decided by the body-table `Type`: `helm|helmv3|helm_release|module|provider` in scope; other types (`docker`, `github-actions`, …) declined with a clear "unsupported manager" notice. Future surfaces (Flux `HelmRelease`, Helmfile, Kustomize `helmCharts`, terraform `required_version`) listed as not-yet-supported.
- Review memory lives inside the skill dir, gitignored, **split by manager**: `renovate-reviews/helm/{charts/<chart>.md, <project>/<unit>.md}` and `renovate-reviews/terraform/{modules/<module>.md, providers/<provider>.md, <project>/<unit>.md}` — package-level (cross-repo upstream analysis) + project-level (caller-config-specific) tiers within each.
- Project/unit memory keyed by **project name** (reverse-map `repo`/`repo_path`) + the bump's module/path; never the raw PR-URL slug; never written to injected files or `index.md`.
- Invocation parses PR URLs for GitHub/Bitbucket/Azure (provider inferred from host); the body+diff fetch issues provider-correct **read-only** commands (gh / bkt / az + base-head `git diff`); none collide with the execpolicy deny-list.
- Validation: PR #84 (helm_release/Bitbucket) and PR #78 (terraform module/Bitbucket) both run end-to-end to a verdict; plus one GitHub Chart.yaml PR and one `provider` bump if a live PR exists. Surfaces without a live PR are dry-inspected and the gap noted.

## Design
Chosen approach — decompose into a **dispatcher skill + per-manager reference reviewers** (the established skills `references/` pattern, like excalidraw — not separate invocable skills). The Renovate **PR body table** is the universal identity surface that makes one dispatcher viable across managers *and* providers. Layered pipeline:
1. **Provider layer** (SKILL.md): infer provider from URL host; fetch PR body + diff via gh/bkt/az.
2. **Identity layer** (SKILL.md): parse body table → `{package, type, current→target, upstream}`; diff / `# renovate:` fallback.
3. **Dispatch** (SKILL.md): `Type` → reference; unsupported → decline.
4. **Reviewer layer** (references/*.md): domain impact analysis — where release notes live + what "config in use" means.
5. **Shared output** (SKILL.md): verdict rubric, report format, memory update (manager-split store).

Why it composes: PRs #84 and #78 show identical body-table shape; only `Type` and the config-locus differ. So the shared core absorbs provider + parsing + memory + verdict, and each reference holds only its domain methodology. New managers later = drop a reference file + a memory subfolder.

Sequence: **rename+skeleton → memory layout → helm reference (port) → terraform reference (greenfield) → providers → validate.** Build the dispatcher + helm reference first (port/repair existing logic), then the greenfield terraform reviewer, then provider generalization (cheap once identity-extraction is uniform), then validate on the two real PRs.

Alternatives considered:
- Separate invocable skills per manager → rejected: duplicates provider/body-table/memory plumbing; one dispatcher + references shares it.
- Per-surface diff parsing for identity → rejected: the body table carries `{package, type, range, upstream}` uniformly; parse it first, diff only for config-locus + annotation confirmation.
- Fold `helm_release` into the terraform reviewer because it lives in `.tf` → rejected: it's a *Helm chart* review by domain; `Type=helm_release` routes it to `helm.md`.
- Resolve `templatefile()` for helm_release values → deferred (v1 surfaces literal `set`/`values`/var-defaults only).
- Store memory under the memory root or per-project → rejected earlier: inside the skill dir for portability, gitignored.

## Decisions (locked)
- Skill = `renovate-manager` (renamed); dispatcher + `references/{helm,terraform}.md`; one trigger, shared plumbing.
- Identity from the Renovate PR body table first; diff / `# renovate:` annotation is the fallback.
- Dispatch + scope by body-table `Type`. v1 in scope: `helm`, `helmv3`, `helm_release`, `module`, `provider`. Behind a reference-file seam.
- `helm_release` impact = surface `set`/`values`/var-defaults only; templatefile resolution deferred.
- Terraform reviewer covers `module` + `provider`.
- Terraform breaking-change verification = `terraform init` + `validate` (+ `fmt -check`) against the module's `examples/` folder at the bumped version. No `apply`, no `plan` against live state. (Consistent with identity's "always fmt+validate" rule; execpolicy allows init/validate/fmt/plan, forbids apply/destroy.)
- "Read-only review" carve-out: non-mutating *validation* commands (terraform init/validate/fmt, helm template/lint) are permitted; repo files, PR state (merge/approve/comment), and running infra are never touched.
- Read-only, orchestrator-invoked; provider calls read-only and execpolicy-clean.
- Memory inside the skill dir, gitignored, split `renovate-reviews/{helm,terraform}/`; package-tier + project-tier within each; project keyed by reverse-map + module/path.
- Provider inferred from URL host (system-wide inference decision).
- Package upstream analysis stays GitHub/Registry-oriented; release-URL override is the non-GitHub fallback.

## Phases
### Phase 1 — Rename + dispatcher skeleton
- Rename canonical dir `skills/review-renovate-pr` → `skills/renovate-manager`; re-point harness symlinks via `link-skills.sh`; move the in-flight `.gitignore`. Update `name`/`description`/frontmatter (broader scope; align to the `metadata:` convention).
- Rewrite `SKILL.md` as the shared pipeline: provider infer → fetch body+diff → parse body table → dispatch on `Type` → (reference) → verdict/report/memory. Strip manager-specific impact logic into references.
- Define the body-table parse spec, the `Type`→reference routing table, and the decline path for unsupported types.

### Phase 2 — Memory layout
- Implement the skill-dir store split by manager: `renovate-reviews/helm/…`, `renovate-reviews/terraform/…`; package-tier + project-tier templates per manager.
- Re-key the project tier by project name (reverse-map) + module/path; retire "workspace". Confirm `.gitignore` covers the whole `renovate-reviews/`.
- No injected-file or `index.md` writes.

### Phase 3 — references/helm.md (port + repair)
- Port the existing Helm impact analysis into the reference: chart-source adapter — `helm`/`helmv3` (Chart.yaml dir + sibling `values/*.yaml`) and `helm_release` (TF `set`/`values`/var-defaults, no templatefile). Upstream = Helm chart GitHub releases (existing Subagent B logic). Verdict rubric shared from SKILL.md.

### Phase 4 — references/terraform.md (greenfield)
- New reviewer for `module` + `provider` bumps: from the body-table source link, fetch the upstream upgrade guide/CHANGELOG/releases (Registry → GitHub); identify breaking input/output/attribute changes; match against the inputs the caller sets (module-block args / provider config); provider constraint implications. Package-tier memory = `modules/<module>.md` / `providers/<provider>.md`.
- **Runnable check:** locate the module's `examples/` folder; at the PR head, `terraform init` + `terraform validate` (+ `fmt -check`) there; feed pass/fail into the verdict. Handle the no-`examples/`-folder case (fall back to doc analysis + note the gap). Define checkout strategy (PR head branch) and that no backend/credentials are required for `validate`.

### Phase 5 — Provider generalization
- URL parsing + host→provider inference (github/bitbucket/azure); per-provider body+diff fetch (gh / bkt / az + base-head `git diff` for Azure). Read-only, execpolicy-clean.

### Phase 6 — Validate
- `helm_release`: PR #84 (Bitbucket). `module`: PR #78 (Bitbucket) — including `terraform init`+`validate` against the bumped module's `examples/` folder. `Chart.yaml`: a GitHub PR if available. `provider`: a live PR or dry-inspect. Run each end-to-end to a verdict; check criteria with evidence.

## Risks / open questions
- **Terraform reviewer is greenfield** — upgrade-guide discovery varies per module/provider (UPGRADE.md vs CHANGELOG vs release notes); the "could not be looked up" Renovate warning means the body source link may be absent → fall back to the Registry/`source` in the diff.
- **`terraform validate` against examples** needs `terraform init` (network: downloads the module + providers at the new version) and assumes the module ships an `examples/` folder; `validate` is offline/credential-free but `init` is not. No `examples/` → degrade to doc analysis. `validate` catches input/constraint/syntax breakage, not runtime or plan-time destruction (which would need `plan` against real state — out of scope).
- **"Config in use" without indirection** — helm_release and terraform both read the caller's literal args; v1 does not resolve `templatefile`, `locals`, or var chains, so impact analysis is shallower where values are indirected.
- **Azure PR-diff has no native CLI** — base/head `git diff` against a local checkout (provider-layer risk).
- **Renovate body-format dependency** — a repo that customizes/disables the PR body table forces the diff+annotation fallback.
- **Rename churn** — re-symlink across all harnesses; ensure no lingering reference to the old skill name.
- **Reverse-map coverage** for project keying; unpinned repo → degrade to URL slug + warn.
