---
name: cetmix-tower-jets
description:
  Build Cetmix Tower Jet Templates — jet_template, jet_state and jet_action records, the
  Prepare/Build/Start/Stop/Restart/Remove/Destroy lifecycle, the required
  state_transit_id, create and destroy actions, why Build and Start must use different
  plans, template dependencies, install/uninstall/clone plans, limit_per_server,
  deletable, and atomized vs monolithic design. Use whenever deploying a managed
  application instance rather than running a one-off flight plan.
---

# Jets and Jet Templates

A **Jet** is a managed application instance on a server — a container, a Compose stack,
a VM, a database, anything with a lifecycle. A **Jet Template** is its blueprint.

Only templates are importable; Jets are created from templates through the wizard or the
API. There is no `jet` YAML model.

Choose Jets when there is a thing whose state someone will want to see and change. For a
one-shot host action, a plain Flight Plan is the right answer — see
`cetmix-tower/references/decision-guide.md`.

## Anatomy

```yaml
- cetmix_tower_model: jet_template
  reference: redis_jet
  name: Redis (Docker)
  show_in_create_wizard: true
  limit_per_server: 0
  tag_ids: [redis, docker]
  note: One password-protected Redis container per Jet. Requires Docker on the server.
  plan_install_id: install_docker
  variable_value_ids:
    - reference: redis_jet_version_value
      variable_id: redis_version
      value_char: "7.4"
  action_ids:
    - reference: redis_jet_action_prepare
      name: Prepare
      priority: 10
      state_transit_id: preparing
      state_to_id: draft
      plan_id: redis_jet_prepare
      note: Entry action - no From State, so the Create Jet wizard uses it.
```

| Field                                                          | Notes                                                                                                     |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `name`                                                         | Required                                                                                                  |
| `show_in_create_wizard`                                        | Must be `true` for the template to appear in the Launch Jet wizard                                        |
| `limit_per_server`                                             | Max Jets of this template per server; `0` = unlimited                                                     |
| `plan_install_id`                                              | Runs when the template is **installed on a server**. Use it to install prerequisites (Docker, a runtime). |
| `plan_uninstall_id`                                            | Runs when the template is removed from a server                                                           |
| `plan_clone_same_server_id` / `plan_clone_different_server_id` | Clone plans; leave empty if cloning is not supported                                                      |
| `variable_value_ids`                                           | Template-level defaults                                                                                   |
| `action_ids`                                                   | The lifecycle — see below                                                                                 |
| `template_requires_ids`                                        | Dependencies on other templates                                                                           |
| `waypoint_template_ids`                                        | Snapshot definitions; see `cetmix-tower-waypoints`                                                        |
| `server_log_ids`, `scheduled_task_ids`                         | Copied onto Jets created from the template                                                                |
| `note`                                                         | Required by convention                                                                                    |

`access_level` is **not** a YAML field on `jet_template`. Neither is `icon`. The fields
`plan_prepare_id`, `plan_build_id`, `plan_start_id`, `plan_stop_id`, `plan_remove_id`
**do not exist** — the lifecycle lives entirely in `action_ids`.

Install/uninstall/clone plans are a **different axis** from the lifecycle. Installing a
template on a server prepares the host; the lifecycle governs each Jet on it.

## States — reuse, never redefine

Eleven `jet_state` records ship with Tower. Their references are the lowercased names:

`preparing` · `draft` · `building` · `starting` · `running` · `stopping` · `stopped` ·
`restarting` · `removing` · `removed` · `destroying`

Reference them as scalars (`state_from_id: draft`). Do not create `jet_state` records
with these references — you would either fail on the unique constraint or create
confusing duplicates. Add a custom state only when the standard set genuinely cannot
express your lifecycle, and say why in its `note`.

The eleven names are what **this module ships**. The target instance may already have
extra states used as transits for extra actions (Rebuild from running, Destroy from
draft, and similar). Before writing plan-line conditions, list `cx.tower.jet.state`
and the template's `action_ids` on that instance. Do not assume the eleven XML names
are the only values `{{ tower.jet.state }}` will take.

### `{{ tower.jet.state }}` during an action is the transit

A plan attached to a jet action runs while that action is in progress.
`{{ tower.jet.state }}` is `state_transit_id`, not the from/to resting state. A Start
line conditioned on `== "running"` is skipped during Rebuild-from-running, so the
container is created and never started. Include the transit of the action that
contains the line. Detail: `cetmix-tower-flight-plan`.

## Actions

`jet_action` has no `jet_template_id` in YAML, so actions **must be nested** under
`jet_template.action_ids`.

| Field              | Notes                                                                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`             | Shown on the Jet, e.g. `Start`                                                                                                                                            |
| `priority`         | Display order; lower first                                                                                                                                                |
| `access_level`     | Minimum level to trigger it. Give `Start`/`Stop` `user`; keep `Destroy` at `manager` or `root`.                                                                           |
| `state_from_id`    | Source state. **Empty = create action** (used by the Create Jet wizard).                                                                                                  |
| `state_transit_id` | **Required.** Shown while the action runs. Import fails without it.                                                                                                       |
| `state_to_id`      | Destination. **Empty = destroy action.**                                                                                                                                  |
| `state_error_id`   | Fallback if the plan fails. None of the eleven shipped states is an error state — a custom one needs a recovery action out of it. See `references/lifecycle-patterns.md`. |
| `plan_id`          | The Flight Plan to run. May be empty for a pure state transition.                                                                                                         |

Only actions whose `state_from_id` matches the Jet's current state are offered to the
user.

### The standard pattern

Follow this unless you have a reason not to:

| Action               | From    | Transit    | To      | On error |
| -------------------- | ------- | ---------- | ------- | -------- |
| Prepare              | —       | preparing  | draft   |          |
| Build                | draft   | building   | stopped | draft    |
| Start                | stopped | starting   | running | stopped  |
| Stop                 | running | stopping   | stopped | running  |
| Restart _(optional)_ | running | restarting | running | stopped  |
| Remove               | stopped | removing   | removed | stopped  |
| Destroy              | removed | destroying | —       |          |

More patterns and variants: `references/lifecycle-patterns.md`.

Pattern 1 is the minimum graph. Some fleets also have extra actions (Rebuild from
running / from stopped, Destroy from draft) copied from existing templates. Copy those
only together with conditions that include **their** transits. Do not copy a Start
condition of `{{ tower.jet.state }} == "running"` into a Rebuild-from-running plan.

### Graph invariants

- **Exactly one create action** — one action with empty `state_from_id`, no more.
- **Exactly one destroy action** — one action with empty `state_to_id`. Destroy is
  terminal; Stop and Restart never are.
- **Every action has `state_transit_id`.**
- **`running` is reachable and leavable.** No dead ends: every state a Jet can enter
  must have a way out.
- The `stopped ⇄ running` loop and a `running → running` Restart are **intended**, not
  defects. Do not try to make the graph acyclic.
- Every state referenced by any action should be reachable from the create action.

### Build and Start must use different plans

This is the most common design error. Build **creates** resources — pulls images,
creates containers, compiles binaries, initialises databases. Start **runs resources
that already exist**. Re-running a Build plan on Start fails because the container is
already there.

| Action  | Does                                | Example                             |
| ------- | ----------------------------------- | ----------------------------------- |
| Prepare | Directory structure, config files   | `mkdir -p`, push `redis.conf`       |
| Build   | Create resources                    | `docker pull`, `docker create`      |
| Start   | Start existing resources            | `docker start`                      |
| Stop    | Stop, remove nothing                | `docker stop`                       |
| Remove  | Delete the container, keep the data | `docker rm`                         |
| Destroy | Delete everything, clean up         | `rm -rf`, drop volumes, drop the DB |

The same separation applies to Stop vs Remove vs Destroy. Actions that do the **same
thing** in different contexts may share a plan (two Start actions in different template
variants); actions that do different things may not.

Prefer explicit lifecycle control (`docker pull` / `create` / `start` / `stop` / `rm`)
over `docker compose up`, because it maps one-to-one onto these actions. Use Compose
only when asked or genuinely required.

## `deletable`

`jet.deletable` defaults to `true`. A Jet cannot be deleted while it is `false`.

Guard partially built Jets: set it `false` in a Python command inside the Prepare or
Build plan, and back to `true` in Destroy.

```python
jet.write({"deletable": False})
result = {"exit_code": 0, "message": "Jet locked against deletion"}
```

## Dependencies

`template_requires_ids` holds `jet_template_dependency` records (nested; they have no
`jet_template_id` in YAML):

```yaml
template_requires_ids:
  - reference: app_jet_requires_db
    template_required_id: mariadb_jet
    state_required_id: running
```

Tower resolves dependencies when a Jet is created, reusing or creating the required
Jets. The required template must already exist in the database or be defined **somewhere
in the same file**. `template_required_id` is one of the deferred fields, so a forward
reference is queued and resolved after the main pass; only a reference that is still
unresolvable at the end raises _"Deferred relation resolution failed"_, naming the
record and field. Order your records properly anyway — do not lean on the deferred pass.

`template_requires_ids` **cannot be updated**. `cx.tower.jet.template.dependency.write`
raises _"You cannot modify an existing template dependency!"_ if `template_id` or
`template_required_id` is in the vals, even when the values are unchanged. A YAML
`update` of the parent template that still carries this field always fails. Strip
`template_requires_ids` from an update payload, or delete the dependency and create a
new one. The importer's savepoint rolls the whole file back, so a failed attempt leaves
nothing behind.

## Atomized vs monolithic

**Atomized** — separate templates for DB, proxy and app, wired with dependencies. Choose
for shared infrastructure, differing lifecycles, and reusable template libraries. Costs:
the user creates several Jets, must know the order, and cross-Jet networking is harder.

**Monolithic** — one template deploys the whole stack. Choose for single-server stacks,
demos and easy onboarding. Costs: no reuse, upgrades redeploy everything.

Default to monolithic for a first self-contained deployment; atomized when the user
already runs shared infrastructure. Record the choice in the manifest `description`.

## Acting on other Jets

From inside a plan, use a command with `action: jet_action` (`jet_template_id` +
`jet_action_id`) rather than duplicating the other Jet's commands.

**The target is derived from the Jet the plan is running on, never named directly**, and
with no matching Jets the command is a silent success. That resolution rule, its failure
modes and its exit codes are documented once, in **`cetmix-tower-command-actions` →
_Which Jets it acts on_**. Read it before wiring a cross-Jet action.

What matters on this side: a fan-out such as "stop all app Jets when the DB Jet stops"
works only if `template_requires_ids` links the two **templates** _and_ the concrete
Jets are actually linked — see _Dependencies_ above.

## Prerequisites for the user

A Jet Template is not usable until:

1. It is imported.
2. Secret values are set.
3. It is **installed on the target server** (`Install` button, or from the server form).
   Dependencies install automatically.
4. `show_in_create_wizard: true` if it should appear in the Launch Jet wizard.

Then Jets are created from it. The Create Jet wizard can target state `Running`, which
runs Prepare → Build → Start in one go — a genuine one-click deploy, but only if all
three actions exist and chain correctly.

The template of an existing Jet **cannot be changed** after creation.

### Drive an existing Jet with `bring_to_state`

`jet.bring_to_state(state_reference)` (e.g. `"running"`) computes the action path and
triggers the first action. Prefer it over `_bring_to_state` in Python commands and
external automation — it checks that the caller may set the target state. It takes a
string, so it is RPC-callable; it returns `None`. See `cetmix-tower-api`.

This is also the recovery path when the create action (Prepare) failed. That action has
no `state_from_id`, so a failed run leaves `state_id` empty unless `state_error_id` is
set. Calling `bring_to_state("running")` starts again from the create action rather
than requiring a second Create Jet wizard.

### Hostname is not only a DNS concern

Stock Prepare plans often gate **both** `set_jet_url` and the Cloudflare registration on
`{{ dns_provider }} == "cloudflare"`. A Jet on any other provider then ends up with no
URL at all — and therefore no `tower.jet.hostname` for TLS certificates.

`set_jet_url` writes `jet.url` (from an existing URL, or from `web_domain` + the Jet
reference). Run it **unconditionally** on Prepare. Gate only the provider-specific
registration. Order: `set_jet_url` first, then the DNS record — the registration needs
the hostname.

Do not edit the shared Prepare plans to fix this; they are used by many templates. Copy
the two-step idiom onto a template-scoped plan instead — see
`cetmix-tower/references/hard-rules.md` rule 16.

## Review checklist

- [ ] `jet_action` records nested under `action_ids`, never top-level
- [ ] Every action has `state_transit_id`
- [ ] Exactly one action with no `state_from_id`; exactly one with no `state_to_id`
- [ ] Destroy is the terminal action; Stop and Restart are not
- [ ] Build and Start use **different** plans; likewise Stop / Remove / Destroy
- [ ] `running` is both reachable and leavable; no dead-end states
- [ ] Standard shipped states referenced, not redefined
- [ ] Plan-line conditions on `{{ tower.jet.state }}` include the action's transit;
      states and extra actions were read from the **target instance**
- [ ] `state_error_id` set on actions that can fail mid-flight, with a recovery action
      out of that state
- [ ] `show_in_create_wizard` set if the wizard should offer it
- [ ] `plan_install_id` installs host prerequisites
- [ ] Production templates define Stop, Remove and Destroy — not just
      Prepare/Build/Start
- [ ] `set_jet_url` (or equivalent) runs unconditionally; only DNS registration is
      provider-gated
- [ ] `template_requires_ids` targets exist earlier in the file or in the database; the
      field is stripped from later YAML updates
- [ ] `note` on the template and on non-obvious actions
- [ ] No `access_level` or `plan_*_id` lifecycle fields invented on `jet_template`
- [ ] A Jet with empty `state_id` after a failed Prepare is recovered with
      `bring_to_state`, not a second Create Jet wizard
