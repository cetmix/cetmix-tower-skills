# Decision guide

Answer these in order. Each answer narrows the set of entities you need.

---

## 1. Jet Template, or plain Flight Plan?

This is the biggest fork. It decides whether you deliver ~3 records or ~30.

**Use a plain Flight Plan (+ commands) when the work is a one-shot action on a host.**

- Host-level provisioning: install a firewall, update packages, add a swap file, harden
  SSH, install Docker.
- Maintenance run against something that already exists: vacuum a database, rotate logs,
  take a backup, restore a backup, reload nginx.
- There is nothing to start, stop or destroy afterwards — or the OS service manager
  already owns that.
- Only ever one of it per server.
- The user wants to trigger it manually, from a shortcut, or on a schedule.

**Use a Jet Template when you are deploying a managed application instance.**

- It has a lifecycle: prepare → build → start → stop → remove → destroy.
- The user will want to start/stop/restart it from the UI.
- More than one instance may live on the same server (dev + staging Redis; several
  WordPress sites), each with its own configuration.
- It needs snapshots/backups you can roll back to → Waypoints.
- It depends on other services being up → template dependencies.
- It has a URL, a state, per-instance variables.

**Litmus test.** Ask: _"after this finishes, is there a thing whose state someone will
want to see and change?"_ Yes → Jet Template. No → Flight Plan.

**When the user asks for a flight plan but describes a lifecycle**, deliver the flight
plan they asked for, and say in one sentence that a Jet Template would give them
start/stop/backup for the same commands — do not silently substitute.

Note that this is not either/or: a Jet Template _is_ a set of flight plans wired to
state transitions. Plans written for a Jet action are reusable as standalone plans and
vice versa, so nothing is wasted if the shape changes later.

---

## 2. Atomized or monolithic Jet Templates?

Only relevant once you have chosen Jets.

**Atomized** — separate templates for database, proxy, application; wired with
`template_requires_ids`.

- Choose when the components are shared (one Traefik for many apps), have different
  lifecycles or owners, or you are building a reusable template library.
- Costs: the user creates several Jets, must understand deployment order, and cross-Jet
  networking is more work.

**Monolithic** — one template deploys the whole stack (e.g. one Compose project with
proxy + DB + app).

- Choose for single-server stacks, demos, POCs, and when ease of onboarding matters more
  than reuse.
- Costs: no component reuse, upgrades redeploy everything.

Default to **monolithic** for a first deployment of a self-contained app, and to
**atomized** when the user already runs shared infrastructure. State your choice and why
in the manifest `description`.

---

## 3. One command, or several?

**Always several.** One Tower command = one statement. This is a hard rule, not a
preference, and the reasons are concrete:

- **Reuse.** `apt-get update` as its own command is used by every plan you ever write.
- **sudo correctness.** When a command containing `&&` is run with _sudo-with-password_,
  Tower splits on `&&` and runs the parts one by one. A command that relies on shell
  chaining will behave differently than you expect. (`no_split_for_sudo: true` plus a
  justification in `note` is the escape hatch for idempotency guards, wait loops and
  capture-and-branch — see `cetmix-tower-command-ssh`.) `;` and `||` are not split —
  they stay joined under one `sudo` and one opaque exit code, so they are still banned,
  just for a different reason.
- **Flow control.** Exit codes and _post-run actions_ are per line. A joined command
  gives you one opaque exit code and no way to branch.
- **Readable logs.** Each line is logged separately, so a failure points at one step.
- **Paths.** `cd x && y` is replaced by the line's `path` field, which Tower applies
  correctly for both plain and sudo execution.

**Group upward, not sideways.** When a sequence of lines recurs across plans, extract it
into its own plan and call it from the parent with a command whose `action: plan` and
`flight_plan_id: <sub_plan>`. This is how "install Docker" gets reused by every stack.

**Granularity guide.** One command per: package install, directory creation, file push,
container create, container start, service enable, single SQL statement, single API
call. If you are tempted to write a 30-line heredoc, that content belongs in a **File
Template**, not in command code.

---

## 4. SSH command, or Python command?

They are different actions on the same `command` model. Pick by _where the work runs_.

**`action: ssh_command` — runs on the remote host over SSH.** Use for anything that
touches the host: packages, files, containers, services, permissions, local CLI tools.

**`action: python_code` — runs inside Tower/Odoo, not on the host.** Use for:

- **Provider and third-party APIs** — create a cloud VM, set a DNS record, call a
  webhook, query a registry. `requests` is available; you get structured error handling
  and a real exit code instead of parsing `curl` output.
- **Reading/writing Tower data** — set variable values, write `server.metadata` /
  `jet.metadata` / `waypoint.metadata`, look up records by reference.
- **Flow control inside a plan** — inspect state and set `custom_values["_flag"]`, which
  later plan lines test in their `condition`.
- **Validation and reporting** — check a URL is live, compare versions, decide whether a
  later step is needed.

**Do not:**

- Use a Python command to shell out to the host. That is what SSH commands are for, and
  `safe_eval` blocks most of what you would need anyway.
- Use an SSH command with `curl` to call an API when the result must drive Tower logic —
  you would have to parse stdout. Use a Python command.
- Put credentials in either one. Use secrets (`#!cxtower.secret.ref!#`), which are
  masked in previews and logs.

**Typical composition for a cloud deployment:**

1. Python command — call the provider API, create the instance, write the IP and root
   password onto the server record, store the provider id in a variable.
2. Python command — `server_check_ssh_connection`-style wait loop until SSH answers.
3. SSH commands — install and configure everything on the host.
4. Python command — `jet.set_variable_value(...)` (or `server.set_variable_value`) for
   any value a later file template must see. `custom_values` is not enough (hard
   rule 17).
5. `file_using_template` command — push the rendered config file.
6. SSH commands — start the service. Recreate the container (`docker create`) if the
   file is consumed as `--env-file` or another create-time input; Restart does not
   re-read it.
7. Python command — verify, set status, report.

---

## 5. How is the work delivered — YAML file, API, or UI?

Ask the user, or follow the project's established practice. All three are first-class;
they differ in who runs them and what you must handle yourself.

**A. YAML file, imported by a person.** Reproducible, reviewable, diffable, portable
between instances. The right deliverable when a human will apply the change, or when the
result belongs in version control. Import via `Cetmix Tower > Tools > Import YAML`.

**B. YAML built by code and imported over the API.** Fully programmatic while still
using the importer, so you keep reference resolution, deduplication by reference,
`access_level` translation, deferred forward references, the safe contexts and a single
savepoint. **For bulk entity creation from code this is usually the best path.** Drive
`cx.tower.yaml.import.wiz.upload` then `cx.tower.yaml.import.wiz`.

**C. Direct ORM create/write over the API** (XML-RPC / JSON-RPC `execute_kw`, or Python
inside Odoo). Necessary for reads, updates, queries and every _operation_ — running
commands and plans, triggering jet actions, installing templates. It also reaches fields
YAML cannot carry (`server_ids` on a command, `ssh_password`, access roles, `server_id`
on a file). The cost is that you reproduce the importer's work by hand and your call
sequence is not atomic.

**D. Build in the UI** when the user is exploring or the change is one field. Then
export YAML from the record's _YAML_ tab and commit it.

If the project drives Tower from code, **B and C together** are the normal answer: B to
create configuration, C to operate it and to set what YAML cannot. Read
`cetmix-tower-api/SKILL.md` before writing either — the differences from YAML (model
names, `access_level` as `"1"`/`"2"`/`"3"`, command tuples, the `from_yaml` and
`skip_ssh_settings_check` contexts, per-model access rights) are where integrations
break.

**Do not import a YAML file onto an instance that already has the same logical
templates** (created via the API, possibly under different command/plan references).
Skip creates unused duplicate plans; update duplicates `plan_line`s and cannot rewrite
`template_requires_ids`. Edit the existing records over the API (path C). Keep the YAML
as a portable copy for empty databases and other instances (hard rule 14).

Note: the _YAML tab_ on a record is an inverse field, so a user or an API caller with
import rights can update a single record by writing `yaml_code` — a fourth, narrower
hybrid.

---

## 6. Variable, Secret, or metadata?

| Store it as                                | When                                                                 | Example                                                          |
| ------------------------------------------ | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Variable** (+ variable_value)            | Human-editable configuration, safe to see in previews and logs       | `odoo_version`, `redis_port`, `instance_root`, `request_timeout` |
| **Secret** (`key`, type `s`)               | Anything sensitive                                                   | API token, DB password, admin password, license key              |
| **Metadata** (JSON on server/jet/waypoint) | Machine-written state and complex structures used only by automation | build digests, monitoring snapshots, backup file lists           |

Rules:

- A value that ever appears in a log or a command preview must not be a secret's job to
  hide — if it is sensitive, it is a Secret, full stop. Variables are rendered in plain
  sight.
- Put values at the **highest level that is still correct**: global > server template
  > server > jet template > jet. Do not copy the same home-directory value onto 40
  > servers; make it global and override the exceptions.
- Values that only matter inside one plan run for SSH, Python, and conditions are
  **custom values** (`custom_values["_flag"]`), not variables. Prefix them with `_`.
  They do not reach `file_using_template` — persist those with `set_variable_value`.
- Resolution order when rendering is **Jet → Jet Template → Server → Global**.

---

## 7. Scope discipline

- Generate only what was asked. No SSL, monitoring, reverse proxy or database unless the
  request needs it.
- Do not force `docker compose`. Prefer explicit lifecycle control (`docker pull` /
  `create` / `start` / `stop` / `rm`) because it maps one-to-one onto jet actions and
  avoids depending on a file on disk. Use Compose only when asked or when the stack
  genuinely needs it.
- If the user names only a category ("a cache", "a database"), present two or three
  leading options with trade-offs and ask which one before generating.
- Keep record count minimal. Do not create a variable for a value that will never
  change.
