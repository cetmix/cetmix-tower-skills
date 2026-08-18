---
name: cetmix-tower-command-python
description:
  Write Cetmix Tower Python commands (command records with action python_code) — the
  safe_eval sandbox, the result dict with exit_code and message, injected objects (env,
  server, jet, jet_template, waypoint, tower, custom_values), available libraries,
  pythonic variable rendering, secrets, metadata, calling provider APIs with requests,
  and the safe_eval restrictions that break normal Python. Use when a Tower command must
  run inside Odoo rather than on a host.
---

# Python commands

`cetmix_tower_model: command` with `action: python_code`. Runs **inside Odoo on the
Tower server**, not on the remote host. No SSH connection is used.

Reach for it when the work is: a third-party/provider HTTP API call, reading or writing
Tower data, controlling flow inside a flight plan, or verification and reporting.
Anything that touches the managed host is an SSH command instead.

## Contract

Assign a `result` dict. That is the command's outcome.

```python
result = {
    "exit_code": 0,
    "message": "Instance created",
}
```

- `exit_code` — `0` is success, anything else is a failure. It becomes the command's
  status, so flight plan `condition`s and post-run actions can branch on it.
- `message` — logged as a result message when `exit_code == 0`, as an error otherwise.
- Default if you assign nothing: `{"exit_code": 0, "message": None}`.

Never let an exception escape. An uncaught exception is reported as a Python running
error with no useful exit code. Catch what you expect and convert it into a non-zero
`exit_code` with a message that says what to fix.

## Sandbox: `safe_eval`

The code runs through Odoo's `safe_eval` in `exec` mode. Consequences you will hit:

- **No `import`.** Only the pre-injected libraries below exist.
- **`getattr` / `setattr` / `eval` / `exec` / `open` and friends are unavailable.**
- **Never assign to a field attribute.** Use `write()`:

  ```python
  server.note = "text"              # raises
  server.write({"note": "text"})    # correct
  ```

- Three helper names are explicitly **banned** anywhere in the code and rejected at save
  time: `_set_secret_values(`, `_get_secret_value(`, `_get_secret_values(`.
- Comprehensions, f-strings, `try/except`, `if/else`, loops and function definitions all
  work normally.

## Injected objects

Full table with types and caveats: `references/eval-context.md`.

| Name                                                                              | What it is                                                                                                                |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `env`                                                                             | Odoo environment                                                                                                          |
| `uid`, `user`                                                                     | Current user id / record                                                                                                  |
| `server`                                                                          | The `cx.tower.server` this runs for, or `None`                                                                            |
| `jet`, `jet_template`, `waypoint`                                                 | The Jet context, or `None`                                                                                                |
| `tower`                                                                           | `cetmix.tower` helper — most methods are **deprecated**, see below                                                        |
| `tower_servers`, `tower_jets`, `tower_commands`, `tower_plans`, `tower_waypoints` | Shortcuts to the corresponding models                                                                                     |
| `custom_values`                                                                   | Mutable dict for SSH, Python, and conditions in one plan run — **not** `file_using_template` (hard rule 17)               |
| `re`, `time`, `datetime`, `dateutil`, `timezone`                                  | Time and regex                                                                                                            |
| `requests`                                                                        | `get`, `post`, `delete`, `request`                                                                                        |
| `urllib_parse`, `json`, `hashlib`, `hmac`                                         | Encoding and hashing. `json` is `dumps` **only** — never `json(...)` or `json.loads`; parse HTTP with `response.json()`. |
| `tldextract`, `dns`                                                               | Domain parsing and DNS                                                                                                    |
| `float_compare`, `UserError`                                                      | Odoo helpers                                                                                                              |
| `_logger`                                                                         | Debug logging only                                                                                                        |

`giturlparse` (Git module), `boto3` (AWS module) and `ovh` (OVH module) are added when
those modules are installed — see `references/eval-context.md` for the wrapped methods.

Only providers that exist in the current context are populated. A command run on a
server has `server` but `jet is None`; a command run on a jet has both plus
`jet_template`; a waypoint plan additionally has `waypoint`.

## Finding records

Always use `get_by_reference`. References are case-sensitive.

```python
srv = tower_servers.get_by_reference("my_server")          # good
srv = env["cx.tower.server"].search([("reference", "=", "my_server")])  # avoid
```

## Variables and secrets in Python code

Both are substituted **before** the code is evaluated — they are text templating, not
runtime lookups.

```python
# Configuration variable — pythonic mode adds the quotes for you
version = {{ odoo_version }}          # -> version = "17.0"
enabled = {{ feature_enabled }}       # -> enabled = False   (booleans/None stay bare)

# Secret — never quote it either
token = #!cxtower.secret.hetzner_api_token!#
```

**Do not wrap either in quotes.** Python commands render in _pythonic mode_: every value
except booleans and `None` is emitted already enclosed in double quotes. Writing
`"{{ odoo_version }}"` produces `""17.0""`, a syntax error.

Because rendering happens first, `{{ }}` cannot appear inside a runtime expression that
needs to vary per iteration. Read those values from `custom_values` or the ORM instead.

Precedence when choosing where a value comes from:

1. Secrets → `#!cxtower.secret.ref!#`
2. Configuration variables → `{{ ref }}`
3. Transient values passed between commands in one plan run →
   `custom_values.get("_key")`

## `custom_values`

A plain dict, shared across the commands of one flight plan run, not persisted.

```python
# Set a flag for later plan lines
if server.os_id.reference == "ubuntu_2404":
    custom_values["_is_ubuntu_latest"] = True

# Override a variable value for later SSH, Python, and conditions in this run
custom_values["odoo_version"] = "18.0"
# Does not reach file_using_template — persist first, see below
```

Then in a flight plan line's `condition`: `{{ _is_ubuntu_latest }}`.

Prefix values you invent with `_` so they cannot shadow a real variable. Unprefixed
keys override a real variable for SSH, Python, and conditions in this run — **not**
for `file_using_template` (hard rule 17).

## Persisting values

| Goal                                            | How                                                             |
| ----------------------------------------------- | --------------------------------------------------------------- |
| Set a variable value on a server                | `server.set_variable_value("hetzner_server_id", str(sid))`      |
| Set a variable value on a jet or jet template   | `jet.set_variable_value("prometheus_datasource_url", url)`      |
| Read a variable with fallback (server → global) | `server.get_variable_value("instance_root")`                    |
| Merge JSON state on a server                    | `server.update_metadata({"build_sha": sha})`                    |
| Replace server state wholesale                  | `server.write({"metadata": {...}})`                             |
| Same for a jet / waypoint                       | `jet.update_metadata({...})`, `waypoint.update_metadata({...})` |
| Read state                                      | `server.metadata`, `jet.metadata`, `waypoint.metadata`          |
| Run a command on a server                       | `server.run_command(cmd_record)`                                |
| Run a plan on a server                          | `server.run_flight_plan(plan_record)`                           |

Use **variables** for human-editable configuration and **metadata** for machine-written
structures. Metadata is read-only in the UI and visible only in developer mode.

`set_variable_value` is on the variable mixin: `server`, `jet`, and `jet_template`.
It returns `None`. Persist on the **Jet** when a later `file_using_template` in this
plan must render the value (hard rule 17). `custom_values` is not enough for files.

### The `tower` helper is mostly deprecated

`tower.server_run_command`, `tower.server_run_flight_plan`,
`tower.server_set_variable_value`, `tower.server_get_variable_value` and
`tower.server_create_from_template` all log a deprecation warning and will be removed.
Documentation examples still show them. Use the models directly instead:

| Deprecated                                       | Use                                                                                         |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `tower.server_run_command(ref, cmd_ref)`         | `tower_servers.get_by_reference(ref).run_command(tower_commands.get_by_reference(cmd_ref))` |
| `tower.server_run_flight_plan(ref, plan_ref)`    | `…get_by_reference(ref).run_flight_plan(tower_plans.get_by_reference(plan_ref))`            |
| `tower.server_set_variable_value(ref, var, val)` | `…get_by_reference(ref).set_variable_value(var, val)`                                       |
| `tower.server_get_variable_value(ref, var)`      | `…get_by_reference(ref).get_variable_value(var)`                                            |
| `tower.server_create_from_template(...)`         | `env["cx.tower.server.template"].create_server_from_template(...)`                          |

Still current and useful:

- `tower.server_check_ssh_connection(server_reference, attempts=5, wait_time=10, try_command=True, try_file=True)`
  → `{"exit_code", "message"}`. The standard "wait for a fresh VM to come up" step.
- `tower.server_validate_secret(secret_value, secret_reference, server_reference=None)`
  → bool.
- `tower.generate_random_id(sections=1, population=4, separator="-")` → readable random
  id.
- `tower.is_valid_url(url, no_scheme_check=False)` → bool.

## Example: create a cloud instance

```python
# Provider token comes from a secret, never from a variable.
api_token = #!cxtower.secret.hetzner_api_token!#

headers = {
    "Authorization": "Bearer " + api_token,
    "Content-Type": "application/json",
}
payload = {
    # Hetzner rejects '_' in names
    "name": server.reference.replace("_", "-"),
    "server_type": {{ hetzner_server_type }}.lower(),
    "image": {{ hetzner_os_image }},
    "location": {{ hetzner_location }}.lower(),
    "public_net": {"enable_ipv4": True},
    "ssh_keys": [server.ssh_key_id.reference.replace("_", "-")]
        if server.ssh_key_id.reference else [],
}

try:
    response = requests.post(
        "https://api.hetzner.cloud/v1/servers",
        headers=headers,
        data=json.dumps(payload),
        timeout=60,
    )
except Exception as e:
    result = {"exit_code": 1, "message": "Request failed: " + str(e)}
else:
    if response.status_code in (200, 201):
        data = response.json()
        server.write({
            "ip_v4_address": data["server"]["public_net"]["ipv4"]["ip"],
            "ssh_password": data["root_password"],
        })
        server.set_variable_value("hetzner_server_id", str(data["server"]["id"]))
        custom_values["_provider_instance_created"] = True
        result = {"exit_code": 0, "message": "Instance created"}
    else:
        result = {"exit_code": response.status_code, "message": response.text}
```

Points worth copying: token from a secret; `timeout` on every request; every failure
path produces a non-zero `exit_code` and a readable message; results persisted where
later steps can find them; a `custom_values` flag for downstream plan lines.

## Fields

Beyond the shared command fields (`name`, `reference`, `note`, `tag_ids`,
`access_level`, `allow_parallel_run`):

- `code` — the Python source.
- `path`, `no_split_for_sudo`, `if_file_exists`, `os_ids` — meaningless here; omit them.
- `server_status` — still works: sets the server's status on success. Useful after a
  provider start/stop call.

## Review checklist

- [ ] `result` is assigned on **every** path, including exception handlers
- [ ] No `import`, no `getattr`/`setattr`, no attribute assignment on records
- [ ] `write()` used for all field updates
- [ ] `{{ variables }}` and `#!cxtower.secret.x!#` are **not** quoted
- [ ] `timeout` on every `requests` call
- [ ] `get_by_reference` used instead of `search`
- [ ] No deprecated `tower.server_*` helpers
- [ ] `custom_values` keys you invent are `_`-prefixed
- [ ] Values a later `file_using_template` must see use `jet.set_variable_value` /
      `server.set_variable_value`, not only `custom_values`
- [ ] `json.dumps(...)` — never `json(...)` or `json.loads` (`json` is dumps-only)
- [ ] Credentials come from secrets, never variables or literals
- [ ] `note` explains what the command does and what it writes
