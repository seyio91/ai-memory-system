# Reviewer: Helm charts (`helm` · `helmv3` · `helm_release`)

Loaded by `SKILL.md` (Phase 4 dispatch) for Helm-chart Renovate bumps. Receives
the **reviewer input** and returns the **reviewer output** defined in SKILL.md.
The dispatcher has already extracted `{package, type, current→target, upstream}`
from the PR body table; this reference does config-locus discovery, upstream
release analysis, and impact analysis.

Per SKILL.md Phase 4 this runs as two parallel subagents (executors):
**Analyzer** = the *Config-source adapter* below; **Upstream** = the *Upstream
release analysis* below — **skipped on a chart-memory cache hit** (exact
`<current>→<target>` range already in `helm/charts/<chart>.md`). The dispatcher
combines them for the impact analysis, verdict, and memory write.

## Config-source adapter (by `type`)

The dispatcher gives you the bumped chart's `{chart, current→target}` and the
diff. Find the **config in use** — the values this repo actually sets for the
chart — by the `type`. Derive every location from the diff/repo; never assume a
fixed layout.

### `helm` / `helmv3` — Kubernetes Chart.yaml dependency
1. Locate the changed `Chart.yaml` (and `Chart.lock`) in the diff → take its
   directory as the deployment dir (do **not** assume `deployments/<name>/`).
2. Read that `Chart.yaml`; glob sibling values relative to it — `values/*.yaml`,
   `values*.yaml`, and any `applicationset.yaml`/`application.yaml` that supplies
   inline `helm.values`/`valueFiles`.
3. "Config in use" = the keys those values files set.

### `helm_release` — Terraform-managed Helm
1. The bump is a chart **version** in `.tf` — usually a `variable`/`local`
   default, or `helm_release { version = … }` directly (confirm via the
   `# renovate: datasource=helm depName=<chart> registryUrl=<repo>` annotation on
   the changed line).
2. In the same module, find the `resource "helm_release"` whose `version`
   resolves to that var/local (match by `chart = "<chart>"` / `name`).
3. "Config in use" = read **literally**, in this order:
   - inline `set { name = … value = … }` / `set_sensitive { … }` blocks,
   - `values = [ <heredoc/yaml literal> ]` entries (literal YAML only),
   - the `helm_release` arguments (`namespace`, `create_namespace`, `atomic`,
     `wait`, etc.) and the variable **defaults** behind any `var.*` it passes.
4. **v1 boundary:** do not resolve `templatefile()`, `file()`, `locals`
   indirection, or `var.*` chains beyond their literal default — if values come
   through `templatefile(...)`, record "values supplied via templatefile —
   not resolved (v1)" so the impact analysis is honestly scoped.
5. **Render-fixture escape hatch (prefer when present — resolves the v1 boundary
   above).** If the module ships a **provider-less render fixture** — a
   `tests/render/` (or similarly named) root module whose `output`s wrap the same
   `templatefile(...)` calls and that emits static `rendered/*.yaml` (often a
   `render.sh`; look for a `tests/render/README.md`) — use those rendered files as
   the config in use. **Search the whole repo, not just the changed module's dir:**
   the fixture is commonly a **repo-root** `tests/render/` root module that renders
   many modules at once, so a search scoped to `<module>/` will miss it. It may also
   be **uncommitted/untracked** — check the working tree (e.g. `git status`/`find`),
   not only the committed/PR tree. If you can't reach it (absent, or it lives
   outside the checkout), say so and fall back to the literal template read with
   confidence scoped accordingly — don't silently skip the lookup. When found,
   treat the module as the `helm`/values-file case (§"config
   in use" = the keys those files set). Read the committed `rendered/*.yaml` if
   present; if absent or stale, regenerate non-mutatingly per the fixture's
   README — `terraform -chdir=<fixture> init -backend=false && apply -auto-approve
   && terraform -chdir=<fixture> output -raw <output> > <fixture>/rendered/<name>.yaml`
   (zero resources, no providers, no live state — execpolicy-clean). The fixture
   is rendered with a kitchen-sink input set, so its keys are the **maximal**
   surface to diff against upstream `values.yaml`/`values.schema.json`. Pattern
   detail: domain memory `terraform` (`[2026-06-15]`).

### `argocd` — ArgoCD Application / ApplicationSet manifest
1. The bump is a chart **`targetRevision`** in a changed `Application`/
   `ApplicationSet` manifest, on a `spec.source`/`spec.sources[]`/
   `spec.template.spec.source(s)` entry that has `chart:` + a Helm `repoURL:`
   (e.g. `repoURL: https://…/helm-charts/`). The chart name is that source's
   `chart:`; the repo is its `repoURL:`.
2. "Config in use" = the **`helm:` block on that same source**. Check, in order:
   - `valuesObject:` / inline `values:` — read literally;
   - `parameters:` — literal key/value overrides;
   - `valueFiles:` — resolve and read each (next step).
3. **Resolve `$values/…` valueFiles.** `$values` is the sibling `- ref: values`
   source; in the common ApplicationSet pattern it points at the **same repo**
   (the addons/GitOps repo) on a templated path — so read it from the checkout.
   Substitute the generator vars in the path: `{{.values.addonChart}}` = the chart
   name (also the `releaseName`), `{{.metadata.labels.environment}}` = each env.
   Typical layout (confirmed in `revvingadmin/kubernetes`):
   - base: `environments/addons/<chart>/default/values.yaml`
   - per-env overlays: `environments/addons/<chart>/environments/<env>/values.yaml`

   Read base + overlays as the config in use; `ignoreMissingValueFiles: true` means
   a missing overlay is fine. Also read **`skipCrds:`** on the `helm:` block —
   `false` (default) means ArgoCD applies the chart's CRDs (mitigates CRD-upgrade
   risk, especially with `ServerSideApply=true`); `true` means CRDs are NOT managed
   → CRD changes in the release become ACTION REQUIRED.
4. **v1 boundary:** if `$values` points to a **different** repo not in the
   checkout, or a path var can't be resolved, record "values via external
   `$values` ref — not resolved (v1)" and scope confidence accordingly.

## Upstream release analysis

The chart upstream is (almost always) a GitHub repo, regardless of the PR host.
Use `upstream_link` from the body table when present; otherwise auto-detect from
the chart repo URL / `# renovate: registryUrl=…`:

- `ghcr.io/<org>/charts/<name>` → `<org>/<name>`
- `ghcr.io/<org>/charts` (name absent) → `<org>/<chart_name>`
- `ghcr.io/<org>/<name>` → `<org>/<name>`
- otherwise search GitHub for "`<chart_name>` helm chart".

Fetch the target release page (try tags `v<target>`, `<target>`,
`<chart_name>-<target>`); the chart version and app/image version may differ, so
fall back to the releases list to map chart version → tag.

**Boilerplate-release fallback:** some chart repos (e.g. `aquasecurity/helm-charts`)
publish uninformative release bodies (a one-line blurb) and skip some tags. When
the chart-repo notes carry no real changelog, resolve the chart's `appVersion`
(from the chart's `Chart.yaml` at each boundary) and read the **underlying app
repo's** changelog instead (e.g. trivy-operator chart → `aquasecurity/trivy-operator`).
Note the chart→app indirection in the report.

Intermediate releases (between current and target, exclusive): from
`gh api repos/<owner>/<repo>/releases --paginate`, scan each body for
`breaking · deprecated · removed · migration · renamed · incompatible · "BREAKING CHANGE"`
and report only those that match; from ALL intermediate releases extract new
features / options / improvements with the version that introduced each.

If the upstream isn't GitHub (rare) or auto-detect fails, use the `override-url`
the dispatcher passed, or ask the user for the release URL.

## Impact analysis (against config in use)

1. **Values-key matching** — do the release notes mention keys present in the
   config in use (helm: values files; helm_release: `set`/`values`/var-defaults)?
   Flag any renamed, removed, or default-changed key this repo relies on. For
   helm_release where values come via unresolved `templatefile()` (v1 boundary),
   say so and downgrade confidence — you can't see those keys.
2. **Adoptable improvements** — mine target + intermediate releases for new
   values/options/security/perf features; for each, note version, automatic-vs-
   values-change, and a concrete snippet (a `values:` key for helm, a `set {}` /
   `values` entry for helm_release).
3. **CRD changes** — scan for `CRD`/`CustomResourceDefinition`/`API version`.
   CRDs often need applying before the chart upgrade → ACTION REQUIRED. Note the
   apply path differs: ArgoCD/helm deployments apply via GitOps; helm_release
   applies via the Terraform `helm` provider on the next apply (CRDs may need
   `skip_crds`/manual handling there).
4. **Deprecation tracking** — features in use that upstream is sunsetting.
5. **Breaking-pattern check (project memory)** — if the project-tier memory
   (`helm/projects/<project>/<unit>.md`, loaded by Subagent A) exists: do any changes in
   this range match a previously-recorded **breaking-change pattern** for this
   deployment? Re-flag matches. Conversely, has a previously-problematic area been
   fixed in this release? Also cross-check the stored **configuration profile**
   against the live config in use — if they diverge, the deployment changed since
   the last review (note it; it feeds the memory update).

Return the findings as the SKILL.md reviewer output; SKILL.md assigns the verdict
and writes memory (including any new breaking pattern to the project tier).

## Memory payload (package + project tiers)

Return the payload for both tiers; SKILL.md writes them. **Templates, keying, and
update discipline: `references/memory.md`.**

- **Package tier** → `helm/charts/<chart>.md`: identity (chart, repo, upstream),
  per-version-range upstream analysis (changelog, intermediate flags, features),
  which projects reviewed which ranges, and upstream quirks. A cached exact range
  lets a future review skip the release fetch entirely.
- **Project tier** → `helm/projects/<project>/<unit>.md`: the deployment's configuration
  profile (values / set-values / features in use), breaking-change patterns seen
  here, and a review-history line.
  - **Skip the project tier when the `helm_release` lives in a reusable Terraform
    module** (a module-library repo like `terraform-modules`), not a concrete
    deployment. There the "config in use" is only module **defaults** /
    consumer-supplied `var.*` — not a real deployment's values — so there's nothing
    durable to profile. Record the **package tier only** (the upgraded chart),
    exactly like the terraform managers. Build the project tier only for `helm`/
    `helmv3`/`argocd` bumps in an actual **deployment/GitOps** repo, where the unit
    is a real deployment whose values are fixed.
