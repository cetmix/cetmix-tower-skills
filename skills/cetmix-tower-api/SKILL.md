---
name: cetmix-tower-api
description:
  Create and manage Cetmix Tower entities programmatically through Odoo's external API
  (XML-RPC/JSON-RPC execute_kw) or in-process Python — real model names, access_level as
  "1"/"2"/"3", x2m command tuples, resolving records with get_by_reference, required
  fields, the contexts that suppress unwanted SSH side effects (from_yaml,
  skip_ssh_settings_check), per-model access rights, idempotent upsert patterns, driving
  the YAML import wizard over the API, and running commands, plans, jet actions and
  template installs. Use whenever Tower records are created or updated by code rather
  than by importing a YAML file in the UI.
---

# Creating Tower entities through the API

## What "the API" is

There is **no REST API module in Cetmix Tower today**. `cetmix_tower_api` (an
OCA-FastAPI module exposing `/tower_api` endpoints) exists only as a specification in
`cetmix-tower-dev-docs/cetmix-tower-ai/TASK-cetmix-tower-api-module.md`. Do not document
or call endpoints from it. If a request assumes those endpoints exist, say they do not.

What is available:

| Surface                                     | How                                                                                                             |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Odoo external API**                       | XML-RPC `/xmlrpc/2/object` or JSON-RPC `/jsonrpc`, `execute_kw(db, uid, password, model, method, args, kwargs)` |
| **In-process Python**                       | Tower Python commands, Odoo automated actions, `odoo shell`, a custom module                                    |
| **YAML import wizard, driven over the API** | `cx.tower.yaml.import.wiz` — see _Hybrid_ below                                                                 |

Everything below applies to all three; only the call syntax differs.

## Three delivery paths — choose deliberately

**A. Direct ORM create/write.** Full control, needed for reads, updates, deletions,
queries and all operations (running commands, triggering actions), plus everything YAML
cannot express — secret values, `ssh_password`, access roles, `server_ids`, metadata,
Jets and waypoints. Cost: you reimplement by hand everything the YAML importer does for
you.

**B. Hybrid: build YAML, import it over the API.** You keep the importer's reference
resolution, deduplication, `access_level` translation, deferred forward references and
the safe contexts, while staying fully programmatic. **For bulk entity creation this is
usually the better path** — it is the same machinery the UI uses, so behaviour matches
exactly.

**C. YAML file, imported by hand in the UI.** For handing work to a person.

Use **B** to create configuration in bulk, **A** for everything else. Mixing is normal.

**The two paths are not interchangeable.** Each can do things the other cannot — most
sharply: only the API can set secret values, delete x2m children, or create Jets; only
YAML gives you reference linking, deferred forward references and one atomic transaction
per file. Read `references/yaml-vs-api.md` before committing to a workflow.

## What the importer does that direct ORM does not

This is the part that bites. The YAML importer is not a thin wrapper — it performs eight
transformations. Via direct ORM you must do each yourself.

| #   | Importer behaviour                                 | Direct ORM equivalent                                                            |
| --- | -------------------------------------------------- | -------------------------------------------------------------------------------- |
| 1   | YAML alias → real model (`plan` → `cx.tower.plan`) | Use the **real** Odoo model name                                                 |
| 2   | `access_level: manager` → `"2"`                    | Write `"1"` / `"2"` / `"3"` yourself                                             |
| 3   | Reference strings → database ids                   | `get_by_reference()`, then pass ids                                              |
| 4   | Nested dicts → create-or-update of related records | Create related records first, in order                                           |
| 5   | Two-pass deferred forward references               | **No deferred pass.** Order your creates.                                        |
| 6   | Sets `from_yaml=True`                              | Pass it yourself, or accept SSH side effects                                     |
| 7   | Sets `skip_ssh_settings_check` for servers         | Pass it yourself, or supply IP + password                                        |
| 8   | Wraps everything in one savepoint                  | One `execute_kw` call = one transaction; a multi-call sequence is **not** atomic |

Point 8 deserves emphasis: a sequence of `execute_kw` calls can fail halfway and leave
partial data. Either use path B, or make your writes idempotent (see _Upsert_).

## Model and field mechanics

**Model names are the real ones.** `cx.tower.command`, `cx.tower.plan`,
`cx.tower.plan.line`, `cx.tower.variable.value`, `cx.tower.jet.template`,
`cx.tower.jet.action`, `cx.tower.key`. Never the YAML aliases. The mapping is
`cx.tower.` + alias with `_` → `.`; full list in
`cetmix-tower-yaml/references/model-fields.md`.

**Do not send `cetmix_tower_model`.** It is a YAML-only key and not a field.

**`access_level` is `"1"` / `"2"` / `"3"`** — strings, not integers, not
`user`/`manager`/`root`. Default is `"2"` (Manager); `cx.tower.jet.state` defaults to
`"1"`.

**All other selection keys are identical to YAML**: `action: "ssh_command"`,
`on_error_action: "e"`, `variable_type: "o"`, `key_type: "s"`, `ssh_auth_mode: "k"`,
`log_type: "command"`, `head_type: "branch"`. See
`cetmix-tower-yaml/references/selection-values.md`.

**You are not limited to the YAML field list.** That list constrains the importer, not
the ORM. Via API you can set fields YAML cannot carry — `server_ids` on a command,
`ssh_password` on a server, `user_ids`/`manager_ids` access roles, `jet_template_id` on
a `jet_action`, `server_id` on a file. This is a real advantage of path A.

**Do not write computed fields.** `command.variable_ids` and `command.secret_ids` are
computed from `code` and `path`; `plan_line.action` is computed from `command_id`;
`jet_template_dependency.name` is related. Writing them is either ignored or
overwritten.

### Relations

`*_id` takes an integer id (or `False`). `*_ids` takes Odoo command tuples:

| Tuple             | Effect                      |
| ----------------- | --------------------------- |
| `(0, 0, {vals})`  | Create a new related record |
| `(1, id, {vals})` | Update an existing one      |
| `(2, id)`         | Delete it                   |
| `(3, id)`         | Unlink without deleting     |
| `(4, id)`         | Link an existing record     |
| `(5,)`            | Unlink all                  |
| `(6, 0, [ids])`   | Replace the whole set       |

Use `(0, 0, {...})` for children that have no owner-link field in YAML (`plan_line`,
`plan_line_action`, `jet_action`, `variable_option`, `server_log`, `shortcut`,
`scheduled_task`, `scheduled_task_cv`, `jet_template_dependency`, `git_source`,
`git_remote`, `git_project_rel` — the full nest list in
`cetmix-tower/references/hard-rules.md`). Alternatively create them standalone and set
the inverse field (`plan_id`, `jet_template_id`, `server_id`, `template_id`, …), which
YAML cannot do.

**Only the API can remove children.** The importer emits only `(0, 0, …)` and `(4, id)`,
so a YAML re-import adds and updates but never removes — a plan re-imported with two
fewer lines keeps the old lines. `(6, 0, [ids])` and `(2, id)` are the only way to
converge on an exact set. See `references/yaml-vs-api.md`.

### Resolving references

`get_by_reference(reference)` exists on every reference-mixin model. It is
**case-sensitive** and `ormcache`-backed; the mixin clears the registry cache on every
create/write/unlink, so it stays correct within a session.

```python
plan = env["cx.tower.plan"].get_by_reference("deploy_redis")   # record or empty
```

**It is not callable over XML-RPC.** `get_by_reference` is not decorated `@api.model`,
and `call_kw` consumes `args[0]` as ids for any method without an `_api` marker — so
`execute_kw(…, "get_by_reference", ["deploy_redis"])` browses the string as ids and then
calls the method with no `reference` argument. Remotely use
`search([("reference", "=", ref)], limit=1)` (the same domain the mixin itself runs, and
equally case-sensitive). In-process, prefer `get_by_reference`.

### References are auto-generated if omitted

The reference mixin derives `reference` from `name`: stripped, lowercased, spaces → `_`,
everything outside `[a-z0-9_]` removed. On collision it appends `_2`, `_3`, …

`create()` runs `_generate_or_fix_reference(reference or name)` on **every** record, so
the collision suffix applies to a reference you passed yourself just as much as to a
derived one — a second `create` with `reference="deploy_redis"` yields `deploy_redis_2`,
not an error. Passing `reference` explicitly is what makes the record findable later; it
is not by itself protection against duplicates. **Upsert** (below) is.

Child records get `<parent_reference>_<model>_<n>` (e.g. `deploy_redis_plan_line_1`)
when the reference is omitted. That derived form is also what Tower **stores** for
`plan_line`, `plan_line_action` and `variable_value` even when you named them in YAML —
a parent write that includes `reference` regenerates those children. Authored names on
those three models are cosmetic and cannot be used for upsert matching. `jet_action`,
`jet_waypoint_template`, `server_log` and `variable_option` keep the name you wrote.
Details: `cetmix-tower-yaml` → _Nested references_.

## Contexts you must pass

These are the difference between a clean API integration and one that unexpectedly opens
SSH connections.

| Context key                     | Why it matters                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `from_yaml=True`                | **Suppresses file push/pull — only when `cetmix_tower_yaml` is installed.** Creating or writing a `cx.tower.file` with `auto_sync=True` calls `_post_create_write`, which immediately pushes (`source: tower`) or pulls (`source: server`) over SSH. The skip lives in that module's `cx.tower.file._post_create_write` override and is the _only_ place this key is read; without the module the context does nothing and the file still syncs. A `cx.tower.file.template` write that cascades to linked files inherits the same context. The importer always sets it; a plain API create does not. |
| `skip_ssh_settings_check=True`  | Server `create` **raises** when `ssh_auth_mode == "p"` and no `ssh_password` is given, and a constraint requires an IPv4 or IPv6 address, plus `ssh_key_id` when `ssh_auth_mode == "k"`. The importer sets this for servers so incomplete records can be staged.                                                                                                                                                                                                                                                                                                                                     |
| `reference_mixin_override=True` | Skips reference generation/validation entirely. Only for migrations where you control references exactly.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `no_command_log=True`           | `run_command` returns the result dict instead of creating a log record. The _Allow Parallel Run_ check **still runs** (the dict can come back with `ANOTHER_COMMAND_RUNNING`); what is skipped is creating this run's log, so later runs cannot see it as blocking.                                                                                                                                                                                                                                                                                                                                  |

Over `execute_kw`, context goes in the trailing kwargs dict:

```python
models.execute_kw(db, uid, pwd, "cx.tower.file", "create",
                  [{"name": "app.conf", "file_type": "text",
                    "server_dir": "/etc/app", "server_id": server_id}],
                  {"context": {"from_yaml": True}})
```

## Side effects on create, write and unlink

Tower models are not passive. Before writing an integration, know these:

| Operation                                                                                                            | Side effect                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cx.tower.file` create/write with `auto_sync=True`                                                                   | SSH push or pull immediately, unless `from_yaml=True`                                                                                                                                                                                                                                                                                                             |
| `cx.tower.file.template` write of `code`, `file_name`, `file_type`, `server_dir`, `keep_when_deleted` or `auto_sync` | Writes **every** linked `cx.tower.file` (`for file in self.mapped("file_ids"): file.write(...)`). Those with `auto_sync=True` and `source: tower` then push immediately. Count servers first (hard rule 16). `from_yaml=True` on the template write is inherited by the file writes and suppresses the push (`cetmix_tower_yaml` required, same as the file row). |
| `cx.tower.file` unlink with `keep_when_deleted=False`, `source: tower`                                               | **Deletes the file on the host**                                                                                                                                                                                                                                                                                                                                  |
| `cx.tower.server` create                                                                                             | Validates SSH settings; raises without password/IP unless `skip_ssh_settings_check`                                                                                                                                                                                                                                                                               |
| `cx.tower.server` unlink                                                                                             | With a `plan_delete_id` set, **the record is not deleted**: the plan is started and the server is left in `deleting`, or set to `delete_error` if the plan finished non-zero. It is deleted right away only when there is no `plan_delete_id`, the context carries `server_force_delete`, or the server is already being deleted.                                 |
| `cx.tower.jet` unlink                                                                                                | Blocked when `deletable` is `False`                                                                                                                                                                                                                                                                                                                               |
| `cx.tower.jet.state` unlink                                                                                          | Blocked when any `jet_action` references it                                                                                                                                                                                                                                                                                                                       |
| Any reference-mixin create/write/unlink                                                                              | Clears the registry cache — batch your writes                                                                                                                                                                                                                                                                                                                     |

Batch with a list: `create([vals1, vals2, vals3])` is one cache clear, not three. All
these models use `@api.model_create_multi`.

## Required fields

Verified against the models. **Required** means `required=True` on the field, which is
what `create` enforces. A field can be both required and defaulted — the _Has a default_
column lists those, and you may omit them from a `create` call. Everything not listed is
optional.

| Model                              | Required                                                                    | Has a default                                                          |
| ---------------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `cx.tower.command`                 | `name`                                                                      | `action` (`ssh_command`), `access_level` (`"2"`)                       |
| `cx.tower.plan`                    | `name`                                                                      | `on_error_action` (`e`), `access_level`                                |
| `cx.tower.plan.line`               | `command_id`                                                                | `action` (computed from the command)                                   |
| `cx.tower.plan.line.action`        | `condition`, `value_char`                                                   | `action` (`n`)                                                         |
| `cx.tower.variable`                | `name`                                                                      | `variable_type` (`s`)                                                  |
| `cx.tower.variable.option`         | `name`, `value_char`, `variable_id`                                         | —                                                                      |
| `cx.tower.variable.value`          | `variable_id`                                                               | —                                                                      |
| `cx.tower.key`                     | `name`, `key_type`                                                          | —                                                                      |
| `cx.tower.tag` / `cx.tower.os`     | `name`                                                                      | —                                                                      |
| `cx.tower.file.template`           | `name`, `source`, `file_type`                                               | `source` (`tower`), `file_type` (`text`)                               |
| `cx.tower.file`                    | `name`, `file_type`, `server_dir`                                           | `file_type` (`text`), `server_dir` (`""`), `sync_date_next` (now)      |
| `cx.tower.server`                  | `name`, `ssh_username`, `ssh_port`, `ssh_auth_mode`                         | `ssh_port` (`22`), `ssh_auth_mode` (`p`)                               |
| `cx.tower.server.log`              | `name`, `log_type`                                                          | `log_type` (`command`)                                                 |
| `cx.tower.shortcut`                | `name`, `action`                                                            | —                                                                      |
| `cx.tower.scheduled.task`          | `name`, `action`, `next_call`                                               | `interval_type` (`months`)                                             |
| `cx.tower.jet.template`            | `name`                                                                      | —                                                                      |
| `cx.tower.jet.action`              | `name`, `state_transit_id`                                                  | `priority` (10)                                                        |
| `cx.tower.jet.state`               | `name`, `sequence`                                                          | `access_level` (`"1"`)                                                 |
| `cx.tower.jet.template.dependency` | `template_id`, `template_required_id`, `state_required_id`                  | —                                                                      |
| `cx.tower.jet.waypoint.template`   | `name`                                                                      | —                                                                      |
| `cx.tower.jet`                     | `name`, `jet_template_id`, `server_id`                                      | —                                                                      |
| `cx.tower.webhook`                 | `name`, `authenticator_id`, `endpoint`, `method`, `content_type`, `user_id` | `method` (`post`), `content_type` (`json`), `user_id` (`SUPERUSER_ID`) |
| `cx.tower.webhook.authenticator`   | `name`                                                                      | —                                                                      |

`reference` is technically optional everywhere but should always be supplied.

`name` on `cx.tower.jet` comes from `cx.tower.reference.mixin`, where it is
`required=True`. `jet_template.create_jet()` generates one for you when you do not pass
it; a raw `create()` does not, and fails without it. The same mixin is why `name` is
required on `cx.tower.webhook` and `cx.tower.webhook.authenticator`.

`user_id` on `cx.tower.webhook` is the "Run as User" field. It defaults to
`SUPERUSER_ID`, so a webhook created over the API runs as Administrator unless you set
it. There is no `run_as_user_id` field — writing that name does nothing.

`template_id` on `cx.tower.jet.template.dependency` is the owner link. It is filled in
for you when the record is created through `jet_template.template_requires_ids` (nested
YAML or a `(0, 0, {...})` tuple); a standalone `create` must pass it explicitly.
`variable_id` on `cx.tower.variable.option` works the same way — nested under
`variable.option_ids` it is filled in, a standalone `create` must pass it.

`cx.tower.variable.value` carries unique constraints — one value per variable per
`server_id` / `server_template_id` / `jet_id` / `jet_template_id` /
`plan_line_action_id`. Upsert rather than blind-create.

## Access rights

The API user's groups decide what it can create. Full matrix:
`references/access-matrix.md`. The traps:

The groups imply each other — `group_root` → `group_manager` → `group_user` — so a
level's effective rights are the union of its own rules and every lower level's.

- **`cx.tower.os`** — Manager gets read only (inherited from User). Creating an OS needs
  Root.
- **`cx.tower.shortcut`** — Manager is **read-only**. Creating one needs Root.
- **`cx.tower.jet.state`** — Manager read-only. Root only.
- **`cx.tower.webhook`, `cx.tower.webhook.authenticator`, `cx.tower.jet.request`** —
  Root only.
- **`cx.tower.variable`** — Manager can create but **not delete**.
- **`cx.tower.command.log`, `cx.tower.plan.log`, `cx.tower.webhook.log`** — read-only
  for every group. Never write them.
- Driving the YAML import wizard needs **`cetmix_tower_yaml.group_import`**, which is
  separate from the Tower access groups.

Record rules apply on top of the model ACL — a Manager also has to be in the record's
`user_ids`/`manager_ids`, or be its creator, for many models. For an integration user,
Root is usually the pragmatic choice; say so explicitly rather than letting the user
discover it through permission errors.

## Idempotent upsert

The pattern to use everywhere, because API sequences are not atomic and get retried:

```python
def upsert(env, model, reference, vals, ctx=None):
    """Create or update a Tower record by reference. Returns the record."""
    Model = env[model].with_context(**(ctx or {}))
    record = Model.get_by_reference(reference)
    if record:
        record.write(vals)
        return record
    return Model.create(dict(vals, reference=reference))
```

Do **not** rely on `create` failing on the reference unique constraint — the mixin
appends `_2` instead of raising, so you get a duplicate rather than an error.

This snippet is in-process. Over XML-RPC the lookup step becomes a `search` — see
_Resolving references_: `get_by_reference` cannot be called through `execute_kw`.

```python
ids = models.execute_kw(db, uid, pwd, model, "search",
                        [[["reference", "=", reference]]], {"limit": 1})
if ids:
    models.execute_kw(db, uid, pwd, model, "write", [ids, vals])
else:
    models.execute_kw(db, uid, pwd, model, "create", [dict(vals, reference=reference)])
```

## Hybrid: import YAML over the API

Two entry points. Prefer the first — it validates.

**Validated (mirrors the UI):**

```python
upload = env["cx.tower.yaml.import.wiz.upload"].create({
    "yaml_file": base64.b64encode(yaml_text.encode()),
    "file_name": "snippet.yaml",
})
action = upload.action_import_yaml()          # validates version + model names
wiz = env["cx.tower.yaml.import.wiz"].browse(action["res_id"])
wiz.write({"if_record_exists": "update"})     # skip | update | create
wiz.action_import_yaml()
```

**Direct (skips validation):**

```python
wiz = env["cx.tower.yaml.import.wiz"].create({
    "yaml_code": yaml_text,
    "if_record_exists": "update",
})
wiz.action_import_yaml()
```

The direct form **does not validate model names** — the upload wizard normally does
that, and the import wizard's code says as much. An invalid `cetmix_tower_model` will
fail with a raw error instead of _"'x' is not a valid model"_. Use the validated form
unless you have already validated the YAML yourself.

Both need `cetmix_tower_yaml.group_import`. Both run inside a savepoint, so a failure
rolls the whole file back. `if_record_exists: "update"` is what makes repeated imports
idempotent.

## Operations, not just entities

Creating records is half the job. The current model methods — **not** the deprecated
`cetmix.tower` helpers, see `cetmix-tower-command-python`:

| Goal                              | Call                                                                                                                                                                                  |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Run a command on a server         | `server.run_command(command, path=None, sudo=None, jet_template=None, jet=None, **kwargs)`                                                                                            |
| Run a flight plan                 | `server.run_flight_plan(plan, jet_template=None, jet=None, **kwargs)` → plan log                                                                                                      |
| Override variables for one run    | pass `variable_values={"odoo_version": "18.0"}` in `kwargs` — SSH/Python/conditions only; not `file_using_template` (hard rule 17)                                                    |
| Get the result instead of a log   | context `no_command_log=True` on `run_command`                                                                                                                                        |
| Create a server from a template   | `env["cx.tower.server.template"].create_server_from_template(template_reference, server_name, ipv4=…, ssh_password=…, configuration_variables={…}, pick_all_template_variables=True)` |
| Install a jet template on servers | `jet_template.install_on_servers(servers)`                                                                                                                                            |
| Create a Jet from a template      | `jet_template.create_jet(server, name=None, state=None, variable_values={…})` → jet or `False`                                                                                        |
| Trigger a jet action              | `jet_action.trigger(jet)`                                                                                                                                                             |
| Drive a Jet to a state            | `jet.bring_to_state(state_reference)` — string (`"running"`), not a record. Prefer over `_bring_to_state`. Returns `None`. Recovery after a failed Prepare: `cetmix-tower-jets`.      |
| Read/set a variable value         | `server.get_variable_value(ref)` / `server.set_variable_value(ref, value)` / `jet.set_variable_value(ref, value)` — mixin; `set_*` returns `None`                                     |
| Merge metadata                    | `server.update_metadata({...})`, `jet.update_metadata({...})`                                                                                                                         |
| Read logs                         | search `cx.tower.command.log` / `cx.tower.plan.log` (read-only for every group)                                                                                                       |

`create_server_from_template` and `install_on_servers` are current. Only the
`cetmix.tower` wrappers (`tower.server_run_command`, `tower.server_set_variable_value`,
`tower.server_create_from_template`, …) are deprecated.

Command and plan logs are **read-only for all groups** — never try to write them.

`install_on_servers`, `create_jet`, `jet_action.trigger` and `server.run_flight_plan`
take recordsets. Over XML-RPC use the wizards in _XML-RPC gotchas_ below.
`bring_to_state` takes a string and is RPC-callable; it still returns `None` (see
that section).

## XML-RPC gotchas

These are specific to driving Tower from outside Odoo. In-process Python (a Tower Python
command, `odoo shell`) is unaffected.

**Recordset-argument methods are not RPC-callable.**
`cx.tower.jet.template.install.install(server, template)` and
`jet_template.create_jet(server, …)` take recordsets; over XML-RPC the arguments arrive
as ints and `ensure_one()` fails. `jet_action.trigger(jet)` is the same. Drive the
wizards instead — create them with integer ids, then call the action method on the
wizard id:

| Want                          | Model                               | Method                    |
| ----------------------------- | ----------------------------------- | ------------------------- |
| Install a template on servers | `cx.tower.jet.template.install.wiz` | `action_install_template` |
| Create a Jet                  | `cx.tower.jet.create.wizard`        | `action_confirm`          |
| Trigger a jet action          | `cx.tower.jet.action.wizard`        | `action_confirm`          |
| Import YAML                   | `cx.tower.yaml.import.wiz`          | `action_import_yaml`      |
| Run one SSH or Python command | `cx.tower.command.run.wizard`       | `run_command_in_wizard`   |
| Run a flight plan             | `cx.tower.plan.run.wizard`          | `run_flight_plan`         |

`install_on_servers` is in-process only for the same reason.

The command-run wizard is the ad-hoc path that still satisfies hard rule 1 (no manual
SSH). Create it with integer `server_ids` / `jet_ids` / `command_id`, write `code` to
override the stored command for that run only (do not edit a shared command), then
call `run_command_in_wizard`. `action` is only `ssh_command` or `python_code`. The
`code` override still goes through Tower's Jinja renderer, so Go-template `{{` and
variable substitution apply. See `cetmix-tower-command-ssh`.

The plan-run wizard is the RPC path for `server.run_flight_plan(plan, …)`, which takes
a recordset. Create it with integer `plan_id`, `server_ids`, and optional `jet_ids`.
When `jet_ids` is set it runs per-jet (`jet.run_flight_plan`); otherwise per-server.

**Methods that return `None` raise after succeeding.** XML-RPC cannot marshal `None`.
Treat any Tower action method as possibly returning `None` — not a fixed list.
`set_variable_value`, `cx.tower.server.log.action_update_log()`, `jet.bring_to_state`
and `file.action_push_to_server` have all done this: the work completed, then the
client saw `"cannot marshal None"`. `action_push_to_server` is not even stable across
modules — `cetmix_tower_server` returns a notification dict, `cetmix_tower_server_queue`
overrides it, enqueues the upload (`with_delay`), and returns `None`. Check the record;
do **not** retry. Use JSON-RPC, set
`allow_none=True` on the proxy, or tolerate the fault.

**Empty domain.** In-process, `search_read([])` means "no filter". `search_read([[]])`
raises an opaque `IndexError` inside `expression.is_false` (`token[1]` on an empty
tuple). Over `execute_kw` the args list adds a wrap: pass `[[]]` (domain `[]`), never
`[[[]]]`.

**A command that has ever run cannot be unlinked.** `cx.tower.command.log.command_id` is
`ondelete="restrict"` (`cx_tower_command_log_command_id_fkey`). Archive it
(`active=False`) instead. `active` is not a YAML field on `command`; write it over the
API.

## Everything else still applies

The API bypasses YAML, not Tower's semantics. All the design rules hold unchanged: one
statement per SSH command, `path` instead of `cd`, `use_sudo` on the plan line, secrets
as `key` records referenced inline, a `variable_value` per scope, `state_transit_id` on
every jet action, Build and Start on separate plans. Read the element skills for the
entity you are creating — this skill only covers _how to get it into the database_.

## Secret values: the API can set them, YAML cannot

This is one of the clearest capability differences, and the opposite of what the YAML
workflow implies.

`cx.tower.key.secret_value`, `cx.tower.key.value.secret_value`,
`cx.tower.server.ssh_password` and `cx.tower.server.host_key` are declared as
`SECRET_FIELDS` on the vault mixin. `create` and `write` intercept them, store the value
in `cx.tower.vault` outside the main table, and NULL the column. So:

```python
env["cx.tower.key"].create({
    "name": "Redis Password", "reference": "redis_password",
    "key_type": "s", "secret_value": "…",           # works
})

# Scoped value (per server / per partner)
env["cx.tower.key.value"].create({
    "key_id": key.id, "server_id": server.id, "secret_value": "…",
})
```

- **Reads always return `\*\*\***`.\*\* The mixin substitutes a placeholder on fetch.
  You can set a secret and never read it back — by design.
- Needs write access to the model (Manager or Root); there is no extra field-level
  group.
- Inside Tower **Python commands** the helpers `_get_secret_value(`,
  `_get_secret_values(` and `_set_secret_values(` are rejected at save time. That ban is
  textual and applies to command code, not to an external API caller using
  `create`/`write`.
- YAML carries only `name`, `key_type`, `note`, `reference` — never a value.

So an API-driven provisioning flow _can_ be fully unattended, including secrets. Say so
rather than telling the user to type them in, and make sure the value reaches the call
from a real secret store, never from a literal in the script or from your own context.

## Review checklist

- [ ] Real Odoo model names, no YAML aliases, no `cetmix_tower_model` key
- [ ] `access_level` as `"1"` / `"2"` / `"3"`
- [ ] Relations as ids and command tuples, not reference strings
- [ ] `reference` passed explicitly on every record
- [ ] Creates ordered so dependencies exist first — there is no deferred pass
- [ ] Upsert by reference; no reliance on unique-constraint failure
- [ ] `from_yaml=True` when touching `cx.tower.file` or `cx.tower.file.template`,
      unless a transfer is intended
- [ ] `skip_ssh_settings_check=True` when staging incomplete servers
- [ ] Computed fields (`variable_ids`, `secret_ids`, `plan_line.action`) not written
- [ ] API user's groups cover every model — Root for `os`, `shortcut`, `jet_state`,
      `webhook*`; `cetmix_tower_yaml.group_import` for the import wizard
- [ ] Non-atomic multi-call sequences either avoided (path B) or made idempotent
- [ ] Deletion side effects understood (files on host, server delete plans)
- [ ] Writes batched into single `create([...])` calls where possible
- [ ] No endpoints from the unimplemented `cetmix_tower_api` spec referenced
- [ ] Recordset-argument methods (`install`, `create_jet`, `trigger`,
      `run_flight_plan`) not called over XML-RPC — wizards instead
- [ ] Ad-hoc SSH/Python via `cx.tower.command.run.wizard` (`code` override); flight
      plans via `cx.tower.plan.run.wizard`
- [ ] Action methods that return `None` not retried on marshal faults — check the
      record instead
