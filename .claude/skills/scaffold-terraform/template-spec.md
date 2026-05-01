# template-spec.md — terraform-aws-s3

This document is the **canonical specification** for every file the `scaffold-terraform` skill emits in this repository. The `SKILL.md` describes *when* and *why* to scaffold; this file describes *exactly what* the scaffolded files must contain — field by field, line by line, where it matters.

When `SKILL.md` and `template-spec.md` disagree on a literal value, **this file wins**. Treat it as the source of truth for templates.

---

## 1. Repository identity

| Field                    | Value                                                                          |
|--------------------------|--------------------------------------------------------------------------------|
| Repo name                | `terraform-aws-s3`                                                             |
| Repo owner / org         | `subhamay-bhattacharyya-tf`                                                    |
| Full slug                | `subhamay-bhattacharyya-tf/terraform-aws-s3`                                   |
| Module shape             | Nested — `modules/bucket/` subdirectory; consumers reference `//modules/bucket`|
| AWS resource type        | `aws_s3_bucket` (and bucket-scoped sub-resources only)                         |
| Out of scope             | IAM policies, S3 access points, replication rules, event notifications, Lambda |
| Module input             | Single `map(object({...}))` named `buckets`, consumed via `for_each`           |
| Badge gist JSON filename | `terraform-aws-s3.json`                                                        |

Every scaffolded file must be self-consistent with this table. If a scaffolded file references a different repo name, owner, or input variable name, it is **broken** and must be regenerated.

---

## 2. File inventory

The scaffolder emits exactly the following files. Anything else is either a user-edited file (preserved as-is) or an error.

| Path                                                                                                                                                | Purpose                                                                       | Owner   |
|-----------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|---------|
| `modules/bucket/versions.tf`                                                                                                                        | Pin Terraform and AWS provider versions                                       | Skill   |
| `modules/bucket/variables.tf`                                                                                                                       | Declare `var.buckets` with validation blocks                                  | Skill   |
| `modules/bucket/main.tf`                                                                                                                            | Bucket resource + bucket-scoped sub-resources, all keyed by `for_each`        | Skill   |
| `modules/bucket/outputs.tf`                                                                                                                         | Five output maps keyed by `var.buckets` keys                                  | Skill   |
| `modules/bucket/README.md`                                                                                                                          | Generated content (auto-doc tables) + hand-written prose                      | Mixed   |
| `examples/single-bucket/main.tf`                                                                                                                    | Single standard bucket example                                                | Skill   |
| `examples/single-bucket/README.md`                                                                                                                  | What the example demonstrates                                                 | Skill   |
| `examples/multi-bucket/main.tf`                                                                                                                     | Three-bucket example (raw / processed / final)                                | Skill   |
| `examples/multi-bucket/README.md`                                                                                                                   | What the example demonstrates                                                 | Skill   |
| `tests/aws_s3_bucket_basic_test.go`                                                                                                                 | Terratest covering `examples/single-bucket/`                                  | Skill   |
| `tests/aws_s3_bucket_multi_test.go`                                                                                                                 | Terratest covering `examples/multi-bucket/`                                   | Skill   |
| `tests/helpers_test.go`                                                                                                                             | Shared test helpers (fixed contract)                                          | Skill   |
| `utils/generate-docs.sh`                                                                                                                            | Refresh terraform-docs tables in `README.md` files                            | Skill   |
| `utils/lint.sh`                                                                                                                                     | tflint + trivy + checkov wrapper                                              | Skill   |
| `utils/align-md-tables.py`                                                                                                                          | Align all GFM tables in `README.md` (MD060)                                   | Skill   |
| `utils/update-badge.sh`                                                                                                                             | Update shields.io custom-endpoint gist JSON                                   | Skill   |
| `package.json` / `package-lock.json`                                                                                                                | semantic-release config; `name` must equal repo name                          | User    |
| `README.md`                                                                                                                                         | Top-level repo README; links to `modules/bucket/` and the examples            | Mixed   |
| `CHANGELOG.md`                                                                                                                                      | Auto-generated by semantic-release / git-cliff                                | Tooling |
| `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `LICENSE`, `.editorconfig`, `.gitignore`, `.pre-commit-config.yaml`, `.releaserc.json`, `install-tools.sh` | Repo hygiene; preserved as-is once scaffolded                                 | User    |

---

## 3. `modules/bucket/versions.tf` — exact spec

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

**Hard requirements:**

- Exactly one `terraform { ... }` block
- Exactly one provider declared: `aws`
- `source` must be `hashicorp/aws` (the canonical Hashicorp AWS provider; no third-party forks)
- `version` must be `>= 5.0` — a single lower bound, no upper cap, so consumers stay free to track newer provider releases
- `required_version` for Terraform itself is `>= 1.5.0` (matches the lowest version that supports `optional()` defaults in object types)

**Forbidden:**

- Any `provider "aws" { ... }` block — provider configuration belongs in examples and consumers, not in the module
- Any `backend` block — modules never declare backends
- Any additional providers (`random`, `null`, `time`, etc.) unless a specific resource in `main.tf` requires them; speculative declarations are forbidden

---

## 4. `modules/bucket/variables.tf` — exact spec

The module declares **exactly one** variable: `buckets`.

```hcl
variable "buckets" {
  description = "Map of S3 buckets to create. Map key is a logical Terraform identifier; the actual S3 bucket name is the `name` field."

  type = map(object({
    name              = string
    versioning        = optional(bool, true)
    force_destroy     = optional(bool, false)
    kms_key_arn       = optional(string, null)
    sse_algorithm     = optional(string, "AES256")
    bucket_key_enabled = optional(bool, true)
    block_public_access = optional(bool, true)
    bucket_policy     = optional(string, null)
    lifecycle_rules = optional(list(object({
      id              = string
      enabled         = bool
      prefix          = optional(string, "")
      expiration_days = optional(number, null)
    })), [])
    tags = optional(map(string), {})
  }))

  default = {}

  validation {
    condition     = alltrue([for k, v in var.buckets : length(v.name) > 0])
    error_message = "Each bucket must have a non-empty `name`."
  }

  validation {
    condition     = alltrue([for k, v in var.buckets : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", v.name))])
    error_message = "Each bucket `name` must be 3–63 characters, lower-case alphanumerics, dots, or hyphens, and start/end alphanumeric."
  }

  validation {
    condition     = alltrue([for k, v in var.buckets : contains(["AES256", "aws:kms"], v.sse_algorithm)])
    error_message = "Each bucket `sse_algorithm` must be either `AES256` or `aws:kms`."
  }

  validation {
    condition     = alltrue([for k, v in var.buckets : v.sse_algorithm != "aws:kms" || v.kms_key_arn != null])
    error_message = "When `sse_algorithm = \"aws:kms\"`, `kms_key_arn` must be set."
  }
}
```

**Field-level spec:**

| Field                 | Type                | Required | Default    | Notes                                                              |
|-----------------------|---------------------|----------|------------|--------------------------------------------------------------------|
| `name`                | `string`            | Yes      | —          | Actual S3 bucket name; must satisfy AWS naming rules               |
| `versioning`          | `bool`              | No       | `true`     | When `true`, S3 versioning is enabled                              |
| `force_destroy`       | `bool`              | No       | `false`    | When `true`, `terraform destroy` will wipe a non-empty bucket      |
| `kms_key_arn`         | `string`            | No       | `null`     | Required when `sse_algorithm = "aws:kms"`; ignored otherwise       |
| `sse_algorithm`       | `string`            | No       | `"AES256"` | One of `AES256` or `aws:kms`                                       |
| `bucket_key_enabled`  | `bool`              | No       | `true`     | S3 Bucket Keys reduce KMS request volume                           |
| `block_public_access` | `bool`              | No       | `true`     | When `true`, all four `aws_s3_bucket_public_access_block` flags on |
| `bucket_policy`       | `string`            | No       | `null`     | Optional bucket policy JSON; omit for default deny-public          |
| `lifecycle_rules`     | `list(object(...))` | No       | `[]`       | List of expiration rules                                           |
| `tags`                | `map(string)`       | No       | `{}`       | Per-bucket tags merged on top of provider `default_tags`           |

**Forbidden in this file:**

- Any variable other than `buckets` (no `region`, `account_id`, `tags` top-level vars — those are caller responsibilities)
- Any `validation` block that references resources or data sources — validation is pure on `var.buckets` only
- Any `sensitive = true` flag — bucket configuration is not secret
- `count` or list-shaped inputs — the module is `for_each`-only

---

## 5. `modules/bucket/main.tf` — exact spec

```hcl
resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket        = each.value.name
  force_destroy = each.value.force_destroy
  tags          = each.value.tags
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = each.value.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    bucket_key_enabled = each.value.bucket_key_enabled

    apply_server_side_encryption_by_default {
      sse_algorithm     = each.value.sse_algorithm
      kms_master_key_id = each.value.sse_algorithm == "aws:kms" ? each.value.kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = { for k, v in var.buckets : k => v if v.block_public_access }

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "this" {
  for_each = { for k, v in var.buckets : k => v if v.bucket_policy != null }

  bucket = aws_s3_bucket.this[each.key].id
  policy = each.value.bucket_policy
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for k, v in var.buckets : k => v if length(v.lifecycle_rules) > 0 }

  bucket = aws_s3_bucket.this[each.key].id

  dynamic "rule" {
    for_each = each.value.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }
    }
  }
}
```

**Hard requirements:**

- Exactly one `aws_s3_bucket.this` resource, with `for_each = var.buckets`
- Each bucket-scoped sub-resource (`versioning`, `server_side_encryption_configuration`, `public_access_block`, `policy`, `lifecycle_configuration`) is its own `for_each` resource keyed by the same map keys
- Sub-resources that are conditional (policy, public access block, lifecycle) use a filtered `for_each` map rather than `count` — keeps map keys consistent
- Every reference to the bucket uses `aws_s3_bucket.this[each.key].id`, never the raw bucket name string
- No `lifecycle` blocks unless a specific drift problem requires it (and then it must be commented inline explaining why)

**Forbidden:**

- Inline IAM policy resources (`aws_iam_policy`, `aws_iam_role_policy`) — IAM lives in a separate module
- `aws_s3_bucket_notification` — notifications live in a separate module
- Data sources for KMS keys — caller passes a resolved ARN via `kms_key_arn`
- `depends_on` — `for_each` over an input map produces correct dependency ordering by itself
- Use of deprecated inline arguments on `aws_s3_bucket` (e.g. inline `versioning {}` block) — every concern is a separate AWS-provider-v5 resource

---

## 6. `modules/bucket/outputs.tf` — exact spec

```hcl
output "bucket_ids" {
  description = "Map of bucket map keys to S3 bucket IDs (which equal bucket names)."
  value       = { for k, v in aws_s3_bucket.this : k => v.id }
}

output "bucket_arns" {
  description = "Map of bucket map keys to S3 bucket ARNs."
  value       = { for k, v in aws_s3_bucket.this : k => v.arn }
}

output "bucket_regional_domain_names" {
  description = "Map of bucket map keys to regional domain names (for use in policies and signed URLs)."
  value       = { for k, v in aws_s3_bucket.this : k => v.bucket_regional_domain_name }
}

output "bucket_versioning_status" {
  description = "Map of bucket map keys to the versioning status (`Enabled` or `Suspended`)."
  value       = { for k, v in aws_s3_bucket_versioning.this : k => v.versioning_configuration[0].status }
}

output "bucket_sse_algorithms" {
  description = "Map of bucket map keys to the configured SSE algorithm (`AES256` or `aws:kms`)."
  value       = { for k, v in aws_s3_bucket_server_side_encryption_configuration.this : k => v.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm }
}
```

**Hard requirements:**

- Exactly five outputs, with these exact names — `tests/helpers_test.go` reads them by name
- Every output is a `map(...)` keyed by `var.buckets` map keys (never a list, never a single value)
- Every output has a non-empty `description`

**Forbidden:**

- `sensitive = true` on any output — bucket metadata is not secret
- Outputs that expose raw resource objects (`output "buckets" { value = aws_s3_bucket.this }`) — too brittle, tests pin against attribute-level outputs
- Outputs sourced from resources gated by a filtered `for_each` (e.g. `aws_s3_bucket_policy.this`) — those produce sparse maps that confuse downstream consumers; if needed, surface them as a separate, explicitly-shaped output

---

## 7. Example spec

Every directory under `examples/` follows the same template. Below is the canonical `main.tf`; the literal values in the `buckets` map are the only thing that varies between examples.

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "s3" {
  source = "../../modules/bucket"

  buckets = {
    # ↓ example-specific entries go here
  }
}
```

**Hard requirements for every example:**

- `source = "../../modules/bucket"` — resolves to the bucket sub-module under the repo root, never `../..`
- `terraform` and `required_providers` blocks must match `modules/bucket/versions.tf` exactly (same lower/upper bounds)
- `provider "aws" { region = "us-east-1" }` — region is set explicitly so the example runs deterministically; auth comes from env vars (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or `AWS_PROFILE`) so the same example runs in every developer's account and in CI without edits
- An accompanying `README.md` (≤ 30 lines) explains: what the example demonstrates, what AWS objects it assumes exist (e.g. a KMS key for the encrypted variant), and how to run it
- `terraform init -backend=false && terraform validate` must pass

### 7.1 `examples/single-bucket/` — exact spec

`buckets` map content:

```hcl
buckets = {
  app_data = {
    name          = "example-app-data-${random_id.suffix.hex}"
    versioning    = true
    force_destroy = true
    sse_algorithm = "AES256"

    lifecycle_rules = [
      {
        id              = "expire-tmp-30-days"
        enabled         = true
        prefix          = "tmp/"
        expiration_days = 30
      }
    ]

    tags = {
      Example = "single-bucket"
    }
  }
}
```

**Constraints:**

- Exactly one entry
- `force_destroy = true` (examples are ephemeral; Terratest needs to destroy non-empty buckets cleanly)
- Bucket name uses a `random_id` suffix to avoid global S3 namespace collisions in CI
- `sse_algorithm = "AES256"` — the simpler default; the KMS path is exercised in `multi-bucket`
- At least one lifecycle rule, so the example also covers the `aws_s3_bucket_lifecycle_configuration` resource

### 7.2 `examples/multi-bucket/` — exact spec

`buckets` map content:

```hcl
buckets = {
  raw = {
    name          = "example-csv-raw-${random_id.suffix.hex}"
    versioning    = true
    force_destroy = true
    sse_algorithm = "aws:kms"
    kms_key_arn   = aws_kms_key.example.arn
    tags          = { Tier = "raw" }
  }
  processed = {
    name          = "example-csv-processed-${random_id.suffix.hex}"
    versioning    = true
    force_destroy = true
    sse_algorithm = "aws:kms"
    kms_key_arn   = aws_kms_key.example.arn
    tags          = { Tier = "processed" }
  }
  final = {
    name          = "example-csv-final-${random_id.suffix.hex}"
    versioning    = true
    force_destroy = true
    sse_algorithm = "aws:kms"
    kms_key_arn   = aws_kms_key.example.arn
    tags          = { Tier = "final" }
  }
}
```

**Constraints:**

- Exactly three entries with logical keys `raw`, `processed`, `final` (the canonical CSV-pipeline shape)
- All three buckets share a single `aws_kms_key.example` declared in the same example file — exercises the KMS-encrypted code path
- `sse_algorithm = "aws:kms"` on every entry — the `single-bucket` example covers the `AES256` path
- `force_destroy = true` on every entry — examples are ephemeral
- The example's `README.md` must explain *why* there are three buckets (the raw → processed → final data-lake pattern) so the example reads as illustrative, not arbitrary

---

## 8. Test file spec

### 8.1 `tests/aws_s3_bucket_basic_test.go` — required structure

```go
package tests

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestAwsS3BucketBasic(t *testing.T) {
    t.Parallel()

    opts := buildTerraformOptions(t, "../examples/single-bucket")
    defer terraform.Destroy(t, opts)

    terraform.InitAndApply(t, opts)

    // 1. Output assertions
    ids := terraform.OutputMap(t, opts, "bucket_ids")
    assert.Len(t, ids, 1)
    assert.Contains(t, ids, "app_data")

    arns := terraform.OutputMap(t, opts, "bucket_arns")
    assert.Contains(t, arns, "app_data")

    versioning := terraform.OutputMap(t, opts, "bucket_versioning_status")
    assert.Equal(t, "Enabled", versioning["app_data"])

    sse := terraform.OutputMap(t, opts, "bucket_sse_algorithms")
    assert.Equal(t, "AES256", sse["app_data"])

    // 2. AWS-side verification
    sess := newAwsSession(t)

    assertBucketExists(t, sess, ids["app_data"])
    assertBucketVersioningEnabled(t, sess, ids["app_data"])
    assertBucketEncryptionAlgorithm(t, sess, ids["app_data"], "AES256")
    assertBucketBlocksPublicAccess(t, sess, ids["app_data"])

    // 3. Idempotency
    plan := terraform.InitAndPlan(t, opts)
    assert.Contains(t, plan, "No changes")
}
```

### 8.2 `tests/aws_s3_bucket_multi_test.go` — required structure

```go
package tests

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestAwsS3BucketMulti(t *testing.T) {
    t.Parallel()

    opts := buildTerraformOptions(t, "../examples/multi-bucket")
    defer terraform.Destroy(t, opts)

    terraform.InitAndApply(t, opts)

    ids := terraform.OutputMap(t, opts, "bucket_ids")
    assert.Len(t, ids, 3)
    for _, key := range []string{"raw", "processed", "final"} {
        assert.Contains(t, ids, key)
    }

    sse := terraform.OutputMap(t, opts, "bucket_sse_algorithms")
    for _, key := range []string{"raw", "processed", "final"} {
        assert.Equal(t, "aws:kms", sse[key])
    }

    sess := newAwsSession(t)
    for _, key := range []string{"raw", "processed", "final"} {
        assertBucketExists(t, sess, ids[key])
        assertBucketEncryptionAlgorithm(t, sess, ids[key], "aws:kms")
    }
}
```

**Hard requirements (both files):**

- `package tests`
- `t.Parallel()` at the top of every top-level test
- `defer terraform.Destroy(t, opts)` is set up **before** `InitAndApply` — never after
- All AWS-side assertions go through helpers (`assertBucketExists`, `assertBucketVersioningEnabled`, `assertBucketEncryptionAlgorithm`, `assertBucketBlocksPublicAccess`, `assertBucketDestroyed`) — never raw AWS SDK calls inline
- Map-key assertions check both length and exact key membership
- Multi-bucket tests iterate over expected keys with `for _, key := range [...]` — never hand-write three near-identical assertions

### 8.3 `tests/helpers_test.go` — fixed contract

Helpers must expose **exactly these symbols** with **exactly these signatures**:

```go
func buildTerraformOptions(t *testing.T, exampleDir string) *terraform.Options
func newAwsSession(t *testing.T) *session.Session
func assertBucketExists(t *testing.T, sess *session.Session, bucketName string)
func assertBucketDestroyed(t *testing.T, sess *session.Session, bucketName string)
func assertBucketVersioningEnabled(t *testing.T, sess *session.Session, bucketName string)
func assertBucketEncryptionAlgorithm(t *testing.T, sess *session.Session, bucketName string, expected string)
func assertBucketBlocksPublicAccess(t *testing.T, sess *session.Session, bucketName string)
func uniqueSuffix(t *testing.T) string
```

**Constraints on helpers:**

- No test logic — helpers are pure setup, teardown, and assertion primitives
- Every helper takes `*testing.T` and uses `t.Fatalf` / `t.Helper()` so failures point at the calling test, not the helper
- `buildTerraformOptions` injects `AWS_REGION` and a `uniqueSuffix(t)`-derived resource name suffix into `opts.Vars`
- `newAwsSession` opens a single `*session.Session` per test, scoped to `AWS_REGION`, with a context timeout
- All bucket-side assertions use the AWS SDK v2 (`github.com/aws/aws-sdk-go-v2/service/s3`), never v1

---

## 9. Utility script spec

Every script under `utils/` must satisfy:

| Constraint           | Bash scripts                                | Python scripts                                                     |
|----------------------|---------------------------------------------|--------------------------------------------------------------------|
| Strict mode          | `set -euo pipefail` on line 1 after shebang | `from __future__ import annotations` + explicit `sys.exit()` codes |
| Idempotent           | Re-running on a clean tree produces no diff | Same                                                               |
| Exit codes           | `0` success, non-zero failure               | Same                                                               |
| Header comment       | Purpose + invocation + required env vars    | Same (module docstring)                                            |
| User-facing strings  | Reference "S3 buckets"                      | Same                                                               |
| Repo-root invocation | `bash utils/<name>.sh`                      | `python utils/<name>.py`                                           |

### 9.1 `generate-docs.sh`

- Wraps `terraform-docs markdown table --output-file README.md --output-mode inject modules/bucket`
- Re-invokes `align-md-tables.py` immediately after on both the top-level `README.md` and `modules/bucket/README.md`
- Fails if `terraform-docs` binary is missing (no silent skip)

### 9.2 `lint.sh`

- Runs `tflint --recursive` first, then `trivy config .`, then `checkov -d modules/bucket --skip-check CKV_AWS_18`
- Exits with the **first** non-zero exit code (does not aggregate)
- Project-specific tflint config lives at `.tflint.hcl`; trivy config inline at the script top
- `CKV_AWS_18` (S3 access logging) is skipped because access logging is a caller concern; document the skip in the script header

### 9.3 `align-md-tables.py`

- Parses `README.md` files with `markdown-it-py` (or equivalent), pads every cell in every table to its column max width, writes back in place
- Operates on both the top-level `README.md` and `modules/bucket/README.md`
- Verifies post-write that every row in every table has identical `|` positions; fails with a diff if not

### 9.4 `update-badge.sh`

- Reads `BADGE_GIST_ID` from env (required)
- Builds the JSON payload: `{ "schemaVersion": 1, "label": "...", "message": "...", "color": "..." }`
- Writes to `terraform-aws-s3.json` in the gist via `gh gist edit`
- Fails if `gh` CLI is not authenticated

---

## 10. Cross-file invariants (always check before declaring scaffolding done)

1. **Variable name** — `modules/bucket/variables.tf` declares exactly one variable, named `buckets`. No other variable exists at the module-root level.
2. **Resource names** — `modules/bucket/main.tf` contains exactly one primary resource (`aws_s3_bucket.this`) plus the bucket-scoped sub-resources listed in §5. Every resource uses `for_each` keyed off `var.buckets` (or a filtered map of `var.buckets`).
3. **Output names** — `modules/bucket/outputs.tf` declares exactly five outputs: `bucket_ids`, `bucket_arns`, `bucket_regional_domain_names`, `bucket_versioning_status`, `bucket_sse_algorithms`. These names are also referenced literally in `tests/aws_s3_bucket_*_test.go`.
4. **Module source paths** — every example uses `source = "../../modules/bucket"` and resolves to the bucket sub-module.
5. **Provider pin parity** — `modules/bucket/versions.tf` and every `examples/*/main.tf` declare the **same** provider source and the **same** version range. A mismatch is a bug.
6. **Helper contract parity** — every test under `tests/` uses only the helpers listed in §8.3; if a test needs a new assertion, the new helper goes in `helpers_test.go`, not inline in the test file.
7. **`package.json` name** — equals `terraform-aws-s3`. `package-lock.json` `name` field equals the same.
8. **`CONTRIBUTING.md`** — references `terraform-aws-s3` and links its **Reporting Issues** section to this repo's issues page.
9. **`README.md` headings** — every heading text is unique across the document (markdownlint MD024). Every GFM table is pipe-aligned (MD060).
10. **No leftover template references** — search the entire scaffolded tree for `terraform-snowflake-view`, `terraform-aws-dynamodb`, `views`, `view_ids`, `snowflake_view`, `gcs_`. Any hit is a regeneration bug.

---

## 11. Drift detection

After scaffolding, run all of the following. **Every command must exit `0`.**

```bash
terraform fmt -check -recursive
( cd modules/bucket && terraform init -backend=false && terraform validate )
( cd examples/single-bucket && terraform init -backend=false && terraform validate )
( cd examples/multi-bucket   && terraform init -backend=false && terraform validate )
bash utils/lint.sh                               # local-only — not invoked from CI
bash utils/generate-docs.sh && python utils/align-md-tables.py
git diff --exit-code README.md modules/bucket/README.md   # docs must be in sync
pre-commit run --all-files
```

The CI workflow (`.github/workflows/ci.yaml`) runs a reduced subset — `terraform-validate`, `examples-validate`, `terratest`, `generate-changelog`, and `semantic-release` — and **does not** invoke `utils/lint.sh`, the docs-drift gate, or `utils/update-badge.sh`. The default Terraform version is pinned to `1.5.0` (overridable via the `TERRAFORM_VERSION` repo variable) to match `versions.tf`'s `required_version = ">= 1.5.0"`. Anything `lint.sh` / docs-drift / badge would catch must therefore be enforced locally (pre-commit) until the corresponding CI jobs are added back.

If any of these fails on a freshly-scaffolded tree, the scaffolder produced inconsistent output — fix `template-spec.md` (this file) first, then regenerate.
