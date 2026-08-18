---
name: cetmix-tower-command-actions
description:
  Choose and wire the right Cetmix Tower command action, and author the four
  orchestration actions in depth — plan (run a child flight plan), jet_action (trigger a
  Jet lifecycle action on itself or on dependent Jets), create_waypoint (snapshot a Jet
  from inside a plan), and file_using_template (render and push or pull a file). Covers
  required companion fields, execution semantics, exit codes and the flight-plan-only
  restriction. Use when a command must orchestrate something rather than run a shell
  statement or Python.
---

# Command actions

`command.action` is required and has exactly six values. Two run code; four orchestrate.

| Action                | Runs                                        | Companion fields                                                   | Form-required?     | Available in the run wizard? |
| --------------------- | ------------------------------------------- | ------------------------------------------------------------------ | ------------------ | ---------------------------- |
| `ssh_command`         | A shell statement on the host               | `code`, optionally `path`                                          | **No** — see below | Yes                          |
| `python_code`         | Python inside Tower                         | `code`                                                             | Yes                | Yes                          |
| `file_using_template` | Renders a file template, pushes or pulls it | `file_template_id`, `if_file_exists`, optionally `disconnect_file` | Yes                | **No**                       |
| `plan`                | A child flight plan                         | `flight_plan_id`                                                   | Yes                | **No**                       |
| `jet_action`          | A Jet lifecycle transition                  | `jet_template_id`, `jet_action_id`                                 | Yes                | **No**                       |
| `create_waypoint`     | Creates a Jet waypoint                      | `waypoint_template_id`, optionally `fly_here`                      | Yes                | **No**                       |

`code` is not `required=True` on the model, and the command form marks it required only
for `action: python_code`. An `ssh_command` with an empty `code` therefore saves and
imports without complaint, and simply does nothing at run time. Nothing will tell you —
check it yourself.

For the two code actions see `cetmix-tower-command-ssh` and
`cetmix-tower-command-python`. This skill covers the other four.

## Flight-plan-only is a hard restriction

The ad-hoc **Run Command** wizard offers only `ssh_command` and `python_code`, and
filters the selectable commands to the chosen action. The other four actions have no
wizard path at all — they run only as a **flight plan line**.

Consequences when designing:

- A `file_using_template`, `plan`, `jet_action` or `create_waypoint` command needs a
  plan wrapping it, even if the plan has a single line.
- A `shortcut` or `scheduled_task` that should trigger one must use `action: plan` and
  point at that wrapper plan, not `action: command`.
- `jet_action` and `create_waypoint` additionally require a **Jet context** — the plan
  must be run on a Jet (from a Jet form, a jet lifecycle action, or a waypoint plan),
  not on a bare server.

## `action: plan` — run a child flight plan

The composition primitive. Wrap a plan in a command so it can be used as one line of a
bigger plan.

```yaml
- cetmix_tower_model: command
  reference: run_install_docker
  name: Install Docker
  action: plan
  access_level: manager
  note: Wrapper so the install_docker plan can be reused as a single plan line.
  flight_plan_id: install_docker

- cetmix_tower_model: plan
  reference: deploy_stack
  name: Deploy Stack
  note: Installs Docker, then deploys the application.
  on_error_action: e
  line_ids:
    - reference: deploy_stack_line_10
      sequence: 10
      command_id: run_install_docker
    - reference: deploy_stack_line_20
      sequence: 20
      command_id: app_create_container
```

Execution semantics:

- **Synchronous.** The child plan runs to completion before the next parent line starts.
- **Same context.** It runs on the same server and inherits `jet_template` and `jet`
  from the parent run, so jet-scoped variables resolve correctly.
- **Status propagates.** The child plan's status becomes the command's exit code, so the
  parent's `on_error_action` and post-run actions branch on it as with any command.
- **Logs nest.** The child plan log records `parent_flight_plan_log_id` and gets a short
  random label, so you can drill from the parent plan log into the child.
- **`custom_values` flow back.** Variable values the child plan set are returned to the
  parent run. A child plan can therefore compute a flag that a later parent line tests
  in its `condition` — worth knowing, and worth documenting in the child plan's `note`,
  since it is invisible from the parent.
- **Server compatibility is checked recursively.** If any command in a nested plan is
  incompatible with the server, the whole thing fails with
  `PLAN_NOT_COMPATIBLE_WITH_SERVER (-306)` before running.

**Recursion is blocked.** Running a child plan sets an internal recursion guard, so a
plan that is already running on that server (and jet) will not start again — it returns
`ANOTHER_PLAN_RUNNING (-301)`. This holds even when `allow_parallel_run: true`. So a
plan cannot call itself, directly or through a chain. Do not design loops this way; use
conditions, or repeat lines.

## `action: jet_action` — trigger a Jet lifecycle action

Runs a Jet action's flight plan and moves that Jet's state. Use it instead of
duplicating another Jet's commands.

```yaml
- cetmix_tower_model: command
  reference: stop_dependent_app_jets
  name: Stop dependent App Jets
  action: jet_action
  access_level: manager
  note: >-
    Triggers the App template's Stop action on every App Jet linked to the current Jet
    by a dependency. Used in the DB Jet's Stop plan so apps stop first.
  jet_template_id: app_jet
  jet_action_id: app_jet_action_stop
```

### Which Jets it acts on — read this carefully

The target is **not** "some other Jet you name". It is resolved from the Jet the command
is running on, against `jet_template_id`:

- **`jet_template_id` == the current Jet's template** → the action is triggered on the
  **current Jet itself**. This is how a plan re-enters its own lifecycle.
- **`jet_template_id` != the current Jet's template** → the action is triggered on the
  current Jet's **dependent Jets of that template**, in **both directions**: Jets this
  one requires, and Jets that require this one. Only **one level** of the dependency
  graph is walked — grandchildren are not included.

So the wiring only works if a `jet_template_dependency` links the two templates and the
concrete Jets are actually linked. See `cetmix-tower-jets`.

**With no matching dependent Jets the command succeeds** with status `0` and a message
like _"Jet X has no dependent jets with template Y"_. It is a silent no-op, not an error
— a missing dependency will not fail your plan, it will quietly do nothing. If the
action is essential, verify it in a following Python command rather than trusting the
exit code.

### Failure modes

| Condition                                          | Command log status                                                    |
| -------------------------------------------------- | --------------------------------------------------------------------- |
| Command not run on a Jet                           | `JET_NOT_FOUND (-503)`                                                |
| `jet_template_id` empty                            | `JET_TEMPLATE_NOT_FOUND (-502)`                                       |
| `jet_action_id` empty                              | `GENERAL_ERROR (-100)`, error _"Jet action is not found."_            |
| Action not valid from a target Jet's current state | `GENERAL_ERROR (-100)`                                                |
| A target Jet's dependencies are unsatisfied        | `GENERAL_ERROR (-100)`                                                |
| One or more target Jets failed                     | `GENERAL_ERROR (-100)`, errors aggregated as `jet_reference: message` |

**The only statuses this command writes to its log are `0`, `-100`, `-502` and `-503`.**
`JET_ACTION_NOT_AVAILABLE (-505)` and `JET_DEPENDENCIES_NOT_SATISFIED (-506)` are
returned by `_trigger_action` per Jet and folded into the aggregated error text; the
runner still finishes the log with `-100`. `JET_ACTION_NOT_FOUND (-501)` is defined in
`constants.py` but never used. Do not write a post-run action on `value_char: '-501'`,
`'-505'` or `'-506'` — it will never match.

Multiple target Jets are all attempted; failures do not stop the loop, they are
collected. An action that is unavailable from a Jet's current state is reported, not
raised — so a Stop fan-out across Jets that are already stopped reports errors rather
than skipping them. Guard with a `condition` on the plan line when that matters.

`jet_action_id` is domain-filtered to actions of `jet_template_id`, so the two fields
must agree. In YAML nothing enforces that — check it yourself.

## `action: create_waypoint` — snapshot a Jet from a plan

```yaml
- cetmix_tower_model: command
  reference: create_pre_upgrade_snapshot
  name: Create pre-upgrade snapshot
  action: create_waypoint
  access_level: manager
  note: >-
    Snapshots the Jet before an upgrade. Runs the waypoint template's Create plan; the
    upgrade lines only proceed once the waypoint is ready.
  waypoint_template_id: redis_snapshot
  fly_here: false
```

- Requires a **Jet context**; the waypoint is created for `log_record.jet_id`.
- `waypoint_template_id` must belong to that Jet's template, or creation fails with
  `WAYPOINT_CREATE_FAILED (-508)`.
- `fly_here: true` makes the new waypoint current immediately. Leave it `false` when you
  only want the backup taken.
- The flight plan marks the Jet busy; the runner passes `ignore_busy=True` so creation
  is allowed anyway. You do not need to work around it.

**Completion is deferred.** Unlike every other action, the runner does not finish the
command log. The log stays _running_ until the waypoint reaches `ready` / `current` /
`error`, at which point a callback finishes it. That means the waypoint's **Create
flight plan runs as part of this line**, and the line's exit code reflects the whole
snapshot, not just the record creation. Budget the time accordingly and do not add a
"wait" line after it.

| Condition                                            | Exit code                            |
| ---------------------------------------------------- | ------------------------------------ |
| Command not run on a Jet                             | `JET_NOT_FOUND (-503)`               |
| `waypoint_template_id` empty                         | `WAYPOINT_TEMPLATE_NOT_FOUND (-507)` |
| Template not valid for this Jet, or creation refused | `WAYPOINT_CREATE_FAILED (-508)`      |

See `cetmix-tower-waypoints` for the waypoint templates themselves.

## `action: file_using_template` — render and transfer a file

```yaml
- cetmix_tower_model: command
  reference: redis_push_conf
  name: Redis - push redis.conf
  action: file_using_template
  access_level: manager
  note: Renders redis_conf and uploads it. Overwrites an existing file.
  file_template_id: redis_conf
  if_file_exists: overwrite
```

- Direction follows the **template's** `source`: `tower` → pushed to the host, `server`
  → pulled into Tower.
- **`path` overrides the template's `server_dir`.** The command's `path`, or the plan
  line's `path` if set, is passed as the target directory; the template's own
  `server_dir` is used only when both are empty. This is how one template serves several
  directories — and how you accidentally write to the wrong place. Leave `path` empty
  unless you mean it.
- `if_file_exists`:
  - `skip` (default) → status `0`, message _"File already exists on server. Upload
    skipped"_
  - `overwrite` → replaces the file
  - `raise` → `FILE_CREATION_FAILED (-400)`, error _"File already exists"_
- `disconnect_file: true` unlinks the created file from its template afterwards, so
  later template edits no longer touch it.
- Transfer failures return `FILE_UPLOAD_FAILED (-401)` / `FILE_DOWNLOAD_FAILED (-402)`.
- Status `0` with _"File created and uploaded successfully"_ is not proof the file
  is on the host — the queue module enqueues the upload. See `cetmix-tower-files`.
- **The plan run's `custom_values` are not applied.** `create_file()` renders from
  stored Jet / Template / Server / Global values only. Persist with
  `jet.set_variable_value` (or `server.set_variable_value`) before this line, or the
  file will contain `None` / `False` and the command will still succeed. Hard rule 17;
  detail in `cetmix-tower-files`.

See `cetmix-tower-files` for the template side.

## `server_status` applies to more than SSH

`command.server_status` sets the **server's** status on success, and it is honoured for
**all six** actions — `ssh_command`, `python_code`, `file_using_template`, `jet_action`,
`create_waypoint` and `plan`. The runner only skips the status write when no runner
matched the action at all. Setting it on an orchestration command is usually wrong — a
child plan finishing does not mean the host changed state. Leave it empty unless the
command genuinely represents a host transition.

## Choosing between them

| Goal                                     | Action                                   |
| ---------------------------------------- | ---------------------------------------- |
| Reuse a command sequence                 | `plan`                                   |
| Fan out to Jets that depend on this one  | `jet_action` with the **other** template |
| Re-enter the current Jet's own lifecycle | `jet_action` with the **same** template  |
| Back up before a risky step              | `create_waypoint`                        |
| Write a config file                      | `file_using_template`                    |
| Anything on the host                     | `ssh_command`                            |
| Anything in Tower, or an HTTP API        | `python_code`                            |

## Review checklist

- [ ] The action's required companion fields are all set
- [ ] `flight_plan_id` only with `action: plan`; `jet_action_id` + `jet_template_id`
      only with `jet_action`; `waypoint_template_id` only with `create_waypoint`;
      `file_template_id` only with `file_using_template`
- [ ] `jet_action_id` belongs to `jet_template_id`
- [ ] For `jet_action` / `create_waypoint`: the plan really runs in a Jet context
- [ ] For `jet_action` across templates: a `jet_template_dependency` links them, and the
      silent-no-op case is acceptable or explicitly verified
- [ ] No plan calls itself directly or transitively
- [ ] `path` left empty on `file_using_template` unless overriding `server_dir` on
      purpose
- [ ] `if_file_exists` chosen deliberately
- [ ] Values the file template must see persisted with `set_variable_value` before this
      line (hard rule 17)
- [ ] Every one of these commands is reachable through a plan, not a bare shortcut or
      scheduled task with `action: command`
- [ ] `server_status` empty on orchestration commands
- [ ] `note` explains what the command orchestrates and what it assumes
