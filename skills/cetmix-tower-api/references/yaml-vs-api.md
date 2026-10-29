# YAML vs API — what each one can actually do

**They are not equivalent.** Each can do things the other cannot. Pick per task, and
know the asymmetries before promising a workflow.

Verified against `cetmix_tower_yaml/models/cx_tower_yaml_mixin.py`, the import wizard
and `cx_tower_vault_mixin.py`. Which fields are exported is the `yaml_export`
attribute on each field.

---

## Only YAML does this (you reimplement it via API)

| Capability                      | Detail                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Link by reference**           | `command_id: create_directory` resolves a reference to an id, creating the record if the value is exploded. Via ORM you pass integer ids.                                                                                                                                                                                                                  |
| **`access_level` words**        | `manager` → `"2"`. ORM takes `"1"`/`"2"`/`"3"` only.                                                                                                                                                                                                                                                                                                       |
| **Deferred forward references** | A reference to a record later in the same file is resolved after the main pass, from the file first and then from the database. A required link that is still unresolved fails before that record is saved. **No ORM equivalent** — order your creates. |
| **One transaction per file**    | The whole import runs in a savepoint; any failure rolls everything back. A sequence of `execute_kw` calls is _not_ atomic.                                                                                                                                                                                                                                 |
| **Safe contexts by default**    | Sets `from_yaml=True` (no file push/pull) and `skip_ssh_settings_check` for servers. Via ORM you must pass these.                                                                                                                                                                                                                                          |
| **Duplicate protection**        | A nested full dict of `variable`, `tag`, `os` or `key` resolves to the existing record. A server adds `plan`, `shortcut`, `scheduled_task` and `command`; a server template adds `plan`, `shortcut` and `scheduled_task`. Owned children (options, files) are never reused, so a copy gets its own. In an exported file those are separate records: **Create a new record** copies only the selected ones and links the others without writing them. |
| **Uniform conflict policy**     | One `if_record_exists` choice (`skip` / `update` / `create`) governs the whole file. Create copies only the selected records (`cetmix_tower_root`, or every top-level record when the file has no marker) and leaves other existing records unchanged.                                                                                                    |
| **Manifest metadata**           | `name`, `summary`, `description`, `author`, `version`, `license`, `price`… is a **file-level** concept for sharing snippets. It is not a record and has no ORM equivalent.                                                                                                                                                                                 |
| **Portability**                 | A file moves between instances and lives in git.                                                                                                                                                                                                                                                                                                           |

---

## Only the API does this

| Capability                             | Detail                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Fields outside the YAML field list** | `command.server_ids` / `plan.server_ids` (restrict to servers), `user_ids` / `manager_ids` (access roles), `jet_action.jet_template_id`, `file.server_id`, `jet_template.icon`, `jet_template.access_level`, `server_log.access_level`, `server.status`, `metadata` (JSON), `git_project_rel.server_id`, and `active` on **every model except `webhook`** — `cx.tower.webhook` is the only one that sets `yaml_export=True` on `active`. |
| **Secret values**                      | `key.secret_value`, `key.value.secret_value`, `server.ssh_password`, `server.host_key` are writable through `create`/`write` — the vault mixin intercepts them and stores them outside the main table. **YAML cannot carry any of these.**                                                                                                                                                                                                    |
| **Models with no YAML path**           | `cx.tower.jet`, `cx.tower.jet.waypoint`, `cx.tower.jet.dependency`, `cx.tower.jet.request`, `cx.tower.jet.template.install(.line)`, `cx.tower.git.project.file.template.rel`. Jets and waypoints are runtime records — YAML only ever defines their templates.                                                                                                                                                                                |
| **Delete and archive**                 | The importer never deletes or archives anything.                                                                                                                                                                                                                                                                                                                                                                                              |
| **Read and query**                     | YAML export writes a flat file, with owned children nested; it is not a query interface.                                                                                                                                                                                                                                                                                                                                                      |
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

Matching is by stored `reference`, and nested children keep the reference written in
the file (see `cetmix-tower-yaml` → _Nested references_). A child whose stored
reference differs from the file — typically one created in the UI before the file
existed — is not matched: a `plan_line` is added again, a `variable_value` aborts on
its unique constraint.

So YAML is idempotent for _additions and field changes on records whose reference
matches_, and **not** for _removals_.

To converge on an exact desired state you need the API:

```python
# Replace the whole set — removes anything not listed
plan.write({"line_ids": [(6, 0, [id1, id2, id3])]})

# Or delete specific children
plan.write({"line_ids": [(2, stale_line_id)]})
```

Practical rule: use YAML to create and to evolve definitions forward; use the API (or
delete in the UI) when something must be _removed_. If a deployment must be
reproducible from scratch, import into a clean database rather than trusting repeated
updates.

If the target instance **already has** the same logical templates (API-created, maybe
under different references), do not import the YAML there at all. Skip and update both
make the live graph worse. Edit those records over the API; keep the YAML for empty
databases and other instances. Hard rule 14.

---

## Recipe: updating a Jet Template that is already imported

If the template was imported from this file (or exported from this instance), a
whole-file `update` re-import works for additions and field changes:

- top-level records (commands, plans, variables, keys, file templates) match by stored
  `reference` and are written;
- nested plan lines, line actions, variable values, jet actions, waypoints and server
  logs keep the reference from the file, so they match too;
- a `template_requires_ids` row is matched by `(template_id, template_required_id)`; an
  existing pair is left unchanged, a new pair is added.

It is still additive. To remove a child, delete it over the API or in the UI:

```python
plan.write({"line_ids": [(5, 0, 0)] + [(0, 0, vals) for vals in lines]})
```

If the instance has the same logical templates under **different** references, do not
import the file there (hard rule 14); edit those records over the API instead.

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
