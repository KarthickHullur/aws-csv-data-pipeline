---
name: tf-versions
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform `versions.tf` file. Trigger when the user mentions "versions.tf", "required_providers", "provider version constraints", "declare providers", or asks to specify which providers a module needs and at what versions. Also trigger when scaffolding a new Terraform module under `infra/<module>/tf/` that already has `backend.tf` and now needs the provider declarations. The defining features of this skill are: **(1)** the file owns the `required_providers` block exclusively — `backend.tf` keeps `required_version` and `cloud { }` but does NOT declare providers, **(2)** only providers the module actually uses are declared (no kitchen-sink baseline), and **(3)** version constraints follow the team's standard form (`>= X.Y` for floors, `~> X.Y` for pinned minor). Do NOT use this skill if the user wants `required_version` declared here (it lives in `backend.tf`), if they want `required_providers` in `backend.tf` instead, or if they want the `provider "..." { }` configuration block — that goes in `providers-aws.tf` / `providers-snowflake.tf`.
---

# Terraform Versions Skill

## Purpose

Generate a `versions.tf` file that declares **only** the `required_providers` block — listing every provider the module actually uses, with a `source` and `version` constraint for each.

This skill enforces a clear separation of concerns across the module's foundational files:

| File | Owns |
|---|---|
| `backend.tf` | `required_version` + `cloud { }` block |
| `versions.tf` | `required_providers` block (this skill) |
| `providers-aws.tf` (and siblings) | Actual `provider "..." { }` configuration |

A common antipattern is for `versions.tf` to drift into a copy-paste of every provider the team has ever used. This skill explicitly resists that: declare what the module needs, nothing more.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create a `versions.tf` for this module"
- "Declare `required_providers`"
- "Pin the AWS / Snowflake / [other] provider version"
- "Scaffold the provider declarations for `infra/<module>/tf/`"
- "Add a new provider to this module" (extending an existing `versions.tf`)

Do **not** use this skill if:

- The user wants `required_version` here — that belongs in `backend.tf` per this team's convention.
- The user wants `required_providers` in `backend.tf` instead — explain the convention split and confirm before proceeding.
- The user wants a `provider "..." { }` configuration block (with `region`, `default_tags`, etc.) — that's the `tf-provider` skill's job.

## Required information

Before writing the file, gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path and description

- **Path:** typically `infra/<module>/tf/versions.tf`. If unspecified, default to that pattern.
- **Module description:** inferred from the directory name (`platform/` → "Platform Module", `data-pipeline/` → "Data Pipeline Module"). If ambiguous, ask.

### 2. Providers actually used by the module

The skill should not declare providers that aren't used. Determine the list from one of these sources, in order of preference:

1. **Existing files in the module** — scan for `provider "..." { }` blocks (in `providers-*.tf`), `module "..." { providers = { ... } }` references in `main.tf`, and direct `resource "<provider>_..." `references in `main.tf`. The set of providers actually referenced is the set to declare.
2. **The user's stated intent** — if the module is being scaffolded fresh, ask which providers it needs. Don't guess.

Common providers and their canonical sources:

| Provider | Source | Typical floor |
|---|---|---|
| AWS | `hashicorp/aws` | `>= 5.0` |
| Snowflake | `snowflakedb/snowflake` | `>= 1.0.0` |
| Random | `hashicorp/random` | `>= 3.0` |
| Null | `hashicorp/null` | `>= 3.0` |
| Time | `hashicorp/time` | `>= 0.9` |
| TLS | `hashicorp/tls` | `>= 4.0` |
| External | `hashicorp/external` | `>= 2.0` |
| HTTP | `hashicorp/http` | `>= 3.0` |
| Local | `hashicorp/local` | `>= 2.0` |
| Archive | `hashicorp/archive` | `>= 2.0` |

If a needed provider isn't on this list, **ask the user for the source string** (e.g. `databricks/databricks`, `mongodb/mongodbatlas`) rather than guessing. Inventing a `source` value is the worst possible failure mode here — `terraform init` will fail with a confusing "provider not found" error that the user then has to debug.

### 3. Version constraint style

Two constraint styles are both valid; the team's convention from the example file is:

- **`>= X.Y`** — minimum version, no upper bound. Used for stable providers where minor-version upgrades are safe (`hashicorp/aws`, `hashicorp/random`).
- **`~> X.Y.Z`** — pessimistic constraint, allows patch-level updates only. Used when you need to pin tightly, typically for less-stable providers or when a specific bug fix matters.

If the user doesn't specify, **default to `>= X.Y`** matching the floors in the table above. Confirm with the user if the module has unusual stability requirements.

## Output template

Write the file to the path the user specifies, defaulting to `infra/<module>/tf/versions.tf`.

The file must follow this **exact** structure:

```hcl
# -- <RELATIVE_PATH> (<MODULE_DESCRIPTION>)
# ============================================================================
# Terraform Version and Provider Requirements
# ============================================================================
terraform {
  required_version = "~> 1.14.0"
  required_providers {
    <PROVIDER_NAME> = {
      source  = "<NAMESPACE>/<NAME>"
      version = "<CONSTRAINT>"
    }
    # ... one block per provider the module uses
  }
}
```

### Header banner

The first comment line uses the standard `# -- <relative_path> (<Module Description>)` form, matching every other file in the module. The section banner reads `# Terraform Version and Provider Requirements` exactly.

### `required_version` here vs. `backend.tf`

In this team's convention:

- `versions.tf` owns `required_providers` (this skill).
- `backend.tf` owns `required_version` and `cloud { }`.

However, the example file shows `required_version = "~> 1.14.0"` declared in **both** files. This is technically allowed by Terraform (the constraints just need to be compatible), but it's a duplication risk. The skill's behavior is:

- **By default, include `required_version` in `versions.tf`** matching what `backend.tf` declares (the example shows this pattern).
- If the user reports that `backend.tf` already declares `required_version` and prefers a single source of truth, **omit it from `versions.tf`**.
- If the two files end up with **conflicting** `required_version` constraints, that's a bug — flag it and ask the user which value is correct.

When in doubt, check `backend.tf` first and match its `required_version` value here.

### Provider block format

Each provider block uses this exact shape:

```hcl
<provider_name> = {
  source  = "<namespace>/<name>"
  version = "<constraint>"
}
```

Rules:

- `source` is **always present** and uses the `namespace/name` form (e.g. `hashicorp/aws`, not just `aws`).
- `version` is **always present** with an explicit constraint — never omit it, never use `>= 0.0.0`.
- Attribute values are aligned (`=` signs in column) within each block.
- Blocks are separated by a blank line **only when** the user explicitly wants them grouped; otherwise they sit consecutively as in the example.
- Order: HashiCorp providers first (alphabetical or by importance — `aws` first if present), then third-party providers (`snowflakedb`, `databricks`, etc.).

## Worked examples

### Example 1: Pure AWS module

Given:
- Path: `infra/data-pipeline/tf/versions.tf`
- Module description: Data Pipeline Module
- Providers used: `aws` only

```hcl
# -- infra/data-pipeline/tf/versions.tf (Data Pipeline Module)
# ============================================================================
# Terraform Version and Provider Requirements
# ============================================================================
terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

### Example 2: AWS + Snowflake module with utilities

Given:
- Path: `infra/platform/tf/versions.tf`
- Module description: Platform Module
- Providers used: `aws`, `snowflake`, `random`, `null`, `time`

```hcl
# -- infra/platform/tf/versions.tf (Platform Module)
# ============================================================================
# Terraform Version and Provider Requirements
# ============================================================================
terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 1.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
```

### Example 3: Adding a provider to an existing file

Given an existing `versions.tf` that declares `aws` only, and the user wants to add `random` for generating unique suffixes:

```hcl
# -- infra/data-pipeline/tf/versions.tf (Data Pipeline Module)
# ============================================================================
# Terraform Version and Provider Requirements
# ============================================================================
terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
```

The new block is appended in canonical order (HashiCorp providers grouped together, alphabetical within the group).

Notice the formatting details that must be preserved across all examples:

- 2-space indentation for `required_providers { ... }`, 4-space (i.e. nested) for each provider block's contents.
- Attribute values aligned within each block (`source` and `version` `=` signs in column).
- No blank line between consecutive provider blocks.
- A trailing newline at the end of the file is required.

## Validation

After writing the file:

1. Run `terraform fmt -check versions.tf` if Terraform is available locally — the file should already be canonically formatted.
2. Run `terraform init` from the module directory. Failures here usually indicate a wrong `source` namespace, a non-existent version, or a provider that's declared but not actually published under that name.
3. Cross-reference the declared providers against the providers actually used:
   - Every `provider "<name>" { }` block in the module must have a matching entry in `versions.tf`.
   - Every `module "..." { providers = { <name> = ... } }` reference in `main.tf` must have a matching entry.
   - Every `resource "<name>_..."` reference in `main.tf` must have a matching entry.
   - Surplus declarations aren't fatal but represent dead code — flag for cleanup.
4. Confirm `required_version` (if present) matches `backend.tf`. Conflicting constraints will fail at plan time.
5. Confirm there is **no** `required_providers` block in `backend.tf`. If there is, that's a convention violation — the two would conflict.

## Common mistakes to avoid

- **Do not** declare providers the module doesn't use. The "kitchen-sink baseline" antipattern (always emit `aws`, `snowflake`, `random`, `null`, `time`) makes `terraform init` slower and makes it harder to see which dependencies are actually required.
- **Do not** put the `required_providers` block in `backend.tf`. This convention puts it in `versions.tf` and only here.
- **Do not** put a `provider "..." { }` configuration block in this file. Provider configurations (with `region`, `default_tags`, `assume_role`, etc.) live in `providers-aws.tf` / `providers-snowflake.tf` etc., one provider per file.
- **Do not** invent a `source` namespace. Always use the canonical `namespace/name` form from the [Terraform Registry](https://registry.terraform.io/). If unsure, ask the user.
- **Do not** use the legacy short-form source (`aws`, `snowflake` without a namespace). Modern Terraform (>= 0.13) requires the full `namespace/name` form.
- **Do not** use `version = ">= 0.0.0"` or omit `version` entirely. Always specify a meaningful floor — without one, `terraform init` will pick whatever's newest, which is exactly the kind of unpinned drift this file exists to prevent.
- **Do not** mix `~>` and `>=` styles arbitrarily. Pick the style that matches the team's convention for each provider — the example file uses `>=` for HashiCorp providers and Snowflake.
- **Do not** rename `required_version` or `required_providers`. They're Terraform reserved keywords and the file will fail to parse if renamed.
- **Do not** add a duplicate `terraform { ... }` block. There must be exactly one `terraform { }` block in this file (and one across the module overall, unless `backend.tf`'s block is structured to coexist — which it is, because the two files declare non-overlapping attributes).