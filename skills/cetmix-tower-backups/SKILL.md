---
name: cetmix-tower-backups
description: >-
  Configure durable Cetmix Tower Jet backups, Backup Templates, backup plans,
  triggers, retention and restore into new Jets. Use when a recovery copy must
  outlive its source Jet; use cetmix-tower-waypoints for ordinary in-place snapshots.
---

# Jet backups

Read `cetmix-tower/references/hard-rules.md` and verify installed modules and
fields against their source. This workflow requires `cetmix_tower_backup`; Git
capture additionally requires `cetmix_tower_backup_git`.

A Backup Template belongs to one Jet Template. Backups retain metadata and the
Jet's own variable values after deleting that Jet. The plans move the bytes;
Tower does not store or transfer backup payloads. Restore creates a **new Jet**.
Use a waypoint to return the same Jet to an earlier state.

## Configure the plans and template

1. Reuse suitable Backup, Restore and optional Delete plans where they exist.
2. Set those plans, every command and every Plan-action sub-plan to Root.
3. Nest `backup_template` records under `jet_template.backup_template_ids`.
4. Choose `keep_last`: `0` keeps all successful backups; a positive count applies per source Jet.
5. Choose a manual, scheduled, command or waypoint trigger.

Template fragment: plan references must resolve to actual Root plans in the same
file or database. See `cetmix-tower-yaml` for the file envelope and
`cetmix-tower-yaml/references/model-fields.md` for supported fields.

```yaml
- cetmix_tower_model: jet_template
  reference: application_jet
  name: Application
  note: Existing application Jet Template with durable backups.
  backup_template_ids:
    - reference: application_backup
      name: Application Backup
      sequence: 10
      plan_backup_id: application_backup_plan
      plan_restore_id: application_restore_plan
      plan_delete_id: application_delete_backup_plan
      keep_last: 3
      note: Preserve recovery objects and replay their metadata on restore.
```

Do not export `backup_template.jet_template_id`; the owning One2many sets it.
Backups are runtime records and are not YAML-exported. Do not replace an existing
Jet Template's lifecycle, logs or configuration with this fragment.

## Triggers and completion

- Root: **Back Up** on a Jet opens the template selector.
- Schedule: `scheduled_task.action: backup`, with `backup_template_id`; assign
  target Jets of that Jet Template in the UI/API. No bare-server targets.
- Command: `action: create_backup`, with `backup_template_id`; run from a Jet
  flight plan or scheduled **Command** task. The Run Command wizard does not offer it.
- Waypoint: set `jet_waypoint_template.backup_template_id`. Leave its Create/Delete
  plans empty. Arrive/Leave require Root plans, commands and sub-plans.

Create Backup waits for Done (`0`) or failure (`-510`). Missing template gives
`-509`, missing Jet gives `-503`. Stop stops the Backup plan. The caller keeps its
own custom values; backup metadata is not returned to it.

## Custom values and metadata

Preserve non-secret location settings as trigger custom values. Restore and Delete
replay them. Keep credentials in Tower keys. Python lines can merge metadata:

```python
backup.update_metadata({"object_key": "recovery/object", "size": 12345})
result = {"exit_code": 0, "message": "Metadata recorded"}
```

This only records metadata; it does not create a real backup.

Values merge in order: stored custom values, Restore-time overrides,
`__backup_<metadata_key>`, then fixed `__backup` and `__backup_template` references.
Metadata cannot replace the fixed identifiers. Restore also receives
`__requested_jet_state__`. Waypoint values win on collisions with backup values.

`backup` is the current sudo backup on operation Python lines, including
backup-waypoint Arrive/Leave lines. It is empty outside a backup run. Sub-plans
inherit custom values but do not automatically inherit the object. `tower_backups`
is a model shortcut. See `cetmix-tower-command-python`.

## Restore, delete and retention

Root restores only Done backups, choosing server, optional name, requested state
and environment. The environment falls back to the captured one, then the template
default. The dialog has no custom-value input; in-process Python can call
`restore(..., variable_values=...)`. `jet.create_backup()` is private to in-process
Python, as are `start`, `finish` and `record` on plan and command logs; see
`cetmix-tower-api`.

The Git bridge captures grouped sources, remotes, enabled flags, ordering, URLs,
heads, protocols, aggregator root directory and notes. Restore creates fresh
records before its first plan line when Use Git Projects is enabled and remotes
exist. Source references and aggregator source directories can change.

Delete uses the source Jet, then its captured server. With neither host left,
only the record can be removed; stored data remains. Delete-plan failure leaves
Deletion Failed and requires a manual retry. Running operations and Restores block
deletion. Delete waypoint-owned backups through their waypoint.

Daily cleanup removes unlinked Failed backups regardless of retention, then excess
Done backups per source Jet. It leaves waypoint-linked backups, orphaned Done
backups and Deletion Failed backups. A running Restore keeps a counted backup
until a later cleanup.

## Access boundary

Only Root can read/configure backups and templates. Managers can trigger configured
paths without reading the fields. Users able to run Tower Python can use `sudo()`;
Root-only ACLs and UI do not isolate backups from those users. Protected logs keep
their plans and commands at Root level while those logs exist.
