---
name: tf-outputs
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform `outputs.tf` file for an AWS module. Trigger when the user mentions "outputs.tf", "Terraform outputs", "expose module results", or asks to surface attributes from child modules so they can be consumed by parent modules, downstream stacks, or HCP Terraform run output. Also trigger when scaffolding a new Terraform module under `infra/<module>/tf/` that already has a `main.tf` with module calls and now needs the outputs layer. The defining features of this skill are: **(1)** outputs are organized by service / module with banner comments mirroring `main.tf`'s phase structure, **(2)** every output has a `description`, **(3)** complex module results are surfaced as **shaped object maps** (using `for k, v in module.X : ...`) rather than raw passthroughs, and **(4)** anything containing credentials, ARNs of trust principals, or external IDs is marked `sensitive = true`. Do NOT use this skill if the user wants a single ad-hoc output, raw `module.X` passthroughs without shaping, or outputs that don't follow the banner-and-description convention.
---

# Terraform Outputs (AWS Module) Skill

## Purpose

Generate an `outputs.tf` file that exposes a Terraform module's results in a **stable, documented shape** — so parent modules and HCP Terraform run summaries see consistent attributes regardless of how the underlying child modules evolve.

The file mirrors `main.tf`'s phase structure with banner comments, descriptions, and (where appropriate) explicitly shaped object maps that decouple downstream consumers from the upstream module's exact output schema.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create an `outputs.tf` for this module"
- "Expose the S3 bucket / IAM role / Lambda details as outputs"
- "Add outputs for the new module call I just added"
- "Scaffold the outputs layer for `infra/<module>/tf/`"
- "Surface module results so the parent stack can consume them"

Do **not** use this skill if:

- The user wants a single one-off `output` block — handle that conversationally rather than regenerating.
- The user is exposing internal debug values that won't be consumed downstream.
- The module produces no useful outputs (not all modules need an `outputs.tf`).

## Required information

Before writing the file, gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path and description

- **Path:** typically `infra/<module>/tf/outputs.tf`. If unspecified, default to that pattern.
- **Module description:** inferred from the directory name (`platform/` → "Platform Module", `data-pipeline/` → "Data Pipeline Module"). If ambiguous, ask.

### 2. Module calls already present in `main.tf`

The skill reads from `main.tf` (or asks the user for) the list of `module "X"` calls already defined. Outputs are derived from these — never invent outputs for modules that don't exist.

For each module call, also identify:

- The **canonical name** people will reference it as (`s3`, `iam_role`, `warehouse` — typically the module block name).
- The **child outputs available** (e.g. `module.s3.bucket_id`, `module.s3.bucket_arn`). If unknown, ask the user for the upstream module's output schema or fall back to a raw passthrough with a TODO to refine later.
- Whether the result is **per-resource** (a single bucket → flat object) or **per-key** (a map of resources → `for k, v in ...` shape).

### 3. Sensitivity

Mark an output `sensitive = true` if it contains:

- Snowflake `iam_user_arn` or `external_id` (storage integration credentials).
- API tokens, passwords, signed URLs, or pre-shared keys.
- Anything the team's security policy classifies as sensitive (ask if unsure).

When in doubt, **ask** rather than defaulting either way — over-marking outputs as sensitive makes them harder to use downstream; under-marking leaks them into HCP Terraform run logs.

### 4. Phase / section grouping

Group outputs by service or by `main.tf` phase. Use the same banner conventions (`# === ... ===` for top-level sections, `# --- ... ---` for individual outputs). The grouping should mirror `main.tf` whenever practical — a maintainer reading both files in sequence should see the same section ordering.

## Output template

Write the file to the path the user specifies, defaulting to `infra/<module>/tf/outputs.tf`.

The file follows this exact structure:

```hcl
# -- <RELATIVE_PATH> (<MODULE_DESCRIPTION>)
# ============================================================================
# <Module Description> Outputs
# ============================================================================

# ============================================================================
# <SECTION 1 NAME, e.g. AWS Outputs>
# ============================================================================

# ----------------------------------------------------------------------------
# <Sub-section / Resource Name>
# ----------------------------------------------------------------------------
output "<name>" {
  description = "<one-line human-readable description>"
  value       = <value-expression>
}

# ----------------------------------------------------------------------------
# <Next sub-section>
# ----------------------------------------------------------------------------
output "<name>" {
  ...
}

# ============================================================================
# <SECTION 2 NAME, e.g. Snowflake Outputs>
# ============================================================================

# ----------------------------------------------------------------------------
# <Sub-section>
# ----------------------------------------------------------------------------
output "<name>" {
  ...
}
```

### Banner rules

- The header banner uses `# -- <path> (<Module>)` followed by `# === ... ===` lines, exactly like `locals.tf` and `main.tf`.
- Top-level sections (`AWS Outputs`, `Snowflake Outputs`, `Networking`, etc.) use the full-width `# === ... ===` form.
- Individual output groups use the `# --- ... ---` form.
- A blank line separates every two `output` blocks.

## Output shaping patterns

Choose the shape that matches the data, in this order of preference.

### Pattern 1: Shaped object — single resource

Use when the module produces **one** resource and the consumer only needs a few fields. Pulling fields explicitly insulates downstream consumers from upstream attribute renames.

```hcl
# ----------------------------------------------------------------------------
# S3 Bucket Outputs
# ----------------------------------------------------------------------------
output "s3_bucket" {
  description = "S3 bucket details for Snowflake external stage"
  value = {
    name              = module.s3.bucket_id
    arn               = module.s3.bucket_arn
    region            = module.s3.bucket_region
    versioning_status = module.s3.versioning_status
  }
}
```

Why: if `terraform-aws-s3` later renames `bucket_id` to `id`, only this file needs to change — every downstream consumer keeps reading `s3_bucket.name`.

### Pattern 2: Shaped object map — many resources keyed by config key

Use when the module produces a **map of resources** (warehouses, databases, file formats, stages, tables, etc.) and you want to expose a stable, curated subset of fields per item.

```hcl
output "warehouses" {
  description = "Map of warehouse names to their details"
  value = {
    for k, v in module.warehouse.warehouses : k => {
      name                      = v.name
      fully_qualified_name      = v.fully_qualified_name
      warehouse_size            = v.warehouse_size
      auto_suspend              = v.auto_suspend
      auto_resume               = v.auto_resume
      min_cluster_count         = v.min_cluster_count
      max_cluster_count         = v.max_cluster_count
      comment                   = v.comment
    }
  }
}
```

Standard fields to include for each Snowflake object type:

| Object | Recommended fields |
|---|---|
| Warehouse | `name`, `fully_qualified_name`, `warehouse_size`, `warehouse_type`, `auto_suspend`, `auto_resume`, `initially_suspended`, `min_cluster_count`, `max_cluster_count`, `scaling_policy`, `comment` |
| Database | `name`, `fully_qualified_name`, `comment` |
| Schema | `name`, `fully_qualified_name`, `database`, `comment` |
| File format | `name`, `fully_qualified_name`, `database`, `schema`, `format_type`, `comment` |

For AWS objects with similar map shapes (e.g. multiple Lambda functions, multiple SQS queues), apply the same pattern with the relevant fields (`name`, `arn`, `function_name`, etc.).

### Pattern 3: Raw module passthrough

Use when the upstream module's output is already well-shaped, the consumer needs everything, or it's not yet clear which fields will be used. Raw passthroughs are a defensible default for prototypes; they should ideally be replaced with shaped outputs (Pattern 1 or 2) before the module hits a release tag.

```hcl
output "stages" {
  description = "Stage outputs from module"
  value       = module.stage
}

output "snowpipes" {
  description = "Map of snowpipe names to their details"
  value       = module.pipe.pipes
}
```

When using this pattern, add a `# TODO:` comment if the intent is to refine the shape later — otherwise the next person to read the file won't know whether the rawness is deliberate.

### Pattern 4: Sensitive outputs

Outputs that contain credentials, trust principals, or external IDs are marked sensitive. The whole module result is usually sensitive in one piece — don't try to selectively redact.

```hcl
output "storage_integrations" {
  description = "Storage integration outputs from module"
  sensitive   = true
  value       = module.storage_integrations
}
```

`sensitive = true` lives **between** `description` and `value` for visual consistency.

### Pattern 5: Targeted scalar passthrough

Use when only one specific child output is needed downstream. Cleaner than re-exposing the whole module result.

```hcl
output "view_names" {
  description = "Map of view config keys to Snowflake view names."
  value       = module.views.view_names
}

output "view_fully_qualified_names" {
  description = "Map of view config keys to fully-qualified Snowflake view names."
  value       = module.views.view_fully_qualified_names
}
```

## Worked example

Given a module with three module calls in `main.tf`:

- `module "s3"` — single S3 bucket
- `module "iam_role"` — single IAM role
- `module "lambda"` — map of Lambda functions

A reasonable `outputs.tf` is:

```hcl
# -- infra/data-pipeline/tf/outputs.tf (Data Pipeline Module)
# ============================================================================
# Data Pipeline Module Outputs
# ============================================================================

# ============================================================================
# AWS Outputs
# ============================================================================

# ----------------------------------------------------------------------------
# S3 Bucket Outputs
# ----------------------------------------------------------------------------
output "s3_bucket" {
  description = "S3 bucket details for the CSV landing zone"
  value = {
    name              = module.s3.bucket_id
    arn               = module.s3.bucket_arn
    region            = module.s3.bucket_region
    versioning_status = module.s3.versioning_status
  }
}

# ----------------------------------------------------------------------------
# IAM Role Outputs
# ----------------------------------------------------------------------------
output "iam_role" {
  description = "IAM role details for Lambda execution"
  value = {
    arn  = module.iam_role.role_arn
    name = module.iam_role.role_name
  }
}

# ----------------------------------------------------------------------------
# Lambda Function Outputs
# ----------------------------------------------------------------------------
output "lambda_functions" {
  description = "Map of Lambda function names to their details"
  value = {
    for k, v in module.lambda.functions : k => {
      name          = v.function_name
      arn           = v.function_arn
      invoke_arn    = v.invoke_arn
      runtime       = v.runtime
      memory_size   = v.memory_size
      timeout       = v.timeout
    }
  }
}
```

Notice the formatting details that must be preserved:

- `description` is the first attribute; `value` is the last.
- Map values inside shaped objects are aligned (`=` signs in column).
- 2-space indentation throughout.
- The header banner uses `# -- <path> (<Module>)` exactly like `locals.tf` and `main.tf`.
- A blank line separates every two `output` blocks; a blank line also separates each banner from the block that follows.

## Validation

After writing the file:

1. Run `terraform fmt -check outputs.tf` if Terraform is available locally — the file should already be canonically formatted.
2. Confirm every `module.X.Y` reference in the file actually exists by cross-checking against `main.tf`. Outputs from a module that hasn't been declared yet will fail at plan time.
3. Confirm every `output` has a `description` — outputs without descriptions are surfaced as `null` in HCP Terraform run summaries and degrade the developer experience.
4. Confirm sensitive outputs are flagged. As a heuristic: if a value contains an external ID, an IAM user ARN belonging to a trust principal, an API token, or a credential, it's sensitive.
5. Cross-reference the section banners against `main.tf`'s phase banners — they should be in the same order. If the module has a Phase 4 in `main.tf` but no outputs section for it in `outputs.tf`, that's worth confirming with the user (it may be intentional, but it's worth asking).

## Common mistakes to avoid

- **Do not** omit `description`. Every output needs one. Treat the description as the public contract for what this output means.
- **Do not** expose secrets without `sensitive = true`. Storage integration credentials, external IDs, and trust principals always need it.
- **Do not** raw-passthrough modules in production code without a `# TODO:` comment if the intent is to refine the shape later. Raw passthroughs are fine for prototypes but become technical debt fast.
- **Do not** use `for_each` syntax inside an output's `value` — that's not valid. Use `for k, v in ... : k => { ... }` instead.
- **Do not** create outputs that mix data from multiple modules into one shape just for convenience. Keep one output per module / service so renames and removals stay localized.
- **Do not** include outputs for resources that don't yet exist in `main.tf`. If a module call hasn't been added, the corresponding output block belongs in the same PR that adds the module call — not earlier.
- **Do not** drop the banner comments. They mirror `main.tf`'s phase structure and make the two files navigable in tandem.
- **Do not** rename existing outputs without checking who consumes them. Outputs are part of the module's public API; renames are breaking changes for parent stacks.