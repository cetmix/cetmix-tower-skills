---
name: cetmix-tower-flight-plan
description:
  Design Cetmix Tower Flight Plans (plan, plan_line, plan_line_action records) — line
  sequencing, Python conditions, use_sudo and path overrides, post-run actions and
  exit-code branching, on_error_action, setting variable values from a line, composing
  sub-plans with action plan, and where plans attach (servers, jet actions, waypoints,
  shortcuts, scheduled tasks). Use when building or reviewing any multi-step Tower
  execution flow.
---

# Flight Plans

A Flight Plan (`cetmix_tower_model: plan`) runs commands in sequence, with conditions
per line and branching on exit codes. It is the unit of work everything else triggers:
servers run plans, jet actions run plans, waypoints run plans, shortcuts and scheduled
tasks run plans.

## Structure

```yaml
- cetmix_tower_model: plan
  reference: deploy_app
  name: Deploy App
  access_level: manager
  allow_parallel_run: false
  color: 1
  tag_ids: [docker, app]
  note: What this plan does and what it expects to already be true.
  on_error_action: e
  line_ids:
    - reference: deploy_app_line_10
      sequence: 10
      command_id: create_app_dir
    - reference: deploy_app_line_20
      sequence: 20
      command_id: pull_app_image
      use_sudo: true
      path: /opt/app
      condition: "{{ deploy_mode }} == 'docker'"
      action_ids:
        - reference: deploy_app_line_20_action_10
          sequence: 10
          condition: "!="
          value_char: "0"
          action: ec
          custom_exit_code: 30
```

`plan_line` and `plan_line_action` have no owner-link field in YAML, so they **must** be
nested — never top-level records.

Every plan needs at least one line, and every line needs a `command_id`. Empty plans are
pointless and detached lines are orphans.

## Plan fields

| Field                | Notes                                                                                                                                                  |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`               | Required                                                                                                                                               |
| `reference`          | Required at top level                                                                                                                                  |
| `allow_parallel_run` | Default `false`: one run per server at a time. Keep `false` for deployments.                                                                           |
| `on_error_action`    | `e` (exit with the command's code, **default**), `ec` (exit with `custom_exit_code`), `n` (run next command). Applies when no post-run action matched. |
| `custom_exit_code`   | Used only with `on_error_action: ec`                                                                                                                   |
| `color`              | 0–10, for kanban                                                                                                                                       |
| `access_level`       | Minimum level to run it                                                                                                                                |
| `note`               | Required by convention                                                                                                                                 |
| `tag_ids`            | Add the technology plus `Jets` when it is part of a lifecycle                                                                                          |

`server_ids` is not importable, so an imported plan is available on every server.

## Line fields

| Field          | Notes                                                                                                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `reference`    | Cosmetic on `plan_line` / `plan_line_action`. Tower stores a derived name; a YAML re-import cannot match it and will duplicate lines. See `cetmix-tower-yaml` → _Nested references_. |
| `sequence`     | Execution order, ascending. Leave gaps (10, 20, 30) so lines can be inserted later.                                                                                                  |
| `command_id`   | The command. **`command_id`, never `command`.**                                                                                                                                      |
| `condition`    | Python expression; the line runs only if it is truthy. Blank = always.                                                                                                               |
| `use_sudo`     | Apply the server's sudo setting to this line. This is the _only_ correct way to use sudo.                                                                                            |
| `path`         | Overrides the command's `path` for this line. Supports variables.                                                                                                                    |
| `action_ids`   | Post-run actions                                                                                                                                                                     |
| `variable_ids` | Computed from `condition`; do not hand-maintain                                                                                                                                      |

## Conditions

A Python expression, rendered with variables first, then evaluated with `safe_eval`:

```python
{{ odoo_version }} == "17.0" and ( {{ nginx_installed }} or {{ traefik_installed }} )
```

```python
{{ tower.server.status }} == 'running' and {{ odoo_demo_version }} == "18.0"
```

Conditions render in **pythonic mode** (`_is_executable_line` calls `render_code_custom`
with `pythonic_mode=True`), so every value except booleans and `None` arrives **already
wrapped in double quotes**. `{{ odoo_version }}` becomes `"17.0"`, not `17.0`.

Consequences:

- **Never quote the `{{ }}` yourself.** `"{{ odoo_version }}"` renders to `""17.0""`,
  which is a syntax error. `safe_eval` raises, the traceback goes to the **Odoo server
  log only**, and the plan continues with the next line. In the plan log the operator
  sees a command log row with `is_skipped` and status `PLAN_LINE_CONDITION_CHECK_FAILED`
  (`-205`) — indistinguishable from a condition that was legitimately false, so a broken
  condition looks like a normal skip unless someone reads the server log.
- Quote the **literal** side, as in the examples above.
- A variable with no value resolves to `None` and renders as `None`, so a comparison
  against it is `False` rather than an error. A value set to an empty string renders as
  `""`. Neither breaks the expression.
- Booleans stay bare: a `custom_values` flag set to `True` renders as `True`.

Guarding with a preceding Python command that sets a boolean `custom_values` flag is
still more robust than a complex inline expression:

```python
# Python command earlier in the plan
if server.os_id.reference == "ubuntu_2404":
    custom_values["_is_ubuntu_latest"] = True
```

```python
# then, as the line condition
{{ _is_ubuntu_latest }}
```

This is the recommended pattern for anything non-trivial: compute in Python, branch in
the condition. Prefix invented keys with `_`.

### `{{ tower.jet.state }}` is the transit while an action runs

A plan attached to a jet action runs **during** that action. `{{ tower.jet.state }}` is
`state_transit_id`, not the from/to resting state. A Start line conditioned on
`{{ tower.jet.state }} == "running"` is skipped while Rebuild-from-running is in
transit (on some instances that transit is a custom state, not one of the eleven
shipped names). Before writing conditions, list `cx.tower.jet.state` and the
template's `action_ids` on the **target instance**. Include the transit of the action
that contains the line. See `cetmix-tower-jets`.

## Post-run actions

Evaluated after the line's command finishes, in `sequence` order. The first match wins.

| Field                | Notes                                                                                                                                   |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `sequence`           | Evaluation order                                                                                                                        |
| `condition`          | `==`, `!=`, `>`, `>=`, `<`, `<=` — compared against the command's exit code                                                             |
| `value_char`         | The compared value, as a **string**: `'0'`, `'1'`, `'255'`                                                                              |
| `action`             | `e` exit with command code · `ec` exit with `custom_exit_code` · `n` run next command (**default**)                                     |
| `custom_exit_code`   | With `action: ec`                                                                                                                       |
| `variable_value_ids` | Variable values injected into the **current run's** variable context when this action fires. **Not written to the server** — see below. |

Common uses:

```yaml
# Tolerate a failure and keep going (e.g. 'docker rm' on a nonexistent container)
action_ids:
- reference: line_30_action_10
  sequence: 10
  condition: '!='
  value_char: '0'
  action: n

# Turn a specific failure into a distinguishable exit code
action_ids:
- reference: line_50_action_10
  sequence: 10
  condition: '!='
  value_char: '0'
  action: ec
  custom_exit_code: 21

# Set a flag for the *rest of this run* after a successful step
action_ids:
- reference: line_60_action_10
  sequence: 10
  condition: '=='
  value_char: '0'
  action: n
  variable_value_ids:
  - reference: line_60_deploy_state_value
    variable_id: deploy_state
    value_char: deployed
```

### `variable_value_ids` do not persist

The plan runner copies these values into the run's `variable_values` dict and stores
that dict on the command log and plan log. It does **not** create or update a
`cx.tower.variable.value` record on the server. So they:

- are visible to later line conditions and to later commands in the same run,
- survive into the plan log for inspection,
- and are **gone when the run ends**.

They are the declarative equivalent of assigning to `custom_values` in a Python command,
not of `server.set_variable_value()`. They reach later SSH and Python commands and
plan-line conditions in this run. They do **not** reach `file_using_template` (hard
rule 17). To record a value that a later file template must render, use a Python
command calling `jet.set_variable_value(reference, value)` or
`server.set_variable_value(reference, value)` (or `update_metadata({...})`), and say so
in the plan's `note`.

## Composition

Extract recurring sequences into their own plan and call them from a parent with a
command whose action is `plan`:

```yaml
- cetmix_tower_model: command
  reference: run_install_docker
  name: Install Docker
  action: plan
  note: Wrapper so the Install Docker plan can be reused as a single plan line.
  flight_plan_id: install_docker

- cetmix_tower_model: plan
  reference: deploy_stack
  name: Deploy Stack
  note: Installs Docker, then deploys the application.
  line_ids:
    - reference: deploy_stack_line_10
      sequence: 10
      command_id: run_install_docker
    - reference: deploy_stack_line_20
      sequence: 20
      command_id: app_create_container
```

Guidance:

- Prefer **one generic plan with conditions** over several near-identical plans.
- Prefer **sub-plans** over copy-pasted line groups.
- Keep sub-plans single-purpose so they compose: `install_docker`,
  `update_host_packages`, `create_app_directories`.
- To act on a Jet from inside a plan, use a command with `action: jet_action`
  (`jet_template_id` + `jet_action_id`) rather than duplicating that Jet's commands. It
  targets the **current Jet** when `jet_template_id` is the current Jet's own template,
  and the current Jet's **dependent Jets** of that template otherwise. Details and
  failure modes: `cetmix-tower-command-actions`.

A child plan runs synchronously on the same server, inherits the jet context, propagates
its status as the command's exit code, and returns its `custom_values` to the parent
run. A plan cannot recurse into itself — the second entry returns
`ANOTHER_PLAN_RUNNING (-301)`.

## Where plans attach

| Consumer                         | Field                                                                                          |
| -------------------------------- | ---------------------------------------------------------------------------------------------- |
| Server / Jet, run manually       | _Run Flight Plan_ button                                                                       |
| Jet lifecycle action             | `jet_action.plan_id`                                                                           |
| Jet template install / uninstall | `jet_template.plan_install_id` / `plan_uninstall_id`                                           |
| Jet template clone               | `plan_clone_same_server_id` / `plan_clone_different_server_id`                                 |
| Waypoint lifecycle               | `jet_waypoint_template.plan_create_id` / `plan_arrive_id` / `plan_leave_id` / `plan_delete_id` |
| After server creation            | `server_template.flight_plan_id`                                                               |
| Before server deletion           | `server.plan_delete_id` / `server_template.plan_delete_id`                                     |
| One-click button                 | `shortcut.plan_id` with `action: plan`                                                         |
| On a schedule                    | `scheduled_task.plan_id` with `action: plan`                                                   |

Actions that do the **same thing** may share a plan (two Start actions in different
template variants). Actions that do **different** things must not — see
`cetmix-tower-jets` for the Build-vs-Start rule.

## Commands that only work inside a plan

The ad-hoc **Run Command** wizard offers only `ssh_command` and `python_code`.
`file_using_template`, `plan`, `jet_action` and `create_waypoint` have no ad-hoc run
path at all — each needs a plan around it, even a single-line one. A `shortcut` or
`scheduled_task` that should trigger one must use `action: plan` pointing at that
wrapper, not `action: command`. See `cetmix-tower-command-actions`.

## Review checklist

- [ ] At least one line; every line has `command_id`
- [ ] `plan_line` / `plan_line_action` nested, never top-level
- [ ] Sequences leave gaps
- [ ] `use_sudo` on lines rather than `sudo` in command code
- [ ] `path` on the line rather than `cd` in command code
- [ ] `on_error_action` deliberate — `e` unless you want the plan to survive failures
- [ ] Post-run actions cover the known failure modes with distinguishable exit codes
- [ ] Conditions leave `{{ }}` unquoted (pythonic mode quotes values already) and still
      behave when a variable is unset (renders as `None`)
- [ ] Conditions on `{{ tower.jet.state }}` include the **transit** of the action that
      contains the line, not only `running` / `stopped`
- [ ] No post-run `variable_value_ids` or `custom_values` relied on to feed a later
      `file_using_template` (hard rule 17)
- [ ] `allow_parallel_run: false` for anything stateful
- [ ] Recurring line groups extracted into sub-plans
- [ ] `note` on the plan says what it expects to already be true
