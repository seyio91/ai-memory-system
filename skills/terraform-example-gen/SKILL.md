---
name: terraform-example-gen
description: Generates or updates examples/main.tf for Terraform modules in this repository. Use this skill whenever the user asks to generate, create, update, or fix a Terraform module example, or when a module's variables change and the example needs updating. Also triggers when the user says things like "write an example for this module", "update the example", "the example is outdated", or "add an example to [module]". Always invoke this skill for any work touching examples/main.tf in a Terraform module directory.
metadata:
  tier: target-write
---

# Terraform Example Generator

Your job is to create or update `example/main.tf` for a Terraform module so it is a minimal, real, working example that passes `terraform init` and `terraform validate`.

## Core rules

- Always reference the module itself with `source = "../"` — never a remote URL
- Dependencies that exist in this repo use a relative path: `source = "./../../<module_name>"` (e.g. `./../../vpc` from `infrastructure/eks_cluster/example/`)
- Only fall back to a git remote source (`git::git@bitbucket.org:...?ref=<version>`) if the dependency does not exist in this repo
- Keep the example minimal — only set required variables plus a small set of important optional ones that meaningfully shape what gets created. Don't enumerate every variable.
- Use realistic placeholder values, not `"foo"` or `"test123"`. Use values like `"example-customer"`, `"dev"`, `"10.0.0.0/16"`, `"db.t3.medium"`.
- Add inline `# comments` on values that the user will need to change for real use.

## Step-by-step process

### 1. Read the module

Read `variables.tf` (or `variable.tf`) and `main.tf` in the target module directory. Understand:
- Which variables are required (no `default`)
- Which optional variables have the most impact on what gets created
- What AWS resources the module creates (determines what dependencies are needed)

### 2. Decide on dependencies

Ask yourself: can this module plan successfully without real infrastructure IDs?

Modules that can stand alone (no VPC/subnet IDs required):
- `vpc`, `ecr`, `generic_iam_role`, `secrets-generator`, `security-group`, `account-init`

Modules that need a VPC:
- `rds`, `rds-snapshot`, `rds-credential-manager`, `elasticache`, `eks_cluster`, `fck-nat`
- Add a `module "vpc"` block using the remote git source

Modules that need both VPC + EKS:
- `eks-roles`, `karpenter`
- Add both `module "vpc"` and `module "eks"` dependency blocks

When adding a dependency module from this repo, look up the latest version from git log or CHANGELOG.md and pin to it.

If no suitable module exists in this repo for a dependency, use the official Terraform Registry module (e.g., `terraform-aws-modules/vpc/aws`).

### 3. Write the example

Structure:

```hcl
# [optional brief description of what this example shows]

# --- Dependencies (if any) ---
module "vpc" {
  source      = "git::git@bitbucket.org:revvingadmin/terraform-modules.git//infrastructure//vpc?ref=<VERSION>"
  environment = "dev"
  customer    = "example-customer"
  vpc_cidr    = "10.0.0.0/16"
  common_tags = { Name = "example", Environment = "dev" }
}

# --- The module under test ---
module "<module_name>" {
  source = "../"

  # required variables first
  environment = "dev"
  customer    = "example-customer"
  common_tags = { Name = "example", Environment = "dev" }

  # dependency references
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets

  # key optional variables
  ...
}
```

No `terraform {}` block, no `provider {}` block — the example directory is consumed as a module, not run directly as a root module. The parent `versions.tf` already defines the provider.

### 4. Update existing example

If `example/main.tf` already exists:
1. Read the existing file
2. Identify what changed in the module (new required variables, removed variables, renamed variables, changed types)
3. Make the minimal diff needed — don't rewrite working sections unless something actually changed
4. Keep any comments the user may have added

## Common patterns to follow

### VPC dependency (used by RDS, EKS, ElastiCache, etc.)
```hcl
module "vpc" {
  source      = "./../../vpc"
  environment = "dev"
  customer    = "example-customer"
  vpc_cidr    = "10.0.0.0/16"
  common_tags = { Name = "example", Environment = "dev" }
}
```

### EKS dependency (used by eks-roles, karpenter)
```hcl
module "eks" {
  source          = "./../../eks_cluster"
  environment     = "dev"
  customer        = "example-customer"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.private_subnets
  route_table_ids = module.vpc.private_route_table_ids
  common_tags     = { Name = "example", Environment = "dev" }
  aws_auth_users  = []
  node_groups_attributes = {
    general = {
      name           = "example"
      instance_types = ["t3a.medium"]
      capacity_type  = "ON_DEMAND"
      ami_type       = "AL2_x86_64"
      taints         = []
      max_size       = 3
      min_size       = 1
      desired_size   = 1
      disk_size      = 50
      subnet_ids     = module.vpc.private_subnets
      pre_bootstrap_user_data = ""
    }
  }
}
```

### RDS (MySQL example)
```hcl
module "rds" {
  source                   = "../"
  db_identifier            = "example-db"
  username                 = "admin"
  engine                   = "mysql"
  engine_version           = "8.0"
  major_engine_version     = "8"
  rds_family               = "mysql8.0"
  db_port                  = 3306
  instance_class           = "db.t3.medium"
  db_storage_size          = 20
  initial_db_name          = "exampledb"
  vpc_id                   = module.vpc.vpc_id
  vpc_cidr_block           = module.vpc.vpc_cidr_block
  rds_subnets              = module.vpc.private_subnets
  intra_subnets            = module.vpc.intra_subnets
  disable_rds_public_access = true
  environment              = "dev"
}
```

## After writing

Tell the user:
- What the example demonstrates
- Which dependencies were added and why
- What values they'll need to replace before running against a real AWS account (region, account IDs, etc.)
- The commands to validate: `terraform init && terraform validate`  (do not run `terraform plan` — that requires real AWS credentials and live infrastructure)
