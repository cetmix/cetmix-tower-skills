# Python command evaluation context

Source of truth: `cx_tower_command._get_python_command_odoo_objects()`,
`_get_python_command_libraries()`, `_get_python_command_eval_context()` and
`_get_banned_python_code_keywords()` in
`cetmix_tower_server/models/cx_tower_command.py`. The live list is also rendered in the
command form's **Help** tab.

## Odoo / Tower objects

| Name              | Value                          | Notes                                                                                                                  |
| ----------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `uid`             | Current user id (int)          |                                                                                                                        |
| `user`            | `res.users` record             |                                                                                                                        |
| `env`             | Odoo environment               | Full ORM access, subject to `safe_eval` restrictions                                                                   |
| `server`          | `cx.tower.server`              | `None` outside a server context                                                                                        |
| `jet_template`    | `cx.tower.jet.template`        | `None` unless run for a jet or template                                                                                |
| `jet`             | `cx.tower.jet`                 | `None` unless run for a jet                                                                                            |
| `waypoint`        | `cx.tower.jet.waypoint`        | Set only in waypoint plans (create / arrive / leave / delete)                                                          |
| `tower`           | `cetmix.tower`                 | Helper model; most methods deprecated                                                                                  |
| `tower_servers`   | `env["cx.tower.server"]`       |                                                                                                                        |
| `tower_jets`      | `env["cx.tower.jet"]`          |                                                                                                                        |
| `tower_commands`  | `env["cx.tower.command"]`      |                                                                                                                        |
| `tower_plans`     | `env["cx.tower.plan"]`         |                                                                                                                        |
| `tower_waypoints` | `env["cx.tower.jet.waypoint"]` |                                                                                                                        |
| `custom_values`   | `dict`                         | Shared across SSH and Python commands of one flight plan run, and plan-line conditions. **Not** passed to `file_using_template` / `create_file()` (hard rule 17). Not persisted as a `variable.value` record. Written back to the plan run after the command finishes. |
| `result`          | you assign it                  | `{"exit_code": int, "message": str}`                                                                                   |

When the jet is set, `jet_template` is forced from `jet.jet_template_id`, so you never
need to derive it yourself.

## Libraries

| Name            | Notes                                                                                                                                                                                                                                                                                |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `re`            | Wrapped: `match`, `fullmatch`, `search`, `sub`, `subn`, `split`, `findall`, `finditer`, `compile`, `template`, `escape`, `error`. **No module constants** — `re.IGNORECASE`, `re.MULTILINE`, `re.DOTALL` etc. are not exposed, so use inline flags (`(?i)`, `(?m)`, `(?s)`) instead. |
| `time`          | via `safe_eval`                                                                                                                                                                                                                                                                      |
| `datetime`      | via `safe_eval`                                                                                                                                                                                                                                                                      |
| `dateutil`      | via `safe_eval`                                                                                                                                                                                                                                                                      |
| `timezone`      | `pytz.timezone` — a **factory**, called as `timezone("Europe/Tallinn")`. Not `datetime.timezone`, so `timezone.utc` does not exist; use `timezone("UTC")`.                                                                                                                           |
| `requests`      | Wrapped: `post`, `get`, `delete`, `request` only                                                                                                                                                                                                                                     |
| `urllib_parse`  | `urllib.parse`                                                                                                                                                                                                                                                                       |
| `json`          | Wrapped: **`dumps` only**. `json(...)` as a call and `json.loads` both fail at runtime. Write `json.dumps(...)`. To parse a JSON HTTP response use `response.json()` (a `requests` method, unaffected by the wrap); no `literal_eval` is in the context as a fallback.                                                 |
| `hashlib`       | `sha1`, `sha224`, `sha256`, `sha384`, `sha512`, `sha3_*`, `shake_128`, `shake_256`, `blake2b`, `blake2s`, `md5`, `new`                                                                                                                                                               |
| `hmac`          | `new`, `compare_digest`                                                                                                                                                                                                                                                              |
| `tldextract`    | e.g. `tldextract.extract(domain)`                                                                                                                                                                                                                                                    |
| `dns`           | dnspython: `dns.resolver`, `dns.reversename`, `dns.exception`                                                                                                                                                                                                                        |
| `float_compare` | Odoo float comparison helper                                                                                                                                                                                                                                                         |
| `UserError`     | Odoo exception class                                                                                                                                                                                                                                                                 |
| `_logger`       | Debug logging only — do not use for user-facing output                                                                                                                                                                                                                               |

Extra modules can add more via `_custom_python_libraries()`. In this repository:

| Module             | Adds          | Wrapped methods                 |
| ------------------ | ------------- | ------------------------------- |
| `cetmix_tower_git` | `giturlparse` | `parse`, `validate`             |
| `cetmix_tower_aws` | `boto3`       | `client`, `resource`, `Session` |
| `cetmix_tower_ovh` | `ovh`         | `Client`                        |

Each is present only when its module is installed. Check the Help tab of a Python
command on the actual instance for the definitive list.

## Restrictions

Odoo `safe_eval`, `mode="exec"`, `nocopy=True`:

- No `import` statements.
- No `getattr`, `setattr`, `delattr`, `eval`, `exec`, `compile`, `open`, `__import__`.
- No dunder attribute access.
- Assigning to a record field attribute raises. Use `record.write({...})`.
- Banned substrings, rejected before execution: `_set_secret_values(`,
  `_get_secret_value(`, `_get_secret_values(`.
- Uncaught exceptions become a generic _"Python code running error"_ with the
  `PYTHON_COMMAND_ERROR` status. Catch and convert.

## `cetmix.tower` helper methods

### Current

| Method                        | Signature                                                                       | Returns                                                                   |
| ----------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `server_check_ssh_connection` | `(server_reference, attempts=5, wait_time=10, try_command=True, try_file=True)` | `{"exit_code", "message"}`                                                |
| `server_validate_secret`      | `(secret_value, secret_reference, server_reference=None)`                       | `bool` — accepts a bare reference or the full `#!cxtower.secret.X!#` form |
| `generate_random_id`          | `(sections=1, population=4, separator="-")`                                     | `str`                                                                     |
| `is_valid_url`                | `(url, no_scheme_check=False)`                                                  | `bool`                                                                    |

### Deprecated — emit warnings, will be removed

`server_create_from_template`, `server_run_command`, `server_run_flight_plan`,
`server_set_variable_value`, `server_get_variable_value`.

Use the model methods instead:

| Model                      | Method                                          | Signature                                                                                     |
| -------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `cx.tower.server`          | `run_command`                                   | `(command, path=None, sudo=None, ssh_connection=None, jet_template=None, jet=None, **kwargs)` |
|                            | `run_flight_plan`                               | `(flight_plan, jet_template=None, jet=None, **kwargs)` → plan log record                      |
|                            | `get_variable_value`                            | `(variable_reference, no_fallback=False)` — follows Jet → Template → Server → Global          |
|                            | `set_variable_value`                            | `(variable_reference, value)` — returns `None`                                                |
|                            | `update_metadata`                               | `(dict)` — merges                                                                             |
|                            | `test_ssh_connection`                           | —                                                                                             |
|                            | `upload_file` / `download_file` / `delete_file` | `(data, remote_path, from_path=False)` / `(remote_path)` / `(remote_path)`                    |
| `cx.tower.jet`             | `set_variable_value`                            | `(variable_reference, value)` — same mixin; persist here when a file template on this Jet must see the value. Returns `None`. |
|                            | `get_variable_value`                            | `(variable_reference, no_fallback=False)`                                                     |
|                            | `update_metadata`                               | `(dict)` — merges                                                                             |
| `cx.tower.jet.template`    | `set_variable_value`                            | `(variable_reference, value)` — returns `None`                                                |
| `cx.tower.server.template` | `create_server_from_template`                   | `(template_reference, server_name, **kwargs)`                                                 |
| any reference-mixin model  | `get_by_reference`                              | `(reference)` — case-sensitive                                                                |

`run_command` / `run_flight_plan` accept `variable_values={"ref": "value"}` in `kwargs`
to override variables for that run (applied only if the user has write access to the
server). Those overrides follow the same rule as `custom_values`: SSH, Python, and
plan-line conditions, **not** `file_using_template` (hard rule 17). `run_command` with context `no_command_log=True` returns the result dict
instead of creating a log record. It still performs the _Allow Parallel Run_ check (and
can return `ANOTHER_COMMAND_RUNNING` in the dict); what it skips is creating the log for
_this_ run, so a concurrent run started later does not see it as blocking. Use it
deliberately.

## Waypoint context

In waypoint plans, `waypoint` is populated and these custom variables are available to
the plan (and thus to line conditions):

| Variable           | Meaning                       |
| ------------------ | ----------------------------- |
| `__waypoint`       | Waypoint reference            |
| `__waypoint_type`  | Waypoint template reference   |
| `__waypoint_state` | Current waypoint state        |
| `__waypoint_<key>` | One per waypoint metadata key |

Clone plans get `__original_jet__`, `__original_server__`, `__requested_jet_state__`,
and `jet.jet_cloned_from_id` in Python.
