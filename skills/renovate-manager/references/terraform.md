# Reviewer: Terraform (`module` · `provider`)

Loaded by `SKILL.md` (Phase 4 dispatch) for Terraform `module` and `provider`
Renovate bumps. Receives the **reviewer input** and returns the **reviewer
output** defined in SKILL.md. The dispatcher has already extracted
`{package, type, current→target, upstream}` from the PR body table; this reference
finds the config in use, fetches the upgrade guide, runs `terraform validate`, and
analyzes impact.

Per SKILL.md Phase 4 this runs as two parallel subagents (executors):
**Analyzer** = the *Config-source adapter* + *Runnable validation* below;
**Upstream** = the *Upstream analysis* below — **skipped on a package-memory cache
hit** (exact `<current>→<target>` range already in
`terraform/{modules,providers}/<addr>.md`). The dispatcher combines them for the
impact analysis, verdict, and memory write.

## Config-source adapter (by `type`)

From the **`.tf` files that changed** in the diff (ignore generated `README.md` /
terraform-docs noise), identify the **consuming module dir(s)** — `<unit>` for
memory — and the config in use. Read literally; do not resolve
`templatefile`/`locals`/`var.*` chains (v1 boundary).

- **`module`** — the bumped `module "<name>" { source = "…", version = "X→Y" }`
  block. "Config in use" = the **inputs the caller passes** to that block (its
  arguments) and the module **outputs** the surrounding config consumes.
- **`provider`** — the bumped `required_providers { <name> = { version = "X→Y" } }`
  constraint. "Config in use" = the `provider "<name>" { … }` configuration
  block(s) and the resources/data sources of that provider in the module.

A PR may bump the same dependency across several module dirs — handle each.

## Upstream analysis

From the body-table `[source]` link (Terraform Registry → GitHub), fetch the
upgrade material for the version range, in order of usefulness:
- module: `UPGRADE.md` / upgrade guide → `CHANGELOG.md` → GitHub releases.
- provider: the provider's upgrade guide (registry docs `…/guides/version-N-upgrade`)
  → CHANGELOG → releases.

Identify breaking **input/output/attribute** changes (renamed/removed variables,
changed defaults, removed outputs, renamed resource attributes) and, for
providers, version-constraint and removed-resource implications. The Renovate
"could not be looked up" warning means the source link may be absent → fall back
to the Registry address / `source` in the diff (`registry.terraform.io/modules/…`
→ its linked GitHub repo).

For **major** bumps, treat a missing/!-marked upgrade guide as higher risk and
lean toward ACTION REQUIRED pending the validate result.

## Runnable validation (primary breaking-change check)

The strongest signal is whether the consuming module still compiles at the bumped
version. Validate the example root module (it wires the module with provider
config), at the PR head — for **every affected folder**: each module dir whose
`.tf` actually changed for this dependency (ignore terraform-docs `README.md`-only
diffs). Don't validate just one and stop.

**Procedure:**

1. **Get the PR head once, without touching the user's working tree.** Prefer a
   worktree off the local checkout (reverse-map `repo_path`):
   `git fetch <remote> <pr-head-ref>` → `git worktree add <tmp> <head-sha>`.
   Fallback: shallow `git clone --branch <pr-head-ref> --depth 1 <repo-url> <tmp>`
   (`GIT_TERMINAL_PROMPT=0` to fail fast on auth). Reuse this one checkout for all
   folders.
2. **For each affected module dir**, discover its example root — accept `example/`
   *or* `examples/` (both seen). If it holds `.tf` directly, that's the root; if it
   holds subdirs, validate **each** subdir (don't silently pick one — if you cap,
   say which you skipped).
3. In each example root: `terraform init -backend=false` (installs providers +
   modules at the bumped version; **`-backend=false` avoids backend/state
   credentials**) → `terraform validate` + `terraform fmt -check -recursive`.
4. Record **per-folder** outcomes under the package tier's *Validated consumers*;
   **any `validate` failure → ACTION REQUIRED**. `fmt` drift is a note, not a
   blocker (often pre-existing).
5. **Clean up:** `git worktree remove <tmp>` (or `rm -r` the temp clone — the
   executor sandbox blocks `rm -rf`). Prefer a workspace-relative temp (`./tmp-sub/…`).

**No `example`/`examples` dir** → try `terraform init -backend=false && validate`
in the module dir directly if it's self-contained; if that's not meaningful
(missing provider config / required vars), degrade to doc analysis only and
**note the gap in the report** (validation skipped — no example).

Never run `terraform plan` against live state, never `apply`. `validate` catches
input/constraint/provider/syntax breakage — not runtime or plan-time destruction.

## Impact analysis

Match the upstream breaking changes against the caller's config in use:
- flag any module-block argument / provider setting the caller sets that was
  renamed, removed, or re-defaulted;
- note new **required** inputs the caller doesn't yet set;
- note removed/renamed **outputs** the surrounding config consumes;
- for providers, note major version-constraint jumps and removed resources/data
  sources in use.

**Prior-review check (package memory)** — if the package-tier file
(`terraform/{modules,providers}/<addr>.md`) has an entry for a nearby/earlier range:
reuse its recorded breaking changes + upstream quirks, and check whether a
previously-flagged break recurs here. (Terraform has **no project tier** — there's
no per-caller profile to compare; the empirical check is `terraform validate`.)

Combine with the validate result: a clean `validate` (all affected examples) + no
caller-facing breaking changes → APPROVE; breaking changes touching config in use,
or any validate failure → ACTION REQUIRED; otherwise APPROVE WITH NOTES. Surface
adoptable new inputs/features as notes.

## Memory payload (package tier only)

Terraform records **only the package tier** — the component being updated, not the
modules consuming it. **Templates + update discipline: `references/memory.md`.**

- **Package tier** → `terraform/modules/<module>.md` or
  `terraform/providers/<provider>.md`: identity (address, upstream), per-range
  upgrade-guide summary + breaking changes, **Validated consumers** (each affected
  `repo/path/example` → pass/fail), which projects reviewed which ranges, upstream
  quirks.
- **No project tier.** The consuming module(s) are validate targets only; their
  pass/fail goes under the package tier's *Validated consumers*.
