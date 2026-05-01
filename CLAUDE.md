# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

End-to-end data pipeline on AWS for processing CSV files. Raw CSV files land in `csv-raw-data`, are preprocessed by Lambda into `csv-processed-data`, cataloged by an AWS Glue Crawler, transformed by a Glue ETL job into `csv-final-data`, and visualized in Amazon QuickSight. All AWS infrastructure is provisioned via Terraform.

> **Current scope:** this iteration of the repository provisions only the **three S3 buckets** (`csv-raw-data`, `csv-processed-data`, `csv-final-data`). Lambda, Glue, and QuickSight resources will be added in subsequent iterations and must not be introduced into the configuration yet.

---

## Skills

This project uses a set of installed skills. Claude Code **must consult the relevant skill before editing any input JSON config or Terraform file**. Do not generate config blocks or Terraform from memory — always read the skill first.

### AWS config skills (`infra/platform/tf/config/aws/config.json`)

| Skill                      | Consult when editing                                             |
| -------------------------- | ---------------------------------------------------------------- |
| `aws-config-s3`            | `aws.region`, `aws.s3.*`, `aws.tf_state.*`                       |

> IAM, Lambda, Glue, and QuickSight skills are **not in scope yet**. Do not edit `aws.iam`, `aws.lambda`, `aws.glue`, or related blocks until the corresponding scope is added in a later iteration.

### Terraform file skills (`infra/platform/tf/`)

| Skill                       | Consult when editing                                             |
| --------------------------- | ---------------------------------------------------------------- |
| `terraform-backend-hcp`     | `backend.tf` — HCP Terraform Cloud workspace + `cloud { }` block |
| `tf-versions`               | `versions.tf` — `required_providers` declarations                |
| `tf-variables`              | `variables.tf` — module input declarations                       |
| `tf-locals`                 | `locals.tf` — JSON config parsing, default tags, naming          |
| `tf-provider`               | `providers-aws.tf` — `provider "aws"` configuration              |
| `tf-main`                   | `main.tf` — phased module orchestration                          |
| `tf-outputs`                | `outputs.tf` — module output shaping                             |
| `tf-validations`            | `validations.tf` — plan-time precondition assertions             |

### When multiple skills apply

When a task touches more than one file or config block, consult **all relevant skills** before making any changes. Adding a bucket, for example, may touch `aws-config-s3` (config JSON), `tf-locals` (naming and config parsing), `tf-main` (the module call), and `tf-outputs` (the bucket's output) — all four skills should be reviewed before the edit.

---

## Common Commands

All Terraform commands run from `infra/platform/tf/`:

```bash
cd infra/platform/tf

terraform init
terraform validate
terraform fmt -recursive

# Apply — provisions the three S3 buckets
terraform apply -var-file="terraform.tfvars"

# Destroy
terraform destroy -var-file="terraform.tfvars"

# Run tests
terraform test
```

### Pre-commit Hooks

The repo uses `pre-commit-terraform` hooks. Install and run:

```bash
pre-commit install
pre-commit run --all-files
```

Hooks include: `terraform_fmt`, `terraform_validate`, `terraform_providers_lock`, `terraform_docs`, `terraform_tflint`, `terraform_trivy`, `terrascan`, `checkov` (skips CKV_AWS_8), and `infracost_breakdown` (alerts if costs exceed $0.01/hour or $1/month).

### CI Pipeline

CI runs on push to `main`, `feature/**`, `bug/**` branches and on PRs to `main`. It only triggers on changes to `infra/platform/tf/**`, `infra/platform/tf/config/**`, or `.github/workflows/ci.yaml`. Uses a reusable workflow from `subhamay-bhattacharyya-gha/tf-ci-reusable-wf` with HCP Terraform remote backend. Changelog is auto-generated via git-cliff on non-main branches; releases are auto-created on merge to main.

---

## Version Constraints

- **Terraform**: ~> 1.14.0
- **AWS provider**: >= 5.0

> Other providers (Snowflake, Random, Null, Time) are not declared in `versions.tf` because they are not used yet. Do not add them speculatively.

---

## Architecture

### Target Pipeline (full scope, for context)

```text
CSV File
   │
   ▼  Upload
csv-raw-data S3 bucket
   │
   ▼  s3:ObjectCreated:* event → Lambda preprocessor
csv-processed-data S3 bucket           (cleaned / formatted CSV)
   │
   ▼  Glue Crawler → Glue Data Catalog
   │
   ▼  Glue ETL Job (Source → Transform → Store)
csv-final-data S3 bucket               (curated output for analytics)
   │
   ▼  Amazon QuickSight
Interactive dashboards & reports
```

### Current Iteration — Storage Layer Only

This iteration provisions the storage tier only — the three S3 buckets that the rest of the pipeline will sit on top of. Lambda, Glue Crawler, Glue Data Catalog, Glue ETL Job, and QuickSight resources are **out of scope** and must not be added yet.

```text
                          AWS Cloud
   ┌────────────────────────────────────────────────────────┐
   │                                                        │
   │   ┌──────────────┐   ┌─────────────────┐   ┌─────────┐ │
   │   │ csv-raw-data │   │ csv-processed-  │   │ csv-    │ │
   │   │   bucket     │   │   data bucket   │   │ final-  │ │
   │   │              │   │                 │   │ data    │ │
   │   │              │   │                 │   │ bucket  │ │
   │   └──────────────┘   └─────────────────┘   └─────────┘ │
   │                                                        │
   └────────────────────────────────────────────────────────┘
```

### Terraform Orchestration — Single Phase

`main.tf` provisions the three buckets in a single phase. There is no inter-bucket dependency — the buckets are independent — but they share the same module source and module-level configuration pattern.

1. **AWS Storage Layer** — three `module "s3_*"` blocks (`s3_raw`, `s3_processed`, `s3_final`), each pointing at the standard S3 module from `subhamay-bhattacharyya-tf/terraform-aws-s3.git//modules/bucket?ref=v1.0.0`.

When the Lambda phase is added in a later iteration, it will become Phase 2 (compute) and Phase 3 (S3 → Lambda event notification wiring); the bucket phase becomes Phase 1 unchanged.

### Provider Aliases

This iteration uses a single AWS provider with no aliases. Multi-provider patterns (cross-account, multi-region) are not in scope.

### Remote Module Sources

The S3 module is sourced from `subhamay-bhattacharyya-tf/terraform-aws-s3.git//modules/bucket`, pinned to a tagged version (`ref=v1.0.0`). When updating a module version, change the `ref=` parameter — do not copy module code locally.

---

## Configuration

### Input JSONs

Terraform reads all resource definitions from JSON config files. **Never hardcode resource names in `.tf` files** — everything comes from these configs.

> **Always consult the `aws-config-s3` skill before editing the config file.**

| File                                       | Purpose                                  | Skills            |
| ------------------------------------------ | ---------------------------------------- | ----------------- |
| `infra/platform/tf/config/aws/config.json` | Region and the three S3 bucket configs   | `aws-config-s3`   |

Environment-specific overrides live in `infra/platform/tf/config/aws/{devl,test,prod}/` and `infra/platform/tf/environments/{devl,test,prod}/terraform.tfvars`.

### AWS Config JSON structure

> Consult `aws-config-s3` before editing.

```text
infra/platform/tf/config/aws/config.json
└── aws.region                      ← aws-config-s3
    aws.s3.raw.*                    ← aws-config-s3
    │   ├── bucket_name, versioning, kms_key_alias, bucket_keys
    │   └── lifecycle_rules[]
    aws.s3.processed.*              ← aws-config-s3
    │   ├── bucket_name, versioning, kms_key_alias, bucket_keys
    │   └── lifecycle_rules[]
    aws.s3.final.*                  ← aws-config-s3
        ├── bucket_name, versioning, kms_key_alias, bucket_keys
        └── lifecycle_rules[]
```

> Do not add `aws.iam`, `aws.lambda`, `aws.glue`, or `aws.quicksight` blocks yet. Those are reserved for later iterations.

### Template Files

There are no `.tpl` templates in this iteration. SQL templates and policy templates will be added when downstream resources (IAM policies, Glue ETL jobs) come into scope.

---

## Bucket Naming

Buckets follow the standard project naming convention: `<project_code>-<base_name>-<environment>-<region>`.

| Logical role  | Base name (in config JSON) | Example resolved name (devl, us-east-1)     |
| ------------- | -------------------------- | ------------------------------------------- |
| Raw zone      | `csv-raw-data`             | `csvpipe-csv-raw-data-devl-us-east-1`       |
| Processed     | `csv-processed-data`       | `csvpipe-csv-processed-data-devl-us-east-1` |
| Final         | `csv-final-data`           | `csvpipe-csv-final-data-devl-us-east-1`     |

The base names are stored in `aws.s3.<role>.bucket_name`; the `<project_code>` and `<environment>` come from `var.project_code` and `var.environment`; the region is read from `local.aws_config.region`.

---

## Conventions

- **Names come from `infra/platform/tf/config/`** — never hardcode AWS resource names in `.tf` files
- **Consult the relevant skill before editing config JSON** — see [Skills](#skills) for the mapping
- **All three buckets are provisioned by the same module** — never special-case one of them
- **`debug-outputs.tf` must be deleted before merging** to `main`
- **`terraform.tfvars` is gitignored** — copy from `terraform.tfvars.example` to set up locally
- **Branch naming**: `feature/SBCSV-XXXX-short-description`
- **Do not add out-of-scope resources** — Lambda, Glue Crawler, Glue Data Catalog, Glue ETL Job, and QuickSight resources are reserved for later iterations and must not be introduced in this one

---

## Roadmap (out of scope for this iteration)

The following resources will be added in subsequent iterations. Do **not** introduce them in this iteration's PRs.

- **Lambda preprocessor** — triggered by `s3:ObjectCreated:*` on `csv-raw-data`; writes cleaned CSVs to `csv-processed-data`.
- **AWS Glue Crawler** — scans `csv-processed-data` and registers schema in the Glue Data Catalog.
- **AWS Glue Data Catalog** — table-level metadata for `csv-processed-data` and `csv-final-data`.
- **AWS Glue ETL Job** — reads from the cataloged source, applies the schema-change transformation, writes to `csv-final-data`.
- **Amazon QuickSight** — dataset and dashboard pointing at `csv-final-data` (via Athena over the Glue Catalog).
- **IAM** — least-privilege execution roles for Lambda and the Glue Job.
- **CloudWatch Logs** — log groups and retention policies for Lambda and the Glue Job.

When any of these comes into scope, the corresponding skill (`aws-config-iam-policies`, `aws-config-lambda`, `aws-config-glue`, etc.) and the corresponding section of this `CLAUDE.md` should be added at the same time.
