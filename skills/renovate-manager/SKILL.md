---
name: renovate-manager
description: >-
  Review Renovate dependency-update PRs across GitHub, Bitbucket, and Azure
  DevOps. Dispatches by Renovate manager type to a per-domain reviewer — Helm
  charts (helm/helmv3 Chart.yaml deps and Terraform helm_release) and Terraform
  module/provider updates. Parses the PR, analyzes impact against the consuming
  config, runs non-mutating validation where applicable, and produces a
  structured verdict. Read-only: never approves, merges, comments, or applies.
  Use when the user passes a Renovate PR URL or says "review renovate PR",
  "renovate upgrade", "helm chart update PR", or "terraform module/provider update".
metadata:
  tier: target-read-only
  domain: platform
  lifecycle: run
---

# Renovate Manager — PR Review Dispatcher

Reviews Renovate-generated pull requests and routes each to the right domain
reviewer by **Renovate manager type**. The shared core here handles everything
that is the same across managers and git providers — parsing, provider
abstraction, the verdict rubric, the report format, and the review-memory store.
The per-domain methodology (what release notes to read, what "config in use"
means, how to verify) lives in `references/<manager>.md`.

The goal per domain is one question: **if this update merges, what breaks, and
what should the reviewer know or do first?**

## Scope & dispatch

Routing is decided by the `Type` column of the Renovate PR body table — never by
the repo or the file layout.

| Renovate `Type`              | Reviewer                  |
|------------------------------|---------------------------|
| `helm`, `helmv3`             | `references/helm.md`      |
| `helm_release`              | `references/helm.md`      |
| `argocd`                     | `references/helm.md`      |
| `module`, `provider`         | `references/terraform.md` |

`helm_release` (in `.tf`) and `argocd` (a chart `targetRevision` in an ArgoCD
Application/ApplicationSet manifest) are both **Helm chart** reviews — they route
to `helm.md`, not `terraform.md`.

**Out of scope (decline):** any other type — `docker`, `github-actions`, `npm`,
`pip`, etc. Emit a one-line notice and stop (see Phase 4).

**Not yet supported (future references):** Flux `HelmRelease`, Helmfile, Kustomize
`helmCharts`, Terraform `required_version`.

## Read-only contract

**DO NOT:**
- Modify any repository files.
- Approve, merge, decline, or comment on the PR (unless the user explicitly asks).
- Apply or mutate running infrastructure: `terraform apply`/`destroy`,
  `kubectl apply`, `helm install`/`upgrade`, `argocd` sync, or `terraform plan`
  against live state/credentials.

**DO (non-mutating analysis + validation only):**
- Fetch and read the PR (body, diff, files) and the consuming config.
- Fetch upstream release notes / changelogs / upgrade guides.
- Run **non-mutating validation**: `terraform init`/`validate`/`fmt -check`
  against a module's `examples/` folder; `helm template`/`lint`.
- Write review memory under this skill's own directory (see Memory store).
- Produce a verdict and recommendations.

## Pipeline

### Phase 1 — Parse input & detect provider

Args: `<PR-URL> [override-url]` (the optional second arg overrides the upstream
release/source URL for the reviewer).

Infer the git provider from the PR URL host (consistent with the system-wide
host→provider inference):

| Host                                   | Provider       | CLI            |
|----------------------------------------|----------------|----------------|
| `github.com`                           | `github`       | `gh`           |
| `bitbucket.org` (and Bitbucket DC host)| `bitbucket`    | `bkt`          |
| `dev.azure.com`, `ssh.dev.azure.com`   | `azure-devops` | `az repos`     |

Parse the PR coordinates from the URL per provider:
- github: `github.com/<owner>/<repo>/pull/<n>`
- bitbucket: `bitbucket.org/<workspace>/<repo>/pull-requests/<n>`
- azure: `dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/<n>`

If the URL matches none, ask the user for a valid PR URL.

### Phase 2 — Fetch PR metadata (orchestrator stays lean)

The orchestrator loads **only what it needs to identify and route**: the PR
**body** (the small Renovate `Package | Type | … | Change` table) and, when the
body lacks `Type`, the **changed-file paths** (names only). It does **NOT** load
the full diff, clone the repo, run `terraform validate`, or fetch release notes —
those are large and belong to the Phase-4 subagents. This footprint discipline is
the whole point of the fan-out: keep heavy artifacts out of the orchestrator
context (see Phase 4). All commands are read-only and execpolicy-clean.

**Body (small):**
- github: `gh pr view <n> --repo <o>/<r> --json title,body,baseRefName,headRefName,files`
- bitbucket: `bkt pr view <n> --repo <r> --workspace <ws>`  (needs `bkt auth status`)
- azure: `az repos pr show --id <n> --output json`  (`.description` + base/head refs)

**Changed-file paths only** (just to infer `Type` if the body omits it — never the diff body):
- github: the `files` field above
- bitbucket: `bkt pr diff <n> --repo <r> --workspace <ws> | grep '^diff --git'`  (pipe so only paths return)
- azure: `git diff --name-only <base>...<head>` in a throwaway checkout

### Phase 3 — Extract identity from the Renovate body table

The Renovate PR body contains a markdown table with columns
`Package | Type | Update | Change` (a `[source](…)` upstream link often accompanies
the package). Parse each row into:

```
package         = the dependency name (chart name, or module/provider address)
type            = the Renovate manager (helm | helmv3 | helm_release | module | provider | …)
current_version = left side of "X -> Y"
target_version  = right side of "X -> Y"
update          = major | minor | patch | digest | …
upstream_link   = the [source] URL if present
```

Multi-row PRs: review each in-scope row; skip rows whose `Type` is out of scope.

**`Type` column absent** (common — many repos' Renovate config emits only
`Package | Update | Change`): the table still gives package + version range; infer
`type` from the diff's changed file(s) and the package's `[source]` link:
- changed `Chart.yaml` `dependencies:` block → `helm`/`helmv3`
- changed `.tf` with a Helm-chart version (`# renovate: datasource=helm`, a
  `helm_release`, or a chart-version variable) → `helm_release`
- changed **ArgoCD `Application`/`ApplicationSet` manifest** — a `targetRevision`
  under a source with `chart:` + a Helm `repoURL:` → `argocd`
- changed `.tf` `module "…" { source/version }` → `module`; changed
  `required_providers { … version }` → `provider`
- a `helm-charts`/`*.github.io/helm-charts` source link signals a Helm chart;
  `registry.terraform.io` signals Terraform.

**Identity fallback** (body table missing or incomplete — e.g. Renovate's "Some
dependencies could not be looked up" warning): recover from the diff —
- helm/terraform annotations: `# renovate: datasource=… depName=… registryUrl=…`
- the changed version line (`version = "X"` / `version: X` / `targetRevision: X`),
  and for Chart.yaml the `dependencies:` block (`name`, `version`, `repository`).

### Phase 4 — Scope gate, then review via parallel subagents

**Scope gate:** look up `type` (inferred per Phase 3 if the table omits it) in the
routing table. Unsupported → print
`Unsupported Renovate manager "<type>" — renovate-manager reviews helm/helmv3/helm_release/argocd and terraform module/provider. Skipping.`
and stop. Supported → load `references/<manager>.md` and run the review as up to
**two parallel subagents**.

**Subagents are dispatched as this project's read-only executors** — primary:
Codex **`codex-mem.sh --executor-bare`** (the `-bare` variant strips the AGENTS.md
memory stack — ~13k tokens — which a read-only review doesn't need; the deny-rules
guardrails still apply); fallback: a Claude `Agent` subagent (`sonnet`/`haiku`),
which is also memory-free and equally lean. Both are **read-only**
(fetch/read/`terraform validate` only; never merge, comment, or apply). This is the
original skill's Subagent A/B fan-out, gated by package memory so the upstream
fetch is skipped when cached.

**Subagent housekeeping:** clone into a **workspace-relative** temp dir (e.g.
`./tmp-sub/...`, not `/tmp`) and clean up with **`rm -r`** — the executor sandbox
policy blocks `rm -rf`.

**Why subagents — context discipline (the main reason they exist).** The
token-heavy work — fetching the **full PR diff**, **cloning/checking out** the
repo, running **`terraform init`/`validate`** (verbose logs), and fetching
**release notes / changelogs / upgrade guides** (large JSON/markdown) — happens
**inside the subagent**, never in the orchestrator. Each subagent returns **only
its slice of the compact reviewer-output contract** (a few structured bullets) —
**not** the raw diff, clone tree, validate logs, or release JSON. The orchestrator
only ever holds: the small body table (identity), the cache-gate lookup, and the
subagents' distilled findings. Do **not** inline these fetches in the main thread.

#### Subagent A — Analyzer (always)
**Fetches the heavy artifacts itself** — the full PR diff (provider diff command)
and, where needed, a clone/checkout of the PR head — runs the reference's
**config-source adapter**, and for terraform clones the head and runs
`terraform init -backend=false` + `validate` on **every affected folder's**
example. Returns **only** the compact result: the **config in use**
(values/inputs), the changed unit/module path(s), and the validate outcome(s) —
**never the raw diff, clone tree, or validate logs**. Dispatch immediately — do
not wait on the cache check.

**Helm only — load the project-tier memory** for comparison (the project analogue
of the package cache-gate — read to *compare*, not to skip): resolve the project
**from the PR repo URL** via the reverse-map (every project maps 1:1 to a repo).
**If the repo doesn't resolve to a project, ask the user** — do not assume or
slugify (see `references/memory.md`). Then read `helm/projects/<project>/<unit>.md` if it
exists and return its stored **configuration profile** + **breaking-change
patterns**; a missing file means **first review** → Phase 5 builds it.

**Terraform has no project tier.** The review concerns the *component being
updated*, not the module consuming it — so the consuming module(s) are only
**`terraform validate` targets**: Subagent A validates **each affected folder's
`example/`** (every module dir whose `.tf` changed for this dependency) and returns
the per-consumer results, which Phase 5 records in the **package tier**.

#### Subagent B — Upstream (conditional, cache-gated)
**Fetches the release notes / changelog / upgrade guide itself** (large
JSON/markdown) and runs the reference's **upstream analysis**, returning **only**
the compact result — changelog summary + flagged breaking changes + features —
**not** the raw release payloads. **Before dispatching, check the package-memory
cache to maybe eliminate B:**
1. You already have `{package, current→target}` from the Phase 3 body table — no
   extra diff needed (the original needed one only because it didn't parse the
   table).
2. Read the package-tier file — `helm/charts/<chart>.md` or
   `terraform/{modules,providers}/<addr>.md`.
3. If it has a **Reviewed versions** entry for the exact `<current> → <target>`
   range → **skip Subagent B**; reuse the stored upstream analysis (at write time,
   just append this project + refresh the date on that entry).
4. Else — or no file, or a release/source-URL override was passed → **dispatch B**.

Dispatch A and B (when B is needed) in a **single parallel batch**.

#### Reviewer contract (the subagents' combined I/O)

**Input:** `{ provider, repo_coords, pr_number, package, type, current_version,
target_version, update, upstream_link, diff_text, repo_checkout (if available) }`

**Output (structured):**
- `changelog_summary` — 3-5 bullets on the target release (from B or cache).
- `flagged_breaking` — breaking changes / deprecations / removals in the range
  (with the version that introduced each), or "None".
- `impact_on_config` — how the changes interact with the config this repo actually
  uses (reference real keys/inputs), or why there's no impact.
- `suggested_changes` — actionable items required before merge, or "None".
- `adoptable_improvements` — new options/features worth adopting (with a concrete
  snippet), or "None".
- `validation` — result of any runnable check (e.g. `terraform validate`), or "n/a".
- `verdict_input` — recommendation toward the shared rubric.
- `memory_payload` — package-tier + project-tier updates.

### Phase 5 — Combine, verdict, report, memory (shared)

Combine Subagent A's config-in-use with B's (or the cached) upstream analysis, run
the reference's **impact analysis**, then:

**Verdict rubric** — assign exactly one:
- **APPROVE** — no impact on the consuming config; no breaking changes anywhere
  in the upgrade range; any runnable validation passed. Safe to merge as-is.
- **APPROVE WITH NOTES** — safe to merge, but noteworthy changes exist
  (deprecations for unused features, adoptable improvements, security fixes,
  project announcements).
- **ACTION REQUIRED** — do not merge without addressing: breaking changes
  affecting config in use; renamed/removed keys/inputs the repo sets; CRDs needing
  manual apply; **a failed `terraform validate`** on the bumped version.

**Report format** (shared skeleton; the reviewer fills the domain sections):

```
## Renovate Review: <package>  (<type>)
### <current_version> → <target_version>  [<update>]  | <repo> via <provider>
### Upstream: <upstream_link or resolved repo>

### Verdict: [APPROVE | APPROVE WITH NOTES | ACTION REQUIRED]
<1-2 sentence justification>

### Changelog Summary
### Flagged Breaking Changes / Deprecations
### Impact on This Repo's Config
### Validation
### Suggested Changes
### Adoptable Improvements
### Analysis Source        (fresh fetch | reused from package memory <date>)
### Memory Updated
```

**Memory update (both tiers, compare-then-merge)** — write the reviewer's
`memory_payload` to the manager-split store (see below):
- **Package tier** — record the upstream analysis for this range (or, on a cache
  hit, just append this project + refresh the date). **Terraform:** also record the
  per-consumer `terraform validate` results under **Validated consumers**.
- **Project tier — helm only** (`helm/projects/<project>/<unit>.md`):
  - **First review (file absent) → build it** per `references/memory.md` → "First
    review (helm)": create from the template, populate the configuration profile
    from Subagent A's observed values, seed history. **Ask the user for anything
    you need and can't derive** (unresolved project, ambiguous unit, required
    deployment context) — never assume.
  - **Subsequent reviews → compare-then-merge, don't blind-overwrite:** update the
    configuration profile only where the observed config differs from what's
    stored; **append** a review-history line (`<current> → <target> on <date>:
    <verdict>`); **add** any newly-observed breaking-change pattern (and note a
    previously-recorded pattern resolved by this release).

Never write to injected memory files or the system `index.md`.

## Memory store (shared plumbing)

Review memory lives **inside this skill's directory** (`<skill_dir>/renovate-reviews/`),
gitignored, split by manager (`helm/`, `terraform/`). Both have a **package tier**
(reusable upstream analysis, keyed by the dependency). **Helm also has a project
tier** (`helm/projects/<project>/<unit>.md` — the deployment's config profile + history),
because helm has no runtime check. **Terraform has package tier only:** the
consuming module is a `terraform validate` target, not a memory subject — its
validate result is recorded in the package tier. Project is resolved from the repo
URL via the reverse-map (`repo`/`repo_path`); **ask the user if it doesn't
resolve — never assume**.

See **`references/memory.md`** for the full layout, the per-tier templates, the
project-key resolution, and the update discipline. **Never** write review memory
to injected memory files (`projects/*/memory.md`, `working.md`) or the system
`index.md` — this data is skill-private.

<!-- partial:self-rating START (managed by scripts/apply-partial.sh — edit scripts/partials/self-rating.md) -->
## Self-rating (first-party)

This skill participates in the self-rating loop. The rating is a signal about
**this skill's own friction** — where its instructions were unclear, slow, or
made you guess — not about the correctness of the work product (that is the
Validator's job).

**Do not rate automatically.** Append a rating **only when the user asks** for
one (e.g. "rate this run", "how did the skill do") or when you hit real friction
worth recording. Silence is the default; an empty log is a healthy log.

When you do rate, append one dated entry to this skill's own folder —
`skills/<this-skill>/self-rating.md` (the always-writable own-folder zone; never
the target repo or the system memory tree). Use this shape:

```
## YYYY-MM-DD — <one-line context>
- score: <1-5>   (1 = fought the skill, 5 = frictionless)
- friction: <what was unclear / slow / had to be guessed, or "none">
- improve: <the smallest concrete change that would raise the score, or "none">
```

Aggregate across skills with `scripts/skill-ratings.sh`.
<!-- partial:self-rating END -->
