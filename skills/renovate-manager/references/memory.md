# Review memory — store layout, templates, keying, discipline

Shared plumbing for the review memory. Loaded when a reviewer produces a
`memory_payload`. The store is **inside this skill's directory** and **gitignored**
(`.gitignore` → `renovate-reviews/`), so it travels with the skill and is never
committed when the skill is copied into a git-tracked harness.

## Resolve the store root

The store root is `<skill_dir>/renovate-reviews/`, where `<skill_dir>` is the
directory containing `SKILL.md` (the path the harness loaded this skill from —
e.g. `~/.claude/skills/renovate-manager`, which resolves through the symlink to
the canonical store; writes via either path land in the same real files).

**Never** write review memory to injected memory files (`projects/*/memory.md`,
`working.md`), to `identity.md`, or to the system `index.md`. This data is
skill-private.

## Directory layout (split by manager, two tiers each)

```
<skill_dir>/renovate-reviews/
  helm/
    charts/<chart>.md                 # package tier
    projects/<project>/<unit>.md      # project tier (helm only)
  terraform/
    modules/<module>.md               # package tier (only tier)
    providers/<provider>.md           # package tier (only tier)
```

- **Package tier** — upstream analysis, reusable across every repo that consumes
  the dependency. Keyed by the dependency itself (chart name; module/provider
  address with `/` → `__`, e.g. `terraform-aws-modules__lambda__aws.md`).
- **Project tier** — the consuming repo's config profile + review history.
  **Helm only, and only for a real deployment** — not a `helm_release` inside a
  reusable Terraform module (see "Why a module-library helm_release has no project
  tier").

### Why terraform has no project tier
A Helm upgrade's per-deployment impact depends on the values that deployment sets,
and there's no runtime check — so helm needs a recorded config profile (the
project tier). Terraform has **`terraform validate`**: whether a bump breaks a
consumer is verified empirically by validating that consumer's `example/`. So for
terraform the **consuming module is a validate target, not a memory subject** —
only the package tier (the component being updated) is recorded, and it notes
which consumer example(s) were validated and the result.

### Why a module-library helm_release has no project tier
The same logic extends to a `helm_release` that lives inside a **reusable Terraform
module** (a module-library repo like `terraform-modules`) rather than a concrete
deployment. There the values are module **defaults** / consumer-supplied `var.*`,
not a fixed deployment's config — so there's no durable config profile to record.
**Record the package tier only** (the upgraded chart), and run `terraform validate`
on the module's `example/` as the empirical check — exactly like the terraform
managers. The helm **project tier is built only for `helm`/`helmv3`/`argocd` bumps
in an actual deployment/GitOps repo**, where the `<unit>` is a real deployment whose
values are fixed in-repo.

## Keying — `<project>` (both tiers) and `<unit>` (helm project tier)

1. **`<project>`** — the project is known from the **PR repo URL**: every project
   maps 1:1 to a repo. Match the PR's remote (host + `owner/repo`) against
   `projects/<name>/memory.md` frontmatter `repo`/`repo_path` and use that
   `<name>`. Used for the helm project-tier path *and* the package-tier "Projects"
   list (cross-repo tracking) for both managers.
   - **If it doesn't resolve** (repo not pinned to a project): **do not assume or
     slugify** — **ask the user** which project this review belongs to (or to pin
     the repo with `/pin`). Proceed only with the user's answer.
2. **`<unit>`** (helm project tier only) — the deployment path that owns the bump,
   from the diff (e.g. `bootstrap/addons/trivy-operator` → `trivy-operator`).
   Slashes → `__`. Disambiguates multiple deployments of the same chart in one
   repo. If ambiguous, ask.

"workspace" terminology from the original skill is retired — keyed by **project**,
resolved from the repo URL; never the raw PR-URL slug.

## First review (helm) — build the project memory

**First, check this is a real deployment.** If the `helm_release` lives in a
reusable Terraform module (module-library repo), there is **no project tier** —
record the package tier only (see "Why a module-library helm_release has no project
tier"). The steps below apply only to `helm`/`helmv3`/`argocd` bumps in a
deployment/GitOps repo.

For **helm**, on the initial run for a `<project>/<unit>` (file absent), **build**
`helm/projects/<project>/<unit>.md` rather than skipping the project tier:

1. Resolve `<project>` from the repo URL (above) — **ask** if it doesn't resolve.
2. Create from the project-tier template; populate the **configuration profile**
   from Subagent A's observed values in use + the chart identity.
3. Leave **breaking-change patterns** as `(none yet)`; add the first review-history
   line.
4. **Ask the user for anything you genuinely need and can't derive** — never
   assume (which project if unresolved, which `<unit>` if ambiguous, deployment
   context the report depends on). Don't invent envs, purposes, or config the repo
   doesn't show.

For **terraform**, there is no project tier to build — record the component
(package tier) with the validated consumer example(s) and result.

## Templates

### helm package tier — `helm/charts/<chart>.md`
```markdown
# <chart> — Chart memory

## Identity
- Chart: <name>   |   Repo: <chart repo URL>   |   Upstream: <owner/repo>

## Reviewed versions
### <current> → <target>   (reviewed <date>)
- Projects: <project1>, <project2>
- Changelog: <bullets>
- Intermediate flags: <flags or None>
- New features: <bullets or None>

## Upstream quirks
<tag-format notes, gotchas>
```

### terraform package tier — `terraform/modules/<module>.md` · `terraform/providers/<provider>.md`
```markdown
# <address> — <module|provider> memory

## Identity
- Address: <registry/source address>   |   Upstream: <owner/repo>

## Reviewed versions
### <current> → <target>   (reviewed <date>)
- Projects: <project1>, …
- Upgrade-guide summary: <bullets>
- Breaking changes: <renamed/removed inputs/outputs/attributes, or None>
- Validated consumers: <repo/path/example → pass | fail: … >, … (or "n/a — no example")
- Adoptable inputs/features: <bullets or None>

## Upstream quirks
<provider-constraint notes, upgrade-path gotchas>
```

### project tier (helm only) — `helm/projects/<project>/<unit>.md`
```markdown
# <project> / <unit> — review memory

## Configuration profile
- Dependency: <chart|module|provider> <address>
- Config in use: <values files / set-values / module-block inputs in use>
- Features in use: <list>

## Breaking-change patterns
<patterns seen here, or "(none yet)">

## Review history
- <current> → <target> on <date>: <verdict>
```

## Update discipline

- **Package tier, new range:** add a `### <current> → <target>` block with this
  review's analysis; add the project to its Projects list.
- **Package tier, cache hit (range already recorded):** append the project to the
  Projects list if absent and refresh the `(reviewed <date>)`; reuse the stored
  analysis instead of re-fetching upstream.
- **Package tier (terraform):** record the per-consumer `terraform validate`
  results under **Validated consumers** for the range; append the consumer if the
  range already exists.
- **Project tier (helm only):** update the configuration profile when new config
  is observed; append a review-history line every review; add breaking-change
  patterns when found.
- Never delete existing entries unless confirmed wrong.
