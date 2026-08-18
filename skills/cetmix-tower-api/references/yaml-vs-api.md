# YAML vs API — what each one can actually do

**They are not equivalent.** Each can do things the other cannot. Pick per task, and
know the asymmetries before promising a workflow.

Verified against `cetmix_tower_yaml/models/cx_tower_yaml_mixin.py`, the import wizard,
`cx_tower_vault_mixin.py` and the per-model `_get_fields_for_yaml()` lists.

---

## Only YAML does this (you reimplement it via API)

| Capability                      | Detail                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Link by reference**           | `command_id: create_directory` resolves a reference to an id, creating the record if the value is exploded. Via ORM you pass integer ids.                                                                                                                                                                                                                  |
| **`access_level` words**        | `manager` → `"2"`. ORM takes `"1"`/`"2"`/`"3"` only.                                                                                                                                                                                                                                                                                                       |
| **Deferred forward references** | A second pass resolves `command.jet_template_id`, `command.jet_action_id`, `command.waypoint_template_id`, `jet_waypoint_template.jet_template_id`, `plan.line_ids[].command_id`, `jet_template.template_requires_ids[].template_required_id`, `scheduled_task.custom_variable_value_ids[].variable_value_id`. **No ORM equivalent** — order your creates. |
| **One transaction per file**    | The whole import runs in a savepoint; any failure rolls everything back. A sequence of `execute_kw` calls is _not_ atomic.                                                                                                                                                                                                                                 |
| **Safe contexts by default**    | Sets `from_yaml=True` (no file push/pull) and `skip_ssh_settings_check` for servers. Via ORM you must pass these.                                                                                                                                                                                                                                          |
| **Duplicate protection**        | `variable`, `variable_option`, `tag`, `os`, `key` always resolve to existing records — even in "Create a new record" mode. Under `server_template`, `plan`, `shortcut` and `scheduled_task` resolve too; under `server` also `command` (and `file` when `cetmix_tower_git` is installed).                                                                  |
| **Uniform conflict policy**     | One `if_record_exists` choice (`skip` / `update` / `create`) governs the whole file.                                                                                                                                                                                                                                                                       |
| **Manifest metadata**           | `name`, `summary`, `description`, `author`, `version`, `license`, `price`… is a **file-level** concept for sharing snippets. It is not a record and has no ORM equivalent.                                                                                                                                                                                 |
| **Portability**                 | A file moves between instances and lives in git.                                                                                                                                                                                                                                                                                                           |

---

## Only the API does this

| Capability                             | Detail                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Fields outside the YAML field list** | `command.server_ids` / `plan.server_ids` (restrict to servers), `user_ids` / `manager_ids` (access roles), `jet_action.jet_template_id`, `file.server_id`, `jet_template.icon`, `jet_template.access_level`, `server_log.access_level`, `server.status`, `metadata` (JSON), `git_project_rel.server_id`, and `active` on **every model except `webhook`** — `cx.tower.webhook` is the only one that lists `active` in `_get_fields_for_yaml`. |
| **Secret values**                      | `key.secret_value`, `key.value.secret_value`, `server.ssh_password`, `server.host_key` are writable through `create`/`write` — the vault mixin intercepts them and stores them outside the main table. **YAML cannot carry any of these.**                                                                                                                                                                                                    |
| **Models with no YAML path**           | `cx.tower.jet`, `cx.tower.jet.waypoint`, `cx.tower.jet.dependency`, `cx.tower.jet.request`, `cx.tower.jet.template.install(.line)`, `cx.tower.git.project.file.template.rel`. Jets and waypoints are runtime records — YAML only ever defines their templates.                                                                                                                                                                                |
| **Delete and archive**                 | The importer never deletes or archives anything.                                                                                                                                                                                                                                                                                                                                                                                              |
| **Read and query**                     | YAML export dumps a record tree; it is not a query interface.                                                                                                                                                                                                                                                                                                                                                                                 |
| **True x2m synchronisation**           | See below — this is the big one.                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Operations**                         | `run_command`, `run_flight_plan`, `jet_action.trigger`, `install_on_servers`, `create_jet`, `create_server_from_template`, `update_metadata`, `set_variable_value`.                                                                                                                                                                                                                                                                           |
| **Batching**                           | `create([vals1, vals2, …])` in one call, one cache clear.                                                                                                                                                                                                                                                                                                                                                                                     |

---

## The x2m asymmetry — read this before relying on re-import

The importer emits **only** `(0, 0, vals)` (create) and `(4, id)` (link). It never emits
`(2, id)`, `(3, id)`, `(5,)` or `(6, 0, [ids])`.

Consequence: **YAML "update" is additive, not a sync.**

Re-import a plan after deleting two lines from its `line_ids` and you get the plan's
remaining lines updated in place — and **the two deleted lines still attached**. Same
for `action_ids` on a jet template, `option_ids` on a variable, `tag_ids`,
`server_log_ids`, everything x2m.

Worse, and silent: `plan_line` and `plan_line_action` **discard** the `reference` you
authored (see `cetmix-tower-yaml` → _Nested references_). A re-import cannot match them,
so it creates a second copy of every line. A 12-line plan becomes 24 and would run every
step twice. `variable_value` hits the same mismatch but has a unique constraint, so the
import aborts instead.

So YAML is idempotent for _additions and field changes on records whose reference is
stable_, and **not** for _removals_ or for those three nested models.

To converge on an exact desired state you need the API:

```python
# Replace the whole set — removes anything not listed
plan.write({"line_ids": [(6, 0, [id1, id2, id3])]})

# Or delete specific children
plan.write({"line_ids": [(2, stale_line_id)]})
```

Practical rule: use YAML to create and to evolve definitions forward; use the API (or
delete in the UI) when something must be _removed_ or when refreshing plan lines /
template dependencies / template-scoped variable values. If a deployment must be
reproducible from scratch, import into a clean database rather than trusting repeated
updates.

If the target instance **already has** the same logical templates (API-created, maybe
under different references), do not import the YAML there at all. Skip and update both
make the live graph worse. Edit those records over the API; keep the YAML for empty
databases and other instances. Hard rule 14.

---

## Recipe: updating a Jet Template that is already imported

A whole-template re-import in `update` mode is not viable. Nested `plan_line`s
duplicate, nested `variable_value`s abort on the unique constraint, and
`template_requires_ids` raises _"You cannot modify an existing template dependency!"_
even when unchanged. Use this instead:

1. Re-import every **top-level** record except the `jet_template` — commands, variables,
   file templates, keys, custom states. Those match by stored `reference` and update
   cleanly. For **plans**, either strip `line_ids` from the payload (so only scalar
   fields update) or skip the plan records and write them in step 4. Importing a plan
   with `line_ids` still attached duplicates every line.
2. Write `jet_template` scalar fields (`note`, `limit_per_server`,
   `show_in_create_wizard`, …) over the API. Alternatively YAML-update the template
   after stripping `template_requires_ids` and `variable_value_ids` from the payload.
3. Never re-import `template_requires_ids` or `variable_value_ids` onto an existing
   template. Change values via `write` on the `variable_value` records (look them up by
   `variable_id` + `jet_template_id`, not by the authored nested reference). Replace a
   dependency by deleting it and creating a new one.
4. Converge plan lines by replacement — authored line references cannot match:

   ```python
   plan.write({"line_ids": [(5, 0, 0)] + [(0, 0, vals) for vals in lines]})
   ```

5. Verify afterwards: compare every command `code` body and every plan's line count
   against the source file. That check is what catches silent duplication.

`jet_action`, `server_log` and `jet_waypoint_template` keep authored references, so
nested updates of those under the template (once `template_requires_ids` /
`variable_value_ids` are stripped) do match. They are still additive: children you
removed from the file stay attached.

---

## Neither can do this

- **Read a secret value back.** Every read of a vault-backed field returns `*****`. The
  API can _set_ secrets but never retrieve them; the banned helpers `_get_secret_value(`
  / `_get_secret_values(` / `_set_secret_values(` are rejected inside Tower Python
  command code.
- **Bypass constraints, record rules or side effects.** Both paths go through the same
  ORM: the same required fields, the same SQL constraints, the same `ir.rule` record
  rules, the same create/write/unlink overrides.

---

## Identical in both

Everything about _design_ is unchanged: one statement per SSH command, `path` not `cd`,
`use_sudo` on the plan line, secrets referenced inline as `#!cxtower.secret.ref!#`, one
`variable_value` per scope, `state_transit_id` on every jet action, Build and Start on
separate plans, `note` on every record that has the field (see hard rule 8 — most child
models do not).

Selection keys are the same in both — except `access_level`.

---

## Choosing

| Task                                                                                         | Path                                      |
| -------------------------------------------------------------------------------------------- | ----------------------------------------- |
| Ship a reusable snippet or commit definitions to git                                         | YAML                                      |
| Bulk-create configuration from code                                                          | YAML built by code, imported over the API |
| Set a secret value, `ssh_password`, or access roles                                          | API                                       |
| Create a Jet, waypoint, or install a template on a server                                    | API                                       |
| Remove children from an existing record                                                      | API                                       |
| Refresh plan lines / template dependencies / template values on an already-imported template | API (see the recipe above)                |
| Query, report, or reconcile existing state                                                   | API                                       |
| Run anything                                                                                 | API                                       |

Using both is normal and expected. The failure mode to avoid is assuming a re-import
will converge state that only the API can converge.
