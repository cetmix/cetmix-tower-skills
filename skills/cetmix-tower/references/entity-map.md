# Entity map

Every Cetmix Tower entity, what it is for, and how it must appear in YAML.

`YAML model` is the value of `cetmix_tower_model`. The mapping rule is
`cx.tower.model.name` → `model_name` (drop the `cx.tower.` prefix, dots → underscores).

## Execution

| YAML model         | Odoo model                  | What it is                                                                                                                                         |
| ------------------ | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `command`          | `cx.tower.command`          | One unit of work. Its `action` decides what it does: `ssh_command`, `python_code`, `file_using_template`, `plan`, `jet_action`, `create_waypoint`. |
| `plan`             | `cx.tower.plan`             | Flight Plan — an ordered list of lines, each running one command, with conditions and per-line error handling.                                     |
| `plan_line`        | `cx.tower.plan.line`        | One step of a plan: `command_id` + `sequence` + `condition` + `use_sudo` + `path`.                                                                 |
| `plan_line_action` | `cx.tower.plan.line.action` | Post-run action: inspect the line's exit code, decide whether to continue, and optionally set variable values.                                     |
| `shortcut`         | `cx.tower.shortcut`         | One-click button on a server form that runs a command or plan. Can elevate access level.                                                           |

## Configuration

| YAML model        | Odoo model                 | What it is                                                                                                                                                                                      |
| ----------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `variable`        | `cx.tower.variable`        | Configuration parameter _definition_ only — name, reference, type, validation, value modifier. **Has no value field.**                                                                          |
| `variable_option` | `cx.tower.variable.option` | One choice of an Options-type variable (`name` shown, `value_char` used).                                                                                                                       |
| `variable_value`  | `cx.tower.variable.value`  | An actual value. Scoped by which parent it is nested under; top-level = **global**.                                                                                                             |
| `key`             | `cx.tower.key`             | Secret (`key_type: s`) or SSH private key (`key_type: k`). Values are never exportable.                                                                                                         |
| `key_value`       | `cx.tower.key.value`       | A scoped value of a key. Carries only `reference` and `key_id` in YAML — no value — so it is not useful in authored YAML; over the API it takes `secret_value` plus `server_id` / `partner_id`. |
| `os`              | `cx.tower.os`              | Operating system, used to flag command/OS incompatibility (warning only).                                                                                                                       |
| `tag`             | `cx.tower.tag`             | Shared tag used across all entities for search and filtering.                                                                                                                                   |

## Files

| YAML model      | Odoo model               | What it is                                                                                                                       |
| --------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `file_template` | `cx.tower.file.template` | Blueprint for a file: name, target directory, content with variables and secrets. Editing it updates every file created from it. |
| `file`          | `cx.tower.file`          | A concrete file on a server. `source: tower` = authored here and pushed; `source: server` = fetched from the host (logs).        |

## Servers

| YAML model        | Odoo model                 | What it is                                                                                            |
| ----------------- | -------------------------- | ----------------------------------------------------------------------------------------------------- |
| `server`          | `cx.tower.server`          | A managed host: SSH connection details, variables, secrets, logs, shortcuts, status.                  |
| `server_template` | `cx.tower.server.template` | Blueprint for creating servers, with a plan that runs after creation and one before deletion.         |
| `server_log`      | `cx.tower.server.log`      | A log view fetched either from a command's output (`log_type: command`) or a file (`log_type: file`). |

## Jets

| YAML model                | Odoo model                         | What it is                                                                                                                       |
| ------------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `jet_template`            | `cx.tower.jet.template`            | Blueprint for a managed application: lifecycle actions, config, dependencies, waypoint templates, install/uninstall/clone plans. |
| `jet_state`               | `cx.tower.jet.state`               | A lifecycle stage. Eleven states ship with Tower — reuse those names, do not redefine them. The instance may have extra transits; list `cx.tower.jet.state` before writing conditions. |
| `jet_action`              | `cx.tower.jet.action`              | A transition: `state_from_id` → `state_transit_id` → `state_to_id` (+ `state_error_id`), running `plan_id`.                      |
| `jet_waypoint_template`   | `cx.tower.jet.waypoint.template`   | Snapshot/backup definition with up to four plans: create, arrive, leave, delete.                                                 |
| `jet_template_dependency` | `cx.tower.jet.template.dependency` | "This template requires template X to be in state Y".                                                                            |

There is no `jet` YAML model — Jets are created from templates through the wizard or the
API, not imported.

## Automation

| YAML model              | Odoo model                       | What it is                                                      |
| ----------------------- | -------------------------------- | --------------------------------------------------------------- |
| `scheduled_task`        | `cx.tower.scheduled.task`        | Runs a command or plan on selected servers/jets on an interval. |
| `scheduled_task_cv`     | `cx.tower.scheduled.task.cv`     | Per-task variable override.                                     |
| `webhook`               | `cx.tower.webhook`               | HTTP endpoint that runs Python code when called. Root-only.     |
| `webhook_authenticator` | `cx.tower.webhook.authenticator` | IP allowlist + custom auth code for webhooks.                   |

## Git

| YAML model        | Odoo model                 | What it is                                                                          |
| ----------------- | -------------------------- | ----------------------------------------------------------------------------------- |
| `git_project`     | `cx.tower.git.project`     | Set of git sources, renderable into files (e.g. git-aggregator format).             |
| `git_source`      | `cx.tower.git.source`      | One source inside a project.                                                        |
| `git_remote`      | `cx.tower.git.remote`      | One remote of a source, with head and head type.                                    |
| `git_repo`        | `cx.tower.git.repo`        | A repository: URL, private flag, access secret. Referenced by `git_remote.repo_id`. |
| `git_repo_owner`  | `cx.tower.git.repo.owner`  | Account or organisation owning repositories, with its own secret.                   |
| `git_project_rel` | `cx.tower.git.project.rel` | Ties a project to a file on a server, in a given format.                            |

The Git module has evolved past its documentation page (repository URL and provider now
live on `cx.tower.git.repo`). Read `cetmix_tower_git/models/*.py` before writing Git
YAML. Field lists: `cetmix-tower-yaml/references/model-fields.md`.

---

## Nesting rules (derived from `_get_fields_for_yaml`)

A child record can only be a **top-level** item in `records` if its own YAML field list
contains the field that links it to its owner. Otherwise it _must_ be nested inside the
parent's x2m field, or it will be created orphaned.

| Model                     | Placement           | Owner field                                                                                                                                            |
| ------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `plan_line`               | **Must nest**       | `plan.line_ids`                                                                                                                                        |
| `plan_line_action`        | **Must nest**       | `plan_line.action_ids`                                                                                                                                 |
| `variable_option`         | **Must nest**       | `variable.option_ids`                                                                                                                                  |
| `jet_action`              | **Must nest**       | `jet_template.action_ids`                                                                                                                              |
| `jet_template_dependency` | **Must nest**       | `jet_template.template_requires_ids`                                                                                                                   |
| `server_log`              | **Must nest**       | `server.server_log_ids` / `server_template.server_log_ids` / `jet_template.server_log_ids`                                                             |
| `shortcut`                | **Must nest**       | `server.shortcut_ids` / `server_template.shortcut_ids`                                                                                                 |
| `scheduled_task`          | **Must nest**       | `server.scheduled_task_ids` / `server_template.…` / `jet_template.…`                                                                                   |
| `scheduled_task_cv`       | **Must nest**       | `scheduled_task.custom_variable_value_ids`                                                                                                             |
| `git_source`              | **Must nest**       | `git_project.source_ids`                                                                                                                               |
| `git_remote`              | **Must nest**       | `git_source.remote_ids`                                                                                                                                |
| `git_project_rel`         | **Must nest**       | `server.git_project_rel_ids` — `server_id` is required on the model but absent from its YAML field list, so a top-level record cannot import           |
| `variable_value`          | Either              | Top-level ⇒ **global value**. Nest under `variable_value_ids` of `server`, `server_template`, `jet_template` or `plan_line_action` for a scoped value. |
| `jet_waypoint_template`   | Either              | Has `jet_template_id` (resolved after the main import pass), so top-level works.                                                                       |
| everything else           | Top-level or nested | —                                                                                                                                                      |

## Fields that YAML cannot carry

Do not promise the user something the importer cannot do:

- **Secret and SSH-key values.** `key` carries only `name`, `key_type`, `note`,
  `reference`. Values must be entered in the UI — or written over the API, which _can_
  set them (`secret_value`, `ssh_password`, `host_key` are vault-backed). See
  `cetmix-tower-api/references/yaml-vs-api.md`.
- **Server restriction on commands and plans.** `server_ids` is not in either model's
  YAML field list — imported commands and plans are available to _all_ servers.
- **Server SSH password.** Not exportable.
- **Jet records themselves.** Only templates.
- **`jet_template.icon`.** Not in the YAML field list.
- **Access roles** (`user_ids` / `manager_ids`). Not exportable; only `access_level` is.
- **`access_level` on `jet_template` and `server_log`.** The field exists on both models
  but is in neither YAML field list. Validation runs _before_ field filtering, so
  `access_level: manager` is accepted and then dropped, while any value outside `user` /
  `manager` / `root` raises _"Wrong value for 'access_level' key"_ and aborts the whole
  import — even on a model that would have discarded the key.
- **`active` on everything except `webhook`.** `cx.tower.webhook` is the only model that
  lists `active` in its YAML field list; archiving anything else needs the API.
