---
name: cetmix-tower-files
description:
  Manage remote files with Cetmix Tower — file_template and file records, tower vs
  server source, text vs binary, server_dir and file_name with variables, rendering
  content with variables and secrets, the file_using_template command action with
  if_file_exists and disconnect_file, auto sync, and using files as server logs. Use
  whenever a configuration file, script or log has to be pushed to or fetched from a
  host.
---

# Files and file templates

Never write a long config file inside command code. Put it in a **File Template** and
push it with a command.

| Model           | Role                                                                                                                          |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `file_template` | The blueprint: target directory, filename, content with variables and secrets. Editing it updates every file created from it. |
| `file`          | A concrete file on a specific server.                                                                                         |

Author **templates**. `file.server_id` is not importable, so an imported `file` record
is not attached to any server — let Tower create files from templates instead.

## File template

```yaml
- cetmix_tower_model: file_template
  reference: redis_conf
  name: Redis configuration
  source: tower
  file_type: text
  server_dir: "{{ redis_data_dir }}/conf"
  file_name: redis.conf
  keep_when_deleted: false
  tag_ids: [redis]
  note: redis.conf rendered from Tower variables and the redis_password secret.
  code: |
    bind 0.0.0.0
    port 6379
    requirepass #!cxtower.secret.redis_password!#
    appendonly yes
    dir /data
```

| Field                         | Notes                                                                                                      |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `name`                        | Human-readable template name                                                                               |
| `source`                      | `tower` = authored here, pushed to the host. `server` = fetched from the host (logs). **Default `tower`.** |
| `file_type`                   | `text` (**default**) or `binary`                                                                           |
| `server_dir`                  | Directory on the host. Supports variables. **Quote values starting with `{`.**                             |
| `file_name`                   | Filename on the host. Supports variables, e.g. `odoo_{{ odoo_version }}.conf`.                             |
| `keep_when_deleted`           | If `true`, the file survives on the host when the Tower record is deleted                                  |
| `code`                        | Content. Supports variables (generic mode) and secrets.                                                    |
| `variable_ids` / `secret_ids` | Computed from `code`. Do not hand-maintain.                                                                |
| `tag_ids`, `note`             | Fill both                                                                                                  |

`server_dir` must exist on the host — create it with an `mkdir -p` command earlier in
the plan. Tower will not create parent directories for you.

### Not every config format accepts comments

A `# Managed by Cetmix Tower` header is the natural provenance note, and most file
templates in this repo carry one. Strict parsers reject it. A Redis ACL file accepts
only `user …` lines and blanks; the header makes Redis abort at startup:

```
Aborting Redis startup because of ACL errors:
/etc/redis/users.acl:1 should start with user keyword followed by the username
```

Leave the header off for Redis ACL, some `authorized_keys`-style files, and INI-strict
formats. Put the provenance in the file template's `note` — it is visible in Tower and
cannot break the host.

## Pushing a file

Use a command with `action: file_using_template`. It is only available **inside a flight
plan**, not in the ad-hoc run wizard.

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

| Field              | Notes                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------- |
| `file_template_id` | The template to render                                                                                    |
| `if_file_exists`   | `skip` (**default**), `overwrite`, `raise`                                                                |
| `disconnect_file`  | If `true`, unlinks the created file from its template afterwards, so later template edits do not touch it |

**`path` overrides the template's `server_dir`** — a stray `path` silently writes the
file somewhere unintended, so leave it empty on `file_using_template` commands unless
you mean to override. The precedence rule, the `if_file_exists` outcomes and the
transfer exit codes live once in **`cetmix-tower-command-actions` →
`file_using_template`**; this skill covers the template side.

For a config file that must reflect current variable values on every deploy, use
`overwrite`. For a file the operator is expected to hand-edit, use `skip`, or
`overwrite` plus `disconnect_file: true` on first creation.

The push runs as the server's SSH user. File operations use those credentials, so the
user needs write access to `server_dir` — including when the surrounding command uses
sudo. If the target directory is root-owned, create it and `chown` it to the SSH user in
earlier plan lines.

### `custom_values` are ignored (hard rule 17)

`create_file()` takes `server` and `jet`. It does not receive the plan run's
`variable_values` / `custom_values`. A Python command that only assigns
`custom_values["prometheus_datasource_url"] = url` still leaves the uploaded file with
`url: None` unless `jet.set_variable_value(...)` (or `server.set_variable_value`) ran
first.

### A successful push is not valid content

A variable with no stored value renders as the literal text `None` or `False`. The
command still returns success.

Status `0` with _"File created and uploaded successfully"_ also does not prove the
file is on the host. When `cetmix_tower_server_queue` is installed, `upload()` is
enqueued (`with_delay`) and `file_using_template` logs success as soon as the job
is queued — the next plan line can run before the file exists. That queued upload
uses `raise_error=False`, so a later job failure does not fail the plan line
either.

After a push, read the host file. That check also catches a push that never landed.
Do not put `chmod`, `stat` or `md5sum` of the just-pushed path on the immediately
following plan line. Inspect it from a later line or a later plan.

### A pushed file is not “the app applied the config”

`file_using_template` updates disk. It does not update an application's internal
database, and Restart does not always re-read the file. If the process only applies a
setting on first init (empty DB, first start), Start / Restart / Rebuild must include a
command that applies it.

`--env-file` on `docker create` is read at **create** time. Changing that file later
does nothing until Rebuild runs `docker create` again. Restart is not enough. See
`cetmix-tower-command-ssh`.

## Fetching a file

`source: server` templates and files pull content **from** the host into Tower. Typical
use is logs:

```yaml
- cetmix_tower_model: file_template
  reference: app_log
  name: Application log
  source: server
  file_type: text
  server_dir: /var/log/myapp
  file_name: app.log
  note: Fetched from the host for the Server Log view.
```

`code` is meaningless for `source: server` — Tower drops it on export.

## Files as server logs

Wire a file into a `server_log` so it shows up in the Server or Jet form:

```yaml
- cetmix_tower_model: server_template
  reference: app_server_template
  name: App Server
  server_log_ids:
    - reference: app_server_log_file
      name: Application log
      log_type: file
      file_template_id: app_log
```

On a **server template** use `file_template_id` (files are created per server); on an
existing **server** use `file_id`. See `cetmix-tower-servers`.

## Auto sync

`file` records support `auto_sync` with `auto_sync_interval` — one of `10-minutes`,
`30-minutes`, `1-hours`, `2-hours`, `6-hours`, `12-hours`, `1-days`, `1-weeks`,
`1-months`, `1-years`. Only meaningful with `source: tower`: the file is re-uploaded
after it changes in Tower. Since `file` records are not usefully importable, this is
normally configured in the UI.

## Binary files

`file_type: binary` stores content in the `file` field as base64. Do not embed large
binaries in YAML — fetch them on the host with a command instead.

## Review checklist

- [ ] Long content lives in a `file_template`, not in command `code`
- [ ] `server_dir` quoted when it starts with `{`
- [ ] A preceding command creates `server_dir` with `mkdir -p`
- [ ] The SSH user can write to `server_dir`
- [ ] `if_file_exists` chosen deliberately
- [ ] Credentials inside content use `#!cxtower.secret.X!#`, with matching `key` records
- [ ] Every `{{ variable }}` in `code`, `server_dir` and `file_name` has a `variable`
      record
- [ ] `file_using_template` commands are only used inside plans
- [ ] Values the template must see are stored on the jet/server before the push (hard
      rule 17); `custom_values` alone is not enough
- [ ] After the first run, the host file is read (exists, and no literal `None` /
      `False`); do not `chmod` / `stat` it on the next plan line
- [ ] `source` and `file_type` correct for the direction of travel
- [ ] `note` filled in, and used instead of a content header when the format rejects
      comments
