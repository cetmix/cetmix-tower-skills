# Exit codes

From `cetmix_tower_server/models/constants.py`. Not in the published documentation.

Use these to write meaningful post-run actions, to pick `custom_exit_code` values that
do not collide with Tower's, and to read plan logs.

`0` is success. Anything else is a failure. Tower's own codes are **negative** (except
`503`), so **use positive integers for your own `custom_exit_code`** values — a positive
code is unambiguously yours.

## General

| Code   | Constant               | Meaning                                                                                          |
| ------ | ---------------------- | ------------------------------------------------------------------------------------------------ |
| `-100` | `GENERAL_ERROR`        | Unclassified failure. Also used when a `jet_action` command had at least one failing target Jet. |
| `-101` | `NOT_FOUND`            | A referenced resource does not exist                                                             |
| `503`  | `SSH_CONNECTION_ERROR` | Could not establish the SSH connection                                                           |

## Command: -200 range

| Code   | Constant                             | Meaning                                                                                |
| ------ | ------------------------------------ | -------------------------------------------------------------------------------------- |
| `-201` | `ANOTHER_COMMAND_RUNNING`            | The command has `allow_parallel_run: false` and another copy is running on this server |
| `-202` | `NO_COMMAND_RUNNER_FOUND`            | No runner for the command's `action` — an invalid or unsupported action value          |
| `-203` | `PYTHON_COMMAND_ERROR`               | The Python command raised, or `safe_eval` rejected it                                  |
| `-205` | `PLAN_LINE_CONDITION_CHECK_FAILED`   | The plan line's `condition` was not met, so the command was skipped                    |
| `-206` | `COMMAND_TIMED_OUT`                  | Timed out and was terminated                                                           |
| `-207` | `COMMAND_NOT_COMPATIBLE_WITH_SERVER` | The command's `server_ids` exclude this server                                         |
| `-208` | `COMMAND_STOPPED`                    | Stopped by a user                                                                      |

`-205` is worth remembering when reading logs: a skipped line is recorded with this
code, not silently omitted.

## Flight plan: -300 range

| Code   | Constant                          | Meaning                                                                                                           |
| ------ | --------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `-301` | `ANOTHER_PLAN_RUNNING`            | The plan is already running on this server (and jet). Also what a plan gets when it tries to recurse into itself. |
| `-302` | `PLAN_IS_EMPTY`                   | The plan has no lines                                                                                             |
| `-303` | `PLAN_NOT_ASSIGNED`               | A command log lacks a valid plan reference                                                                        |
| `-304` | `PLAN_LINE_NOT_ASSIGNED`          | A command log lacks a valid plan line reference                                                                   |
| `-306` | `PLAN_NOT_COMPATIBLE_WITH_SERVER` | The plan, or a command in it, or a command in a nested plan, is incompatible with this server                     |
| `-308` | `PLAN_STOPPED`                    | Stopped by a user                                                                                                 |

## Files: -400 range

| Code   | Constant               | Meaning                                                                                  |
| ------ | ---------------------- | ---------------------------------------------------------------------------------------- |
| `-400` | `FILE_CREATION_FAILED` | Could not create the file. With `if_file_exists: raise` this is _"File already exists"_. |
| `-401` | `FILE_UPLOAD_FAILED`   | Push to the host failed                                                                  |
| `-402` | `FILE_DOWNLOAD_FAILED` | Pull from the host failed                                                                |

## Jets and waypoints: -500 range

| Code   | Constant                         | Meaning                                                                                                                                                                                                      |
| ------ | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-501` | `JET_ACTION_NOT_FOUND`           | Defined in `constants.py` but **never used**. An empty `jet_action_id` finishes the log with `GENERAL_ERROR (-100)` and the error _"Jet action is not found."_                                               |
| `-502` | `JET_TEMPLATE_NOT_FOUND`         | `jet_template_id` is empty on a `jet_action` command                                                                                                                                                         |
| `-503` | `JET_NOT_FOUND`                  | The command needs a Jet context and was run without one                                                                                                                                                      |
| `-504` | `JET_STATE_ERROR`                | Jet state transition error. Written only to the Jet's `current_command_log_id`, which no shipped code path sets — so not a status you will see on a command log.                                             |
| `-505` | `JET_ACTION_NOT_AVAILABLE`       | The action is not valid from the Jet's current state. Returned by `_trigger_action` to its caller; on a `jet_action` command the runner folds it into the aggregated error and finishes the log with `-100`. |
| `-506` | `JET_DEPENDENCIES_NOT_SATISFIED` | Required Jets are not in their required states. Same as `-505`: returned, not written as the command's status.                                                                                               |
| `-507` | `WAYPOINT_TEMPLATE_NOT_FOUND`    | `waypoint_template_id` is empty                                                                                                                                                                              |
| `-508` | `WAYPOINT_CREATE_FAILED`         | Creation refused — e.g. the waypoint template does not belong to this Jet's template                                                                                                                         |

A `jet_action` command log only ever carries `0`, `-100`, `-502` or `-503`. Match on
those, not on `-501` / `-504` / `-505` / `-506`.

## Writing post-run actions against these

`plan_line_action.value_char` is a **string**, and `condition` is one of `==`, `!=`,
`>`, `>=`, `<`, `<=`.

```yaml
# Continue when a container was already absent (docker rm returns non-zero)
action_ids:
  - reference: remove_container_line_action_10
    sequence: 10
    condition: "!="
    value_char: "0"
    action: n
```

```yaml
# Distinguish "SSH is down" from an application failure
action_ids:
  - reference: deploy_line_action_10
    sequence: 10
    condition: "=="
    value_char: "503"
    action: ec
    custom_exit_code: 10
  - reference: deploy_line_action_20
    sequence: 20
    condition: "!="
    value_char: "0"
    action: ec
    custom_exit_code: 20
```

Comparisons are numeric, so `> 0` matches only shell-style failures and never Tower's
negative internal codes. `!= 0` matches both — prefer it when you want to catch
everything.

To let a plan survive any failure of one line, use `action: n` with `condition: '!='`
and `value_char: '0'`. To make the plan stop on anything unexpected, leave the plan's
`on_error_action: e` and add post-run actions only for the failures you want to
tolerate.
