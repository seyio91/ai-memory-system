---
plan: reorg-followups
status: done
created: 2026-06-03
completed: 2026-06-03
owner: orchestrator
---

# Reorganize follow-ups (the three flagged items)

## A. Fill `client-a-modules/memory.md` (grounded in the real repo)
Repo = `client-a-enterprise-tf-modules` (<org>), checkout `~/Downloads/personal/client-a/client_a_modules`,
remote `git@github.com:<org>/client-a-enterprise-tf-modules.git`. Shared remote Terraform modules
library consumed by `client-a-infrastructure`, `client-a-infra-scaffolder` (v0.2.0/v0.3.0), `client-a-ec2`.
- Replace template placeholders; 5 required sections + frontmatter (topic/scope/summary + `repo` + `tags`).
- Record local checkout as a body "Repo path:" line (mirrors access-eks house style); do NOT set
  `repo_path` frontmatter (no back-pin / non-default projects root → would trip lint).
- Current State: `infrastructure/` active (ec2, ecr, eks-roles, eks_cluster, elasticache,
  generic_iam_role, gh-actions-iam-role, gitops, openvpn, rds, rds-cluster, rds-credential-manager,
  rds-snapshot, s3, secrets-generator, security-group, tf-backend, vpc); `kubernetes/` deprecated.
  In flight: branch `feat/s3-iam-writer` (s3 bundles optional IAM writer + Secrets Manager, fixed
  `s3_bucket_id` output, iam-user via `create` flag not `count`). Tags v0.3.0 latest.

## B. Extract cross-cutting facts → new domain files
- `domain/fineract.md` — Fineract needs BOTH `fineract_tenants` + `fineract_default` databases
  (general rule; project files keep their PR-specific audit detail and reference it).
- `domain/shell.md` — macOS bash 3.2 compatibility (no `mapfile`, no associative arrays, no
  `${var,,}`, guard empty arrays under `set -u`).
- Each: frontmatter (topic, triggers, summary) + `## Knowledge` entries.

## C. Reference domain files from project files (keep repo-specific delta)
- `client-a-infrastructure` + `client-a-infra-scaffolder`: trim the *general* statement to a pointer at
  `domain/fineract.md` / `domain/shell.md`, keep the repo-specific detail (PR #83, `794df0b`, file paths).

## D. Promote the pending learning
- `client-a-modules/working.md` "Open learnings" (plan-mode default path vs canonical memory-system plan
  path) → `claude-memory-system/memory.md` Known Constraints / Gotchas. Clear it from working.md
  (snapshot to `archive/working/` per promote convention).

## E. Finalize
- `regenerate-index.sh` (new domain rows; client-a-modules now has real topic/summary/tags). Lint exit 0.
