---
name: scaffold-terraform
description: Use this skill whenever the user asks to scaffold, bootstrap, generate, or initialize a new reusable Terraform module repository — typically named `terraform-<provider>-<resource>` (e.g. `terraform-aws-s3`, `terraform-snowflake-view`, `terraform-aws-iam`). Trigger when the user mentions "scaffold a Terraform module", "create a new terraform-aws-* repo", "bootstrap a Snowflake module", "generate the standard module layout", or asks to produce the full set of files (versions/variables/main/outputs, examples, Terratest, utility scripts) that a publishable single-resource module needs. Also trigger when the user pastes an existing `template-spec.md` and asks to apply it to a new repo. The defining features of this skill are: **(1)** the module wraps a single primary resource (with bucket-scoped or resource-scoped sub-resources allowed), **(2)** the module input is a single `map(object({...}))` consumed via `for_each` — never `count`, never a list, never multiple top-level variables, **(3)** every scaffolded repo ships with two examples, Terratest coverage with a fixed helpers contract, four utility scripts, and a `template-spec.md` that pins down literal values per repo, and **(4)** scaffolding is governed by that per-repo `template-spec.md` — when the spec and this skill disagree on a literal value, the spec wins. Do NOT use this skill for multi-resource orchestration modules (those belong in `infra/<module>/tf/` and use `tf-main` instead), for editing files in an already-scaffolded repo (handle conversationally), or for non-Terraform projects.
---

# Scaffold Terraform Module Skill

## Purpose

Generate the complete file tree for a new reusable Terraform module repository following this team's conventions: a single primary resource, a `map(object({...}))` input consumed via `for_each`, two runnable examples, Terratest coverage, four utility scripts, and a per-repo `template-spec.md` that captures every literal value the scaffolder needs.

This skill produces the **scaffolding only**. Once a repo is scaffolded, ongoing edits to individual files (adding a new validation, tweaking a Terratest assertion, updating a utility script) are handled conversationally — re-running the scaffolder on a populated repo would clobber user work.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Scaffold a new Terraform module called `terraform-<provider>-<resource>`"
- "Bootstrap the `terraform-aws-<service>` repo"
- "Generate the module structure for a new Snowflake / AWS resource"
- "I have a `template-spec.md` — produce all the files it describes"
- "Set up the standard layout for a publishable Terraform module"

Do **not** use this skill if:

- The user wants to scaffold a **multi-resource orchestration module** (the `infra/platform/tf/` shape with phased `main.tf`, JSON-driven config, and remote module calls). That uses the `tf-main`, `tf-locals`, `tf-variables`, `tf-outputs`, `tf-provider`, `tf-versions`, `tf-validations`, `terraform-backend-hcp`, and `tf-config-json` skills together — not this one.
- The repo already has scaffolded files and the user wants to edit them. Re-running this skill on a populated tree would overwrite hand-edited content.
- The repo isn't a Terraform module (no `*.tf` files, no `provider`/`resource` blocks).
- The module wraps multiple unrelated primary resources (e.g. "S3 bucket + Lambda + DynamoDB"). Each primary resource gets its own module repo.

## The two-document contract

Scaffolding is governed by **two documents working together**:

1. **`SKILL.md`** (this file) — describes *when* and *why* to scaffold, and the cross-repo conventions every scaffolded module shares.
2. **`template-spec.md`** (one per repo) — describes *exactly what* the scaffolded files must contain, field by field, line by line. Every repo has its own.

When the two disagree on a literal value, **`template-spec.md` wins**. The skill defines the shape; the spec defines the content.

If the user hasn't written a `template-spec.md` yet for the new module, **the skill's first job is to produce one** — generated from a short conversation (repo name, owner, primary resource type, input field shape) and modeled on existing specs (`template-spec.md` files for `terraform-snowflake-view`, `terraform-aws-s3`, etc.). Only after the spec is approved does the skill emit the actual `*.tf`, `*.go`, and `*.sh` files.

## Required information

Before writing any files, gather these inputs from the conversation. If the user has provided a `template-spec.md`, most of this is read from there.

### 1. Repo identity

- **Repo name** — `terraform-<provider>-<resource>` form (e.g. `terraform-aws-s3`, `terraform-snowflake-view`).
- **Owner / org** — typically `subhamay-bhattacharyya-tf`. Confirm if it differs.
- **Primary resource type** — the single AWS or Snowflake resource the module wraps (`aws_s3_bucket`, `snowflake_view`, `aws_iam_role`, etc.).
- **Module shape** — flat (`*.tf` at repo root) or nested (`modules/<name>/`). Check existing consumers in `main.tf` files: if they reference `//modules/<name>?ref=...`, the shape is nested.
- **Input variable name** — typically the plural of the resource (`buckets`, `views`, `roles`, `functions`).

### 2. Provider declaration

- **Provider source** — `hashicorp/aws`, `snowflakedb/snowflake`, etc.
- **Provider version floor** — typically `>= 5.0` for AWS, `>= 1.0.0` for Snowflake. No upper bound.
- **`required_version`** — `>= 1.5.0` is the standard floor (matches `optional()` defaults in object types).

### 3. Input schema (the `var.<input>` object shape)

For each field in the input object:

- **Name** (snake_case, matches the underlying resource argument where possible).
- **Type** (`string`, `bool`, `number`, `list(...)`, `map(...)`, nested `object({...})`).
- **Required vs. optional** — required fields have no `optional()`; optional fields use `optional(type, default)`.
- **Validation rules** — at least one validation block per non-trivially-constrained field (non-empty strings, regex matches, enum membership, cross-field dependencies).

### 4. Examples

Always **at least two** examples covering different code paths (e.g. simple vs. configured, encrypted vs. unencrypted, public vs. secure). For each:

- The example's purpose.
- The literal `<input>` map content.
- Any prerequisite resources (KMS keys, IAM roles, Snowflake databases) declared inline in the example.

### 5. Test contract

- The Terratest function names and what they assert.
- The helper signatures in `tests/helpers_test.go` (these are a fixed contract — every test in the repo uses the same helpers).

If any of the above is missing and there's no safe default, **ask the user**. Inventing values for a published module repo creates technical debt that's expensive to unwind.

## File tree produced

A flat-shape repo:

```
<repo-name>/
├── versions.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── README.md
├── examples/
│   ├── <example-1>/
│   │   ├── main.tf
│   │   └── README.md
│   └── <example-2>/
│       ├── main.tf
│       └── README.md
├── tests/
│   ├── <repo>_basic_test.go
│   ├── <repo>_<variant>_test.go      # one test file per example
│   └── helpers_test.go
├── utils/
│   ├── generate-docs.sh
│   ├── lint.sh
│   ├── align-md-tables.py
│   └── update-badge.sh
├── template-spec.md
├── package.json
├── package-lock.json
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── LICENSE
├── .editorconfig
├── .gitignore
├── .pre-commit-config.yaml
├── .releaserc.json
└── install-tools.sh
```

A nested-shape repo replaces the four root-level `*.tf` files and the `README.md` with a `modules/<name>/` subdirectory containing them, and updates example `source` paths from `../..` to `../../modules/<name>`. The `template-spec.md`, examples, tests, and utils stay at the repo root.

## Conventions every scaffolded module follows

These are the cross-repo invariants that **never vary** between modules. Per-repo `template-spec.md` files codify the *literal* values; this skill enforces the *shape*.

### Module input

- **Exactly one variable**, typically named for the plural of the resource (`buckets`, `views`, `roles`).
- **Type is always `map(object({...}))`**, consumed via `for_each`. Never `count`, never a list, never multiple top-level variables.
- **`default = {}`** so the module is a no-op when called with no input.
- **Validation blocks are pure on the input only** — never reference resources, data sources, or other variables.
- **No `sensitive = true`** unless the input genuinely carries secrets (rare for infra-config inputs).

### Resource block

- **Exactly one primary resource** with the local name `this` and `for_each = var.<input>`.
- **Sub-resources** (versioning, encryption, public-access-block, etc.) are separate `for_each` resources keyed off the same map keys.
- **Conditional sub-resources** use a filtered `for_each` map, not `count` — keeps map keys consistent with the parent.
- **No `depends_on`** unless a real cross-resource ordering issue exists; `for_each` over an input map produces correct dependency ordering by itself.
- **No `lifecycle` blocks** unless a specific drift problem requires one (and then it must be commented inline).

### Outputs

- **All outputs are `map(...)` shapes**, keyed by the input map keys. Never single values, never lists.
- **Every output has a non-empty `description`.**
- **No `sensitive = true`** unless the output genuinely carries secrets.
- **No raw resource passthroughs** (`output "x" { value = <resource>.this }`) — outputs expose specific attributes so tests pin against stable shapes.
- **Output names are referenced literally in tests** — renaming an output is a breaking change for the test suite.

### Examples

- **Always at least two**, exercising different code paths.
- **`source = "../.."`** (flat shape) or **`source = "../../modules/<name>"`** (nested shape). Never absolute paths or remote sources.
- **`terraform { required_version, required_providers }` matches the module's `versions.tf` exactly** — same source, same version range.
- **Provider blocks in examples are minimal** — for AWS, `provider "aws" { region = "<region>" }`; for Snowflake, `provider "snowflake" {}` (auth via env vars).
- **`terraform init -backend=false && terraform validate` must pass** for every example.

### Tests

- **Terratest in Go**, package `tests`.
- **`t.Parallel()` at the top of every top-level test.**
- **`defer terraform.Destroy(t, opts)` is set up before `InitAndApply`** — never after.
- **All resource-side assertions go through helpers** (`assertBucketExists`, `assertViewIsSecure`, etc.) — never raw SDK calls or SQL inline.
- **`tests/helpers_test.go` is a fixed contract** — every test in the repo uses only the symbols it exposes. New assertions become new helpers.
- **Idempotency check** — every test ends with a re-plan that asserts `No changes`.

### Utility scripts

Four scripts under `utils/`, all idempotent, all `set -euo pipefail` for Bash:

- **`generate-docs.sh`** — runs `terraform-docs markdown table --output-file README.md --output-mode inject` against the module root, then re-invokes `align-md-tables.py`.
- **`lint.sh`** — runs `tflint --recursive`, then `trivy config .`, then (for AWS modules) `checkov`. Exits with the **first** non-zero exit code.
- **`align-md-tables.py`** — pads every cell in every GFM table to its column max width, in place. Verifies post-write that pipe positions align.
- **`update-badge.sh`** — updates a shields.io custom-endpoint gist JSON, named `<repo-name>.json`, via `gh gist edit`.

## Output ordering

When the user invokes this skill on a fresh repo, produce files in this order:

1. **`template-spec.md`** first (if it doesn't exist) — the rest of the scaffolding is governed by it.
2. **`versions.tf`** — establishes the provider and Terraform version floor.
3. **`variables.tf`** — the input contract.
4. **`main.tf`** — the resource definitions.
5. **`outputs.tf`** — the output contract.
6. **`examples/<example-1>/`** then **`examples/<example-2>/`**.
7. **`tests/helpers_test.go`** — must exist before the test files reference it.
8. **`tests/<repo>_*_test.go`** — one per example.
9. **`utils/*.sh`** and **`utils/*.py`**.
10. **Top-level `README.md`** (auto-doc tables get filled in by `generate-docs.sh` afterwards).
11. **Repo hygiene files** — `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `LICENSE`, `.editorconfig`, `.gitignore`, `.pre-commit-config.yaml`, `.releaserc.json`, `install-tools.sh`, `package.json`, `package-lock.json`.

This order means each step's output is consumable by the next. Skipping ahead — for example, writing tests before `helpers_test.go` exists — produces a tree that doesn't compile.

## Validation

After scaffolding, run all of the following from the repo root. **Every command must exit `0`.**

```bash
terraform fmt -check -recursive

# Flat shape:
terraform init -backend=false && terraform validate
# Nested shape:
( cd modules/<name> && terraform init -backend=false && terraform validate )

# Every example:
( cd examples/<example-1> && terraform init -backend=false && terraform validate )
( cd examples/<example-2> && terraform init -backend=false && terraform validate )

bash utils/lint.sh                                # local-only — not invoked from CI
bash utils/generate-docs.sh && python utils/align-md-tables.py
git diff --exit-code README.md                    # docs must be in sync
pre-commit run --all-files
```

If any of these fails on a freshly-scaffolded tree, the scaffolder produced inconsistent output. **Fix `template-spec.md` first**, then re-scaffold — never patch the generated files in place, because the next regeneration will overwrite the patch.

The scaffolder must also pass each module's per-repo cross-file invariants (the §10 section of every `template-spec.md`). Before declaring scaffolding done, walk through that section and verify every item.

## Common mistakes to avoid

- **Do not** scaffold without a `template-spec.md`. The spec is the source of truth — generating files first and writing the spec afterward leads to drift no one catches until the next regeneration.
- **Do not** use `count` for the primary resource. Every scaffolded module is `for_each`-only. `count` produces index-based addresses that break when the input order changes.
- **Do not** declare more than one input variable. The contract is a single `map(object({...}))`. If a module needs region, account ID, or other context, those come from the caller's provider configuration — not from extra variables.
- **Do not** put a `provider "..." { }` configuration block in the module's `versions.tf` or `main.tf`. Provider configuration belongs in the **caller** (or in `examples/`), never in the module itself.
- **Do not** hand-write SDK calls in test files. All resource-side verification goes through helpers in `tests/helpers_test.go`. New assertions become new helpers — that's the contract.
- **Do not** raw-passthrough resources as outputs. Outputs are `map(...)` shapes of specific attributes. Raw `value = <resource>.this` is brittle and breaks every time the upstream provider renames an attribute.
- **Do not** use absolute paths or remote sources in examples. `source = "../.."` (or `../../modules/<name>`) is the only acceptable form. Absolute paths break in CI; remote sources defeat the purpose of testing local changes.
- **Do not** scaffold tests that don't end with an idempotency re-plan. Idempotency is the most common bug class in Terraform modules and the cheapest one to catch.
- **Do not** combine multiple unrelated primary resources into one module. Each primary resource gets its own repo. The module-per-resource pattern is what makes the orchestration layer (`infra/platform/tf/main.tf`, etc.) clean.
- **Do not** leave template references from a previous scaffold in the new repo. Search the entire tree for the previous repo's name, primary resource, and input variable — any hit is a regeneration bug. The §10 invariants in each `template-spec.md` enumerate the strings to search for.
- **Do not** patch generated files instead of fixing `template-spec.md`. Regeneration is the contract; patches will be overwritten the next time the scaffolder runs.
- **Do not** invent helper signatures. Every test file uses only the symbols listed in §8 of the per-repo `template-spec.md`. New helpers go in `helpers_test.go`, not inline in the test.