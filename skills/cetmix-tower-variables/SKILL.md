---
name: cetmix-tower-variables
description:
  Model Cetmix Tower configuration with variables — variable, variable_option and
  variable_value records, the Jet to Jet Template to Server to Global resolution order,
  global vs scoped values, String vs Options types, validation patterns, value
  modifiers, generic vs pythonic rendering, the tower.server / tower.jet / tower.tools
  system variables, custom_values, and when to use metadata instead. Use when deciding
  what should be configurable or when writing variable YAML.
---

# Variables

Three separate models. Confusing them is the most common authoring error.

| Model             | Role                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------ |
| `variable`        | The **definition**: reference, name, type, validation, value modifier. **No value.** |
| `variable_option` | One choice of an Options-type variable                                               |
| `variable_value`  | An **actual value**, scoped by the parent it is attached to                          |

`variable` has no `default_value_char` and no value field of any kind. A default is a
`variable_value` with no owner (a _global_ value).

## Defining a variable

```yaml
- cetmix_tower_model: variable
  reference: request_timeout
  name: Request Timeout
  variable_type: s
  note: Nginx proxy read timeout in seconds.
  validation_pattern: ^[0-9]+$
  validation_message: Must be a whole number of seconds.
```

Options type:

```yaml
- cetmix_tower_model: variable
  reference: odoo_version
  name: Odoo Version
  variable_type: o
  note: Odoo major version used to select images and branches.
  option_ids:
    - reference: odoo_version_18_0
      sequence: 10
      name: "18.0"
      value_char: "18.0"
    - reference: odoo_version_17_0
      sequence: 20
      name: "17.0"
      value_char: "17.0"
```

`variable_option` must be nested under `option_ids` — it has no `variable_id` in YAML.

| Field                | Notes                                                                           |
| -------------------- | ------------------------------------------------------------------------------- |
| `reference`          | The name used in `{{ }}`. `snake_case`, self-explanatory.                       |
| `variable_type`      | `s` = String (**default**, omit it), `o` = Options                              |
| `validation_pattern` | Regex the value must fully satisfy — checked on the **stored** value, see below |
| `validation_message` | Shown when validation fails                                                     |
| `applied_expression` | Value modifier — see below                                                      |
| `access_level`       | Minimum level to see it; values may only be equal or higher                     |
| `tag_ids`, `note`    | Always fill both. `tag_ids` is not optional.                                |

Naming: `request_timeout`, not `var_1`. `redis_data_dir`, not `dir2`.

### `validation_pattern` sees the raw value, not the rendered one

`cx.tower.variable.value` has an `@api.constrains` on `value_char` that runs
`variable._validate_value(value_char)` against the value **exactly as stored**.
Rendering happens later, at run time. So a variable whose values may be composed from
other variables needs a pattern that tolerates `{{ ... }}`, or the import fails:

```yaml
# Rejects 'redis_{{ tower.jet.reference }}' at import time
validation_pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$

# Accepts a literal name or a template that produces one
validation_pattern: '^([a-zA-Z0-9][a-zA-Z0-9_.-]*|.*\{\{.+\}\}.*)$'
```

Either widen the pattern or leave it off — do not add a strict pattern to a variable you
also intend to compose. The pattern is a guard against user typos in the UI, not a
security boundary.

## Setting values

```yaml
# Global default — a top-level variable_value has no owner
- cetmix_tower_model: variable_value
  reference: request_timeout_global
  variable_id: request_timeout
  value_char: "60"
```

```yaml
# Scoped — nested under the owner's variable_value_ids
- cetmix_tower_model: jet_template
  reference: odoo_jet
  name: Odoo
  variable_value_ids:
    - reference: odoo_jet_version_value
      variable_id: odoo_version
      value_char: "18.0"
```

| Field          | Notes                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------- |
| `variable_id`  | The variable this value belongs to                                                             |
| `value_char`   | The value. For Options types set the option's `value_char`; Tower resolves `option_id` itself. |
| `variable_ids` | Computed from `value_char` — other variables used inside this value. Do not hand-maintain.     |
| `required`     | Only honoured on **server templates**: blocks server creation until filled                     |
| `access_level` | Must be equal to or higher than the variable's, never lower                                    |
| `sequence`     | Display order                                                                                  |

Valid owners (via each model's `variable_value_ids`): `server`, `server_template`,
`jet_template`, `jet`, `plan_line_action`. All of them except `jet` can be authored in
YAML — `plan_line_action` lists `variable_value_ids` in its importable fields, so a
post-run action's own values are nested under the action, which is nested under the plan
line (see `cetmix-tower-flight-plan`). Jet-level values are set at runtime only.

## Resolution order

**Jet → Jet Template → Server → Global.** First one found wins. That is the runtime
chain — what a command or plan line sees when it runs on a server or a jet.

`_get_value` walks only the levels present in the calling context, and two contexts
short-circuit entirely:

| Context                                               | Chain                                                                    |
| ----------------------------------------------------- | ------------------------------------------------------------------------ |
| **Jet** (command or plan running on a jet)            | Jet → Jet Template → Server → Global                                     |
| **Jet Template**, no jet                              | Jet Template → Server → Global                                           |
| **Server only** (a command or plan on a bare server)  | Server → Global — **jet-template values are never consulted**            |
| **Server Template** (the create-server wizard)        | Server Template → Global **only** — never a server, never a jet template |
| **Plan Line Action** (a post-run action's own values) | That value alone — **no fallback**, not even to global                   |

Two consequences worth remembering: a plan run on a plain server does **not** pick up a
value you set on a jet template, and a value you expect the server-template wizard to
inherit from a jet template will not appear there either.

Practical consequence: put a value at the **highest level that is still correct**. A
home directory that is `/home/<user>` on 39 of 40 servers is one global value plus one
server override, not 40 server values.

`custom_values` sit above stored values for **SSH commands, Python commands, and
plan-line conditions** for the duration of one flight plan run:
`custom_values["odoo_version"] = "18.0"` in a Python command overrides the resolved
value for those consumers only, and is never persisted.

They do **not** override `file_using_template`. `create_file()` renders from stored
Jet → Template → Server → Global values only (hard rule 17). If a later file template
must see a computed value, persist it first:

```python
jet.set_variable_value("prometheus_datasource_url", url)
```

Persist on the Jet when the file is rendered in a Jet context. A missing stored value
is not an empty string: Jinja prints the literal `None` or `False` and the push still
succeeds. After a file push, read the Tower file or the host file; those literals mean
the variable was not stored at a level `create_file()` can see.

## Composing values

Variable values may reference other variables:

```yaml
- cetmix_tower_model: variable_value
  reference: log_dir_global
  variable_id: log_dir
  value_char: "{{ instance_root }}/logs"
```

Quote any value that starts with `{` — otherwise YAML reads it as a flow mapping.

## Rendering modes

Jinja2, in one of two modes chosen by the consumer:

**Generic mode** — SSH commands, files, file templates. Values substituted raw:

```bash
current_branch={{ branch }}       # current_branch=main
current_version={{ package_version }}   # current_version=0.12
need_update={{ update_available }}       # need_update=False
```

A variable with **no stored value** is `None` in this dict, so generic mode prints the
text `None` (or `False` for a boolean). The file command still returns success.

**Pythonic mode** — Python commands **and flight plan line conditions**. Everything
except booleans and `None` is emitted already wrapped in double quotes:

```python
current_branch = {{ branch }}       # current_branch = "main"
need_update = {{ update_available }}  # need_update = False
```

Never add your own quotes in a Python command or a line condition — `"{{ branch }}"`
renders to `""main""` and is a syntax error. Always add your own quotes where the shell
needs them in an SSH command.

Full Jinja2 works in both — `{% if %}`, `{% for %}`, filters:

```bash
docker run -d -p {{ app_port }}:8069 \
{% if app_workers and app_workers != '0' %}
  --env WORKERS={{ app_workers }} \
{% endif %}
  {{ app_image }}
```

## Value modifier (`applied_expression`)

Python applied to the value **after** rendering, so it does not change what the UI
shows. Available names: `value`, `result`, standard string methods, `re`.

```python
if value.startswith('http'):
    result = value.lower().strip().replace('_', '-').replace(" ", "")
else:
    result = 'https://' + re.sub(r'\s+', '', value)
```

Use it to normalise user input once, centrally — hostnames to lowercase, paths without
trailing slashes — instead of repeating `| lower` in twenty commands.

## The `tower` system variable

Read-only system values, addressed as `tower.<provider>.<property>`. Which providers are
populated depends on the context; missing providers are empty dicts.

| Context                          | `tower.server`        | `tower.jet_template`    | `tower.jet`        | `tower.tools` |
| -------------------------------- | --------------------- | ----------------------- | ------------------ | ------------- |
| Command / value on a **server**  | yes                   | no                      | no                 | yes           |
| Value on a **jet template** only | no                    | yes                     | no                 | yes           |
| Command or plan on a **jet**     | yes (jet's server)    | yes                     | yes                | yes           |
| Files and file templates         | if linked to a server | if linked to a template | if linked to a jet | yes           |

`tower.server`: `name`, `reference`, `username`, `partner_name`, `ipv4`, `ipv6`,
`status`, `os`, `url`, `hostname`, `netloc`, `port`

`tower.jet_template`: `name`, `reference`

`tower.jet`: `name`, `reference`, `url`, `state`, `cloned_from`, `hostname`, `netloc`,
`port`, `waypoint.reference`, `waypoint.type`, `waypoint.<metadata_key>`

`waypoint.*` is the **current** waypoint (`jet.waypoint_id`). During a Create plan it
renders as the string `False`. Use `{{ __waypoint }}` instead — see
`cetmix-tower-waypoints`.

`tower.tools`: `uuid`, `today` (`2026-02-28`), `now` (`2026-02-28 21:58:31`),
`today_underscore`, `now_underscore`

Only reference providers that exist in your context — `tower.jet.name` is empty in a
server-only command. Never define a variable called `tower`.

## Variable, secret, or metadata?

| Use                                        | For                                              | Example                                           |
| ------------------------------------------ | ------------------------------------------------ | ------------------------------------------------- |
| **Variable**                               | Human-editable config, safe in logs and previews | `odoo_version`, `redis_port`, `instance_root`     |
| **Secret** (`key`)                         | Anything sensitive                               | tokens, passwords, private keys                   |
| **Metadata** (JSON on server/jet/waypoint) | Machine-written state and complex structures     | build digests, backup file lists, monitoring data |
| **`custom_values`**                        | Transient values inside one plan run for SSH, Python, and conditions — **not** files | `_is_ubuntu_latest`, computed flags |

Variable values appear verbatim in command previews and logs. A GitHub token in a
variable is a leak. Use a `key` — see `cetmix-tower-secrets`.

## Review checklist

- [ ] Every `{{ x }}` used anywhere has a `variable` record with `reference: x`
- [ ] No `default_value_char` — defaults are global `variable_value` records
- [ ] `variable_option` nested under `option_ids`
- [ ] Options-type values set `value_char` to an existing option's `value_char`
- [ ] Values placed at the highest correct level
- [ ] Value access level ≥ variable access level
- [ ] Values starting with `{` are quoted in YAML
- [ ] Nothing sensitive stored as a variable
- [ ] References are readable (`request_timeout`, not `var_1`)
- [ ] `note` filled in on every variable
- [ ] `tag_ids` filled in on every variable
- [ ] Values a later `file_using_template` must see are persisted with
      `set_variable_value`, not only `custom_values` (hard rule 17)
- [ ] Only context-valid `tower.*` providers referenced
