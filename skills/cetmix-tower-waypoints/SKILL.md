---
name: cetmix-tower-waypoints
description:
  Add snapshot and backup capability to Cetmix Tower Jets with waypoints —
  jet_waypoint_template records and their create/arrive/leave/delete flight plans, the
  waypoint state machine, saving and restoring variable values, waypoint metadata and
  the __waypoint_* custom variables, and the create_waypoint command action. Use when a
  Jet needs backups, restore points or the ability to switch between saved
  configurations.
---

# Waypoints

A **Waypoint** is a saved state and configuration of a Jet that you can return to — a
backup or a snapshot. Waypoints belong to a Jet and are created from a **waypoint
template** defined on the Jet Template.

Only `jet_waypoint_template` is importable. Waypoints themselves are runtime records.

## Waypoint template

```yaml
- cetmix_tower_model: jet_template
  reference: redis_jet
  name: Redis (Docker)
  waypoint_template_ids:
    - reference: redis_snapshot
      name: Snapshot
      sequence: 10
      access_level: manager
      note: >-
        Saves an RDB dump plus the Jet's variable values so the instance can be rolled
        back.
      plan_create_id: redis_snapshot_create
      plan_arrive_id: redis_snapshot_arrive
      plan_leave_id: redis_snapshot_leave
      plan_delete_id: redis_snapshot_delete
```

| Field             | Notes                                                                                     |
| ----------------- | ----------------------------------------------------------------------------------------- |
| `name`            | Shown as the waypoint **Type**                                                            |
| `sequence`        | Display order                                                                             |
| `access_level`    | `manager` or `root` — Users have no waypoint access                                       |
| `jet_template_id` | Present in YAML, so the template may also be a top-level record                           |
| `plan_create_id`  | Runs when the waypoint is **prepared** (draft → preparing → ready). Take the backup here. |
| `plan_arrive_id`  | Runs when flying **to** this waypoint. Restore here.                                      |
| `plan_leave_id`   | Runs when flying **away** from this waypoint. Capture current state here.                 |
| `plan_delete_id`  | Runs before the waypoint is deleted. Clean up stored artefacts.                           |
| `note`            | Required by convention                                                                    |

All four plans are optional. With no `plan_create_id` a waypoint becomes `ready`
immediately; with no `plan_delete_id` it is deleted immediately.

## Lifecycle

States: `draft` → `preparing` → `ready` → `arriving` → `current`, plus `leaving`,
`deleting`, `deleted` and `error`.

**Creating.** Add a waypoint on the Jet's Waypoints tab (state `draft`), then click
**Prepare**. `plan_create_id` runs; success → `ready`, failure → `error`.

**Activating** (_Fly here_, on a `ready` waypoint):

1. New waypoint → `arriving`.
2. If another waypoint is `current`, it goes to `leaving`; its Jet-level variable values
   are **saved onto it**; its `plan_leave_id` runs.
3. The new waypoint's `plan_arrive_id` runs.
4. Variable values are **restored from** the new waypoint onto the Jet.
5. New waypoint → `current`; the previous one → `ready`.

**Deleting.** `draft` deletes immediately. `ready`/`error` run `plan_delete_id` first
(state `deleting`). Other states cannot be deleted. **The `current` waypoint cannot be
deleted** — fly elsewhere first.

Only **one** waypoint per Jet can be `current`.

Failures: during preparation → `error`; during arrival → variable values are restored
from the previous current waypoint, that waypoint becomes `current` again, and the new
one goes to `error`; during leaving → `error`; during deletion the waypoint stays in
`deleting`. Waypoints in `error` are unusable until re-prepared.

## What is saved automatically

Only **Jet-level** variable values. Template, server and global values are not touched,
so each waypoint can represent a different per-instance configuration while shared
config stays shared.

Everything else — files on disk, database dumps, image tags — is your plans' job.

## Metadata

Waypoints carry a JSON `metadata` field. Use it to record what the backup consists of.

```python
# In a Python command inside plan_create_id or plan_leave_id
waypoint.update_metadata({
    "db_version": "15.0",
    "backup_files": ["/data/db.sql", "/data/media.tar.gz"],
    "custom_note": "Before major upgrade",
})
result = {"exit_code": 0, "message": "Snapshot metadata saved"}
```

```python
# In a Python command inside plan_arrive_id
version = waypoint.metadata.get("db_version")
backup_files = waypoint.metadata.get("backup_files", [])
```

`update_metadata()` merges keys; `waypoint.write({"metadata": {...}})` replaces the
whole dict. The field is read-only in the UI and visible only in developer mode.

## Custom variables in waypoint plans

Available in every plan run for a waypoint (create, arrive, leave, delete) — usable in
command code and in plan line conditions:

| Variable           | Meaning                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------ |
| `__waypoint`       | Waypoint reference                                                                         |
| `__waypoint_type`  | Waypoint template reference                                                                |
| `__waypoint_state` | Current waypoint state                                                                     |
| `__waypoint_<key>` | One per metadata key — metadata `{"environment": "production"}` → `__waypoint_environment` |

Also exposed to variable rendering in a jet context as `tower.jet.waypoint.reference`,
`tower.jet.waypoint.type` and `tower.jet.waypoint.<key>`.

**Those `tower.jet.waypoint.*` values are the Jet's _current_ waypoint**,
`jet.waypoint_id`. While `plan_create_id` runs the waypoint is not yet current, so Jinja
renders Python `False` as the **string** `False` (verified with Jinja2 3.x). `False` is
non-empty, so `[ -z "$WP" ]` passes. Every snapshot then lands in one shared directory,
overwriting the last; restore — which resolves the reference correctly, because by then
the waypoint is current — looks somewhere that never exists.

Use `{{ __waypoint }}` in SSH (including artefact names) and `waypoint.reference` in
Python. Both are set for every waypoint plan, including Create.

If a command still reads `tower.jet.waypoint.reference`, guard both conditions:

```bash
WP="{{ tower.jet.waypoint.reference }}"
if [ -z "$WP" ] || [ "$WP" = "False" ]; then exit 96; fi
```

```bash
docker exec {{ redis_instance_name }} sh -c \
  'REDISCLI_AUTH=$(sed -n "s/^requirepass //p" /usr/local/etc/redis/redis.conf) \
   redis-cli --no-auth-warning --rdb /data/{{ __waypoint }}.rdb'
```

## Creating a waypoint from a plan

A command with `action: create_waypoint` creates a waypoint for the current Jet. Only
available **inside a flight plan**.

```yaml
- cetmix_tower_model: command
  reference: create_pre_upgrade_snapshot
  name: Create pre-upgrade snapshot
  action: create_waypoint
  note: Snapshots the Jet before an upgrade so the plan can roll back.
  waypoint_template_id: redis_snapshot
  fly_here: false
```

`fly_here: true` makes the new waypoint current immediately after creation. Leave it
`false` when you only want the backup taken.

Two things to know about how this line behaves:

- **It waits.** The command log is not finished when the waypoint record is created; it
  stays running until the waypoint reaches `ready` / `current` / `error`. So the
  waypoint template's **Create plan runs as part of this line**, and the line's exit
  code covers the whole snapshot. Do not add a "wait for the waypoint" line after it.
- **Jet busy is handled.** The surrounding flight plan marks the Jet busy; the runner
  bypasses that check, so you do not need to work around it.

Failures: `JET_NOT_FOUND (-503)` when the plan is not running on a Jet,
`WAYPOINT_TEMPLATE_NOT_FOUND (-507)` when `waypoint_template_id` is empty, and
`WAYPOINT_CREATE_FAILED (-508)` when the waypoint template does not belong to this Jet's
template.

This is how you build "back up, then upgrade" plans: create the waypoint, run the
upgrade, and on failure the operator flies back. See `cetmix-tower-command-actions`.

## Design guidance

- **Create** should produce a self-contained artefact named after `{{ __waypoint }}` and
  record its location in metadata. Do not assume it is the only waypoint.
- **Arrive** must be idempotent and must tolerate the artefact having been created by a
  different Tower version.
- **Leave** captures the _current_ state before it is replaced. Skip it if you only need
  restore-to-a-fixed-point, not switch-between-configurations.
- **Delete** must remove the artefacts, or the host fills up.
- Storing dumps under the Jet's own data directory means a Destroy that does `rm -rf`
  takes the backups with it. Put them somewhere Destroy does not touch, or state the
  trade-off in the note.
- Stop the app before a filesystem-level snapshot, or use the app's own consistent-dump
  mechanism (`BGSAVE`, `pg_dump`, `mysqldump`).

## Review checklist

- [ ] `access_level` is `manager` or `root` — never `user`
- [ ] All four plans exist, or the missing ones are deliberately omitted
- [ ] `plan_delete_id` removes what `plan_create_id` produced
- [ ] Artefact names include `{{ __waypoint }}` so waypoints do not collide — never
      `tower.jet.waypoint.reference` in a Create plan
- [ ] Metadata records what the backup contains
- [ ] Arrive is idempotent and handles missing artefacts with a clear exit code
- [ ] Backups live outside anything the Destroy plan deletes, or the trade-off is noted
- [ ] Dumps are taken consistently (app-level dump, or the app stopped first)
- [ ] `note` explains what the waypoint captures and what it does not
