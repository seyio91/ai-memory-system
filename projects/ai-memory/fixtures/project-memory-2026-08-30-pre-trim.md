---
topic: acme-gitops
category: acme
scope: project
summary: ArgoCD app-of-apps for acme EKS — addon + workload ApplicationSets, multi-cluster fan-out via cluster Secret annotations
repo: git@github.com:acme-eng/acme-gitops.git
repo_path: acme/proj-100/acme-gitops
---

# Project: acme-gitops

## What It Is
ArgoCD app-of-apps repo for managing Kubernetes addons and workloads for acme EKS.

## Current State
Most addons are stable. Standing backlog: observability dashboards and alerts, plus small fixes. `database.monitoring.enabled` is on for CNPG/Postgres tenants; off for `tenant-a`, `tenant-a-synapse-consumer`, and `tenant-b` (MySQL/PXC needs chart PodMonitor wiring).

`max_slot_wal_keep_size` is present on all seven workload clusters; absent on addon clusters `n8ndb`, `dashboard`, and `superset`. The `tenant-a` setting is dead config because it is RDS-backed. Zero `tb_*` series exist until TigerBeetle metrics are enabled on `tenant-a`; this is accepted and tracked in [[tenant-a-tigerbeetle-hostpath-to-pvc]]. Retain `tigerbeetle.json` (`uid: tigerbeetle-metrics`). `tenant-c` is fully removed; zero references remain. Every CNPG cluster on `acme-us-east-2-dev` now runs `instances: 1`; `provisioning-service-db` was the last multi-instance one until PR #235 (2026-08-30).

## Architecture Decisions
- Layout split: `bootstrap/` holds ArgoCD ApplicationSet manifests, `environments/` holds the values consumed by them. Sub-divided into `addons/` (cluster-wide infra) vs `workloads/` (app-of-apps for product workloads).
- Multi-cluster fan-out via the ApplicationSet `clusters` generator — per-cluster context (clustername, repo URL/revision, IAM role ARNs, etc.) flows through cluster labels/annotations rather than per-cluster files.
- Multi-source Applications: a wrapper Helm chart from public ECR (`public.ecr.aws/x0x0x0x0/charts/acme-base-apps`) is the renderer, with `$values` ref pointing back at this repo so values stay in-tree while the chart is shared.
- Keep monitor selector helpers separate from Deployment selector helpers; monitor selectors are mutable while Deployment selectors are immutable. Reuse an in-chart precedent before adding a helper.
- Per-addon directory convention: `default/values.yaml` is the baseline; `environments/<env>/values.yaml` overrides; optional `chart/` for in-repo templates and `resources/` for raw manifests sourced as a second path.
- Workloads use internal Helm charts published to ECR; this repo only carries values + ApplicationSet wiring.
- Land chart capability separately from enabling it when enablement mutates the pod template and carries the blast radius.
- Sync defaults are `automated: {}` with `CreateNamespace=true` and `ServerSideApply=true`; ordering via `argocd.argoproj.io/sync-wave` annotations.
- Enable an addon per cluster by setting its `enable_<addon>` cluster-Secret label in acme-infrastructure; do not add per-cluster config here.
- Secrets are pulled via External Secrets Operator (external-secrets + external-secret-store addons) — no plaintext secrets in this repo.
- DNS handled by external-dns; ingress by ingress-nginx and AWS LB controller; node lifecycle by Karpenter (+ karpenter-nodepool).
- Treat an `archive_timeout` increase as a PITR RPO decision; it reduces forced WAL churn but widens maximum data loss.
- Decide `selfHeal` independently of pruning; it manages drift, not orphan cleanup.
- Re-evaluate queue mode only if a window exceeds five workloads, queue tail nears `EXECUTIONS_TIMEOUT`, or redeploys interrupt executions.
- Accept that a Recreate rollout of single-instance n8n can lose in-flight executions; queue mode is the mitigation if this becomes unacceptable.
- Keep custom-image ECR provisioning manual while additions remain rare; replace it with catalog-derived provisioning only when the sibling ECR change recurs more than quarterly.
## Related Projects

| Sibling | Repo | Relationship | Ordering |
|---|---|---|---|
| acme-infrastructure | `git@github.com:acme-eng/acme-infrastructure-v2.git` (`repo_path: acme/proj-100/acme-infrastructure-v2`) | Generates catalog-derived files here; generated `databases.conf` and autoshutdown artifacts are never hand-edited here. | Infra catalog/generator change → CI-only Terraform apply/bot update → ArgoCD consumption. Delegate sibling work per OEV; do not load sibling memory. |
| acme-charts | `git@github.com:acme-eng/acme-enterprise-helm-v2.git` (project label is "acme-charts" ≠ repo name) | Owns chart templates; this repo pins OCI `targetRevision` and supplies values. | Chart change there → OCI release → version bump here. Delegate sibling chart work per OEV; do not load sibling memory. |
| acme-images | `git@github.com:opsvendor/acme-images.git` (`repo_path: acme/proj-100/n8n-opsvendor`) | Owns images; this repo pins image tags. | Custom image: infra ECR repo → image prerelease/release → tag bump here. Delegate sibling work per OEV; do not load sibling memory. |

Detail: [sibling-repository-contracts](wikis/sibling-repository-contracts.md).

Active initiatives: `eks-cost-reduction` (Targets here: `tenant-a-nodepool-rightsizing`,
`namespace-request-rightsizing`, `orphaned-pv-cleanup`) — load
`initiatives/eks-cost-reduction.md` before starting any of them. Its sibling
`aws-account-cost-reduction` has no Target in this repo.

## Known Constraints / Gotchas
- Omit `version` from provisioned Grafana datasources; a stored higher version makes provisioning silently no-op.
- Verify Grafana datasource provisioning from `grafana.db`'s `data_source` table, not the ConfigMap or mounted file.
- Grafana datasources provision only at boot; list every datasource CM in `grafana.annotations.configmap.reloader.stakater.com/reload`.
- Chart-bump review: render both versions with real values; inventory resources; verify overrides, ports, paths, selectors, pod labels, and checksum/reloader; use ReplicaSet creation time to prove no rollout. A version number tells you nothing about content — diff the tag, never infer from the bump.
- Under ArgoCD SSA, keep a live single-replica RWO Deployment on RollingUpdate with `maxSurge: 0` and `maxUnavailable: 1`; `Recreate` cannot apply and default rollout can Multi-Attach deadlock.
- ServiceMonitor selectors must not include `helm.sh/chart`; chart-version labels make them churn on every bump.
- Diagnose a ServiceMonitor selector fault by zero discovered targets; `down` targets diagnose workload health, not selector matching.
- Prove selector stability by re-rendering a published chart after forcing a fake higher chart version; metadata labels may change but selectors must not.
- Do not use jsonpath to test absence of keys containing `.` or `/`; inspect the whole selector map as JSON.
- Treat ArgoCD `Synced/Healthy` as cached-state evidence only; compare `status.sync.revisions` with `origin/main` before declaring a commit live.
- Check every fleet pin before calling a chart version unexercised.
- When replacing a legacy chart pin, update `repoURL` and `targetRevision` together; release-please artifacts require the `/charts` path.
- Keep `tenant-a` on `fineract-synapse-tigerbeetle`; before any workload chart bump, diff `helm template` old vs new for template inventory.
- A GitHub chart release does not prove ECR publication; `helm pull` the exact version before pinning it.
- **`tempo` is pinned to chart 1.24.4, which is `deprecated: true` upstream** — `tempo-distributed` is the maintained path, and vParquet2 is removed in Tempo 2.10, gating any further bump. The 2.3.0 → 2.9.0 upgrade fixed the compactor OOM at an unchanged 1Gi limit; peak sits at 845 MiB / 1024 MiB (83%), so a heavier trace day could still cross it.
- Treat `NodeMemoryHighUtilization` as accepted dev noise only for requests-full `platform-nodepool` nodes with no OOMs, evictions, or restarts; do not raise it to 95% because small-node eviction occurs first.
- Change a node-exporter mixin threshold by disabling the default rule in `defaultRules.disabled` and re-authoring it in `extraManifests`; no values knob exists.
- Keep the two `acme-dev` uptime rules in lockstep; paired probes need paired fixes.
- Use `unless on() (kube_deployment_spec_replicas{namespace=...,deployment=...} == 0)` for scale-to-zero guards; never join only on namespace.
- Map a blackbox target to its backing Deployment from ingress paths, not alert labels.
- Do not remove a scale-to-zero guard until `AcmeDevWorkloadPartiallyScaledUp` still covers a partially scaled namespace.
- Use rule scoping, not Alertmanager mute timings, to resolve a brief-filed alert; mutes suppress notification but leave the alert active.
- Exclude `tenant-a` workload alerts from platform alert triage; do not file fixes or mute proposals from a morning brief. Infrastructure work remains in scope.
- With `goTemplateOptions: ["missingkey=error"]`, every cluster must define every referenced annotation or the ApplicationSet generates no Apps.
- Cluster-Secret annotations are the source of truth for per-cluster wiring and live outside this repo; ensure referenced annotations exist before changing AppSets.
- Sync waves matter: addons span `-10` through `4`. CRD owners (cert-manager, operators, karpenter) install early-negative; consumers depend on those waves running first. Don't reorder casually.
- `skipCrds` varies by addon — most chart-based addons keep CRDs (`skipCrds: false`), karpenter explicitly skips them. Flipping this can either drop CRDs in-place or cause double-install conflicts.
- Before editing addon values, check each cluster's `addons_repo_revision`; values apply only when the App's `targetRevision` resolves to the edited branch.
- `ServerSideApply=true` is used widely; switching off (or to `Replace=true` like clickhouse-cdc) changes conflict resolution and can fight other controllers/operators.
- Secrets come from External Secrets — never hardcode them in values; always reference an ExternalSecret/SecretStore that the cluster has provisioned.
- Some addons have BOTH a `chart/` (in-repo Helm sub-chart) and a `resources/` path mounted as a separate source — both must be in sync; editing one without the other can cause out-of-sync Apps.
- New YAML in `bootstrap/workloads/` or `bootstrap/addons/` fan-outs to every selected cluster; use cluster labels to constrain scope.
- **RDS-backed workloads have no `<db>-db-secret`; discover the ESO Secret by `app.kubernetes.io/component=db-credentials`.** Detail: rds-workload-db-credentials.
- Keep addon pruning off by default. Enable it only where list-derived names can leave active orphans; never enable it fleet-wide because a transient CRD-owner render failure can cascade-delete CRs.
- Do not treat ArgoCD pruning as cleanup for hook or Job resources; they can persist even when pruning is enabled.
- **Workload autoshutdown is GitOps-owned here; acme-infrastructure generates its fragments and AppSet from the catalog — never hand-edit them.** Gated by `enable_autoshutdown`. Detail: autoshutdown-gitops-migration.
- Treat workload catalog configuration as the source of truth for generated autoshutdown GitOps artifacts; do not hand-edit generated output.
- A green autoshutdown CronJob proves only webhook receipt; diagnose missing scaling in Slack and the n8n execution log, not Job status.
- Autoshutdown `start` intentionally sets development workloads to one replica; do not restore prior replica counts.
- **The ApplicationSet's `valueFiles` list is generated, so it tracks the catalog** — but this is temporary. When ArgoCD 3.5.0 ships (multi-source `$ref` glob, argo-cd PR #26768; 3.5.0-prerelease as of 2026-08-03), the list collapses to one glob line and the appset should return to hand ownership here, dropping the infra generator and `.github/scripts/autoshutdown_reference_guard.py`.
- `autoshutdown.enabled` defaults to `false` in acme-infrastructure; a schedule without `enabled` remains disabled. Changing that default enables autoshutdown fleet-wide.
- Do not enable database monitoring for MySQL/PXC tenants until the chart has MySQL PodMonitor wiring.
- Ship `enablePDB: false` with every `instances: 1` CNPG cluster. Unset takes CNPG's CRD default `true`, leaving only the `-primary` PDB at ALLOWED DISRUPTIONS 0 — an unevictable pod that stalls Karpenter consolidation.
- **Single-instance CNPG eviction is an ACCEPTED dev risk, not a defect.** Do not flip `enablePDB`: `minAvailable: 1` yields `ALLOWED DISRUPTIONS=0`, preventing eviction and stalling Karpenter consolidation. Detail: cnpg-karpenter-churn.
- Treat `wal_level: logical` as a CNPG default unless the live cluster proves otherwise; assess restart risk from the effective value. Restrict CNPG parameter changes to SIGHUP-reloadable settings; `wal_level` forces a restart and outages a single-instance cluster.
- Do not use `KafkaConnector Ready=True` or `state=RUNNING` as connector health; alert on `.status.connectorStatus.tasks[0].state`.
- Size `max_slot_wal_keep_size` from WAL segment cadence and connector downtime, not database size or apparent write volume when `archive_timeout` forces segment rotation.
- Estimate WAL burn over hours with `pg_stat_archiver` or long-window LSN movement; instantaneous samples are not representative.
- Estimate only the forced-switch component as scaling with `archive_timeout`; measure total WAL burn and quote the measured headroom.
- Quote short-window WAL headroom as a range and re-measure over hours when precision matters.
- Remove a temporary connector `spec.state` after recovery instead of setting `running`, so Git remains authoritative.
- Use `max_slot_wal_keep_size` as the WAL guard only for CNPG clusters with a rendered `spec.postgresql.parameters` path. Do not configure it for RDS-backed tenant-a; it has no CNPG Cluster for values to affect.
- ArgoCD SSA merges a partial `spec.postgresql.parameters` map with webhook defaults; validate the resulting live spec on a non-critical target first.
- Ship CNPG parameter values with a chart pin that renders them, then verify the live Cluster spec; values alone prove nothing.
- Migrate tenant-a TigerBeetle storage from hostPath to one PVC per replica before enabling metrics; enablement rolls all replicas and risks quorum on the current storage model.
- **`n8ndb` can be evicted mid-flight; a green autoshutdown CronJob can still leave scaling undone.** Diagnose through `execution_entity` in the `n8n` database, not Job status. Detail: cnpg-karpenter-churn.
- Bound regular-mode n8n scheduler concurrency with `N8N_CONCURRENCY_PRODUCTION_LIMIT: "5"`; this is not queue mode.



## Current Goal
Build out platform and per-tenant observability: a two-level Grafana view (platform/fleet health → drill-down into a tenant environment), a Synapse dashboard, and PrometheusRule alerts for Synapse, TigerBeetle and Fineract per the [monitoring-alerts](wikis/monitoring-alerts.md) wiki. Earlier blackbox-exporter/n8n endpoint probing and the CNPG dashboard rollout are done; the tunneller RDS-credential track closed 2026-07-26.

## Wikis
On-demand deep-dive pages in `wikis/` — load the file only when the topic comes up.
- [tenant-a-cdc-setup](wikis/tenant-a-cdc-setup.md) — Tenant A CDC side stack: Oracle XE → Debezium LogMiner → `cdc-kafka`; ArgoCD wiring, dependencies, rendered resources, tuning, gotchas.
- [superset-addon](wikis/superset-addon.md) — Apache Superset BI addon: first upstream-chart 3-source addon; CNPG + bundled Redis/Celery; ESO no-plaintext secret injection (incl. the `${ADMIN_PASSWORD}` init trick); ingress, validation, follow-ons.
- [tigerbeetle-metrics](wikis/tigerbeetle-metrics.md) — TigerBeetle (`acme-tigerbeetle`) Prometheus metrics: statsd-exporter export path, `tb_*` taxonomy, label schema, counter-vs-gauge query patterns, what-to-monitor, and the metrics-tigerbeetle dashboard.
- [monitoring-alerts](wikis/monitoring-alerts.md) — Alerting proposal for TigerBeetle + Fineract (not implemented): what to trigger on, grounded in live metrics; kube-prom defaultRules coverage vs gaps (`TargetDown` disabled), no-histogram constraint, verified COB-failure expr.
- [helm-v2-chart-release-workflow](wikis/helm-v2-chart-release-workflow.md) — Helm-v2 chart-release CI trigger failure and self-unblocking manual-dispatch fix.
- [sibling-repository-contracts](wikis/sibling-repository-contracts.md) — Reference detail for acme-infrastructure, acme-charts, and acme-images contracts consumed by this repository.
- [rds-workload-db-credentials](wikis/rds-workload-db-credentials.md) — RDS-backed workload database-credential Secret discovery and AWS Secrets Manager path conventions.
- [namespace-cost-allocation](wikis/namespace-cost-allocation.md) — Requests-based per-namespace EKS cost model: method, blended rates, PromQL, the 2026-08-27 table, and the Karpenter/KSM metric gaps that cap its accuracy.
