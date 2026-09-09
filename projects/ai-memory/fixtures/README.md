# Fixtures

Labelled inputs for testing memory-system checks. Not memory — nothing here is
loaded into context, and `lint-memory.sh` does not scan this directory (its globs
are all single-level over `memory.md`, `working*.md`, `plans/`, `investigations/`).

Distinct from `scripts/tests/fixtures/`, which holds synthetic sample data for the
shell suite. This directory holds real, hand-labelled corpora.

## Sanitization

This repository is public, so no client project's memory is committed verbatim.
Fixtures are **pseudonymised, not redacted** — every project-scoped identifier is
replaced by a stable fake one, because the property under test is precisely
*"does this bullet name a project-scoped identifier?"*. Redacting them would
delete the true negatives and leave a corpus that only tests the easy half.

Public OSS names (ArgoCD, CNPG, Karpenter, Fineract, TigerBeetle, n8n, Tempo,
Superset, Oracle XE, Debezium) are kept as-is; they identify no one and removing
them would make the bullets unrealistic.

Substitutions are consistent across the file: client org → `acme` / `acme-eng`,
repo path prefix → `acme/proj-100`, tenants → `tenant-a` / `tenant-b` /
`tenant-c`, cluster → `acme-us-east-2-dev`, environment → `acme-dev`, ECR
registry alias → `x0x0x0x0`, image vendor → `opsvendor`, and any alert name
embedding the environment → `AcmeDev…`. Bullet count, structure and section
layout are untouched, so scoring is unaffected.

## `project-memory-2026-08-30-pre-trim.md`

A project `memory.md` as it stood on 2026-08-30 **before** a manual Known
Constraints trim: 57 bullets in `## Known Constraints / Gotchas`, 16,859 B
sanitized (16,873 B in the original). Serves task
`3cbf6850-c619-8142-80c4-ca98ae158719` /
[[lint-known-constraints-domain-rehoming]].

Its value is that the correct answer is known, because the trim was done by hand
and each decision recorded. A rehoming heuristic can be **scored** against it
rather than eyeballed.

**Should be flagged as rehoming candidates** (all four were in fact moved, and all
four name no project-scoped identifier):

| bullet (first words) | went to |
|---|---|
| `Chart-bump review: render both versions…` | `domain/helm.md` |
| `Under ArgoCD SSA, keep a live single-replica RWO…` | `domain/argocd.md` |
| `Do not use jsonpath to test absence of keys…` | `domain/k8s.md` |
| `Treat ArgoCD Synced/Healthy as cached-state evidence…` | `domain/argocd.md` |

Four more were rehomed in later passes and are also present in this fixture:
`skipCrds varies by addon…`, `With goTemplateOptions: ["missingkey=error"]…`,
`Cluster-Secret annotations are the source of truth…` (all → `domain/argocd.md`),
and `Do not treat ArgoCD pruning as cleanup for hook or Job resources…`
(→ `domain/argocd.md`).

**Must NOT be flagged** — correctly project-scoped despite reading generic:

- `Do not remove a scale-to-zero guard until AcmeDevWorkloadPartiallyScaledUp…`
  — names an environment-specific alert. The true negative that matters; a
  heuristic keying only on "sounds generic" fails here.
- `Sync waves matter: addons span -10 through 4…` — the concept is generic, the
  range is repo-specific.
- `Keep tenant-a on fineract-synapse-tigerbeetle…` — names a workload and a chart.

**Known duplicates** the near-duplicate check should catch:

- `Treat workload catalog configuration as the source of truth…` restates the
  autoshutdown bullet directly above it.
- `Secrets come from External Secrets — never hardcode…` restates an entry in
  `## Architecture Decisions` in the same file.

**Known contradiction** (harder; out of scope for the first pass, recorded because
the fixture contains it): two `enablePDB` bullets added months apart, one saying
ship `enablePDB: false`, the other saying do not flip `enablePDB`. They agree in
substance but read as opposites without the history.

**Event residue in `## Current State`** — for the present-tense check. The paragraph at L18 holds
four facts; two are events and one is a duplicated rule:

| text | verdict |
|---|---|
| `` `tenant-c` is fully removed; zero references remain `` | event — completed deletion |
| `` `provisioning-service-db` was the last multi-instance one until PR #235 (2026-08-30) `` | event — past tense + PR ref + date; was 8 hours old when written |
| `` The `tenant-a` setting is dead config because it is RDS-backed `` | duplicated rule, not event residue |
| `` `max_slot_wal_keep_size` is present on all seven workload clusters `` | clean — must not be flagged |

End state after all passes, measured on the unsanitized original: 24 bullets /
11,635 B.
