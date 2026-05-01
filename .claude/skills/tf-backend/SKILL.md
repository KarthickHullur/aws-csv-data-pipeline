---
name: tf-backend
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform `backend.tf` file that uses HCP Terraform (formerly Terraform Cloud) as the backend. Trigger when the user mentions "backend.tf", "Terraform backend", "HCP Terraform configuration", "Terraform Cloud workspace", or asks to wire a Terraform module to a remote workspace. Also trigger when scaffolding a new Terraform module or platform module that needs remote state managed by HCP Terraform. The defining feature of this skill is that the **workspace name must match the current repository name** — do NOT use this skill if the user explicitly wants a different workspace name, an S3/local backend, or no backend block at all.
---

# Terraform Backend (HCP Terraform) Skill

## Purpose

Generate a `backend.tf` file that configures Terraform to use HCP Terraform (Terraform Cloud) as the remote backend, with the workspace name automatically set to match the current repository name.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create a `backend.tf` file"
- "Set up the Terraform backend"
- "Configure HCP Terraform / Terraform Cloud for this module"
- "Scaffold a Terraform module" (and HCP Terraform is the team's standard)
- "Wire this repo to a Terraform Cloud workspace"

Do **not** use this skill if:

- The user explicitly requests a different backend (S3, GCS, local, Consul, etc.).
- The user explicitly specifies a workspace name that differs from the repository name.
- The user is asking about backend migration rather than initial setup (handle conversationally instead).

## Required information

Before writing the file, the skill needs three values. Determine them in this order:

### 1. Repository name (used as the workspace name)

The workspace name **must equal the current repository name**. Determine it using the first of the following that succeeds:

```bash
# Preferred: derive from the git remote
basename -s .git "$(git config --get remote.origin.url)"

# Fallback: derive from the working directory (if the repo root is the cwd)
basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

If neither command produces a usable value, **ask the user for the repository name explicitly** — do not guess and do not invent a placeholder.

### 2. Organization name

Default to the organization the user has indicated previously in the conversation, or to a sensible team default if one has been established. If unknown, ask the user — never fabricate an organization name.

Common patterns the user may have already mentioned:
- `subhamay-snowflake-projects`
- `<team>-<domain>-projects`
- `<company>-<environment>`

### 3. Required Terraform version

Default to `~>1.14.0` unless the user specifies a different version constraint. Other common constraints to recognize:

- `~>1.14.0` — patch-level pinning (default for this skill)
- `>=1.14.0` — minimum version, no upper bound
- `~>1.14` — minor-level pinning

## Output template

Write the file to the path the user specifies. If no path is given, default to `backend.tf` in the current Terraform module directory (commonly something like `infra/<module>/tf/backend.tf` or `infra/<module>/backend.tf`).

The file must follow this exact structure:

```hcl
# ============================================================================
# <RELATIVE_PATH_HEADER>
# ============================================================================
# Terraform Backend Configuration
# ============================================================================
terraform {
  required_version = "<TERRAFORM_VERSION_CONSTRAINT>"
  cloud {
    organization = "<HCP_ORGANIZATION_NAME>"
    workspaces {
      name = "<REPOSITORY_NAME>"
    }
  }
}
```

### Header comment

The first comment line should describe the file's location and module purpose. Use the form:

```
# -- <relative_path_to_file> (<Module Description>)
```

Examples:
- `# -- infra/platform/tf/backend.tf (Platform Module)`
- `# -- infra/data-pipeline/tf/backend.tf (Data Pipeline Module)`
- `# -- infra/networking/backend.tf (Networking Module)`

Infer the module description from the directory name (`platform/` → "Platform Module", `data-pipeline/` → "Data Pipeline Module") or ask the user if it's ambiguous.

## Worked example

Given:
- Repository: `customer360-snowflake-pipeline`
- Organization: `subhamay-snowflake-projects`
- Path: `infra/platform/tf/backend.tf`
- Module description: Platform Module
- Terraform version: `~>1.14.0` (default)

The generated file should be **exactly**:

```hcl
# -- infra/platform/tf/backend.tf (Platform Module)
# ============================================================================
# Terraform Backend Configuration
# ============================================================================
terraform {
  required_version = "~>1.14.0"
  cloud {
    organization = "subhamay-snowflake-projects"
    workspaces {
      name = "customer360-snowflake-pipeline"
    }
  }
}
```

Notice the formatting details that must be preserved:
- The `terraform { ... }` block uses 2-space indentation.
- `required_version` sits at the top, followed by the `cloud { ... }` block.
- The version constraint uses `~>` with no space (matches HashiCorp style).
- String values use double quotes.
- The trailing newline at the end of the file is required.

## Validation

After writing the file:

1. Run `terraform fmt -check backend.tf` if Terraform is available locally — the file should already be canonically formatted.
2. Confirm the workspace name in the file matches the output of the repo-name detection command above.
3. Mention to the user that they will need to run `terraform login` (or set `TF_TOKEN_app_terraform_io`) before `terraform init` will succeed with the new backend.

## Common mistakes to avoid

- **Do not** hardcode a workspace name that doesn't match the repository — this is the single most important contract of this skill.
- **Do not** wrap the workspace block in `workspaces { tags = [...] }`; this skill always uses a single named workspace, not the tags-based selection style.
- **Do not** include `backend "remote" { ... }` syntax — that's the legacy form. Always use the modern `cloud { ... }` block.
- **Do not** invent or guess the organization name. If it's not in conversation context, ask.
- **Do not** add extra blocks (`required_providers`, etc.) to `backend.tf` — those belong in `versions.tf` or `providers.tf`. Keep `backend.tf` focused on the backend configuration only.
- **Do not** omit the header comment line — it's used by the team to identify file purpose at a glance in code review.