---
name: tf-validations
description: Use this skill whenever the user asks to create, generate, scaffold, or write a Terraform `validations.tf` file. Trigger when the user mentions "validations.tf", "Terraform precondition", "terraform_data lifecycle", "fail plan early", "config assertions", "validate JSON config", or asks to add a plan-time check that surfaces a clear error before any resource is created. Also trigger when the user describes a class of bug they want to prevent (path doubling, naming collisions, missing required keys, invalid enum values) and the right tool is a precondition rather than a `variable` validation block. The defining features of this skill are: **(1)** assertions are implemented as `resource "terraform_data" "validate_<group>"` blocks with `lifecycle.precondition`, **(2)** related checks are grouped into a single resource per category (template paths, naming, required keys, enums, cross-references), **(3)** each block opens with a banner comment explaining what the check guards against and why, and **(4)** `error_message` heredocs are concrete with both the bad input and the corrected form. Do NOT use this skill for variable validation (`validation { }` blocks inside `variable`) — those belong in `variables.tf` and are handled by the `tf-variables` skill.
---

# Terraform Validations Skill

## Purpose

Generate a `validations.tf` file that asserts plan-time invariants — failing `terraform plan` early with a concrete, actionable error message before any resources are created or any cryptic downstream error fires.

This file exists because some bugs only show up deep inside `templatefile()`, `for_each`, or upstream-module errors, where the resulting message gives no clue about the actual cause. A targeted precondition surfaces the real problem at the top of the plan output, with a message the user can act on directly.

## When to use this skill

Use this skill when the user asks for any of the following:

- "Create a `validations.tf` for this module"
- "Add a check that fails plan when `<X>` is wrong"
- "Guard against `<regression Y>`"
- "Validate the JSON config before applying"
- "Make plan fail early if `<convention violated>`"

Do **not** use this skill if:

- The check belongs inside a `variable` block (single-value validation against allowed types or enum values) — that's the `tf-variables` skill's job.
- The check belongs near a specific resource (postcondition on a data source, precondition on a resource) — that's an inline `lifecycle` block, not this file.
- The check requires runtime data only available after apply — preconditions are evaluated during plan, so they can only inspect values knowable at plan time.

## Required information

Before writing the file, gather these inputs from the conversation. Ask the user only for what isn't already established.

### 1. Module path

- **Path:** typically `infra/<module>/tf/validations.tf`. If unspecified, default to that pattern.

### 2. Categories of checks

Group related checks into named categories. Each category becomes one `terraform_data` resource. Common categories:

| Category | Resource name | What it guards |
|---|---|---|
| Template paths | `validate_template_paths` | File paths in JSON config are filenames only, not directory paths |
| Naming conventions | `validate_naming` | Resource names match length, character, or prefix rules |
| Required keys | `validate_required_keys` | Every entry in a config map has the required attributes |
| Enum values | `validate_enums` | Config values fall within an allowed set |
| Cross-references | `validate_references` | Items referenced by other items actually exist |
| Mutually exclusive | `validate_mutex` | Exactly one of N options is set |
| Resource limits | `validate_limits` | Counts or sizes don't exceed module-level caps |

Add new categories as needed — but **don't put unrelated checks in the same resource**. If two checks fail for unrelated reasons, the user should see two distinct error messages, not one merged one.

### 3. For each check, gather

- **What it asserts** (one sentence).
- **What goes wrong if it's violated** — the cryptic downstream error this prevents.
- **The condition expression** in HCL (`alltrue(...)`, `length(...) == 0`, `can(regex(...))`, etc.).
- **A concrete error message** showing both bad and good forms.

If any of these is missing, ask the user — preconditions with vague error messages are nearly as bad as no preconditions at all.

## Output template

Write the file to the path the user specifies, defaulting to `infra/<module>/tf/validations.tf`.

The file follows this exact structure:

```hcl
# -- <RELATIVE_PATH>
# ============================================================================
# Config assertions — fail plan early when required conventions are violated.
# ============================================================================

# ============================================================================
# <CATEGORY 1 NAME, e.g. Template Paths>
# ============================================================================
# <Multi-line rationale: what the check guards against, what cryptic error
# this prevents, and any context a future maintainer needs.>
# ============================================================================
resource "terraform_data" "validate_<group>" {
  lifecycle {
    precondition {
      condition     = <expression>
      error_message = <<-EOT
        <Concrete error message — see Error message format below.>
      EOT
    }
  }
}

# ============================================================================
# <CATEGORY 2 NAME>
# ============================================================================
# <Rationale.>
# ============================================================================
resource "terraform_data" "validate_<group>" {
  lifecycle {
    precondition { ... }
    precondition { ... }   # multiple checks in the same category are fine
  }
}
```

### Banner rules

- The header banner uses `# -- <path>` (no module description suffix needed for this file — the path alone is sufficient).
- Each category has a full-width `# === ... ===` banner introducing it.
- The rationale paragraph following the category banner is **not optional**. If you can't articulate what the check guards against, the check probably shouldn't exist.
- Categories are separated by a blank line.

### Resource block format

```hcl
resource "terraform_data" "validate_<group>" {
  lifecycle {
    precondition {
      condition     = <expression>
      error_message = <<-EOT
        ...
      EOT
    }
  }
}
```

Rules:

- Always use `resource "terraform_data"` — not `null_resource`. `terraform_data` is the modern, provider-less primitive for this pattern.
- The resource name is `validate_<group>`, snake_case, matching the category.
- Every precondition has both `condition` and `error_message`.
- Always use the `<<-EOT` heredoc form for `error_message` — it preserves indentation and lets you write multi-line messages naturally.
- Multiple related checks can sit inside a single `lifecycle { }` block as separate `precondition { }` entries — useful when they share context but have distinct failure modes.

### Condition expression patterns

Common shapes for the `condition` expression:

```hcl
# All items in a flat collection satisfy a predicate
condition = alltrue([for x in local.items : <predicate(x)>])

# All items in a nested collection satisfy a predicate
condition = alltrue(flatten([
  for db_key, db in local.config.databases : [
    for schema in db.schemas : [
      for item in schema.items : <predicate(item)>
    ]
  ]
]))

# A specific value matches an allowed set
condition = contains(["a", "b", "c"], local.value)

# A string does not contain a forbidden character
condition = !can(regex("/", local.value))

# A required key exists
condition = lookup(local.config, "required_key", null) != null

# Counts/lengths are within bounds
condition = length(local.items) <= 100

# Cross-reference — every referenced item exists
condition = alltrue([
  for ref in local.references : contains(keys(local.targets), ref)
])
```

When in doubt, **prefer `alltrue([for ... : <predicate>])`** over chained boolean expressions. It's easier to read, easier to extend, and produces a single check with one error message.

### Error message format

Heredocs should follow this shape:

```
Invalid <thing> in <where>.
<One sentence explaining the rule.>

Bad:
    "<key>": "<bad value>"

Good:
    "<key>": "<good value>"

<Optional: 1-2 sentences explaining why, or pointing at the file that
processes the value.>
```

Concrete examples beat abstract ones every time. The user reading this error message at 11pm should be able to fix the bug without reading the Terraform source.

## Worked example

Given:
- Path: `infra/platform/tf/validations.tf`
- Two categories: template paths (filenames-only check), and required-keys (every snowpipe must have `name` and `database`)

```hcl
# -- infra/platform/tf/validations.tf
# ============================================================================
# Config assertions — fail plan early when required conventions are violated.
# ============================================================================

# ============================================================================
# Template Paths
# ============================================================================
# locals.tf renders SQL templates via `templatefile()` and prepends a fixed
# directory prefix to each referenced filename:
#
#   - snowpipes[].copy_template        → templates/snowpipe-copy-statements/<file>
#   - dynamic_tables[].query_template  → templates/dynamic-tables/<file>
#
# If the config JSON value contains that prefix as well, the rendered path
# doubles up (e.g. templates/dynamic-tables/templates/dynamic-tables/file.tpl)
# and `terraform plan` fails with a cryptic templatefile() error. Guard against
# that regression by asserting values are filenames only (no `/`).
# ============================================================================
resource "terraform_data" "validate_template_paths" {
  lifecycle {
    precondition {
      condition = alltrue(flatten([
        for db_key, db in lookup(local.snowflake_config, "databases", {}) : [
          for schema in lookup(db, "schemas", []) : concat(
            [
              for pipe_key, pipe in lookup(schema, "snowpipes", {}) :
              !can(regex("/", lookup(pipe, "copy_template", "")))
            ],
            [
              for dt_key, dt in lookup(schema, "dynamic_tables", {}) :
              !can(regex("/", lookup(dt, "query_template_file", "")))
            ]
          )
        ]
      ]))
      error_message = <<-EOT
        Invalid template path in Snowflake config JSON.
        Fields `copy_template` (under snowpipes) and `query_template_file`
        (under dynamic_tables) must be filenames only, e.g.:
            "query_template_file": "clean_northbridge.tpl"
        Not:
            "query_template_file": "templates/dynamic-tables/clean_northbridge.tpl"
        locals.tf prepends the directory prefix automatically when rendering
        the template.
      EOT
    }
  }
}

# ============================================================================
# Required Keys
# ============================================================================
# Every snowpipe entry must declare `name` and `database` — locals.tf assumes
# both are present when constructing the snowpipe map. Without these, the
# downstream module fails with a "key not found" message that doesn't point
# at the offending entry.
# ============================================================================
resource "terraform_data" "validate_required_keys" {
  lifecycle {
    precondition {
      condition = alltrue(flatten([
        for db_key, db in lookup(local.snowflake_config, "databases", {}) : [
          for schema in lookup(db, "schemas", []) : [
            for pipe_key, pipe in lookup(schema, "snowpipes", {}) :
            lookup(pipe, "name", null) != null &&
            lookup(pipe, "database", null) != null
          ]
        ]
      ]))
      error_message = <<-EOT
        Snowpipe entry missing required keys in Snowflake config JSON.
        Every snowpipe must declare both `name` and `database`. Example:
            {
              "name": "RAW_NORTHBRIDGE_PIPE",
              "database": "NORTHBRIDGE_DATABASE",
              ...
            }
      EOT
    }
  }
}
```

Notice the formatting details that must be preserved:

- 2-space indentation throughout.
- The `condition` expression starts on the same line as `condition =` for short expressions, or opens with `(` on the same line and continues on the next line for multi-line expressions.
- The `<<-EOT` heredoc opener is followed by a newline; content is indented 8 spaces from the column of the `EOT` (Terraform's `<<-` strips the leading indentation).
- A blank line separates each `# === ... ===` category from the next.
- Multiple checks within the same category live in **the same `lifecycle { }` block** as multiple `precondition { }` entries.

## Validation

After writing the file:

1. Run `terraform fmt -check validations.tf` if Terraform is available locally — the file should already be canonically formatted.
2. Run `terraform plan` against a known-good config — all preconditions should pass cleanly.
3. Run `terraform plan` against a deliberately-broken config (one violation per category) — each violation should fail with the relevant error message and not with a downstream cryptic error.
4. Confirm every `terraform_data` resource is named `validate_<group>` and has at least one `precondition` block.
5. Confirm `error_message` heredocs include both bad and good examples — an abstract message ("Invalid value") is a code smell for this skill.

## Common mistakes to avoid

- **Do not** use `null_resource` for this pattern. `terraform_data` (introduced in Terraform 1.4) is the modern equivalent and doesn't require the `null` provider.
- **Do not** put unrelated checks into one resource. If two preconditions fail for unrelated reasons, the user should see two distinct error messages.
- **Do not** write vague error messages. "Invalid input" is unhelpful at 11pm; "Invalid template path. Use `clean_northbridge.tpl` not `templates/dynamic-tables/clean_northbridge.tpl`" is actionable.
- **Do not** drop the rationale comment above each category. The "what does this check guard against" paragraph is the most valuable part of the file for future maintainers — it answers the question "can I delete this check?"
- **Do not** put runtime values (resource attributes, data source results that depend on apply-time state) in the condition. Preconditions evaluate at plan time; runtime values aren't available yet.
- **Do not** use this file for `variable` validation. Single-value enum or type checks belong inside the `variable` block in `variables.tf`. This file is for invariants that span multiple values, multiple variables, or parsed config structures.
- **Do not** forget that `terraform_data` resources show up in plan output with no diff but still count as "resources to create" on first apply. That's expected — the resource exists solely to host the lifecycle block.
- **Do not** make a precondition depend on values that may legitimately be absent (e.g. a section of JSON that's optional). Use `lookup(..., default)` to handle absence gracefully rather than throwing on missing keys.