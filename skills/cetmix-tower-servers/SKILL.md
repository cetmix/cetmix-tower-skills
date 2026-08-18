---
name: cetmix-tower-servers
description:
  Define Cetmix Tower hosts and their supporting records — server and server_template
  (SSH settings, use_sudo, variables, required values, creation and deletion plans),
  server_log for log views, shortcut for one-click actions, os for OS scoping, and tag
  for classification. Use when provisioning servers, building a server template, or
  adding logs and shortcuts to a host.
---

# Servers and supporting records

## Server

A managed host. Rarely authored by hand — usually created from a template or by a
provider API — but importable for bootstrapping.

```yaml
- cetmix_tower_model: server
  reference: prod_web_1
  name: Production Web 1
  ip_v4_address: 203.0.113.10
  os_id: ubuntu_2404
  ssh_username: tower
  ssh_port: 22
  ssh_auth_mode: k
  ssh_key_id: production_ssh_key
  use_sudo: n
  tag_ids: [production]
  note: Front-end web host. Managed by Tower; do not configure by hand.
```

| Field                                                                                      | Notes                                                                                                                                                                                             |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ip_v4_address` / `ip_v6_address`                                                          | IP or hostname without a protocol (`pepe.meme.com`). IPv6 is used when IPv4 is unset.                                                                                                             |
| `ssh_auth_mode`                                                                            | `p` = password, `k` = key (**default `p`**)                                                                                                                                                       |
| `ssh_key_id`                                                                               | A `key` record with `key_type: k`; required for `ssh_auth_mode: k`                                                                                                                                |
| `use_sudo`                                                                                 | Selection: `n` = sudo without password, `p` = sudo with password, empty = no sudo. On `plan_line`, `shortcut` and `server_log` the same-named field is a **Boolean** — never write `n`/`p` there. |
| `skip_host_key`                                                                            | Skips host-key verification. Leaves the connection open to MITM — do not set it by default.                                                                                                       |
| `os_id`                                                                                    | Used to warn when a command is run on an OS it was not written for                                                                                                                                |
| `plan_delete_id`                                                                           | Plan run **before** the server is deleted                                                                                                                                                         |
| `url`                                                                                      | Web interface URL; feeds `tower.server.hostname` / `netloc` / `port`                                                                                                                              |
| `variable_value_ids`, `secret_ids`, `server_log_ids`, `shortcut_ids`, `scheduled_task_ids` | Nested children                                                                                                                                                                                   |

**`ssh_password` is not importable.** A server imported with `ssh_auth_mode: p` needs
its password entered in the UI. Prefer key authentication.

`status` is not importable either. Set it from commands (`command.server_status`),
Python code, or an API. Values: `stopped`, `starting`, `running`, `stopping`,
`restarting`, `deleting`, `delete_error`. Read it back as `tower.server.status`.

## Server template

The right way to define hosts: preconfigured SSH settings, default variables and a plan
that runs after creation.

```yaml
- cetmix_tower_model: server_template
  reference: web_server_template
  name: Web Server
  color: 1
  os_id: ubuntu_2404
  ssh_username: tower
  ssh_port: 22
  ssh_auth_mode: k
  ssh_key_id: production_ssh_key
  use_sudo: n
  tag_ids: [production]
  note: Ubuntu 24.04 web host with Docker and UFW.
  flight_plan_id: provision_web_server
  plan_delete_id: decommission_web_server
  variable_value_ids:
    - reference: web_server_template_instance_root
      variable_id: instance_root
      value_char: /opt/app
    - reference: web_server_template_domain
      variable_id: domain_name
      value_char: false
      required: true
  server_log_ids:
    - reference: web_server_template_nginx_log
      name: Nginx error log
      log_type: file
      file_template_id: nginx_error_log
  shortcut_ids:
    - reference: web_server_template_restart_nginx
      name: Restart Nginx
      sequence: 10
      access_level: user
      action: command
      command_id: restart_nginx
      use_sudo: true
      note: Restarts Nginx without needing Manager access.
```

- `flight_plan_id` runs **after** a server is created from the template — this is where
  provisioning happens.
- `plan_delete_id` runs **before** deletion — deprovision cloud resources here.
- `required: true` on a `variable_value` **blocks server creation** until the value is
  filled. Use it for values that cannot have a sensible default, like a domain name.
- `server_log_ids`, `shortcut_ids` and `scheduled_task_ids` are copied onto every new
  server.

Server templates are Manager-and-above only; Users have no access.

## Server log

A log view on the Server or Jet form. Must be **nested** (`server_log` has no
`server_id` in YAML).

```yaml
server_log_ids:
  # From a command's output
  - reference: app_container_log
    name: Container log
    log_type: command
    command_id: tail_app_container_log
    use_sudo: true
  # From a file
  - reference: app_file_log
    name: Application log
    log_type: file
    file_template_id: app_log_template
```

- `log_type: command` → set `command_id` (and `use_sudo` if needed). The command must be
  `ssh_command` or `python_code`, and **must tolerate parallel execution** — several
  people may open the log at once. Set `allow_parallel_run: true` on it.
- `log_type: file` → on a **server** use `file_id`; on a **server template** use
  `file_template_id`, so a file is created per server.

Log output supports HTML; a custom formatter can be added by overriding
`_format_log_text()` on `cx.tower.server.log`.

Valid parents: `server`, `server_template`, `jet_template`.

## Shortcut

A one-click button on the server form. Must be nested under `shortcut_ids`.

```yaml
shortcut_ids:
  - reference: deploy_app_shortcut
    name: Deploy application
    sequence: 10
    access_level: user
    action: plan
    plan_id: deploy_app
    note: Full application deploy. Takes about two minutes.
```

| Field          | Notes                                                                         |
| -------------- | ----------------------------------------------------------------------------- |
| `action`       | `command` (set `command_id`, optionally `use_sudo`) or `plan` (set `plan_id`) |
| `sequence`     | Position on the form; lower is higher                                         |
| `access_level` | **Overrides** the target's access level                                       |
| `note`         | Shown when the shortcut is clicked — use it as the operator's instruction     |

The access-level override is the point: it lets a User run a Manager-level plan through
a vetted button without granting broader rights. That also makes it a
privilege-escalation surface — only lower the level for actions that are safe in a
User's hands, and never for anything destructive.

## OS

```yaml
- cetmix_tower_model: os
  reference: ubuntu_2404
  name: Ubuntu 24.04
  color: 2
  parent_id: ubuntu
```

`parent_id` points at the previous version, forming a version history. Set `os_ids` on
commands whose syntax is distribution-specific. It is **advisory only** — Tower warns in
the run wizard but never blocks. Never rely on it for correctness; branch on
`tower.server.os` or a Python check instead.

## Tag

```yaml
- cetmix_tower_model: tag
  reference: production
  name: Production
  color: 2
```

`color` is 0–10. Tags are shared across all entity types. Tag by technology and by role:
a plan that starts a Dockerised Jet gets `Jets` and `Docker`.

Tags, OSes, variables, variable options and keys are always resolved to existing records
rather than duplicated, even in "Create a new record" import mode. Referencing an
existing tag by reference is safe. Under a `server` the same protection covers `plan`,
`shortcut`, `scheduled_task` and `command` (plus `file` with `cetmix_tower_git`); under
a `server_template` it covers `plan`, `shortcut` and `scheduled_task` — **not**
`command`.

## Access levels in short

| Level     | Roughly                                                                        |
| --------- | ------------------------------------------------------------------------------ |
| `user`    | Read what they are listed on; run User-level commands and plans; no key access |
| `manager` | Create and update most records; read secrets; own what they created            |
| `root`    | Everything                                                                     |

Access **roles** (`user_ids` / `manager_ids`) are not importable — only `access_level`
is. Tell the user which roles to set after import.

## Review checklist

- [ ] `server_log`, `shortcut` and `scheduled_task` nested, never top-level
- [ ] `ssh_key_id` set when `ssh_auth_mode: k`; the `key` record has `key_type: k`
- [ ] `skip_host_key` left `false`
- [ ] Password-auth servers flagged to the user (no YAML path for the password)
- [ ] Commands used by `log_type: command` have `allow_parallel_run: true`
- [ ] `file_template_id` on templates, `file_id` on servers
- [ ] `required: true` on template values with no sensible default
- [ ] Shortcut access-level overrides justified and never destructive
- [ ] `os_ids` treated as advisory, not as a guard
- [ ] `note` on servers, templates and shortcuts
