---
name: tf-variables
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform `variables.tf` file for an AWS module. Trigger when the user mentions "variables.tf", "Terraform input variables", "module inputs", "feature flags", "tagging variables", or asks to declare the variables that `locals.tf`, `main.tf`, and `providers-aws.tf` reference. Also trigger when scaffolding a new Terraform module under `infra/<module>/tf/` that already has `backend.tf` and now needs the variable declarations. The defining features of this skill are: **(1)** variables are organized into clearly-banner-separated sections (Module Identity, Snowflake Provider, Config Paths, Feature Flags, Tagging Metadata), **(2)** every variable has a `description` and an explicit `type`, **(3)** `default` values are provided wherever a sensible local-run default exists, **(4)** sensitive values are flagged with `sensitive = true`, and **(5)** environment-like fields use `validation` blocks. Do NOT use this skill if the user wants a single ad-hoc variable, variables spread across multiple files (e.g. `variables-aws.tf`, `variables-snowflake.tf`), or wants to skip the section-banner convention.
---

# Terraform Variables (AWS Module) Skill

## Purpose

Generate a `variables.tf` file that declares every input variable referenced by `locals.tf`, `main.tf`, `providers-aws.tf`, and any other file in the module — with descriptions, types, defaults, sensitivity flags, and validations applied consistently.

The file is the module's **public API**. Anyone calling the module (or running `terraform plan` from a workspace) reads `variables.tf` first to understand what they need to supply, what's defaulted, and what's sensitive. Treat it accordingly: every block is a contract, every default is a deliberate choice.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create a `variables.tf` for this module"
- "Declare the inputs this module needs"
- "Scaffold the variables layer for `infra/<module>/tf/`"
- "Add the standard tagging variables"
- "Add a feature flag for `<thing>`"

Do **not** use this skill if:

- The user wants a single ad-hoc variable added — handle conversationally rather than regenerating.
- The user is splitting variables across multiple files (`variables-aws.tf`, `variables-snowflake.tf`). The convention this skill enforces is a single `variables.tf` with section banners.
- The module needs Terraform's [variable validation in postcondition form](https://developer.hashicorp.com/terraform/language/expressions/custom-conditions) (preconditions/postconditions) — those live in `main.tf` near the resources they validate, not here.

## Required information

Before writing the file, gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path and description

- **Path:** typically `infra/<module>/tf/variables.tf`. If unspecified, default to that pattern.
- **Module description:** inferred from the directory name (`platform/` → "Platform Module", `data-pipeline/` → "Data Pipeline Module"). If ambiguous, ask.

### 2. Variables actually used by the module

The skill should not declare variables that aren't referenced. Cross-reference these sources:

- `locals.tf` — every `var.X` reference.
- `main.tf` — every `var.X` reference.
- `providers-aws.tf` and other provider files — every `var.X` reference.

If `locals.tf` follows the standard pattern from the `tf-locals` skill, the **standard tagging set** (`project_code`, `environment`, `repository`, `component`, `owner`, `cost_center`, `data_classification`, `git_ref`, `git_commit_sha`) is required, plus `aws_config_path`.

### 3. Sensitivity

Mark a variable `sensitive = true` if it contains:

- Private keys, API tokens, passwords, or pre-shared secrets.
- Anything that should not appear in plan output or HCP Terraform run logs.

When in doubt, **ask**. Over-marking variables sensitive makes debugging harder; under-marking leaks them.

### 4. Defaults vs. required

Use this decision rule:

- **Provide a default** when a sensible local-run value exists and forgetting to supply it shouldn't break anything (project codes, environment names, role names, tag fields, file paths, feature flags).
- **Omit `default`** (making it required) when the value must come from CI / the user every time and there is no safe fallback (Snowflake credentials, organization names, account names, private keys).

Pattern: secrets and account-level identifiers are required; everything else has a default.

## Output template

Write the file to the path the user specifies, defaulting to `infra/<module>/tf/variables.tf`.

The file follows this exact section structure. Sections may be **omitted** when the module doesn't need them (e.g. a pure AWS module with no Snowflake provider drops the "Snowflake Provider Variables" section). Do not reorder them.

```hcl
# -- <RELATIVE_PATH> (<MODULE_DESCRIPTION>)
# ============================================================================
# <Module Description> Variables
# ============================================================================

# Module identity (project_code, environment) — no banner; these come first.
variable "environment" { ... }
variable "project_code" { ... }

# ============================================================================
# Snowflake Provider Variables
# ============================================================================
# (only if the module talks to Snowflake)

variable "snowflake_organization_name" { ... }
variable "snowflake_account_name" { ... }
# ... etc

# ============================================================================
# Configuration File Paths
# ============================================================================

variable "aws_config_path" { ... }
variable "snowflake_config_path" { ... }   # only if Snowflake is in scope

# ============================================================================
# Feature Flags
# ============================================================================
# (only if the module has feature flags)

variable "enable_<thing>" { ... }

# ============================================================================
# Tagging Metadata (injected from CI; safe defaults for local runs)
# ============================================================================

variable "git_ref" { ... }
variable "git_commit_sha" { ... }
variable "cost_center" { ... }
variable "component" { ... }
variable "owner" { ... }
variable "data_classification" { ... }
variable "repository" { ... }
```

### Banner rules

- The header banner uses `# -- <path> (<Module>)` followed by `# === ... ===` lines, exactly like every other file in the module.
- Top-level sections use the full-width `# === ... ===` form.
- The first two variables (`environment` and `project_code`) sit **directly under the file header with no section banner** — they're the module's identity and don't need their own banner.
- A blank line separates every two `variable` blocks.

### Variable block format

Every variable follows this exact attribute order:

```hcl
variable "<name>" {
  description = "<one-line human-readable description>"
  type        = <type>
  default     = <value>           # only when a default exists
  sensitive   = true              # only when sensitive
  
  validation {                    # only when validation applies
    condition     = <expression>
    error_message = "<message>"
  }
}
```

Rules:

- `description` is **always first** and **always present**.
- `type` is **always present** and explicit (`string`, `bool`, `number`, `list(string)`, `map(string)`, `object({ ... })`).
- `default` follows `type` if present. Skipping `default` makes the variable required.
- `sensitive = true` follows `default` (or `type` if no default).
- `validation` blocks come last, separated by a blank line from the attributes.
- Attribute values are aligned (`=` signs in column) within each block.

## Section-by-section guidance

### Module identity (no banner)

Always required. Two variables, no banner above them.

```hcl
variable "environment" {
  description = "Environment name (devl, test, prod)"
  type        = string
  default     = "ci"

  validation {
    condition     = contains(["ci", "devl", "test", "prod"], var.environment)
    error_message = "Environment must be devl, test, or prod."
  }
}

variable "project_code" {
  description = "Project code prefix for resource naming (e.g., snw-lkh)"
  type        = string
  default     = "<module-default>"
}
```

The `environment` validation list should match the team's deployment tiers exactly. If the user has a different set, update both the `condition` and the `error_message` together — out-of-sync validation is a confusing failure mode.

### Snowflake Provider Variables

Include this section **only** if the module configures the Snowflake provider. Variables in this section are typically required (no `default`) and the private key is sensitive.

```hcl
variable "snowflake_organization_name" {
  description = "Snowflake organization name (set via TF_VAR_snowflake_organization_name env var)"
  type        = string
}

variable "snowflake_account_name" {
  description = "Snowflake account name (set via TF_VAR_snowflake_account_name env var)"
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake user for Terraform operations (set via TF_VAR_snowflake_user env var)"
  type        = string
}

variable "snowflake_private_key" {
  description = "Base64-encoded PEM private key file. Generate with: base64 -i snowflake_key.p8 | tr -d '\\n'"
  type        = string
  sensitive   = true
}

variable "db_provisioner_role" {
  description = "Snowflake role for database provisioning operations"
  type        = string
  default     = "DB_PROVISIONER"
}

variable "warehouse_provisioner_role" {
  description = "Snowflake role for warehouse provisioning operations"
  type        = string
  default     = "WAREHOUSE_PROVISIONER"
}

variable "data_object_provisioner_role" {
  description = "Snowflake role for data object provisioning operations"
  type        = string
  default     = "DATA_OBJECT_PROVISIONER"
}

variable "ingest_object_provisioner_role" {
  description = "Snowflake role for ingest object provisioning operations"
  type        = string
  default     = "INGEST_OBJECT_PROVISIONER"
}

variable "snowflake_warehouse" {
  description = "Snowflake warehouse for Terraform operations"
  type        = string
  default     = "COMPUTE_WH"
}
```

Pattern: **identifiers and credentials are required, role names and warehouse names default to standard values.** This makes local runs and CI both work without leaking secrets into defaults.

### Configuration File Paths

Always required when `locals.tf` parses JSON config files (the standard pattern from the `tf-locals` skill).

```hcl
variable "aws_config_path" {
  description = "Path to AWS config JSON file (relative to module)"
  type        = string
  default     = "config/aws/devl/config.json"
}

variable "snowflake_config_path" {
  description = "Path to Snowflake config JSON file (relative to module)"
  type        = string
  default     = "config/snowflake/devl/config.json"
}
```

Defaults point at the `devl` config because that's the safest local-run target — promoting through environments overrides the default explicitly.

### Feature Flags

Include this section only if the module has runtime toggles. Each flag should have an explicit description that explains **when** to flip it, not just what it controls.

```hcl
variable "enable_snowpipe_creation" {
  description = "Enable Snowpipe creation. Set to false on first apply, then true on second apply after trust policy is updated."
  type        = bool
  default     = true
}
```

The "set to X on first apply, Y on second apply" pattern is common for resources with bootstrap circular dependencies (storage integrations + IAM trust policies) — when this exists, document the sequence in the description.

### Tagging Metadata

Always required. These variables back the `local.default_tags` map in `locals.tf`.

```hcl
variable "git_ref" {
  description = "Git ref (branch or tag) that produced this apply. Set via TF_VAR_git_ref in CI."
  type        = string
  default     = "local"
}

variable "git_commit_sha" {
  description = "Short git commit SHA. Set via TF_VAR_git_commit_sha in CI."
  type        = string
  default     = "local"
}

variable "cost_center" {
  description = "Cost center for billing allocation."
  type        = string
  default     = "data-platform"
}

variable "component" {
  description = "Component name within the project (e.g., platform, ingestion, dashboard)."
  type        = string
  default     = "<module-default>"
}

variable "owner" {
  description = "Owning team for the resources."
  type        = string
  default     = "data-platform"
}

variable "data_classification" {
  description = "Data classification tier (public, internal, confidential, restricted)."
  type        = string
  default     = "confidential"
}

variable "repository" {
  description = "GitHub repository name (owner/repo). Set via TF_VAR_repository in CI."
  type        = string
  default     = ""
}
```

Pattern: **CI-injected fields default to a safe local-run sentinel** (`"local"` for git fields, `""` for repository). The `local.default_tags` map in `locals.tf` should already handle the `repository != ""` case to convert empty strings to `null` in the tag.

## Worked example — pure AWS module (no Snowflake)

Given:
- Path: `infra/data-pipeline/tf/variables.tf`
- Module description: Data Pipeline Module
- No Snowflake provider, no feature flags

The generated file should be:

```hcl
# -- infra/data-pipeline/tf/variables.tf (Data Pipeline Module)
# ============================================================================
# Data Pipeline Module Variables
# ============================================================================

variable "environment" {
  description = "Environment name (devl, test, prod)"
  type        = string
  default     = "ci"

  validation {
    condition     = contains(["ci", "devl", "test", "prod"], var.environment)
    error_message = "Environment must be devl, test, or prod."
  }
}

variable "project_code" {
  description = "Project code prefix for resource naming (e.g., snw-lkh)"
  type        = string
  default     = "datapipe"
}

# ============================================================================
# Configuration File Paths
# ============================================================================

variable "aws_config_path" {
  description = "Path to AWS config JSON file (relative to module)"
  type        = string
  default     = "config/aws/devl/config.json"
}

# ============================================================================
# Tagging Metadata (injected from CI; safe defaults for local runs)
# ============================================================================

variable "git_ref" {
  description = "Git ref (branch or tag) that produced this apply. Set via TF_VAR_git_ref in CI."
  type        = string
  default     = "local"
}

variable "git_commit_sha" {
  description = "Short git commit SHA. Set via TF_VAR_git_commit_sha in CI."
  type        = string
  default     = "local"
}

variable "cost_center" {
  description = "Cost center for billing allocation."
  type        = string
  default     = "data-platform"
}

variable "component" {
  description = "Component name within the project (e.g., platform, ingestion, dashboard)."
  type        = string
  default     = "data-pipeline"
}

variable "owner" {
  description = "Owning team for the resources."
  type        = string
  default     = "data-platform"
}

variable "data_classification" {
  description = "Data classification tier (public, internal, confidential, restricted)."
  type        = string
  default     = "confidential"
}

variable "repository" {
  description = "GitHub repository name (owner/repo). Set via TF_VAR_repository in CI."
  type        = string
  default     = ""
}
```

Notice the formatting details that must be preserved:

- 2-space indentation throughout.
- Attribute values aligned within each block (`description`, `type`, `default` all line up at the `=`).
- A blank line between the attribute section and the `validation` block.
- A blank line between every two `variable` blocks.
- Section banners use `# === ... ===` exactly like `locals.tf` and `main.tf`.

## Validation

After writing the file:

1. Run `terraform fmt -check variables.tf` if Terraform is available locally — the file should already be canonically formatted.
2. Cross-reference every `var.X` reference in `locals.tf`, `main.tf`, and `providers-aws.tf` against the variables declared here. Missing variables fail at plan time with `Reference to undeclared input variable`; surplus variables aren't an error but represent dead code that should be cleaned up.
3. Confirm every variable has a `description`. Variables without descriptions degrade the HCP Terraform run UI and the `terraform-docs` output.
4. Confirm sensitive variables (private keys, tokens, passwords) have `sensitive = true`. Use the heuristic from the "Sensitivity" section above.
5. Confirm `validation` blocks have `error_message` text that names the field and lists the allowed values — generic "Invalid input" messages are unhelpful.
6. Confirm the variables in this file align with the team's tagging contract (the `local.default_tags` map in `locals.tf`). Drift between the two is a common source of `Repository` showing up as `null` in production tags.

## Common mistakes to avoid

- **Do not** omit `description`. Every variable needs one. Treat the description as the public contract for what the variable means and where it gets set (env var name, CI source, etc.).
- **Do not** omit `type`. Implicit-type variables work but make the module's API harder to read.
- **Do not** add a `default` to credentials, private keys, or account identifiers. Required is the right shape — defaults invite leaking secrets into VCS.
- **Do not** hardcode environment tier names (`["dev", "stage", "prod"]`) without confirming with the user. The team's actual tiers may differ (`["ci", "devl", "test", "prod"]` per the example).
- **Do not** put module-call inputs (e.g. specific bucket names, role ARNs) in `variables.tf`. Those belong in JSON config files, parsed by `locals.tf`. Variables in this file are for things that change per-environment or per-CI-run, not per-resource.
- **Do not** spread variables across multiple files (`variables-aws.tf`, `variables-snowflake.tf`). The single-file convention with section banners is what makes the module's API legible at a glance.
- **Do not** drop the section banners. They're how a maintainer skims the file to find what they need.
- **Do not** add `validation` blocks for things Terraform's type system can already enforce (e.g. validating that a `bool` is one of `[true, false]`). Reserve validation for genuine value constraints.
- **Do not** forget to update `locals.tf` if you add a new variable here. A variable not referenced anywhere is dead code; a variable referenced in `locals.tf` but missing here will fail at plan time. The two files evolve together.