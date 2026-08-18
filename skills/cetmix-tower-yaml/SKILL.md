---
name: cetmix-tower-yaml
description:
  Write, review or fix Cetmix Tower YAML — the import/export format for Tower records.
  Covers file structure (cetmix_tower_yaml_version / manifest / records), the
  cetmix_tower_model names, relational field syntax (_id vs _ids, reference vs
  exploded), which child models must be nested, record ordering, the import wizard
  procedure and conflict handling, plus the authoritative per-model allowed-field lists.
  Use whenever producing or debugging a .yaml file for Cetmix Tower.
---

# Cetmix Tower YAML

The format mirrors the Odoo database. One file can carry records of many models.

## File skeleton

```yaml
# Optional leading comment.
cetmix_tower_yaml_version: 1
manifest: # optional, top-level ONLY
  name: My Snippet
records: # REQUIRED, a non-empty list
  - cetmix_tower_model: command # required on every top-level record
    reference: my_command # required on every top-level record
    name: My Command # then the model's own fields
    action: ssh_command
    code: echo hello
```

Only these three top-level keys exist. Anything else — `variables:`, `commands:`,
`flight_plans:`, `jet_templates:` — is a made-up schema and will not import.

`manifest` is **not** a record. Never put `cetmix_tower_model: manifest` in `records`.

### Hard requirements

- `records` must exist and be non-empty, or import fails with _"YAML file doesn't
  contain any records"_.
- **Every item in `records` must have `reference`**, or import fails with _"Record
  reference is missing"_. Nested records may omit it; Tower then generates one from the
  parent (e.g. `my_plan_plan_line_1`). Naming a nested record explicitly does **not**
  keep re-imports stable for every model — see _Nested references_ below.
- Every item in `records` must have a valid `cetmix_tower_model`.
- `cetmix_tower_yaml_version` higher than the instance's supported version (currently
  `1`) aborts the import.

## Model names

`cx.tower.model.name` → `model_name`: strip `cx.tower.`, replace dots with underscores.
The importer does the inverse, so the name must map exactly.

Full list with allowed fields: `references/model-fields.md`.

Frequent mistakes:

| Wrong                  | Right                                |
| ---------------------- | ------------------------------------ |
| `flight_plan`          | `plan`                               |
| `secret`               | `key` (with `key_type: s`)           |
| `ssh_key`              | `key` (with `key_type: k`)           |
| `jet`                  | not importable — only `jet_template` |
| `waypoint`             | `jet_waypoint_template`              |
| `manifest` as a record | top-level `manifest:` key            |

## Field values

| Odoo type       | YAML                                                                                                               |
| --------------- | ------------------------------------------------------------------------------------------------------------------ |
| Char / Text     | String. Use `\|-` for multi-line code.                                                                             |
| Integer / Float | Number                                                                                                             |
| Boolean         | `true` / `false`                                                                                                   |
| Date / Datetime | `2026-01-31` / `2026-01-31 12:00:00`                                                                               |
| Selection       | The **key**, not the label: `on_error_action: e`, `variable_type: o`, `key_type: s`                                |
| `access_level`  | `user`, `manager` or `root` (translated to `"1"`/`"2"`/`"3"`) — this is the one selection that uses friendly words |

Selection keys per field: `references/selection-values.md`.

`access_level` with any other value raises _"Wrong value for 'access_level' key"_.

### `use_sudo` is two different fields

Same name, different types, depending on the model. Copying one form onto the other
model writes a nonsense value:

| Model                                 | Type      | YAML                                                                                |
| ------------------------------------- | --------- | ----------------------------------------------------------------------------------- |
| `server`, `server_template`           | Selection | `use_sudo: n` (without password) · `use_sudo: p` (with password) · omit for no sudo |
| `plan_line`, `shortcut`, `server_log` | Boolean   | `use_sudo: true` / `false` — "apply whatever the server is configured for"          |

The Boolean form is the one you write on a flight plan line; the Selection form is a
property of the host.

Unknown keys are silently dropped. That is the most dangerous failure mode in this
format: a typo'd or invented field imports "successfully" and does nothing. Check every
field against `references/model-fields.md`.

`access_level` is the one exception: it is translated _before_ keys are filtered, so a
bad value raises and aborts the import even on a model whose field list does not carry
it.

## Relational fields

Suffix decides **structure**; it says nothing about create-vs-link.

- `*_id` (many2one) → **scalar**: a reference string, a single mapping, or `false`.
- `*_ids` (one2many / many2many) → **list**.

```yaml
# many2one, three valid forms
command_id: create_directory            # reference string
command_id:
  reference: create_directory           # reference-only mapping
command_id:                             # exploded: create or update, then link
  reference: create_directory
  name: Create directory
  action: ssh_command
  code: mkdir {{ dir }}

# many2many / one2many
tag_ids: [docker, system]               # reference strings
tag_ids:
- reference: docker                     # reference-only mappings
- reference: system
tag_ids:
- reference: docker                     # exploded
  name: Docker
  color: 4
```

Never wrap a `*_id` value in a list. Never give a `*_ids` field a scalar.

### Reference mode vs exploded mode

- **Reference mode** (string, or a mapping whose only key is `reference`) links to a
  record that already exists in the database _or_ was fully defined earlier in this
  file. If neither is true the importer logs a warning and **skips the link** — no
  error, so the omission is easy to miss.
- **Exploded mode** (a mapping with `reference` plus other fields) creates the record if
  missing, or **updates** it if it exists.

Consequence: exploding a record you did not intend to change will overwrite its fields.
When you only want to link, use reference mode.

Five models are always resolved to existing records rather than duplicated, even in
"Create a new record" import mode: `variable`, `variable_option`, `tag`, `os`, `key`.
That protects shared configuration from duplication. Records reached through a parent
add more, so importing a server does not clone the plans and commands it points at:

| Parent                                      | Adds                                                |
| ------------------------------------------- | --------------------------------------------------- |
| `server`                                    | `plan`, `shortcut`, `scheduled_task`, **`command`** |
| `server_template`                           | `plan`, `shortcut`, `scheduled_task`                |
| `server`, with `cetmix_tower_git` installed | also **`file`**                                     |

Note the asymmetry: `command` resolves under `server` but not under `server_template`.

### Nested vs top-level

A child may only be a top-level record if its own field list contains the link back to
its owner. These must be **nested** (see `cetmix-tower/references/entity-map.md` for the
whole table):

`plan_line`, `plan_line_action`, `variable_option`, `jet_action`,
`jet_template_dependency`, `server_log`, `shortcut`, `scheduled_task`,
`scheduled_task_cv`, `git_source`, `git_remote`, `git_project_rel`.

Special case: **a top-level `variable_value` is a global value**, because
`server_id`/`jet_template_id` etc. are not importable fields. Nest it under a parent's
`variable_value_ids` to scope it.

`cetmix_tower_model` inside a nested record is optional — real Tower exports omit it and
the importer discards it if present. Match the export style: omit it in nested records.

### Nested references: preserved vs discarded

The importer matches existing records by the **stored** `reference`. Four nested models
keep the name you wrote. Three overwrite it with a derived one, so a re-import in
`update` mode cannot find them and treats every child as new. The API page that says
references are auto-generated "if omitted" is true of create; it does not mean an
authored nested name is honoured on the next write of the parent.

| Nested model              | Authored `reference` | Stored as                               | Re-import match       |
| ------------------------- | -------------------- | --------------------------------------- | --------------------- |
| `jet_action`              | preserved            | what you wrote                          | yes                   |
| `jet_waypoint_template`   | preserved            | what you wrote                          | yes                   |
| `server_log`              | preserved            | what you wrote                          | yes                   |
| `variable_option`         | preserved            | what you wrote                          | yes                   |
| `jet_template_dependency` | preserved            | what you wrote                          | yes, then write fails |
| `plan_line`               | discarded            | `<plan>_plan_line_<n>`                  | no                    |
| `plan_line_action`        | discarded            | `<line>_plan_line_action_<n>`           | no                    |
| `variable_value`          | discarded            | `<var>_variable_value_<scope>_<parent>` | no                    |

For the three discarding models the authored `reference` is cosmetic — useful in the
file, useless for matching. A parent write that includes `reference` (YAML `update`
always does) regenerates those children from `_get_dependent_model_relation_fields`
(`plan.line_ids`, `plan_line.action_ids`, `variable.value_ids`). What happens next
depends on constraints — see _Common errors_ and _`update` is additive_.

`jet_template_dependency` keeps the name, then the write of `template_required_id` fails
anyway; see `You cannot modify an existing template dependency`.

## Record ordering

Two ways to organise a file:

- **Nested (single root).** One top-level record with everything inline. This is what
  Tower exports for a jet template or server template. Order does not matter.
- **Flat.** One list item per record. **Each record must appear before anything that
  references it.** In particular:
  - `key` records first. A forward-referenced `key` does **not** raise — the importer
    logs a warning, skips the link, and the import succeeds with an empty `ssh_key_id`
    or a dropped secret link. This is the _silently missing link_ failure mode below.
  - `jet_template` records referenced through `template_requires_ids` must already exist
    or be defined earlier (this one _is_ deferred — see below).

A few forward references are handled by a deferred second pass:
`command.jet_template_id`, `command.jet_action_id`, `command.waypoint_template_id`,
`jet_waypoint_template.jet_template_id`, `plan.line_ids[].command_id`,
`jet_template.template_requires_ids[].template_required_id`, and
`scheduled_task.custom_variable_value_ids[].variable_value_id`. If a deferred reference
still cannot be resolved after the main pass, the import raises _"Deferred relation
resolution failed"_ naming the record and field. Do not rely on this — order your
records properly.

## Omit defaults

Keep files minimal. Drop a key whose value equals the default:

| Field           | Default          |
| --------------- | ---------------- |
| `access_level`  | `manager`        |
| `variable_type` | `s`              |
| Boolean fields  | `false`          |
| Char / Text     | empty or `false` |
| `*_id`          | `false`          |
| `*_ids`         | `[]`             |

Exception: `state_from_id: false` and `state_to_id: false` on `jet_action` are
**meaningful** — they mark the create and destroy actions. Write them explicitly (or
omit the key entirely; both read as empty) and say which is which in the `note`.

Tower's own exports include every field, defaults included. That is fine to read but do
not imitate it when authoring.

## Import procedure

1. `Cetmix Tower > Tools > Import YAML`, upload the file, **Process**. This validates
   YAML syntax, the version, and that every `cetmix_tower_model` exists and supports
   YAML.
2. The wizard shows the manifest, a code preview, the list of secrets found in the file,
   and **If Record Exists**:

   | Option                   | Behaviour                                                                         |
   | ------------------------ | --------------------------------------------------------------------------------- |
   | `Skip record` (default)  | Leave the existing record untouched                                               |
   | `Update existing record` | Overwrite it with the YAML values                                                 |
   | `Create a new record`    | Create a duplicate with a new reference (except the always-resolved models above) |

   The choice applies to the whole file.

3. **Import**. Field-level failures (bad selection key, constraint violation) appear
   here. The whole import runs in a savepoint, so a failure leaves nothing behind.
4. Set secret values — YAML never carries them. Manually in the UI, or over the API
   (which _can_ write them; see `cetmix-tower-api`).

### Do not import onto an instance that already has the templates

If the live database already has the same logical templates or commands (created via
the API, possibly with different plan/command references), **do not import this file
onto that instance** (hard rule 14). `Skip record` leaves the live records untouched
and creates unused duplicate plans for every new nested reference. `Update existing
record` duplicates `plan_line`s and cannot rewrite `template_requires_ids`. Edit the
existing records over the API. Keep the YAML as a portable copy for empty databases
and other instances. Writing a YAML file does not mean the live instance matches it.

### `update` is additive, not a sync

The importer only ever emits "create" and "link" operations on x2m fields — never
"unlink" or "replace". So re-importing with **`update`**:

- updates matched records in place (by **stored** `reference`),
- creates records that are new,
- **leaves behind children you removed from the file**,
- and **duplicates children whose authored `reference` does not match what is stored**
  (`plan_line`, `plan_line_action`). Nothing surfaces this: a 12-line Prepare plan
  becomes 24 and would run every step twice.

Delete two lines from a plan's `line_ids`, re-import, and the plan still has them. Keep
the twelve lines and re-import, and you may get twenty-four. The same additive behaviour
applies to `action_ids`, `option_ids`, `tag_ids`, `server_log_ids` — every x2m field.

YAML is therefore idempotent for additions and field changes on records whose
`reference` is stable, **not for removals**, and **not for the three discarding nested
models** above. `variable_value` hits a unique constraint and aborts (safe, because of
the savepoint). `plan_line` / `plan_line_action` have no such constraint.

To converge on an exact set, use the API (`(5, 0, 0)` then `(0, 0, vals)`, or
`(6, 0, [ids])` / `(2, id)`) or delete in the UI. A whole-template re-import in `update`
mode is not a viable way to refresh an already-imported Jet Template — see
`cetmix-tower-api/references/yaml-vs-api.md`. If a deployment must be reproducible from
scratch, import into a clean database rather than trusting repeated updates.

After any re-import, compare every command `code` body and every plan's line count
against the source file. That is what catches silent duplication.

Round-trip: build in the UI, then export from the record's **YAML** tab (needs the
_Cetmix Tower YAML > Export_ right) and commit the file. The YAML tab is also writable
with _Import_ rights, so a single record can be updated by pasting YAML.

## Manifest

Optional, used when publishing snippets. Keys: `name`, `summary`, `description`,
`author` (string or list), `version`, `website`, `license`, `license_text`, `price`,
`currency`.

`license` accepts only `agpl-3`, `lgpl-3`, `mit`, `custom`. `proprietary` is invalid —
use `custom` plus `license_text`.

Write `description` as a multi-line block covering: what it does, the stack and
versions, what must be configured before use (secrets, servers, template installs), the
step-by-step usage, and troubleshooting. This is the only documentation the person
importing your file will read.

## Multi-file delivery

Allowed, but each file must be independently importable: its own `manifest` and
`records`, complete in itself. Never split one file across messages. State the import
order.

## Common errors

| Message                                                                                                       | Cause                                                                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `YAML file doesn't contain any records`                                                                       | No top-level `records`, or it is empty                                                                                                                                                                                                                                                      |
| `Record reference is missing`                                                                                 | A top-level record without `reference`                                                                                                                                                                                                                                                      |
| `Record model is missing for record X`                                                                        | Missing `cetmix_tower_model`                                                                                                                                                                                                                                                                |
| `'X' is not a valid model`                                                                                    | Bad model name (e.g. `flight_plan`)                                                                                                                                                                                                                                                         |
| `Model 'X' does not support YAML import`                                                                      | Real model, no YAML mixin                                                                                                                                                                                                                                                                   |
| `Wrong value for 'access_level' key`                                                                          | Not `user` / `manager` / `root`                                                                                                                                                                                                                                                             |
| `Invalid YAML file`                                                                                           | Syntax error — usually indentation, or an unquoted `{{ ... }}` at the start of a value                                                                                                                                                                                                      |
| `Deferred relation resolution failed`                                                                         | A forward reference never resolved                                                                                                                                                                                                                                                          |
| `YAML version is higher than…`                                                                                | `cetmix_tower_yaml_version` too high                                                                                                                                                                                                                                                        |
| `duplicate key value violates unique constraint "cx_tower_variable_value_unique_variable_value_jet_template"` | Nested `variable_value` re-import: the authored `reference` never matches, so the importer creates a second value and unique `(variable_id, jet_template_id)` aborts. The savepoint rolls the whole file back — retrying is safe.                                                           |
| `You cannot modify an existing template dependency! Please remove it and create a new one.`                   | Any `update` of a `jet_template` that still carries `template_requires_ids`. The model rejects writes of `template_id` / `template_required_id` even when the values are unchanged. Strip `template_requires_ids` from the payload, or delete the dependency first. Also savepoint-wrapped. |
| _silent plan-line duplication_                                                                                | Same discarded-reference cause as the unique-constraint error, but `plan_line` / `plan_line_action` have no unique constraint, so lines are created again with no error. Compare line counts after every re-import.                                                                         |
| _silently missing field_                                                                                      | Field not in that model's YAML field list                                                                                                                                                                                                                                                   |
| _silently missing link_                                                                                       | Reference mode pointing at something that does not exist yet                                                                                                                                                                                                                                |

### Quoting `{{ }}`

A value that _starts_ with `{` is a YAML flow mapping. Quote it:

```yaml
server_dir: '{{ redis_data_dir }}/conf'   # correct
server_dir: {{ redis_data_dir }}/conf     # YAML syntax error
code: mkdir -p {{ redis_data_dir }}/data  # fine — does not start with '{'
```

The same applies to values starting with `%`, `*`, `&`, `!`, `@`, or containing `: `.
