# Selection field values

YAML carries the selection **key**, never the human label. Verified against
`cetmix_tower_server/models/*.py`, `cetmix_tower_webhook/models/*.py` and
`cetmix_tower_git/models/*.py`.

## `access_level` — the one exception

Every model that has it accepts the friendly word, not the stored key:

| YAML      | Stored | Meaning               |
| --------- | ------ | --------------------- |
| `user`    | `"1"`  | User                  |
| `manager` | `"2"`  | Manager (**default**) |
| `root`    | `"3"`  | Root                  |

Any other value raises _"Wrong value for 'access_level' key"_.

Applies to: `command`, `plan`, `variable`, `variable_option`, `variable_value`,
`jet_state`, `jet_action`, `jet_waypoint_template`, `shortcut`.

Not importable on `jet_template` or `server_log`: both have the field on the model, but
neither lists it in `_get_fields_for_yaml`, so a value is validated and then silently
dropped.

---

## `command.action` — required, default `ssh_command`

| Key                   | Meaning                                    | Notes                                                                   |
| --------------------- | ------------------------------------------ | ----------------------------------------------------------------------- |
| `ssh_command`         | Run a shell statement on the host over SSH |                                                                         |
| `python_code`         | Run Python inside Tower                    |                                                                         |
| `file_using_template` | Render a file template and push/pull it    | **Flight-plan only**                                                    |
| `plan`                | Run another Flight Plan                    | **Flight-plan only**; set `flight_plan_id`                              |
| `jet_action`          | Trigger a Jet lifecycle action             | **Flight-plan only**; set `jet_template_id` + `jet_action_id`           |
| `create_waypoint`     | Create a Waypoint for the current Jet      | **Flight-plan only**; set `waypoint_template_id`, optionally `fly_here` |

All four **Flight-plan only** actions have no ad-hoc run path: the Run Command wizard's
own `action` field offers `ssh_command` and `python_code` only, and it filters the
selectable commands by it. `jet_action` and `create_waypoint` additionally need a Jet
context — the plan must be running on a Jet. See `cetmix-tower-command-actions`.

## `command.if_file_exists` — default `skip`

`skip` · `overwrite` · `raise` (only for `action: file_using_template`)

## `command.server_status`

Status to set on the server after a successful run. Leave empty to keep it unchanged.

`stopped` · `starting` · `running` · `stopping` · `restarting` · `deleting` ·
`delete_error`

Same list as `server.status`.

---

## `plan.on_error_action` — required, default `e`

| Key  | Meaning                                  |
| ---- | ---------------------------------------- |
| `e`  | Exit with the failed command's exit code |
| `ec` | Exit with `custom_exit_code`             |
| `n`  | Run the next command                     |

## `plan_line_action.condition` — required

`==` · `!=` · `>` · `>=` · `<` · `<=`

Compared against `value_char` (a **string**: `'0'`, `'1'`, `'255'`).

## `plan_line_action.action` — required, default `n`

Same three keys as `plan.on_error_action`: `e` · `ec` · `n`

---

## `variable.variable_type` — required, default `s`

`s` = String · `o` = Options (requires `option_ids`)

---

## `key.key_type` — required

`k` = SSH Key · `s` = Secret

---

## `file` / `file_template`

| Field                | Values                                                                                                     | Default |
| -------------------- | ---------------------------------------------------------------------------------------------------------- | ------- |
| `source`             | `tower` (authored here, pushed to host) · `server` (fetched from host)                                     | `tower` |
| `file_type`          | `text` · `binary`                                                                                          | `text`  |
| `auto_sync_interval` | `10-minutes` `30-minutes` `1-hours` `2-hours` `6-hours` `12-hours` `1-days` `1-weeks` `1-months` `1-years` | —       |

---

## `server` / `server_template`

| Field                                    | Values                                                                           | Default |
| ---------------------------------------- | -------------------------------------------------------------------------------- | ------- |
| `ssh_auth_mode`                          | `p` = Password · `k` = Key                                                       | `p`     |
| `use_sudo`                               | `n` = without password · `p` = with password · empty = no sudo                   | empty   |
| `status` (`server` only, not importable) | `stopped` `starting` `running` `stopping` `restarting` `deleting` `delete_error` | unset   |

**`use_sudo` is a Selection only here.** On `plan_line`, `shortcut` and `server_log` it
is a **Boolean** (`true` / `false`) meaning "apply the server's sudo setting". Never
write `n`/`p` on those, and never write `true`/`false` on a server or server template.

---

## `server_log.log_type` — required, default `command`

`command` (output of `command_id`) · `file` (content of `file_id` / `file_template_id`)

---

## `shortcut.action` — required

`command` (set `command_id`, optionally `use_sudo`) · `plan` (set `plan_id`)

---

## `scheduled_task`

| Field           | Values                                          | Default  |
| --------------- | ----------------------------------------------- | -------- |
| `action`        | `command` · `plan`                              | —        |
| `interval_type` | `minutes` `hours` `days` `dow` `weeks` `months` | `months` |

With `interval_type: dow`, at least one of `monday`…`sunday` must be `true`.

---

## `webhook`

| Field          | Values          | Default |
| -------------- | --------------- | ------- |
| `method`       | `post` · `get`  | `post`  |
| `content_type` | `json` · `form` | `json`  |

---

## Git

| Field                            | Values                     |
| -------------------------------- | -------------------------- |
| `git_remote.head_type`           | `branch` · `pr` · `commit` |
| `git_project_rel.project_format` | `git_aggregator`           |

---

## Colour fields

`tag.color`, `plan.color`, `os.color`, `server.color`, `server_template.color`,
`jet_state.color`: integer **0–10** (Odoo kanban palette).

## Jet state references

Not a selection, but effectively fixed. The eleven states shipped in
`cetmix_tower_server/data/cx_tower_jet_state.xml` have auto-generated references equal
to their lowercased names:

`preparing` · `draft` · `building` · `starting` · `running` · `stopping` · `stopped` ·
`restarting` · `removing` · `removed` · `destroying`
