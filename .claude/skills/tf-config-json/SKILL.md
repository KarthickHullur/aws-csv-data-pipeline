---
name: tf-config-json
description: Use this skill whenever the user asks to create, generate, scaffold, or write the AWS resource configuration JSON files that Terraform reads via `var.aws_config_path`. Trigger when the user mentions "config json", "config-s3.json", "config-iam.json", "AWS resource config", "JSON-driven config", or asks to define resource attributes (bucket names, IAM policies, lifecycle rules, lambda settings, glue jobs, etc.) in JSON rather than HCL. Also trigger when scaffolding a new Terraform module under `infra/<module>/tf/` that follows the convention of one config JSON per resource type. The defining features of this skill are: **(1)** there is **one JSON file per AWS resource type** (`config-s3.json`, `config-iam.json`, `config-lambda.json`, etc.), each containing a single top-level `aws.<resource>` block, **(2)** every file is environment-scoped under `config/aws/<environment>/`, **(3)** policy resource ARNs use **placeholder tokens** (`s3-bucket-arn`, `s3-bucket-arn/*`, `kms-key-arn`) that `locals.tf` rewrites at apply time, and **(4)** every resource type has a fixed schema that the skill enforces. Do NOT use this skill for Snowflake config JSON, for Terraform `.tf` files (use `tf-locals` / `tf-main` / etc. instead), or for inline HCL configuration.
---

# Terraform Config JSON Skill

## Purpose

Generate the per-resource AWS configuration JSON files that the Terraform module reads at plan time via `jsondecode(file("${path.module}/${var.aws_config_path}"))`. Each file contains the configuration for **exactly one resource type** (S3, IAM, Lambda, Glue, etc.) and lives under `config/aws/<environment>/`.

This skill covers the **schema** of each file. The Terraform side of the contract — how `locals.tf` parses these files and how `main.tf` consumes the resulting maps — is owned by the `tf-locals` and `tf-main` skills.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create the AWS config JSON for this module"
- "Add a new bucket / IAM policy / Lambda function to the config"
- "Scaffold `config-s3.json` / `config-iam.json` / etc. for `<environment>`"
- "Generate the per-environment overrides for `<resource>`"
- "Validate / fix the structure of an existing config JSON"

Do **not** use this skill if:

- The user wants Snowflake configuration — that lives in a separate `config-snowflake-*.json` family with its own schema (out of scope for this skill).
- The user is asking for HCL changes, not JSON. The `.tf` files don't go here — use `tf-locals`, `tf-main`, etc.
- The user wants inline configuration baked into `.tf` files. The convention this skill enforces is that all per-environment configuration lives in JSON, not in HCL.

## Required information

Before writing the file(s), gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path

- **Path:** typically `infra/<module>/tf/`. Config files live at `infra/<module>/tf/config/aws/<environment>/config-<resource>.json`.

### 2. Environment

- One of `devl`, `test`, `prod` — confirm with the user. If multiple environments are needed, the same skill produces one file per environment, with environment-specific values (region, bucket prefixes, instance sizes, etc.) overridden as appropriate.

### 3. Resource types to generate

Each resource type maps to exactly one file:

| Resource type | Filename                | Top-level key       |
|---|---|---|
| S3 buckets | `config-s3.json` | `aws.s3` |
| IAM roles & policies | `config-iam.json` | `aws.iam` |
| Lambda functions | `config-lambda.json` | `aws.lambda` |
| Glue (Crawler, Catalog, Job) | `config-glue.json` | `aws.glue` |
| SQS queues | `config-sqs.json` | `aws.sqs` |
| SNS topics | `config-sns.json` | `aws.sns` |
| KMS keys | `config-kms.json` | `aws.kms` |
| EventBridge rules | `config-eventbridge.json` | `aws.eventbridge` |
| API Gateway | `config-apigateway.json` | `aws.apigateway` |
| DynamoDB tables | `config-dynamodb.json` | `aws.dynamodb` |
| Region (shared root) | `config-region.json` | `aws.region` |

If the user asks for a resource type not on this list, ask for the desired filename and top-level key rather than inventing one.

### 4. Resource-specific values

The schemas below define what each file should contain. For each resource the user is configuring, gather:

- The **logical role** (raw, processed, final, ingestion, transform, etc.) — used as the map key.
- The **base name** — combined with project code, environment, and (for S3) region to produce the actual AWS resource name.
- **Environment-specific overrides** — region, lifecycle days, instance sizes, etc.

If a value isn't provided and there's no safe default, **ask** rather than inventing.

## File layout

Every config JSON lives at:

```
infra/<module>/tf/config/aws/<environment>/config-<resource>.json
```

Examples:

```
infra/platform/tf/config/aws/devl/config-s3.json
infra/platform/tf/config/aws/devl/config-iam.json
infra/platform/tf/config/aws/test/config-s3.json
infra/platform/tf/config/aws/prod/config-s3.json
```

Every file has exactly **one** top-level key (`aws`) with **one** sub-key (`<resource>`):

```jsonc
{
  "aws": {
    "<resource>": { ... }
  }
}
```

The `region` is a **shared root** that lives in its own file (`config-region.json`) and is loaded alongside the resource-specific file:

```jsonc
{
  "aws": {
    "region": "us-east-1"
  }
}
```

`locals.tf` is responsible for merging these files via `jsondecode(file(...))` calls — the JSON files themselves never reference each other.

## Schema reference

Each resource type has a fixed schema. Use these as the canonical templates.

### S3 (`config-s3.json`)

For modules with **a single bucket**:

```jsonc
{
  "aws": {
    "s3": {
      "bucket_name": "<base-name>",
      "bucket_keys": ["<prefix-1>", "<prefix-2>"],
      "versioning": true,
      "kms_key_alias": "<alias-or-omit>",
      "force_destroy": false,
      "lifecycle_rules": [
        {
          "id": "<rule-id>",
          "enabled": true,
          "prefix": "<object-prefix>",
          "expiration_days": 91
        }
      ]
    }
  }
}
```

For modules with **multiple buckets** (e.g. raw / processed / final), key by logical role:

```jsonc
{
  "aws": {
    "s3": {
      "raw": {
        "bucket_name": "csv-raw-data",
        "bucket_keys": ["incoming/"],
        "versioning": true,
        "kms_key_alias": "SB-KMS",
        "force_destroy": false,
        "lifecycle_rules": []
      },
      "processed": {
        "bucket_name": "csv-processed-data",
        "bucket_keys": ["cleaned/"],
        "versioning": true,
        "kms_key_alias": "SB-KMS",
        "force_destroy": false,
        "lifecycle_rules": []
      },
      "final": {
        "bucket_name": "csv-final-data",
        "bucket_keys": ["curated/"],
        "versioning": true,
        "kms_key_alias": "SB-KMS",
        "force_destroy": false,
        "lifecycle_rules": []
      }
    }
  }
}
```

**Field rules for S3:**

- `bucket_name` is the **base name** only — `locals.tf` prepends `<project_code>-` and appends `-<environment>-<region>`. Do not include any of those in the JSON.
- `bucket_keys` is a list of object-key prefixes the application will use — used for documentation and (optionally) for prefix-scoped lifecycle rules. Always an array, never a string.
- `versioning` is a boolean. Default to `true` for production and staging; `false` is only acceptable for ephemeral buckets.
- `kms_key_alias` may be a bare alias (`SB-KMS`) or include the `alias/` prefix (`alias/SB-KMS`); `locals.tf` normalizes both. Omit the field entirely (don't set it to `null` or `""`) when SSE-S3 is preferred over a customer-managed key.
- `force_destroy` is `false` by default. Setting it to `true` allows `terraform destroy` to wipe a non-empty bucket — acceptable in `devl`, never in `prod`.
- `lifecycle_rules` is always an array (possibly empty `[]`). Each rule needs `id`, `enabled`, `prefix`, and `expiration_days`. Use `prefix = ""` to apply the rule bucket-wide.

### IAM (`config-iam.json`)

```jsonc
{
  "aws": {
    "iam": {
      "role_name": "<base-name>",
      "policies": [
        {
          "name": "<PolicyName>",
          "sid": "<StatementId>",
          "effect": "Allow",
          "action": [
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ],
          "resource": "s3-bucket-arn"
        }
      ]
    }
  }
}
```

**Field rules for IAM:**

- `role_name` is the **base name** only — `locals.tf` prepends `<project_code>-` and appends `-<environment>`.
- `policies` is an array of inline policy statements. Each statement becomes one inline policy attached to the role.
- `name` is the policy name (PascalCase, ends with `Policy` by convention).
- `sid` is the Statement ID (PascalCase, no `Policy` suffix).
- `effect` is `Allow` or `Deny` — almost always `Allow`.
- `action` is **always an array**, even for a single action. Sort within a logical grouping (S3 reads together, S3 writes together, etc.).
- `resource` uses one of the **placeholder tokens** below, OR a literal ARN, OR `"*"` for service-wide actions.

#### Resource placeholder tokens (CRITICAL)

The `resource` field uses tokens that `locals.tf` rewrites to real ARNs at apply time. **Never** put real account IDs or bucket names into the JSON.

| Token              | Rewrites to (in `locals.tf`)                                    |
|---|---|
| `s3-bucket-arn`    | `arn:aws:s3:::<resolved-bucket-name>`                            |
| `s3-bucket-arn/*`  | `arn:aws:s3:::<resolved-bucket-name>/*`                          |
| `kms-key-arn`      | The ARN of the KMS key looked up via `data "aws_kms_key"`        |
| `*`                | Literal `*` — used for service-wide actions like `sqs:SendMessage` where the queue isn't known until apply |

If a new placeholder token is needed, **add it to `locals.tf` first** (in the `resource =` rewrite block of `iam_role_config.inline_policies`) and document it here.

### Lambda (`config-lambda.json`)

For modules with **a single function**:

```jsonc
{
  "aws": {
    "lambda": {
      "function_name": "<base-name>",
      "runtime": "python3.12",
      "handler": "handler.lambda_handler",
      "memory_size": 256,
      "timeout_seconds": 60,
      "source_dir": "../../lambda/<function-name>",
      "environment_variables": {
        "LOG_LEVEL": "INFO"
      },
      "reserved_concurrency": null,
      "log_retention_days": 14
    }
  }
}
```

For multiple functions, key by logical role (`preprocessor`, `notifier`, etc.).

**Field rules for Lambda:**

- `function_name` is the base name only.
- `runtime` is a string matching AWS's runtime identifiers (`python3.12`, `nodejs20.x`, `java21`, etc.) — this skill does not validate the value, but `locals.tf` should.
- `handler` follows the language convention (`module.function` for Python, `file.function` for Node.js).
- `memory_size` in MB; `timeout_seconds` in seconds.
- `source_dir` is relative to the module directory — used by the Terraform Lambda module to package the deployment artifact.
- `environment_variables` is always an object (possibly empty `{}`).
- `reserved_concurrency` is `null` to omit (no reservation), or an integer.
- `log_retention_days` defaults to `14` for `devl`/`test`, `90` for `prod`.

### Glue (`config-glue.json`)

```jsonc
{
  "aws": {
    "glue": {
      "database_name": "<base-name>_db",
      "crawlers": [
        {
          "name": "<crawler-base-name>",
          "schedule": null,
          "s3_target_role": "processed",
          "s3_target_path": "cleaned/"
        }
      ],
      "jobs": [
        {
          "name": "<job-base-name>",
          "script_path": "scripts/glue/transform.py",
          "worker_type": "G.1X",
          "number_of_workers": 2,
          "timeout_minutes": 30,
          "source_role": "processed",
          "target_role": "final"
        }
      ]
    }
  }
}
```

**Field rules for Glue:**

- `database_name` is the base name only — `locals.tf` may prefix it with project code.
- `crawlers[].schedule` is `null` for on-demand or a cron expression (`"cron(0 1 * * ? *)"`) for scheduled.
- `s3_target_role` / `source_role` / `target_role` reference logical bucket roles in `config-s3.json` — `locals.tf` resolves these to actual bucket names. Never use literal bucket names or ARNs here.

### SQS, SNS, KMS, etc.

The same conventions apply: one file, one resource block, base names only, no real ARNs in policy `resource` fields. When a new resource type is added, document its schema in this skill before generating the first file — undocumented schemas drift across modules.

## Worked example

Given:
- Module: `infra/platform/tf/`
- Environment: `devl`
- Resources: S3 (single bucket), IAM (with policies referencing the bucket and a KMS key), and shared region

The skill produces three files.

### `infra/platform/tf/config/aws/devl/config-region.json`

```json
{
  "aws": {
    "region": "us-east-1"
  }
}
```

### `infra/platform/tf/config/aws/devl/config-s3.json`

```json
{
  "aws": {
    "s3": {
      "bucket_name": "northbridge-raw-data",
      "bucket_keys": ["raw-data/json"],
      "versioning": true,
      "kms_key_alias": "SB-KMS",
      "force_destroy": false,
      "lifecycle_rules": [
        {
          "id": "expire-raw-json-90-days",
          "enabled": true,
          "prefix": "raw-data/json",
          "expiration_days": 91
        }
      ]
    }
  }
}
```

### `infra/platform/tf/config/aws/devl/config-iam.json`

```json
{
  "aws": {
    "iam": {
      "role_name": "northbridge-snowflake-role",
      "policies": [
        {
          "name": "SnowflakeS3ListBucketPolicy",
          "sid": "SnowflakeS3ListBucket",
          "effect": "Allow",
          "action": [
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ],
          "resource": "s3-bucket-arn"
        },
        {
          "name": "SnowflakeS3ObjectAccessPolicy",
          "sid": "SnowflakeS3ObjectAccess",
          "effect": "Allow",
          "action": [
            "s3:GetObject",
            "s3:GetObjectVersion"
          ],
          "resource": "s3-bucket-arn/*"
        },
        {
          "name": "SnowflakeKMSAccessPolicy",
          "sid": "SnowflakeKMSAccess",
          "effect": "Allow",
          "action": [
            "kms:Decrypt",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
          ],
          "resource": "kms-key-arn"
        },
        {
          "name": "SnowflakeSQSSendMessagePolicy",
          "sid": "SnowflakeSQSSendMessage",
          "effect": "Allow",
          "action": [
            "sqs:SendMessage",
            "sqs:GetQueueUrl",
            "sqs:GetQueueAttributes"
          ],
          "resource": "*"
        }
      ]
    }
  }
}
```

Notice the formatting details that must be preserved across all files:

- 2-space indentation throughout.
- Top-level key is always `aws`, with exactly one resource sub-key per file.
- Arrays use multi-line form with one item per line; single-element arrays are still arrays (`["raw-data/json"]`, not `"raw-data/json"`).
- Trailing commas are forbidden — strict JSON.
- Files end with a trailing newline.
- Property order within an object is consistent: identifying fields first (`name`, `sid`), then `effect`, then `action`, then `resource`. For S3, the order is `bucket_name`, `bucket_keys`, `versioning`, `kms_key_alias`, `force_destroy`, `lifecycle_rules`.

## Validation

After writing the file(s):

1. Run `jq . <file>` (or any JSON linter) to confirm valid JSON. Trailing commas, unquoted keys, and stray `null`s are the most common issues.
2. Confirm every file has exactly one `aws.<resource>` top-level structure — no mixing of resource types in a single file.
3. Confirm `resource` fields in IAM policies use placeholder tokens (`s3-bucket-arn`, `s3-bucket-arn/*`, `kms-key-arn`) or literal `*` — never real ARNs with account IDs.
4. Confirm `bucket_name`, `role_name`, `function_name`, `database_name`, etc. are base names only — no project code prefixes, no environment suffixes, no region suffixes.
5. Confirm `kms_key_alias` is omitted (not `null`, not `""`) when the resource doesn't need a customer-managed key.
6. Cross-reference the file's keys against `locals.tf` — every value referenced via `local.aws_config.<resource>.X` must exist in the JSON.
7. Run `terraform plan` and confirm no validation preconditions in `validations.tf` fire on this config.

## Common mistakes to avoid

- **Do not** put real ARNs or account IDs in the `resource` field. Always use placeholder tokens (`s3-bucket-arn`, `kms-key-arn`, etc.). The whole point of the JSON-driven config is that the same file works across accounts.
- **Do not** combine multiple resource types into one file. `config-s3.json` holds S3 only; `config-iam.json` holds IAM only. The one-file-per-resource convention is what makes the configs reviewable in isolation.
- **Do not** include `<project_code>-` prefixes or `-<environment>-<region>` suffixes in `bucket_name`, `role_name`, etc. Those are added by `locals.tf` at apply time. Putting them in the JSON breaks per-environment overrides.
- **Do not** use a string for `action` or `bucket_keys`. Both are always arrays, even with one element.
- **Do not** set `kms_key_alias` to `null` or `""`. Omit the field entirely — `locals.tf` distinguishes "key configured" (truthy alias) from "no key configured" (field absent), and an empty string breaks that distinction.
- **Do not** invent placeholder tokens. If you need `dynamodb-table-arn` and it isn't documented above, **add the rewrite logic to `locals.tf` first**, then document the new token in this skill.
- **Do not** copy `config-s3.json` from `devl` to `prod` and forget to flip `force_destroy` to `false`. Always review per-environment overrides explicitly.
- **Do not** use trailing commas, comments, or other JSON5 features. The file is parsed by Terraform's `jsondecode()`, which is strict JSON only.
- **Do not** introduce new top-level sibling keys to `aws` (e.g. `aws.environment`, `aws.tags`) without coordinating with `locals.tf`. The contract is `aws.region` + `aws.<resource>` only.
- **Do not** leave `lifecycle_rules` out when the bucket should have one. An empty array `[]` is fine if no rules apply; omitting the key entirely will fail when `locals.tf` tries to iterate it.