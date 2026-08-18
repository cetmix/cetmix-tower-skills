# Access rights matrix

Generated from every `cetmix_tower_*/security/ir.model.access.csv`. This is the
**model-level ACL** — it decides whether the API user can touch a model at all. Record
rules apply on top (see below).

`R` read · `W` write · `C` create · `D` delete · `—` no rights granted by that group's
own rule.

`—` covers two different CSV shapes with the same effective outcome: no row at all, and
an explicit all-zero row. `cx.tower.key`, `cx.tower.scheduled.task`,
`cx.tower.scheduled.task.cv` and `cx.tower.vault` have deliberate `group_user` rows of
`0,0,0,0`. Effective rights are identical either way; only the intent differs, which
matters if you are editing the CSVs rather than reading them.

!!! Read the table cumulatively The groups imply each other: **`group_root` implies
`group_manager`, which implies `group_user`**. A Root user therefore holds all three
groups, and Odoo grants the **union** of every matching rule. So a `—` in the Root
column does not mean "no access" — it means Root has no rule of its own and inherits
Manager's. Effective rights for a level are the union of its column and every column to
its left.

Regenerate after a Tower upgrade:

```bash
cat cetmix_tower_*/security/ir.model.access.csv
grep -A 3 "group_root\|group_manager" cetmix_tower_server/security/cetmix_tower_server_groups.xml
```

| Model                                    | User | Manager | Root |
| ---------------------------------------- | ---- | ------- | ---- |
| `cetmix.tower`                           | RW   | —       | —    |
| `cx.tower.command`                       | R    | RWCD    | RWCD |
| `cx.tower.command.log`                   | R    | R       | R    |
| `cx.tower.file`                          | R    | RWCD    | RWCD |
| `cx.tower.file.template`                 | —    | RWCD    | RWCD |
| `cx.tower.git.project`                   | —    | RWCD    | RWCD |
| `cx.tower.git.project.file.template.rel` | —    | RWCD    | RWCD |
| `cx.tower.git.project.rel`               | —    | RWCD    | RWCD |
| `cx.tower.git.remote`                    | —    | RWCD    | RWCD |
| `cx.tower.git.repo`                      | —    | RWCD    | RWCD |
| `cx.tower.git.repo.owner`                | —    | RWC     | RWCD |
| `cx.tower.git.source`                    | —    | RWCD    | RWCD |
| `cx.tower.jet`                           | R    | RWCD    | RWCD |
| `cx.tower.jet.action`                    | R    | RWCD    | RWCD |
| `cx.tower.jet.dependency`                | —    | RWCD    | RWCD |
| `cx.tower.jet.request`                   | —    | —       | RWCD |
| `cx.tower.jet.state`                     | R    | R       | RWCD |
| `cx.tower.jet.template`                  | R    | RWCD    | —    |
| `cx.tower.jet.template.dependency`       | —    | RWCD    | —    |
| `cx.tower.jet.template.install`          | —    | R       | RWCD |
| `cx.tower.jet.template.install.line`     | —    | R       | RWCD |
| `cx.tower.jet.waypoint`                  | —    | RWCD    | RWCD |
| `cx.tower.jet.waypoint.template`         | —    | RWCD    | RWCD |
| `cx.tower.key`                           | —    | RWCD    | RWCD |
| `cx.tower.key.value`                     | —    | RWCD    | RWCD |
| `cx.tower.os`                            | R    | —       | RWCD |
| `cx.tower.plan`                          | R    | RWCD    | RWCD |
| `cx.tower.plan.line`                     | R    | RWCD    | RWCD |
| `cx.tower.plan.line.action`              | R    | RWCD    | RWCD |
| `cx.tower.plan.log`                      | R    | R       | R    |
| `cx.tower.scheduled.task`                | —    | RWCD    | RWCD |
| `cx.tower.scheduled.task.cv`             | —    | RWCD    | RWCD |
| `cx.tower.server`                        | R    | RWCD    | RWCD |
| `cx.tower.server.log`                    | R    | RWCD    | RWCD |
| `cx.tower.server.template`               | —    | RWCD    | RWCD |
| `cx.tower.shortcut`                      | R    | R       | RWCD |
| `cx.tower.tag`                           | R    | RWCD    | RWCD |
| `cx.tower.variable`                      | R    | RWC     | RWCD |
| `cx.tower.variable.option`               | R    | RWCD    | RWCD |
| `cx.tower.variable.value`                | R    | RWCD    | RWCD |
| `cx.tower.vault`                         | —    | —       | —    |
| `cx.tower.webhook`                       | —    | —       | RWCD |
| `cx.tower.webhook.authenticator`         | —    | —       | RWCD |
| `cx.tower.webhook.log`                   | —    | —       | R    |
| `cx.tower.yaml.manifest.author`          | —    | —       | RWCD |
| `cx.tower.yaml.manifest.tmpl`            | —    | —       | RWCD |

Transient wizard models are omitted; they are all `RWCD` for the group that owns them.

## Separate YAML groups

The YAML module uses its own groups, independent of User/Manager/Root:

| Model                               | Group                            | Perms |
| ----------------------------------- | -------------------------------- | ----- |
| `cx.tower.yaml.export.wiz`          | `cetmix_tower_yaml.group_export` | RWCD  |
| `cx.tower.yaml.export.wiz.download` | `cetmix_tower_yaml.group_export` | RWCD  |
| `cx.tower.yaml.import.wiz`          | `cetmix_tower_yaml.group_import` | RWCD  |
| `cx.tower.yaml.import.wiz.upload`   | `cetmix_tower_yaml.group_import` | RWCD  |
| `cx.tower.yaml.manifest.tmpl`       | `cetmix_tower_yaml.group_export` | R     |
| `cx.tower.yaml.manifest.author`     | `cetmix_tower_yaml.group_export` | R     |

The `yaml_code` field on every YAML-enabled model is gated to
`group_export,group_import`, and a constraint raises _"You are not allowed to create
records from YAML"_ if the user has export but not import rights.

## Traps for an integration user

| Model                                                               | Trap                                                                                                         |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `cx.tower.os`                                                       | No Manager rule; Manager gets **read only**, inherited from User. Create requires Root.                      |
| `cx.tower.shortcut`                                                 | Manager is **read-only**. Create requires Root.                                                              |
| `cx.tower.jet.state`                                                | Manager is **read-only**. Create requires Root.                                                              |
| `cx.tower.webhook`, `cx.tower.webhook.authenticator`                | Root only.                                                                                                   |
| `cx.tower.jet.request`                                              | Root only.                                                                                                   |
| `cx.tower.variable`                                                 | Manager can create but **not delete**.                                                                       |
| `cx.tower.git.repo.owner`                                           | Manager can create but **not delete**.                                                                       |
| `cx.tower.jet.template`, `cx.tower.jet.template.dependency`         | Manager `RWCD`, no Root rule — Root still gets `RWCD` through group implication.                             |
| `cx.tower.command.log`, `cx.tower.plan.log`, `cx.tower.webhook.log` | **Read-only for everyone.** Never write them.                                                                |
| `cx.tower.vault`                                                    | No group has access. Internal only.                                                                          |
| `cx.tower.jet.template.install`, `…install.line`                    | Manager read-only; Root creates. Use `jet_template.install_on_servers()` rather than writing these directly. |

## Record rules apply on top

Passing the model ACL is not enough. Most models add `ir.rule` conditions — a Manager
typically also needs to be in the record's `user_ids` / `manager_ids`, or be its
creator, and for many models the related Server's roles matter too. The per-entity
access tables in the official documentation spell these out.

Access roles (`user_ids` / `manager_ids`) are **not** importable via YAML but **are**
writable via the API, so an integration can grant them — a genuine advantage of the
direct ORM path.

For an unattended integration user, Root avoids the whole class of problem. Recommend it
explicitly, and be precise about why: Root is a normal group (`group_root` implies
`group_manager` implies `group_user`), and most Tower models ship a Root `ir.rule` with
`domain_force` `[(1, '=', 1)]`. Rules of different groups are OR'd, so that permissive
rule wins and Root effectively sees and edits every record on those models. Record rules
are still evaluated — this is **not** `sudo()` / uid 1, which skips `ir.rule`
altogether. The difference is observable: the creator-only global rules on the Tower
wizard models (`cx.tower.yaml.import.wiz`, `cx.tower.command.run.wiz`, …) carry no
`groups`, so they are AND'ed in and constrain Root too.
