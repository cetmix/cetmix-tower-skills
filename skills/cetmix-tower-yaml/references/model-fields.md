# Allowed YAML fields per model

**This is the authoritative list.** Any key not listed for a model is silently dropped
during import. It is generated from `_get_fields_for_yaml()` in the YAML modules:

- `cetmix_tower_yaml/models/*.py` — core models
- `cetmix_tower_webhook/models/*.py` — `webhook`, `webhook_authenticator`
- `cetmix_tower_git/models/*.py` — `git_*` models, plus extra fields on `plan_line`

`reference` is available on every model and is required on top-level records.

To regenerate after a Tower upgrade, grep the `_get_fields_for_yaml` methods across
**all** modules — the optional ones add fields to core models too (`cetmix_tower_git`
adds `git_project_rel_ids` to `server` and two fields to `plan_line`):

```bash
find <addons>/cetmix_tower_yaml/models <addons>/cetmix_tower_git/models <addons>/cetmix_tower_webhook/models -name '*.py' -exec awk '/def _get_fields_for_yaml/,/return/ {print FILENAME": "$0}' {} +
```

The `awk` range ends at the method's `return`, so it prints each list in full. Do not
use `grep -A <n>`: the longest method is already 28 lines and a fixed window truncates
silently as soon as a model gains fields.

Do the same for `_get_force_x2m_resolve_models` — `cetmix_tower_git` extends that on
`server` as well.

---

## Execution

### `command` — `cx.tower.command`

`reference`, `access_level`, `name`, `action`, `allow_parallel_run`, `note`, `os_ids`,
`tag_ids`, `path`, `file_template_id`, `if_file_exists`, `disconnect_file`,
`flight_plan_id`, `jet_template_id`, `jet_action_id`, `waypoint_template_id`,
`fly_here`, `code`, `no_split_for_sudo`, `server_status`, `variable_ids`, `secret_ids`

- `name` and `action` are required.
- `variable_ids` is **computed from `code` and `path`**, `secret_ids` from `code` only —
  Tower fills both. Declare the `variable` and `key` records themselves instead.
- `server_ids` is **not** importable: imported commands are available to all servers.

### `plan` — `cx.tower.plan`

`reference`, `name`, `access_level`, `allow_parallel_run`, `color`, `tag_ids`, `note`,
`on_error_action`, `custom_exit_code`, `line_ids`

- `server_ids` is **not** importable.

### `plan_line` — `cx.tower.plan.line` _(nest under `plan.line_ids`)_

`reference`, `sequence`, `condition`, `use_sudo`, `path`, `command_id`, `action_ids`,
`variable_ids` With `cetmix_tower_git` also: `git_project_id`, `is_make_copy`

### `plan_line_action` — `cx.tower.plan.line.action` _(nest under `plan_line.action_ids`)_

`reference`, `sequence`, `condition`, `value_char`, `action`, `custom_exit_code`,
`variable_value_ids`

### `shortcut` — `cx.tower.shortcut` _(nest under `server`/`server_template`.`shortcut_ids`)_

`reference`, `name`, `sequence`, `access_level`, `action`, `command_id`, `use_sudo`,
`plan_id`, `note`

---

## Configuration

### `variable` — `cx.tower.variable`

`reference`, `name`, `access_level`, `variable_type`, `option_ids`,
`applied_expression`, `validation_pattern`, `validation_message`, `note`, `tag_ids`

**No value field.** `default_value_char` does not exist.

### `variable_option` — `cx.tower.variable.option` _(nest under `variable.option_ids`)_

`reference`, `sequence`, `access_level`, `name`, `value_char`

### `variable_value` — `cx.tower.variable.value`

`reference`, `sequence`, `access_level`, `variable_id`, `value_char`, `variable_ids`,
`required`

- Top-level ⇒ **global** value. Nest under `variable_value_ids` of `server`,
  `server_template`, `jet_template` or `plan_line_action` to scope it.
- For an Options-type variable set `value_char` to the option's `value_char`; Tower
  resolves `option_id` automatically.
- `required` is only honoured on server templates.
- Access level must be **equal to or higher** than the variable's.

### `key` — `cx.tower.key`

`reference`, `name`, `key_type`, `note`

**Values are never importable or exportable via YAML.** Set them in the UI, or over the
API — `secret_value` is a vault-backed field that `create`/`write` accept (reads return
`*****`).

### `key_value` — `cx.tower.key.value`

`reference`, `key_id` — carries no value, so not useful in authored YAML. Over the API
the same model takes `secret_value` plus `server_id` / `partner_id` for scoped secrets.

### `os` — `cx.tower.os`

`reference`, `name`, `color`, `parent_id`

### `tag` — `cx.tower.tag`

`reference`, `name`, `color` (`color`: 0–10)

---

## Files

### `file_template` — `cx.tower.file.template`

`reference`, `name`, `source`, `file_type`, `server_dir`, `file_name`,
`keep_when_deleted`, `tag_ids`, `note`, `code`, `variable_ids`, `secret_ids`

### `file` — `cx.tower.file`

`reference`, `name`, `source`, `file_type`, `server_dir`, `code`, `file`,
`variable_ids`, `secret_ids`, `template_id`, `keep_when_deleted`, `auto_sync`,
`auto_sync_interval`, `sync_date_next`, `sync_date_last`, `server_response`

- `server_id` is **not** importable — an imported `file` is not attached to a server.
  Author `file_template` records instead and let Tower create files.
- On export, `code` is dropped when `source: server`.

---

## Servers

### `server` — `cx.tower.server`

`reference`, `name`, `ip_v4_address`, `ip_v6_address`, `skip_host_key`, `color`,
`os_id`, `tag_ids`, `url`, `note`, `ssh_port`, `ssh_username`, `ssh_key_id`,
`ssh_auth_mode`, `use_sudo`, `variable_value_ids`, `secret_ids`, `server_log_ids`,
`shortcut_ids`, `scheduled_task_ids`, `plan_delete_id`, `file_ids`, `command_ids`,
`plan_ids` With `cetmix_tower_git` also: `git_project_rel_ids`

- `ssh_password` is **not** importable.
- `command_ids` / `plan_ids` / `shortcut_ids` / `scheduled_task_ids` always resolve to
  existing records where possible rather than duplicating.

### `server_template` — `cx.tower.server.template`

`reference`, `name`, `color`, `os_id`, `tag_ids`, `note`, `ssh_port`, `ssh_username`,
`ssh_key_id`, `ssh_auth_mode`, `use_sudo`, `variable_value_ids`, `server_log_ids`,
`shortcut_ids`, `scheduled_task_ids`, `flight_plan_id`, `plan_delete_id`

- `flight_plan_id` runs **after** a server is created; `plan_delete_id` **before**
  deletion.

### `server_log` — `cx.tower.server.log` _(nest under a `_\_log_ids` field)\*

`reference`, `name`, `log_type`, `command_id`, `use_sudo`, `file_template_id`, `file_id`

- `command_id` + `use_sudo` for `log_type: command`; `file_id` (servers) or
  `file_template_id` (templates) for `log_type: file`.
- `access_level` **exists on the model** (from `access.mixin`) but is **not** in this
  list, so a value set here is validated and then silently dropped. Do not set it.

---

## Jets

### `jet_template` — `cx.tower.jet.template`

`reference`, `name`, `note`, `tag_ids`, `limit_per_server`, `show_in_create_wizard`,
`plan_install_id`, `plan_uninstall_id`, `plan_clone_same_server_id`,
`plan_clone_different_server_id`, `variable_value_ids`, `action_ids`,
`template_requires_ids`, `waypoint_template_ids`, `server_log_ids`, `scheduled_task_ids`

- `access_level` is **not** in this list — do not set it here.
- `plan_prepare_id`, `plan_build_id`, `plan_start_id`, `plan_stop_id`, `plan_remove_id`
  **do not exist**. The lifecycle lives in `action_ids`.
- `icon` is not importable.

### `jet_state` — `cx.tower.jet.state`

`reference`, `name`, `sequence`, `access_level`, `color`, `note`

Eleven states ship with Tower — reference them, do not redefine them. See
`cetmix-tower-jets/references/lifecycle-patterns.md`.

### `jet_action` — `cx.tower.jet.action` _(nest under `jet_template.action_ids`)_

`reference`, `name`, `note`, `priority`, `access_level`, `state_from_id`,
`state_transit_id`, `state_to_id`, `state_error_id`, `plan_id`

- `state_transit_id` is **required** at the model level (`required=True`).
- `jet_template_id` is not importable, which is why actions must be nested.

### `jet_template_dependency` — `cx.tower.jet.template.dependency` _(nest under `template_requires_ids`)_

`reference`, `template_required_id`, `state_required_id`

### `jet_waypoint_template` — `cx.tower.jet.waypoint.template`

`reference`, `name`, `sequence`, `access_level`, `jet_template_id`, `plan_create_id`,
`plan_arrive_id`, `plan_leave_id`, `plan_delete_id`, `note`

Has `jet_template_id`, so it may be top-level or nested under `waypoint_template_ids`.

---

## Automation

### `scheduled_task` — `cx.tower.scheduled.task` _(nest under a `scheduled_task_ids` field)_

`reference`, `name`, `sequence`, `action`, `command_id`, `plan_id`, `interval_number`,
`interval_type`, `next_call`, `last_call`, `monday`, `tuesday`, `wednesday`, `thursday`,
`friday`, `saturday`, `sunday`, `custom_variable_value_ids`

### `scheduled_task_cv` — `cx.tower.scheduled.task.cv` _(nest under `custom_variable_value_ids`)_

`reference`, `variable_value_id` — the rest (`name`, `variable_id`, `option_id`,
`value_char`) is copied from the linked variable value on import.

### `webhook` — `cx.tower.webhook`

`reference`, `name`, `active`, `authenticator_id`, `endpoint`, `method`, `code`,
`content_type`, `variable_ids`, `secret_ids`

The "Run as User" field is `user_id` (**not** `run_as_user_id`, which does not exist).
It is `required=True` with `default=SUPERUSER_ID` and is not importable — set it in the
UI.

### `webhook_authenticator` — `cx.tower.webhook.authenticator`

`reference`, `name`, `code`, `allowed_ip_addresses`, `trusted_proxy_ips`,
`variable_ids`, `secret_ids`

---

## Git

The Git module's models have changed since the docs page was written. Verify against
`cetmix_tower_git/models/*.py` before authoring.

| Model                                                         | Fields                                                                     |
| ------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `git_project`                                                 | `reference`, `name`, `note`, `source_ids`, `git_aggregator_root_dir`       |
| `git_source` _(nest)_                                         | `reference`, `name`, `enabled`, `sequence`, `remote_ids`                   |
| `git_remote` _(nest)_                                         | `reference`, `name`, `enabled`, `sequence`, `repo_id`, `head`, `head_type` |
| `git_repo`                                                    | `reference`, `url`, `is_private`, `secret_id`                              |
| `git_repo_owner`                                              | `reference`, `display_name`, `name`, `secret_id`                           |
| `git_project_rel` _(nest under `server.git_project_rel_ids`)_ | `reference`, `file_id`, `git_project_id`, `project_format`, `auto_sync`    |

Note the URL and privacy flag live on `git_repo`, not on `git_remote` — the
documentation page still shows the old shape.

`git_repo_owner.reference` and `git_repo.reference` are **not** author-controlled.
Unlike every other model, both are stored computes with no "keep the existing reference"
guard, so an authored `reference:` is overwritten on create and on write:

- `git_repo_owner.reference` — computed from `name` (`_compute_display_name`); renaming
  the owner changes it.
- `git_repo.reference` — computed from `name` (`_compute_name`), itself
  `host/owner/repo`, all three of which are `readonly` fields derived from the `url` you
  author (`_inverse_url` → `_parse_url`). So the repo reference follows the URL: change
  the URL and the reference changes with it.

A file that relies on a stable owner or repo reference will not round-trip.
`git_repo.name` is not in the YAML field list at all, so authoring it does nothing.

`git_remote.name` is likewise a stored compute — remotes are named `remote_<n>` from
their position in `source_id.remote_ids`. Authoring `name` on a `git_remote` does
nothing.

`git_project_rel.server_id` is `required=True` on the model and **not** in its YAML
field list, so the record can only be created nested under `server.git_project_rel_ids`.
Its `file_id` must point at a file on that same server (`_check_server_file_relation`).
