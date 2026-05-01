---
name: tf-main
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform `main.tf` file for an AWS module. Trigger when the user mentions "main.tf", "Terraform orchestration", "phased Terraform layout", or asks to wire up module calls in a multi-phase apply (e.g. "first create S3, then IAM, then Lambda"). Also trigger when scaffolding a new Terraform module under `infra/<module>/tf/` that already has a `locals.tf` and needs the orchestration layer. The defining features of this skill are: **(1)** the file follows a strict phased layout with ASCII-banner phase headers, **(2)** module calls reference Git-pinned modules from the `subhamay-bhattacharyya-tf` GitHub organization, and **(3)** module inputs come from `local.*` configurations rather than inline HCL. Do NOT use this skill if the user wants a flat (non-phased) `main.tf`, modules from a different source (Terraform Registry, local paths, other Git orgs), or if the file would only contain a single resource.
---

# Terraform Main Orchestration (AWS Module) Skill

## Purpose

Generate a `main.tf` file that orchestrates an AWS Terraform module's resources in **explicit, numbered phases**, with each phase preceded by an ASCII-banner comment, each module call introduced by a sub-banner, and dependencies expressed via `depends_on` between phases.

This skill produces the orchestration layer only. Resource configuration values come from `local.*` (defined in `locals.tf`) and variables (defined in `variables.tf`) — `main.tf` should be readable as a high-level execution plan, not a configuration dump.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create a `main.tf` for this module"
- "Wire up the module calls in phases"
- "Scaffold the orchestration layer for `infra/<module>/tf/`"
- "Add a new phase to `main.tf`" (regenerate or extend)
- "Show me how to call the S3 / IAM / Lambda module here"

Do **not** use this skill if:

- The module is small enough that a flat list of `resource` / `module` blocks would be clearer than phased layout (≤ 2 module calls).
- The user wants to use modules from the Terraform Registry, a local path, or a different Git organization.
- The user is asking for a one-off resource, not an orchestration file.
- The module is already deployed and the user wants to edit a single block — handle that conversationally rather than regenerating.

## Required information

Before writing the file, gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path and description

- **Path:** typically `infra/<module>/tf/main.tf`. If unspecified, default to that pattern.
- **Module description:** inferred from the directory name (`platform/` → "Platform Module", `data-pipeline/` → "Data Pipeline Module"). If ambiguous, ask.

### 2. Top-level module purpose

A one-line description of what this module does end-to-end (e.g. "S3-to-Lambda data pipeline orchestration"). Used in the file's title banner. If not stated, ask the user.

### 3. Phases

A list of phases in execution order. Each phase has:

- A **phase number** (1, 2, 3, …).
- A **phase name** (e.g. "AWS Foundation", "Compute Layer", "Wiring & Notifications").
- A list of **steps** (e.g. "1.1 S3 bucket", "1.2 IAM role").

If the user hasn't articulated phases, infer them from the resources they've described — but always confirm the proposed phasing before writing the file. The phased layout is the contract of this skill, so getting it right matters.

### 4. Modules referenced (per step)

For each step, identify:

- The Git source (must be under `subhamay-bhattacharyya-tf/*`).
- The pinned ref — a tagged version (`v1.2.0`) is strongly preferred over a branch (`feature/...`).
- The local config map it consumes (e.g. `local.s3_config`, `local.iam_role_config`).

If a module isn't yet known, mark the source as `<TBD — confirm with user>` rather than inventing a URL.

### 5. Inter-phase dependencies

Identify which phases have hard ordering requirements. Examples:

- IAM role must exist before it can be assumed by a Lambda function.
- An S3 bucket must exist before its event notification can be configured.
- A KMS key must exist before resources reference it for encryption.

These become `depends_on = [module.X, module.Y]` lines.

## Output template

Write the file to the path the user specifies, defaulting to `infra/<module>/tf/main.tf`.

The file follows this **exact** four-part structure:

1. **Header banner** — file path, module name, and ASCII-art phase overview diagram.
2. **Phase banners** — one per phase, separating module calls.
3. **Step sub-banners** — one per module call inside a phase.
4. **Module / resource blocks** — using `local.*` for configuration, `depends_on` for ordering.

### Header banner format (mandatory)

Every `main.tf` produced by this skill begins with:

```hcl
# -- <RELATIVE_PATH> (<MODULE_DESCRIPTION>)
# ============================================================================
# <ONE-LINE MODULE PURPOSE>
# ============================================================================
#
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 1: <Phase 1 Name>                                    │
# ├─────────────────────────────────────────────────────────────┤
# │  • 1.1 <Step description>                                   │
# │  • 1.2 <Step description>                                   │
# └─────────────────────────────────────────────────────────────┘
#                             │
#                             ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 2: <Phase 2 Name>                                    │
# ├─────────────────────────────────────────────────────────────┤
# │  • 2.1 <Step description>                                   │
# │  • 2.2 <Step description>                                   │
# └─────────────────────────────────────────────────────────────┘
#
# ============================================================================
```

Rules for the diagram:

- Box width: **63 characters** between the outer `│` characters.
- Pad phase names and step descriptions with trailing spaces so the right-side `│` aligns vertically across all rows.
- Each phase box is connected to the next by a centered `│` and `▼` (column 30 from the start of `#`).
- Always close with a separator line (`# ===…`) after the last phase box.

This banner is the file's table of contents — the rest of the file's layout must match the phases listed here, in the same order, with the same numbering.

### Phase banner format

Between the header and each phase's blocks:

```hcl
# ============================================================================
# PHASE <N>: <Phase Name>
# ============================================================================
```

Optional explanatory paragraph follows on commented lines, ending with a separator line:

```hcl
# Optional 1–4 lines explaining what this phase does and any non-obvious
# ordering or workaround context. End with a separator.
# ----------------------------------------------------------------------------
```

### Step sub-banner format

Before each `module` or `resource` block:

```hcl
# ----------------------------------------------------------------------------
# • <N.M> <Step description>
# ----------------------------------------------------------------------------
```

If the step needs explanation (a workaround, a non-obvious dependency, a pinned-branch rationale), expand the sub-banner:

```hcl
# ----------------------------------------------------------------------------
# • <N.M> <Step description>
# <2–6 lines of rationale — why this exists, what it works around, when it
# can be removed. Keep it specific. "Workaround" is more valuable than
# "configures the resource".>
# ----------------------------------------------------------------------------
```

Inline rationale comments are **encouraged and expected** — they're the difference between a maintainable orchestration file and one no one wants to touch.

### Module call format

Module calls follow this exact shape:

```hcl
module "<name>" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/<REPO>.git?ref=<TAG>"

  <input_name> = local.<config>

  depends_on = [module.<earlier_module>]
}
```

Rules:

- `source` always uses `git::https://...?ref=...` form — never `https://...`, never local paths, never bare GitHub shorthand.
- `ref` is **always pinned**. Tagged versions (`v1.2.0`) are preferred. Feature-branch refs are allowed only with an inline comment explaining the temporary pin and what tag will replace it.
- Submodule paths use `//modules/<sub>` between the repo and `?ref=` (e.g. `//modules/bucket?ref=v1.0.0`).
- Inputs come from `local.*` rather than inline HCL where possible — keeps `main.tf` focused on orchestration, not configuration.
- A blank line separates `source` from inputs and inputs from `depends_on`.
- `depends_on` is omitted when the dependency is implicit (Terraform infers it from a reference).

### Inline resource format

When a phase needs a one-off resource that isn't worth its own module (e.g. a bucket lifecycle rule, a single grant, a trust policy reconcile), it's inlined in the same phase. Same sub-banner pattern, same `depends_on` discipline. Inline resources are fine — the goal is execution clarity, not module purity.

## Worked example

Given:
- Path: `infra/data-pipeline/tf/main.tf`
- Module description: Data Pipeline Module
- One-line purpose: "Event-driven CSV processing pipeline"
- Phases:
  - Phase 1: AWS Foundation (S3 bucket, IAM role)
  - Phase 2: Compute Layer (Lambda function)
  - Phase 3: Wiring (S3 → Lambda event notification)

The generated file should look like:

```hcl
# -- infra/data-pipeline/tf/main.tf (Data Pipeline Module)
# ============================================================================
# Event-Driven CSV Processing Pipeline
# ============================================================================
#
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 1: AWS Foundation                                    │
# ├─────────────────────────────────────────────────────────────┤
# │  • 1.1 S3 Bucket (CSV landing zone)                         │
# │  • 1.2 IAM Role (Lambda execution role)                     │
# └─────────────────────────────────────────────────────────────┘
#                             │
#                             ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 2: Compute Layer                                     │
# ├─────────────────────────────────────────────────────────────┤
# │  • 2.1 Lambda Function (CSV preprocessor)                   │
# └─────────────────────────────────────────────────────────────┘
#                             │
#                             ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 3: Wiring                                            │
# ├─────────────────────────────────────────────────────────────┤
# │  • 3.1 S3 Event Notification → Lambda                       │
# └─────────────────────────────────────────────────────────────┘
#
# ============================================================================

# ============================================================================
# PHASE 1: AWS Foundation
# ============================================================================

# ----------------------------------------------------------------------------
# • 1.1 S3 Bucket for CSV landing zone
# ----------------------------------------------------------------------------
module "s3" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-aws-s3.git//modules/bucket?ref=v1.0.0"

  s3_config = local.s3_config
}

# ----------------------------------------------------------------------------
# • 1.2 IAM Role for Lambda execution
# ----------------------------------------------------------------------------
module "iam_role" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-aws-iam.git//modules/role?ref=v1.0.0"

  iam_role = local.iam_role_config

  depends_on = [module.s3]
}

# ============================================================================
# PHASE 2: Compute Layer
# ============================================================================

# ----------------------------------------------------------------------------
# • 2.1 Lambda Function — CSV preprocessor
# ----------------------------------------------------------------------------
module "lambda" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-aws-lambda.git?ref=v1.0.0"

  lambda_config = local.lambda_config

  depends_on = [module.iam_role]
}

# ============================================================================
# PHASE 3: Wiring
# ============================================================================

# ----------------------------------------------------------------------------
# • 3.1 S3 Event Notification → Lambda
# ----------------------------------------------------------------------------
module "s3_notification" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-aws-s3-bucket.git//modules/event-notification?ref=v1.0.0"

  bucket_name = local.s3_config.bucket_name

  lambda_notifications = [
    {
      id                  = "csv-upload-trigger"
      lambda_function_arn = module.lambda.function_arn
      events              = ["s3:ObjectCreated:*"]
    }
  ]

  depends_on = [module.s3, module.lambda]
}
```

Notice the formatting details that must be preserved:

- 2-space indentation throughout.
- Blank line between phase banners and the first sub-banner that follows.
- Blank line between every two module/resource blocks.
- Module `source` line always immediately under the opening brace; inputs follow after a blank line; `depends_on` after another blank line.
- Phase numbers in the body match the header diagram exactly — no skipping, no reordering.

## Standard module repository reference

When the user mentions a service, prefer these canonical sources from the `subhamay-bhattacharyya-tf` org. Always confirm the **current pinned tag** with the user — the versions below are illustrative.

| Service / purpose | Source |
|---|---|
| S3 bucket | `subhamay-bhattacharyya-tf/terraform-aws-s3.git//modules/bucket` |
| S3 event notification | `subhamay-bhattacharyya-tf/terraform-aws-s3-bucket.git//modules/event-notification` |
| IAM role | `subhamay-bhattacharyya-tf/terraform-aws-iam.git//modules/role` |
| IAM policy | `subhamay-bhattacharyya-tf/terraform-aws-iam.git//modules/policy` |
| Lambda function | `subhamay-bhattacharyya-tf/terraform-aws-lambda.git` |
| KMS key | `subhamay-bhattacharyya-tf/terraform-aws-kms.git` |
| DynamoDB table | `subhamay-bhattacharyya-tf/terraform-aws-dynamodb.git` |
| SNS topic | `subhamay-bhattacharyya-tf/terraform-aws-sns.git` |
| SQS queue | `subhamay-bhattacharyya-tf/terraform-aws-sqs.git` |
| API Gateway | `subhamay-bhattacharyya-tf/terraform-aws-apigateway.git` |
| EventBridge rule | `subhamay-bhattacharyya-tf/terraform-aws-eventbridge.git` |

If a needed module isn't on this list, **ask the user for the source URL** rather than guessing. Inventing a Git URL that doesn't exist is the worst possible failure mode here.

## Validation

After writing the file:

1. Run `terraform fmt -check main.tf` if Terraform is available locally — the file should already be canonically formatted.
2. Confirm every `local.*` reference in the module calls maps to a value defined in `locals.tf`. If not, list the missing locals — they need to be added before `terraform init` will succeed.
3. Confirm every module `source` is a `git::https://...?ref=<tag-or-branch>` URL pointing at the `subhamay-bhattacharyya-tf` org.
4. Confirm the body's phase numbers and step numbers exactly match the header diagram.
5. Confirm each `depends_on` references a module that's defined earlier in the file (no forward references).

## Common mistakes to avoid

- **Do not** invent module repo URLs. If the source isn't in the conversation or the standard reference table above, ask the user.
- **Do not** use unpinned refs (`?ref=main`) — every module call must pin a tag or branch. Branch pins require an inline rationale comment.
- **Do not** mix the phased layout with a flat layout. Either every module is in a phase, or none are. (If "none" feels right, this skill is the wrong tool.)
- **Do not** put configuration values inline (long policy JSON, large lists). Move them into `locals.tf` and reference via `local.*`.
- **Do not** drop the ASCII-banner header. It's the file's table of contents and the single most useful thing a future maintainer reads first.
- **Do not** let phase numbers drift between the header diagram and the body. If you renumber one, renumber the other.
- **Do not** add `depends_on` for relationships Terraform can already infer from references. Reserve `depends_on` for cases where the dependency isn't expressed in the configuration itself (cross-module ordering, IAM trust resolution, eventually-consistent APIs).
- **Do not** combine multiple unrelated phases into one. If two pieces of work could fail independently and need to be reasoned about separately, they're separate phases.
- **Do not** include providers, variables, outputs, or backend configuration in `main.tf`. Those belong in `providers.tf`, `variables.tf`, `outputs.tf`, and `backend.tf` respectively.