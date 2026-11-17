---
name: cetmix-tower-monitoring
description:
  Add current-state monitoring to Cetmix Tower servers and jets with the
  cetmix_tower_monitoring module — metric records (progress bar, gauge, number), their
  thresholds (Warning, Critical, Stale) that can run a command or flight plan, collector
  Python commands that call record_metric(), pulling data on a schedule, metrics on
  server and jet templates, pushing values from a webhook, and the metric objects and
  __metric_* custom values available to threshold actions. Use when a server or jet must
  show disk, memory, load or any custom value, or react when one crosses a limit.
---

# Monitoring

Source of truth: `cetmix_tower_monitoring/models/*.py` and its `readme/`. The module
depends on `cetmix_tower_webhook` (and through it on `cetmix_tower_yaml`). Check that it
is installed before writing any of this: without it, `metric` is not a valid
`cetmix_tower_model` and the import fails.

Monitoring keeps **one current value per metric per server or jet**, with the time of
the last update. There is **no history** and no graphs. If the request needs trends,
say so and propose an external system that pushes values in.

## What to create

| YAML model                                 | What it is                                                                                     |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| `metric`                                   | What is measured, how it is shown, its collector, its thresholds. Top-level record.            |
| `metric_threshold` (nest in `threshold_ids`) | A condition that sets a severity and can run a command or flight plan.                       |
| `jet_template_metric` (nest in `jet_template.metric_ids`) | A metric every jet of the template gets, optionally only in some environments. |
| `server_template.metric_ids`               | A list of metric references copied to servers created from the template.                      |
| `command` (`action: python_code`)          | The collector, and optionally the threshold action.                                            |

Metric **values** (`cx.tower.metric.value`) are not exported or imported. They are
created by `record_metric()`, by the templates, or by a user on the **Monitoring** tab.

Allowed fields: `cetmix-tower-yaml/references/model-fields.md` (Monitoring section).
Selection keys: `cetmix-tower-yaml/references/selection-values.md`.

## Worked example — runtime-validated

Imported through the validating upload wizard on an instance with the module installed:
the collector link, all three thresholds and the server template metric were created as
written.

```yaml
cetmix_tower_yaml_version: 1
records:
  - cetmix_tower_model: tag
    reference: monitoring
    name: Monitoring
    color: 2
  - cetmix_tower_model: command
    reference: my_disk_root_bytes
    name: "Monitoring: Root Disk Bytes"
    action: ssh_command
    tag_ids:
      - monitoring
    note: Prints used and total bytes of the root filesystem.
    code: df -B1 --output=used,size /
  - cetmix_tower_model: command
    reference: my_collect_disk_root
    name: "Monitoring: Collect Root Disk"
    action: python_code
    tag_ids:
      - monitoring
    note: Collector of my_disk_root. Runs the df command and records used and total GiB.
    code: |
      runner = server.with_context(no_command_log=True)
      disk = runner.run_command(tower_commands.get_by_reference("my_disk_root_bytes"))
      if disk["status"] == 0:
          used, total = disk["response"].strip().splitlines()[-1].split()
          server.record_metric(
              "my_disk_root", used=int(used) / 1024 ** 3, total=int(total) / 1024 ** 3
          )
          result = {"exit_code": 0, "message": "my_disk_root recorded"}
      else:
          result = {"exit_code": 1, "message": "my_disk_root failed: %s" % disk["error"]}
  - cetmix_tower_model: command
    reference: my_report_threshold
    name: "Monitoring: Report Threshold"
    action: python_code
    tag_ids:
      - monitoring
    note: Threshold action. Reports the metric, its state and its value.
    code: |
      result = {
          "exit_code": 0,
          "message": "%s is %s: %s of %s %s" % (
              metric.name, metric_value.state, metric_value.value,
              metric_value.max_value, metric.unit or "",
          ),
      }
  - cetmix_tower_model: metric
    reference: my_disk_root
    name: Root Disk
    widget: progressbar
    unit: GiB
    note: Used and total space of the root filesystem, from df.
    show_on_kanban: true
    stale_after_minutes: 30
    pull_data_minutes: 15
    command_id: my_collect_disk_root
    threshold_ids:
      - reference: my_disk_root_warning
        sequence: 10
        condition: ">="
        value_float: 80
        severity: warning
        action: none
      - reference: my_disk_root_critical
        sequence: 20
        condition: ">="
        value_float: 90
        severity: critical
        action: command
        command_id: my_report_threshold
      - reference: my_disk_root_stale
        sequence: 30
        condition: stale
        action: none
  - cetmix_tower_model: server_template
    reference: my_monitored_template
    name: Monitored Server
    tag_ids:
      - monitoring
    note: Servers created from this template start with the my_disk_root metric.
    metric_ids:
      - my_disk_root
```

The import does not prove the collector works on a host: that needs a real run (the
**Refresh** button on the server's **Monitoring** tab).

## Metric

| Field                 | Notes                                                                                                                         |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `reference`           | What `record_metric()` names. Keep it stable: collectors and webhooks hard-code it.                                           |
| `widget`              | `progressbar` (used of total, e.g. disk, memory), `gauge` (value with an optional maximum, e.g. CPU %), `number` (default).   |
| `unit`                | Free text shown next to the value.                                                                                            |
| `note`                | What is measured and how. Fill it: it is the only place a reader learns what the number means.                                |
| `stale_after_minutes` | Default 30. A value not updated for this long becomes Stale. Must exceed the collection interval.                             |
| `show_on_kanban`      | Default true. Keep the kanban card to the two or three metrics that matter.                                                   |
| `pull_data_minutes`   | 0 (default) = never pulled. Otherwise the collector runs about every N minutes on servers with **Pull data** enabled, and their jets. |
| `command_id` / `plan_id` | The collector. Set one or none (none = values arrive only by webhook or another command).                                  |
| `threshold_ids`       | Nested thresholds, evaluated on every new value.                                                                              |

**Progress bar units.** The form shows whole numbers only (45.2 of 100 → `45 / 100`).
Record disk in GiB and memory in MiB, never memory in GiB.

**Only Root creates or changes metrics and their thresholds.** Managers read them. The
import therefore needs a Root user.

## Thresholds

| Field         | Notes                                                                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `condition`   | `>=` (default), `<=`, `>`, `<`, `==`, `stale`. Quote the operators in YAML: `">="`.                                                           |
| `value_float` | Compared value. For `progressbar` metrics the comparison is on **used / total in percent** (`">=" 90` = 90 % used). For `gauge` and `number` it is the raw value. Ignored for `stale`. |
| `severity`    | `warning` or `critical`. **Required** on every condition except `stale`, where it is not used — the state is Stale anyway.                   |
| `action`      | `none` (default), `command` + `command_id`, `plan` + `plan_id`.                                                                               |
| `sequence`    | Order of evaluation; the value state is the worst matching severity.                                                                          |

**Actions run on the transition, not on every sample.** Each threshold is tracked on
its own: its action runs when **that threshold's** condition starts to match, and runs
again only after that condition stopped matching and then matches again. The value does
not need to return to OK in between: with the example's thresholds, samples of 95 % →
85 % → 95 % run the Critical action twice while the value stays Warning or Critical. Do
not write an action that expects to run periodically while a problem lasts.

Actions run on the value's server; for a jet value, on the jet's server with that jet.

Overrides for one server or jet (`threshold_ids` on the metric value) are set in the UI
and replace the metric thresholds completely for that value. They are not in YAML.

## Collectors

- A collector is a **Python command**, or a flight plan whose Python commands record
  values. SSH commands cannot call `record_metric()`: run the SSH command from Python
  with `server.with_context(no_command_log=True).run_command(...)` and parse
  `result["response"]` (check `result["status"] == 0` first; the error is in
  `result["error"]`).
- **Name every metric explicitly.** The Refresh button, pulling and scheduled tasks run
  the collector without any metric context, so `metric` is `None` there.
- One collector can record several metrics; it runs once per server or jet even if
  several of its metrics are due.
- Respect hard rule 2 in the SSH commands it calls: one statement each. For a locale
  dependent tool, prefix the variable (`LC_ALL=C free -b`) rather than chaining.
- Make it fail loudly: return `exit_code: 1` with a message when a sample cannot be
  read, instead of recording a zero.

### `record_metric()`

On `server` and `jet` records, in Python commands and webhook code:

```python
server.record_metric("my_disk_root", used=45.2, total=100.0)  # progressbar
server.record_metric("cpu", value=37.5, total=100)            # gauge, total optional
jet.record_metric("load_1", value=1.37)                       # number
```

- The metric must already exist (`ValidationError` otherwise).
- `progressbar`: `used` and `total`, `total > 0`. `gauge` / `number`: `value`.
- Finite numbers only: `nan` and `inf` are refused.
- The calling user must be able to write the server or jet (in its **Managers**), or
  the value is not saved.
- On a jet, a value created by `record_metric()` is **manual**: the Jet Template will
  never change or delete it.

## Getting values periodically

| Way                         | When                                                                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `pull_data_minutes` on the metric | Default choice. Also needs **Pull data** enabled on each server (UI, Monitoring tab; not in YAML). Logs of these runs are deleted when they finish. |
| `scheduled_task` (see `cetmix-tower-automation`) | Custom schedule, or when the run logs must be kept.                                                                  |
| Webhook push                | The host or an external agent already measures; Tower only stores. See below.                                                        |

The pull cron runs every 5 minutes by default, so the real interval is N rounded up to
the next cron run: a value below 5 behaves like 5. Negative values are refused.

## Templates

**Jet Template** — nest lines under `metric_ids`:

```yaml
- cetmix_tower_model: jet_template
  reference: my_app_template
  name: My App
  metric_ids:
    - metric_id: my_disk_root
    - metric_id: load_1
      environment_ids:
        - my_prod
```

Runtime-validated. Empty `environment_ids` = all jets of the template. Lines are kept
in sync with existing jets (values added or removed). Referenced environments must
exist on the target; an environment used by a line cannot be deleted.

**Server Template** — a list of metric references under `metric_ids` (see the worked
example). Copied **once**, when a server is created from the template. Later template
changes do not reach existing servers.

## Push values with a webhook

Webhook code has no `server`: resolve the target from the payload. `metric` and
`metric_value` are not available in webhook code; `tower_metrics` and
`tower_metric_values` are.

```python
server = tower_servers.get_by_reference(payload["server_reference"])
for item in payload["metrics"]:
    server.record_metric(
        item["reference"],
        value=item.get("value"),
        used=item.get("used"),
        total=item.get("total"),
    )
result = {"exit_code": 0, "message": "ok"}
```

Set the webhook **Run as User** (UI only, field `user_id`) to a user that is a Manager
of the target servers. See `cetmix-tower-automation` for webhook and authenticator
records.

## Threshold action context

In a Python command run by a threshold, and in every Python command of a flight plan
run by a threshold (nested plans included):

| Name           | Value                                                                  |
| -------------- | ---------------------------------------------------------------------- |
| `metric`       | `cx.tower.metric` whose threshold fired                                |
| `metric_value` | `cx.tower.metric.value`: `value`, `max_value`, `state`, `last_update`  |
| `server`, `jet` | The server; the jet for a jet value, else `None`                     |

`metric` and `metric_value` are `None` in every other run. `tower_metrics` and
`tower_metric_values` are always available.

SSH commands and plan line conditions get custom values instead (also in
`custom_values` in Python):

| Key                         | Content                                         |
| --------------------------- | ----------------------------------------------- |
| `__metric__`                | Metric reference                                |
| `__metric_value__`          | Current value                                   |
| `__metric_max__`            | Total or maximum, empty if none                 |
| `__metric_unit__`           | Unit                                            |
| `__metric_state__`          | New state                                       |
| `__metric_previous_state__` | State before this update                        |
| `__metric_severity__`       | Threshold severity, empty for `stale`           |
| `__server__`                | Server reference                                |
| `__jet__`                   | Jet reference, empty for a server value         |

## States

`unknown` (no value yet), `ok`, `warning`, `critical`, `stale`. A server's or jet's
overall state is the worst of its values: critical > stale > warning > unknown > ok.

## Review checklist

- [ ] `cetmix_tower_monitoring` is installed on the target, and the importing user is Root
- [ ] Every metric has a `note` and a `unit` that fits its widget
- [ ] Commands and the server template have a `note` and `tag_ids` (hard rule 8)
- [ ] Progress bar metrics record used **and** total; thresholds on them are percentages
- [ ] The collector names each metric it records and returns `exit_code: 1` on a failed read
- [ ] SSH commands the collector calls are single statements (hard rule 2)
- [ ] `stale_after_minutes` is longer than the collection interval
- [ ] If `pull_data_minutes` is set, the user is told to enable **Pull data** on the servers
- [ ] Threshold actions do not rely on running repeatedly while a condition lasts
- [ ] Every non-`stale` threshold has a `severity`
- [ ] The YAML was imported, or is labelled **not runtime-validated**
