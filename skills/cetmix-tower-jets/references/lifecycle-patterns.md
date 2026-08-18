# Jet lifecycle patterns

## Shipped states

From `cetmix_tower_server/data/cx_tower_jet_state.xml`. References are the lowercased
names (the reference mixin generates them from `name`).

| Reference    | Name       | Seq | Colour | Meaning                 |
| ------------ | ---------- | --- | ------ | ----------------------- |
| `preparing`  | Preparing  | 1   | 4      | Being prepared          |
| `draft`      | Draft      | 2   | 4      | Prepared, not built     |
| `building`   | Building   | 3   | 4      | Being built             |
| `starting`   | Starting   | 4   | 3      | Being started           |
| `running`    | Running    | 5   | 10     | Running                 |
| `stopping`   | Stopping   | 6   | 1      | Being stopped           |
| `stopped`    | Stopped    | 7   | 9      | Stopped, ready to start |
| `restarting` | Restarting | 8   | 6      | Being restarted         |
| `removing`   | Removing   | 9   | 7      | Being removed           |
| `removed`    | Removed    | 10  | 7      | Removed                 |
| `destroying` | Destroying | 11  | 8      | Being destroyed         |

Transit states are `preparing`, `building`, `starting`, `stopping`, `restarting`,
`removing`, `destroying`. Resting states are `draft`, `stopped`, `running`, `removed`.

A `jet_state` cannot be deleted while any `jet_action` references it.

`jet_state.access_level` (default `user`) is the minimum level required to set a Jet to
that state **manually**, independently of the actions.

---

## Pattern 1 — full standard lifecycle

The default. Use it unless the application genuinely does not fit.

```
        (create)
           │  Prepare
           ▼
      ┌─ draft ─┐
      │  Build  │
      ▼         │
   stopped ◄────┘
    │   ▲
Start│   │Stop
    ▼   │
   running ──┐ Restart
      ▲      │
      └──────┘
   stopped
    │ Remove
    ▼
  removed
    │ Destroy
    ▼
  (destroy)
```

| Action  | From    | Transit    | To      | On error | Plan does                                   |
| ------- | ------- | ---------- | ------- | -------- | ------------------------------------------- |
| Prepare | —       | preparing  | draft   |          | Create directories, push config files       |
| Build   | draft   | building   | stopped | draft    | Pull images, create containers, init the DB |
| Start   | stopped | starting   | running | stopped  | Start existing resources, health-check      |
| Stop    | running | stopping   | stopped | running  | Stop the process                            |
| Restart | running | restarting | running | stopped  | Reload or restart in place                  |
| Remove  | stopped | removing   | removed | stopped  | Delete the container, keep the data         |
| Destroy | removed | destroying | —       |          | Delete data, volumes, DBs; clean up         |

Restart is optional. Add it when the app supports reload-without-teardown.

---

## Pattern 2 — minimal (demo / POC)

Three actions. Acceptable for a proof of concept; **not** for production, because the
user cannot tear it down cleanly.

| Action | From    | Transit  | To      |
| ------ | ------- | -------- | ------- |
| Create | —       | building | running |
| Stop   | running | stopping | stopped |
| Start  | stopped | starting | running |

Invalid as written: nothing has an empty `state_to_id`, so there is no destroy action
and the Jet can never be removed. Add at least:

| Destroy | stopped | destroying | — |

---

## Pattern 3 — one-click deploy

Same as pattern 1. The Create Jet wizard can target state `Running`, which chains
Prepare → Build → Start automatically. It only works when:

- the create action leads to `draft`,
- an action goes `draft → stopped`,
- an action goes `stopped → running`.

Do not collapse the three into one action to "make it one click" — you lose the ability
to rebuild without re-preparing, and Start ends up recreating resources.

---

## Pattern 4 — stateless / externally managed

The app is managed by systemd or the platform, so Tower only installs and removes it.

| Action    | From    | Transit    | To      |
| --------- | ------- | ---------- | ------- |
| Install   | —       | building   | running |
| Uninstall | running | destroying | —       |

Valid: one create, one destroy, `running` reachable and leavable. Consider whether this
should be a plain Flight Plan instead — if there is nothing to start and stop, a Jet
adds ceremony without benefit. Choose a Jet here only when you still want per-instance
configuration, multiple instances per host, or waypoints.

---

## Pattern 5 — atomized stack

Three templates, wired with dependencies. Each has its own full pattern-1 lifecycle.

```
mariadb_jet  (running)  ◄── app_jet.template_requires_ids
traefik_jet  (running)  ◄── app_jet.template_requires_ids
```

```yaml
- cetmix_tower_model: jet_template
  reference: app_jet
  name: Application
  template_requires_ids:
    - reference: app_jet_requires_mariadb
      template_required_id: mariadb_jet
      state_required_id: running
    - reference: app_jet_requires_traefik
      template_required_id: traefik_jet
      state_required_id: running
```

`mariadb_jet` and `traefik_jet` must exist in the database or be defined **earlier in
the same file**. Tower creates or reuses the required Jets when the app Jet is created.

Follows the demo-data shape: `docker` → `nginx` / `postgres` / `mariadb` → `odoo` /
`wordpress`.

---

## Anti-patterns

| Anti-pattern                           | Why it breaks                                      | Fix                                |
| -------------------------------------- | -------------------------------------------------- | ---------------------------------- |
| Start reuses the Build plan            | `docker create` fails; the container exists        | Separate plan with `docker start`  |
| No `state_transit_id`                  | Import fails — the field is `required=True`        | Add a transit state                |
| Two actions with empty `state_from_id` | Ambiguous create action                            | Keep one                           |
| No action with empty `state_to_id`     | Jet can never be destroyed                         | Add a Destroy                      |
| Stop is terminal (`state_to_id` empty) | Stopping destroys the Jet                          | Stop goes to `stopped`             |
| `plan_build_id` on the template        | Field does not exist; silently ignored             | Use `action_ids`                   |
| Redefining `jet_state` `running`       | Unique-constraint failure or a confusing duplicate | Reference the shipped state        |
| A state with no exit action            | Jet gets stuck                                     | Give every resting state a way out |
| Custom error state, no recovery action | Jet has no available actions                       | Add Error → Stopped (or similar)   |
| Destroy leaves data behind             | Recreating the Jet inherits stale state            | Destroy removes data, volumes, DBs |
| Prepare creates containers             | Prepare should only lay out structure              | Move to Build                      |
| `jet_action` as a top-level record     | No `jet_template_id` in YAML — orphaned            | Nest under `action_ids`            |
| Start line `state == "running"` inside Rebuild-from-running | Transit is not `running`; Start is skipped; container never starts | Condition on the action's transit, or on a flag that is true in that plan |

---

## Deletion guard

```python
# In a Python command inside the Prepare or Build plan
jet.write({"deletable": False})
result = {"exit_code": 0, "message": "Jet locked against deletion"}
```

```python
# In a Python command inside the Destroy plan
jet.write({"deletable": True})
result = {"exit_code": 0, "message": "Jet unlocked"}
```

`deletable` defaults to `true`, so without the guard a half-built Jet can be deleted,
leaving orphaned resources on the host.

---

## Containerised Jets

None of the eleven shipped states is an error state. `state_error_id` pointing at a
custom state (for example `error`) leaves the Jet with **no available actions** unless
you also define a recovery transition out of it — typically Error → Stopped that
force-removes the container.

A healthcheck plus a Start that waits for `health=healthy` turns a broken deploy into a
clean failure. Without it the Jet reports Running while the process is dead in a restart
loop.

### Reliability checklist

- Publish no ports by default; make host exposure an explicit variable.
- Set `--memory` / `--cpus` and an application-level memory cap (`maxmemory`, JVM heap).
- Add a healthcheck and make Start block on it (`docker ps --filter health=healthy`, not
  a Go template).
- Set an explicit stop grace period sized to the workload — Docker's 10s default
  truncates a large final save.
- Pull the image explicitly in Build before `docker create`, and allow a digest pin.
- `--env-file` (and other `docker create` flags) are applied at **create** time.
  Changing the env file or image tag later requires Rebuild (`docker create` again).
  Restart starts the existing container and does not re-read the file.
- Label the **container**, any **volumes** you create, and any **images** you build with
  `tower.jet={{ tower.jet.reference }}`. Shared cleanup commands filter on that label:
  `delete_jet_volumes` uses `docker volume ls --filter label=…`; `remove_all_jet_images`
  uses `docker images --filter label=…`. A container label does not make a volume match.
- Define a custom error state and a recovery action out of it.

---

## Clone plans

`plan_clone_same_server_id` and `plan_clone_different_server_id` run **on the clone**,
not on the original. Available custom variables: `__original_jet__`,
`__original_server__`, `__requested_jet_state__`. In Python, `jet.jet_cloned_from_id`
gives the original record.

Leave both empty when cloning does not make sense — the buttons then do not appear.
