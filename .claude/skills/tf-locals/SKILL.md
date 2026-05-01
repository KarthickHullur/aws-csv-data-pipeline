---
name: tf-locals
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform `locals.tf` file for an AWS module. Trigger when the user mentions "locals.tf", "Terraform local values", "compute defaults from config", "default tags", or asks to wire a module to a JSON-driven configuration pattern. Also trigger when scaffolding a new Terraform module that follows the team's standard layout (`infra/<module>/tf/`) and needs locals derived from a JSON config file. The defining feature of this skill is that **AWS configuration comes from a JSON file referenced by `var.aws_config_path`**, naming follows the `<project_code>-<base_name>-<environment>[-<region>]` convention, and every resource is tagged via a `default_tags` local. Do NOT use this skill if the user wants inline HCL configuration only, a non-JSON config source, or a custom naming convention that diverges from the standard.
---

# Terraform Locals (AWS Module) Skill

## Purpose

Generate a `locals.tf` file for an AWS Terraform module that:

- Parses an external JSON config file via `var.aws_config_path`.
- Computes a standard `default_tags` map applied to every resource.
- Builds resource configurations (S3, IAM, KMS, etc.) using a consistent naming convention.
- Exposes those configurations as named `local.*` values for use by `main.tf` and module calls.

The file is treated as a set of **building blocks** — pick the patterns that fit the module's scope, skip the ones that don't.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create a `locals.tf` for this AWS module"
- "Add a `default_tags` block"
- "Wire this module to read from a JSON config file"
- "Set up the standard naming and tagging locals"
- "Scaffold the locals for a new infra module"

Do **not** use this skill if:

- The user wants inline HCL (no external JSON config).
- The user specifies a different naming convention (e.g. `<env>-<name>` or fully custom).
- The user is asking for a different cloud (GCP, Azure) or for non-AWS Terraform configuration.
- The module already has a `locals.tf` and the user wants to edit one specific block — handle that conversationally rather than regenerating.

## Required information

Before writing the file, gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path and description

- **Path:** typically `infra/<module>/tf/locals.tf`. If unspecified, default to that pattern.
- **Module description:** inferred from the directory name (`platform/` → "Platform Module", `data-pipeline/` → "Data Pipeline Module"). If ambiguous, ask.

### 2. Required variables (must already be declared in `variables.tf`)

The skill assumes these variables exist. If they don't, tell the user they need to be added before the locals will compile:

| Variable | Purpose |
|----------|---------|
| `var.project_code` | Short prefix used in all resource names (e.g. `c360`, `acme`) |
| `var.environment` | Deployment env (`dev`, `stg`, `prod`) |
| `var.aws_config_path` | Relative path to the AWS JSON config file |
| `var.repository` | Source repository name (for the `Repository` tag) |
| `var.component` | Module's component name (e.g. `platform`, `ingestion`) |
| `var.owner` | Owning team or person |
| `var.cost_center` | Finance cost center code |
| `var.data_classification` | Data sensitivity (`public`, `internal`, `confidential`) |
| `var.git_ref` | Git branch or tag at apply time |
| `var.git_commit_sha` | Git commit SHA at apply time |

### 3. Resource patterns to include

Ask the user which of these the module needs (or infer from context):

- **Default tags** — almost always required.
- **AWS config parsing** — required if the module reads from a JSON file.
- **KMS key lookup** — include only if the module encrypts resources with a customer-managed key.
- **S3 configuration** — include only if the module creates an S3 bucket.
- **IAM role configuration** — include only if the module creates an IAM role.

## Output template

Write the file to the path the user specifies, defaulting to `infra/<module>/tf/locals.tf`.

The file must follow this exact structure, including the header banner. Patterns marked **(optional)** should be omitted when not needed — keep the file scoped to what the module actually uses.

```hcl
# -- <RELATIVE_PATH> (<MODULE_DESCRIPTION>)
# ============================================================================
# Local Values
# ============================================================================

data "aws_caller_identity" "current" {}

# <OPTIONAL KMS KEY LOOKUP — see Pattern: KMS Key Alias>

locals {
  # ============================================================================
  # Default tags (applied to every AWS resource via provider default_tags)
  # ============================================================================
  default_tags = {
    Project            = var.project_code
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Repository         = var.repository != "" ? var.repository : null
    Component          = var.component
    Owner              = var.owner
    CostCenter         = var.cost_center
    DataClassification = var.data_classification
    GitRef             = var.git_ref
    GitCommitSHA       = var.git_commit_sha
  }

  # Parse config from JSON file (relative to module path)
  aws_config_file = jsondecode(file("${path.module}/${var.aws_config_path}"))

  # Extract nested sections
  aws_config = local.aws_config_file.aws

  # ============================================================================
  # AWS Configuration
  # ============================================================================

  # <PATTERN BLOCKS GO HERE — see Patterns section below>
}
```

## Patterns (building blocks)

Compose `locals.tf` from these reusable blocks. Each one is independent — include only what the module needs.

### Pattern: KMS key alias resolution

Use when the module encrypts resources with a customer-managed KMS key referenced by alias in the JSON config.

Goes **outside** the main `locals` block (because `data` sources can't sit inside `locals {}`):

```hcl
# Compute KMS key alias first (no dependency on s3_config or other resources)
locals {
  kms_key_alias_raw = try(jsondecode(file("${path.module}/${var.aws_config_path}")).aws.s3.kms_key_alias, null)
  kms_key_alias     = local.kms_key_alias_raw != null ? (startswith(local.kms_key_alias_raw, "alias/") ? local.kms_key_alias_raw : "alias/${local.kms_key_alias_raw}") : null
}

data "aws_kms_key" "kms" {
  count  = local.kms_key_alias != null ? 1 : 0
  key_id = local.kms_key_alias
}
```

Why this pattern: the alias may be stored in config either as `my-key` or `alias/my-key`. The local normalizes it, and the `count = … ? 1 : 0` makes the data source optional so the module still applies cleanly when no key is configured.

### Pattern: Default tags

Always include this. The map below is the canonical version — add or remove keys only if the team's tagging policy actually changes.

```hcl
default_tags = {
  Project            = var.project_code
  Environment        = var.environment
  ManagedBy          = "Terraform"
  Repository         = var.repository != "" ? var.repository : null
  Component          = var.component
  Owner              = var.owner
  CostCenter         = var.cost_center
  DataClassification = var.data_classification
  GitRef             = var.git_ref
  GitCommitSHA       = var.git_commit_sha
}
```

These are wired into the AWS provider in `providers.tf`:

```hcl
provider "aws" {
  default_tags {
    tags = local.default_tags
  }
}
```

### Pattern: JSON config parsing

Always include if the module is config-driven.

```hcl
# Parse config from JSON file (relative to module path)
aws_config_file = jsondecode(file("${path.module}/${var.aws_config_path}"))

# Extract nested sections
aws_config = local.aws_config_file.aws
```

The JSON file is expected to have an `aws` top-level key, with sub-sections per service (`s3`, `iam`, `region`, etc.). Example:

```json
{
  "aws": {
    "region": "us-east-1",
    "s3": {
      "bucket_name": "data-lake",
      "versioning": true,
      "kms_key_alias": "data-lake-cmk"
    },
    "iam": {
      "role_name": "data-access",
      "policies": [...]
    }
  }
}
```

### Pattern: Naming convention

Standard form: `<project_code>-<base_name>-<environment>[-<region>]`

Examples:

```hcl
# Bucket name (region-suffixed because S3 names are global)
bucket_name = "${var.project_code}-${local.aws_config.s3.bucket_name}-${var.environment}-${local.aws_config.region}"

# IAM role name (region not needed)
iam_role_name = "${var.project_code}-${local.aws_config.iam.role_name}-${var.environment}"
```

Promote a name to its own standalone local (outside the resource-config map) when **other** locals need to reference it without pulling in the larger map — this avoids accidental dependency cycles.

### Pattern: S3 configuration

Use when the module provisions an S3 bucket. Note that `kms_key_alias`, `sse_algorithm`, and `bucket_keys` are conditional on KMS being configured.

```hcl
s3_config = {
  bucket_name   = "${var.project_code}-${local.aws_config.s3.bucket_name}-${var.environment}-${local.aws_config.region}"
  versioning    = local.aws_config.s3.versioning == true ? true : false
  kms_key_alias = local.kms_key_alias != null ? replace(local.kms_key_alias, "alias/", "") : null
  sse_algorithm = local.kms_key_alias != null ? "aws:kms" : null
  bucket_keys   = try(local.aws_config.s3.bucket_keys, null)
  bucket_policy = templatefile("${path.module}/templates/bucket-policy/s3-bucket-policy.tpl", {
    aws_account_id = data.aws_caller_identity.current.account_id
    bucket_name    = "${var.project_code}-${local.aws_config.s3.bucket_name}-${var.environment}-${local.aws_config.region}"
  })
}
```

Bucket policies live as `.tpl` files under `templates/bucket-policy/` to keep `locals.tf` readable.

### Pattern: IAM role configuration

Use when the module provisions an IAM role with inline policies.

```hcl
iam_role_config = {
  name               = local.iam_role_name
  assume_role_policy = local.assume_role_policy   # define separately, see below
  s3_bucket_arn      = "arn:aws:s3:::${local.s3_config.bucket_name}"
  kms_key_arn        = local.kms_key_alias != null ? data.aws_kms_key.kms[0].arn : null
  inline_policies = [
    for policy in local.aws_config.iam.policies : {
      name = policy.name
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid      = policy.sid
          Effect   = policy.effect
          Action   = policy.action
          Resource = (
            policy.resource == "s3-bucket-arn"   ? "arn:aws:s3:::${local.s3_config.bucket_name}" :
            policy.resource == "s3-bucket-arn/*" ? "arn:aws:s3:::${local.s3_config.bucket_name}/*" :
            policy.resource == "kms-key-arn"     ? (local.kms_key_alias != null ? data.aws_kms_key.kms[0].arn : "*") :
            policy.resource
          )
        }]
      })
    }
  ]
}
```

**Resource placeholder convention:** policies in JSON refer to resources by short tokens (`s3-bucket-arn`, `s3-bucket-arn/*`, `kms-key-arn`) and the local rewrites them to real ARNs. This keeps the JSON cloud-account-agnostic.

The `assume_role_policy` itself usually goes in its own local so other resources can reference it cleanly:

```hcl
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = { Service = "lambda.amazonaws.com" }   # or whatever the trusted principal is
    Action    = "sts:AssumeRole"
  }]
})
```

## Worked example

Given:
- Path: `infra/platform/tf/locals.tf`
- Module description: Platform Module
- Patterns needed: default tags, JSON config parsing, KMS key lookup, S3 config, IAM role config

The generated file should follow this skeleton:

```hcl
# -- infra/platform/tf/locals.tf (Platform Module)
# ============================================================================
# Local Values
# ============================================================================

data "aws_caller_identity" "current" {}

# Compute KMS key alias first (no dependency on s3_config)
locals {
  kms_key_alias_raw = try(jsondecode(file("${path.module}/${var.aws_config_path}")).aws.s3.kms_key_alias, null)
  kms_key_alias     = local.kms_key_alias_raw != null ? (startswith(local.kms_key_alias_raw, "alias/") ? local.kms_key_alias_raw : "alias/${local.kms_key_alias_raw}") : null
}

data "aws_kms_key" "kms" {
  count  = local.kms_key_alias != null ? 1 : 0
  key_id = local.kms_key_alias
}

locals {
  # ============================================================================
  # Default tags (applied to every AWS resource via provider default_tags)
  # ============================================================================
  default_tags = {
    Project            = var.project_code
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Repository         = var.repository != "" ? var.repository : null
    Component          = var.component
    Owner              = var.owner
    CostCenter         = var.cost_center
    DataClassification = var.data_classification
    GitRef             = var.git_ref
    GitCommitSHA       = var.git_commit_sha
  }

  # Parse config from JSON file (relative to module path)
  aws_config_file = jsondecode(file("${path.module}/${var.aws_config_path}"))

  # Extract nested sections
  aws_config = local.aws_config_file.aws

  # ============================================================================
  # AWS Configuration
  # ============================================================================

  iam_role_name = "${var.project_code}-${local.aws_config.iam.role_name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  # S3 Configuration
  s3_config = {
    bucket_name   = "${var.project_code}-${local.aws_config.s3.bucket_name}-${var.environment}-${local.aws_config.region}"
    versioning    = local.aws_config.s3.versioning == true ? true : false
    kms_key_alias = local.kms_key_alias != null ? replace(local.kms_key_alias, "alias/", "") : null
    sse_algorithm = local.kms_key_alias != null ? "aws:kms" : null
    bucket_keys   = try(local.aws_config.s3.bucket_keys, null)
    bucket_policy = templatefile("${path.module}/templates/bucket-policy/s3-bucket-policy.tpl", {
      aws_account_id = data.aws_caller_identity.current.account_id
      bucket_name    = "${var.project_code}-${local.aws_config.s3.bucket_name}-${var.environment}-${local.aws_config.region}"
    })
  }

  # IAM Role Configuration
  iam_role_config = {
    name               = local.iam_role_name
    assume_role_policy = local.assume_role_policy
    s3_bucket_arn      = "arn:aws:s3:::${local.s3_config.bucket_name}"
    kms_key_arn        = local.kms_key_alias != null ? data.aws_kms_key.kms[0].arn : null
    inline_policies = [
      for policy in local.aws_config.iam.policies : {
        name = policy.name
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Sid      = policy.sid
            Effect   = policy.effect
            Action   = policy.action
            Resource = (
              policy.resource == "s3-bucket-arn"   ? "arn:aws:s3:::${local.s3_config.bucket_name}" :
              policy.resource == "s3-bucket-arn/*" ? "arn:aws:s3:::${local.s3_config.bucket_name}/*" :
              policy.resource == "kms-key-arn"     ? (local.kms_key_alias != null ? data.aws_kms_key.kms[0].arn : "*") :
              policy.resource
            )
          }]
        })
      }
    ]
  }
}
```

Notice the formatting details that must be preserved:
- 2-space indentation throughout.
- Map values are aligned with each other (`=` signs in column).
- Section banners use the `# ===…` form, not single-line comments.
- The header comment uses the `# -- <path> (<Module Description>)` pattern.
- Two-`locals` block layout when KMS lookup is involved: one for `kms_key_alias_raw`/`kms_key_alias` (pre-data-source), one for everything else (post-data-source).

## Validation

After writing the file:

1. Run `terraform fmt -check locals.tf` if Terraform is available — it should already be canonically formatted.
2. Run `terraform validate` from the module directory to confirm references resolve. Expect failures only on missing variables or missing JSON config — both indicate prerequisites that need to be addressed in `variables.tf` or the config file, not in `locals.tf`.
3. Confirm any `data "aws_kms_key"` block has `count` (not `for_each`) so the lookup remains optional.
4. Confirm the JSON config file referenced by `var.aws_config_path` actually exists at that path and contains the expected keys.

## Common mistakes to avoid

- **Do not** put `data` sources inside `locals { }` — they must live at the top level.
- **Do not** combine the two `locals` blocks (pre- and post-KMS-data-source) into one when KMS lookup is in play; the pre-block must be evaluated before the data source can be queried.
- **Do not** drop the `default_tags` map or rename its keys — those tag names are part of the team's tagging contract and downstream cost reports depend on them.
- **Do not** hardcode AWS account IDs, region names, or bucket names. Always derive them from `data.aws_caller_identity.current.account_id`, `local.aws_config.region`, or the naming convention.
- **Do not** read JSON config inline at every reference. Parse once into `local.aws_config_file` / `local.aws_config` and reuse those.
- **Do not** create a dependency cycle by referencing a resource-config map (e.g. `local.iam_role_config`) from a value that the map itself depends on. When this risk exists, promote the shared piece (e.g. `local.iam_role_name`, `local.assume_role_policy`) to its own standalone local first.
- **Do not** use `try(... )` without a sensible fallback. `try(value, null)` is the standard for optional config keys; avoid `try(value, "")` unless an empty string is explicitly meaningful.
- **Do not** add Snowflake, Glue, Lambda, or other service-specific blocks unless the module actually provisions those resources. Keep `locals.tf` scoped to the module's responsibility.