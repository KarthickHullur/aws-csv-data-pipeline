---
name: tf-providers
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform AWS provider configuration file (typically `providers-aws.tf` or `providers.tf`) for an AWS module. Trigger when the user mentions "providers.tf", "providers-aws.tf", "AWS provider configuration", "default tags", "configure the AWS provider", or asks to wire region and tagging into a module's provider block. Also trigger when scaffolding a new Terraform module under `infra/<module>/tf/` that already has `backend.tf`, `locals.tf`, and `variables.tf`, and now needs the provider layer. The defining features of this skill are: **(1)** the AWS provider's `region` is sourced from `local.aws_config.region` (parsed out of the JSON config), **(2)** the `default_tags` block references `local.default_tags` defined in `locals.tf`, and **(3)** the file's header explicitly notes that `required_providers` lives in `backend.tf`, not here. Do NOT use this skill if the user wants the `required_providers` block in this file, hardcoded regions, inline tag maps, or multiple distinct AWS provider aliases (multi-account / multi-region setups need separate handling).
---

# Terraform AWS Provider Skill

## Purpose

Generate the AWS provider configuration file (`providers-aws.tf` by convention) for an AWS Terraform module. The file does one thing: it tells the AWS provider where to operate (`region`) and what to tag every managed resource with (`default_tags`).

The `required_providers` block lives in `backend.tf` alongside `required_version` and the `cloud { }` block — this skill **does not** generate `required_providers`, and explicitly notes that fact in the file header so future maintainers don't add it here by accident.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create a `providers-aws.tf` for this module"
- "Configure the AWS provider for this module"
- "Wire up `default_tags` for this module"
- "Set the AWS region from the JSON config"
- "Scaffold the provider layer for `infra/<module>/tf/`"

Do **not** use this skill if:

- The user wants the `required_providers` block here — that belongs in `backend.tf`.
- The user is using hardcoded region values instead of JSON-config-driven values.
- The module needs **multiple AWS provider aliases** (e.g. cross-account or cross-region orchestration). Multi-provider modules need a different pattern — handle conversationally.
- The module isn't AWS — for Snowflake, GCP, Azure, etc., this skill does not apply.

## Required information

Before writing the file, gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path and description

- **Path:** typically `infra/<module>/tf/providers-aws.tf`. If the module already uses `providers.tf` (single file for everything), default to that filename instead.
- **Module description:** inferred from the directory name (`platform/` → "Platform Module", `data-pipeline/` → "Data Pipeline Module"). If ambiguous, ask.

### 2. Filename convention

Two conventions are common in this codebase. Check the existing module structure (or ask the user) to pick the right one:

- **`providers-aws.tf`** — used when the module has multiple providers, each in its own file (e.g. `providers-aws.tf`, `providers-snowflake.tf`). This is the more common pattern in mixed AWS-and-Snowflake modules.
- **`providers.tf`** — used when the module has only an AWS provider, with no other providers configured.

When in doubt, prefer `providers-aws.tf` — it makes future provider additions less disruptive.

### 3. Required prerequisites in `locals.tf`

The skill assumes these locals exist in `locals.tf`. If they don't, tell the user they need to be added before the provider file will compile:

| Local | Purpose | Source |
|---|---|---|
| `local.aws_config.region` | The AWS region the provider operates in | Parsed from `var.aws_config_path` JSON's `aws.region` key |
| `local.default_tags` | The standard tag map applied to every AWS resource | Computed in `locals.tf` from project-level variables |

Both are part of the standard `locals.tf` produced by the `tf-locals` skill — if the locals file follows that pattern, no additional work is needed.

### 4. Required prerequisites in `backend.tf`

The `required_providers` block must exist in `backend.tf` and must declare `aws` with a version constraint. Example:

```hcl
terraform {
  required_version = "~>1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.80"
    }
  }
  cloud {
    organization = "<org>"
    workspaces { name = "<repo-name>" }
  }
}
```

If the user reports that `backend.tf` only has the `cloud { }` block and no `required_providers`, this skill should **flag that as a prerequisite** — the AWS provider won't initialize cleanly without a declared version constraint.

## Output template

Write the file to the path the user specifies, defaulting to `infra/<module>/tf/providers-aws.tf`.

The file must follow this **exact** structure:

```hcl
# -- <RELATIVE_PATH> (<MODULE_DESCRIPTION>)
# ============================================================================
# AWS Provider Configuration
# ============================================================================
# NOTE: required_providers block is in backend.tf
# ============================================================================
provider "aws" {
  region = local.aws_config.region
  default_tags {
    tags = local.default_tags
  }
}
```

### Header comment

The first comment line uses the standard `# -- <relative_path> (<Module Description>)` form, matching every other file in the module.

The second-banner `NOTE:` line is **mandatory** — it tells future maintainers exactly where to find the `required_providers` block. Without it, the most common modification mistake is "I'll just add `required_providers` here," which then conflicts with `backend.tf`.

### Provider block

- `region` is **always** read from `local.aws_config.region` — never hardcoded, never read from `var.region`.
- `default_tags { tags = local.default_tags }` is **always** present.
- No other arguments. If the module needs `assume_role`, `profile`, or alternate auth, that's a multi-provider scenario and this skill doesn't apply — handle conversationally.

## Worked example

Given:
- Path: `infra/platform/tf/providers-aws.tf`
- Module description: Platform Module

The generated file should be **exactly**:

```hcl
# -- infra/aws/tf/providers.tf
# ============================================================================
# AWS Provider Configuration
# ============================================================================
# NOTE: required_providers block is in backend.tf
# ============================================================================
provider "aws" {
  region = local.aws_config.region
  default_tags {
    tags = local.default_tags
  }
}
```

Notice the formatting details that must be preserved:

- The `provider "aws"` block uses 2-space indentation.
- `region` sits directly above `default_tags`, with no blank line between them.
- The `default_tags` block uses 2-space indentation for `tags = local.default_tags`.
- A trailing newline at the end of the file is required.
- The "NOTE: required_providers block is in backend.tf" line is the **last** banner line before the provider block — it should not be moved or rephrased.

## Validation

After writing the file:

1. Run `terraform fmt -check providers-aws.tf` if Terraform is available locally — the file should already be canonically formatted.
2. Run `terraform validate` from the module directory. Expect failures only if `local.aws_config.region` or `local.default_tags` aren't defined — both indicate missing pieces in `locals.tf`, not in the provider file.
3. Confirm `backend.tf` declares `required_providers` with an `aws` entry. If it doesn't, surface that as a follow-up before running `terraform init`.
4. Confirm there are no other `provider "aws"` blocks in the module — duplicate providers cause initialization conflicts.

## Common mistakes to avoid

- **Do not** add a `required_providers` block in this file. It belongs in `backend.tf`. The mandatory `NOTE:` line in the header exists specifically to prevent this.
- **Do not** hardcode the region (`region = "us-east-1"`). It must come from `local.aws_config.region` so the JSON config remains the single source of truth.
- **Do not** read region from a variable directly (`region = var.region`). The JSON config wraps the region in `local.aws_config`, and the standard pattern is to derive everything AWS-related from there.
- **Do not** define `default_tags` inline as a literal map. It must reference `local.default_tags`, which is computed in `locals.tf` from the project-level variables (`var.project_code`, `var.environment`, `var.git_commit_sha`, etc.).
- **Do not** add `assume_role`, `profile`, `endpoints`, or other auth-related arguments. Authentication is handled by HCP Terraform via workspace credentials or by AWS CLI environment variables — not by per-module provider config.
- **Do not** add an `alias` to the AWS provider. Aliased providers are a multi-account / multi-region pattern that this skill explicitly doesn't cover.
- **Do not** drop the `NOTE:` banner line. It's the file's most important comment — it tells the next person where `required_providers` lives.
- **Do not** rename `default_tags` to something else (`tags`, `common_tags`). `default_tags` is the AWS provider's actual block name and renaming it will cause Terraform to error.