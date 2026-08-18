---
name: cetmix-tower-automation
description:
  Trigger Cetmix Tower work without a human click — scheduled_task records for
  interval-based runs of commands or flight plans on servers and jets, webhook and
  webhook_authenticator records for inbound HTTP triggers with their result contracts
  and IP allowlists, and git_project / git_source / git_remote for repository
  definitions. Use when something must run on a schedule, be triggered by an external
  system, or track git sources.
---

# Automation

## Scheduled tasks

Runs a command or a flight plan on selected servers and jets on an interval. A system
cron picks up due tasks; the form also has **Run Manually**.

`scheduled_task` has no server or jet link in YAML, so it **must be nested** under
`server.scheduled_task_ids`, `server_template.scheduled_task_ids` or
`jet_template.scheduled_task_ids`.

```yaml
- cetmix_tower_model: jet_template
  reference: redis_jet
  name: Redis (Docker)
  scheduled_task_ids:
    - reference: redis_nightly_snapshot
      name: Nightly snapshot
      sequence: 10
      action: plan
      plan_id: redis_snapshot_create
      interval_number: 1
      interval_type: days
      next_call: 2027-01-01 02:00:00 # a real future datetime — a past one fires at once
```

| Field                       | Notes                                                                                                                                                                                              |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `action`                    | `command` (set `command_id`) or `plan` (set `plan_id`)                                                                                                                                             |
| `interval_number`           | Must be > 0                                                                                                                                                                                        |
| `interval_type`             | `minutes` `hours` `days` `dow` `weeks` `months` (**default `months`**)                                                                                                                             |
| `monday`…`sunday`           | Booleans; with `interval_type: dow` at least one must be `true`                                                                                                                                    |
| `next_call`                 | First due datetime. `required=True`, `default=now` — omit it and the task is **due immediately**. Set a future datetime unless that is what you want, and never copy a past one out of an example. |
| `last_call`                 | Runtime value; do not author it                                                                                                                                                                    |
| `custom_variable_value_ids` | `scheduled_task_cv` records overriding variables for this task only                                                                                                                                |

Attachment semantics differ by parent:

- On a **server** or **jet**: the task runs on that server/jet.
- On a **server template** or **jet template**: the task is **copied onto every new**
  server/jet created from it. It does not run on the template itself.

Task interval shorter than the system cron interval → the task runs later than
configured, and the form warns about it. Do not schedule a 1-minute task.

`scheduled_task_cv` carries only `variable_value_id`; the rest (`name`, `variable_id`,
`option_id`, `value_char`) is copied from the linked variable value on import.

Guidance:

- The target command or plan must be safe to run unattended: non-interactive,
  idempotent, and with a deliberate `on_error_action`.
- Set `allow_parallel_run: false` on anything stateful, so a slow run cannot overlap the
  next tick.
- Prefer scheduling a **plan** over a command — you get per-step error handling.
- Logs land in Command Logs or the plan log, linked to the task.

## Webhooks

An HTTP endpoint that runs Python code. **Root-only**, both the menu and the records.

URL: `<tower_url>/cetmix_tower_webhooks/<endpoint>`

```yaml
- cetmix_tower_model: webhook_authenticator
  reference: deploy_api_key_auth
  name: Deploy API key
  allowed_ip_addresses: 203.0.113.0/24,2001:db8::/32
  code: |
    provided = (headers or {}).get("X-Api-Key")
    expected = #!cxtower.secret.deploy_webhook_key!#
    if provided and hmac.compare_digest(provided, expected):
        result = {"allowed": True}
    else:
        result = {"allowed": False, "http_code": 401, "message": "Invalid API key"}

- cetmix_tower_model: webhook
  reference: deploy_webhook
  name: Trigger deploy
  active: true
  authenticator_id: deploy_api_key_auth
  endpoint: deploy/app
  method: post
  content_type: json
  code: |
    server = tower_servers.get_by_reference(payload.get("server", ""))
    if not server:
        result = {"exit_code": 1, "message": "Unknown server"}
    else:
        plan = tower_plans.get_by_reference("deploy_app")
        server.run_flight_plan(plan)
        result = {"exit_code": 0, "message": "Deploy started"}
```

### Webhook fields

| Field                         | Notes                                                                                                               |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `endpoint`                    | Path segment. Must start and end with a letter or digit; letters, digits, `_`, `-`, `/` allowed. Unique per method. |
| `method`                      | `post` (**default**) or `get`; the request method must match                                                        |
| `content_type`                | `json` (**default**) or `form`; how a POST body is parsed. Irrelevant for GET.                                      |
| `authenticator_id`            | **Required**                                                                                                        |
| `active`                      | `false` → the URL returns 404                                                                                       |
| `code`                        | Python, same sandbox as Python commands                                                                             |
| `variable_ids` / `secret_ids` | Computed from `code`                                                                                                |

The "Run as User" field is `user_id` — there is **no** `run_as_user_id` field, so
writing that name over the API silently does nothing. `user_id` is `required=True` and
defaults to `SUPERUSER_ID` (Administrator); execution runs
`self.with_user(self.user_id)`. It is **not importable** and must be set in the UI. Say
so in the handover; a webhook running as Administrator is a large blast radius.

### Result contracts

Webhook code must set `result` with `exit_code` (0 = success) and `message`. Default is
`{"exit_code": 0, "message": None}`.

Authenticator code must set `result` with `allowed` (bool), optionally `http_code` and
`message`. **Default is `{"allowed": False}`** — fail-closed, so an authenticator whose
code forgets to set `result` denies everything.

Both run through `safe_eval`, so the restrictions from `cetmix-tower-command-python`
apply: no `import`, no attribute assignment, use `write()`. `server` is **not** in the
webhook context — resolve it from the payload with `get_by_reference`. Secrets in
`message` are masked before logging.

### Authenticator fields

| Field                  | Notes                                                                    |
| ---------------------- | ------------------------------------------------------------------------ |
| `allowed_ip_addresses` | Comma-separated IPs and CIDRs, IPv4 and IPv6. **Empty means allow all.** |
| `trusted_proxy_ips`    | Comma-separated; needed behind a reverse proxy for the real client IP    |
| `code`                 | Custom auth on top of the IP check                                       |

Security rules:

- Never leave `allowed_ip_addresses` empty on a webhook that changes anything.
- Compare shared secrets with `hmac.compare_digest`, never `==`.
- For provider webhooks (GitHub and similar), verify the HMAC signature over `raw_data`
  rather than trusting a token in the payload.
- Keep the shared secret in a `key`, never in a variable.
- Validate every payload field before use — the payload is attacker-controlled.

Authenticator context: `headers`, `raw_data` (bytes), `payload`. Webhook context:
`payload`, `headers`.

Working examples for API-key and GitHub authentication exist in the
`cetmix-tower-packages` repository (`cx_webhook_authenticator_api_key`,
`cx_webhook_authenticator_github`, `cx_webhook_github`) — read them before writing one.

## Git projects

Repository definitions that render into files (e.g. git-aggregator format), used to
drive source checkouts on hosts.

| Model             | Placement                                   | Fields                                                        |
| ----------------- | ------------------------------------------- | ------------------------------------------------------------- |
| `git_project`     | top-level                                   | `name`, `note`, `source_ids`, `git_aggregator_root_dir`       |
| `git_source`      | nest under `source_ids`                     | `name`, `enabled`, `sequence`, `remote_ids`                   |
| `git_remote`      | nest under `remote_ids`                     | `name`, `enabled`, `sequence`, `repo_id`, `head`, `head_type` |
| `git_repo`        | top-level                                   | `url`, `is_private`, `secret_id`                              |
| `git_repo_owner`  | top-level                                   | `display_name`, `name`, `secret_id`                           |
| `git_project_rel` | **nest** under `server.git_project_rel_ids` | `file_id`, `git_project_id`, `project_format`, `auto_sync`    |

`head_type`: `branch` · `pr` · `commit`. `project_format`: `git_aggregator`.

`git_project_rel` must be nested: `server_id` is `required=True` on the model but is
**not** in its YAML field list, so a top-level record has no way to satisfy the owner
link and the import fails. `server.git_project_rel_ids` is added by `cetmix_tower_git`
and is the only importable path. `file_id` and `git_project_id` are required too, and
`file_id`'s file must belong to the same server (`_check_server_file_relation`).

The Git module also adds `git_project_id` and `is_make_copy` to `plan_line`, and these
have a side effect that lives only in `cetmix_tower_git`'s `cx.tower.server` override:
when a `file_using_template` line runs, the created file is linked to a Git project by
creating a `cx.tower.git.project.rel` for `(server, file, project)`. The project comes
from the line's `git_project_id`, or from `custom_values["__git_project__"]` (a project
_reference_), which wins when set. An unresolvable `__git_project__` reference only logs
a warning and leaves the file unlinked. With `is_make_copy` the project is **copied**
per server first, so each server gets its own project record.

Computed fields to know about. `git_repo_owner.reference` is a stored compute on `name`
with no guard, so an authored `reference:` is silently overwritten and the owner will
not round-trip. `git_repo.reference` behaves the same way: it is computed from `name`
(`host/owner/repo`), and those three come from the `url` you author, so the repo
reference follows the URL and an authored one is discarded. `git_repo.name` is not
importable at all. `git_remote.name` is computed as `remote_<n>` from position, so
authoring it does nothing.

**The documentation page for Git is out of date** — it shows `url`, `is_private` and
`repo_provider` on `git_remote`, but the URL and privacy flag now live on `git_repo`.
Read `cetmix_tower_git/models/*.py` before authoring Git YAML, and tell the user you
did.

## Choosing a trigger

| Need                                       | Use                                                        |
| ------------------------------------------ | ---------------------------------------------------------- |
| Operator presses a button on a server      | `shortcut`                                                 |
| Runs on a clock                            | `scheduled_task`                                           |
| External system pushes an event            | `webhook`                                                  |
| Another Jet's state changes                | command with `action: jet_action` inside that Jet's plan   |
| After a server is created                  | `server_template.flight_plan_id`                           |
| Before a server is deleted                 | `server.plan_delete_id` / `server_template.plan_delete_id` |
| When a Jet template is installed on a host | `jet_template.plan_install_id`                             |

## Review checklist

- [ ] `scheduled_task` and `scheduled_task_cv` nested, never top-level
- [ ] `next_call` set explicitly to a **future** datetime (omitted or past ⇒ due at
      once)
- [ ] `interval_type: dow` has at least one weekday `true`
- [ ] Interval not shorter than the system cron interval
- [ ] Scheduled target is non-interactive and idempotent, with
      `allow_parallel_run: false`
- [ ] Webhook has an `authenticator_id`
- [ ] `allowed_ip_addresses` non-empty for any state-changing webhook
- [ ] `trusted_proxy_ips` set if Tower sits behind a proxy
- [ ] Authenticator `result` sets `allowed` on every path
- [ ] Secret comparison uses `hmac.compare_digest`
- [ ] Payload fields validated before use
- [ ] Webhook `user_id` ("Run as User") flagged to the user — it defaults to
      Administrator
- [ ] Git YAML checked against the module source, not the docs page
