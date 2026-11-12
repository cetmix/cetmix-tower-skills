# Hard rules — the canonical list

**This file is the single source for the Cetmix Tower authoring rules.** Three entry
points each carry a five-rule shortlist and point here for the rest: the agent digest
(`AGENTS.md`), the Cursor rule (`cetmix-tower.mdc`) and this skill's own `SKILL.md`.
Change a rule **here**; do not add rules to the entry points, or the lists drift apart
again. Where those files sit depends on how the assets were installed — under
`skills/` and `rules/` in this repository, and under `.claude/` / `.cursor/` once
installed — so they are named by role above, not by path.

Read this before writing any Tower record.

**Reading the pointers in these files.** A path with a skill name in front —
`cetmix-tower-yaml/references/model-fields.md` — is resolved against the **skills root**
(`.claude/skills/`, `.cursor/skills/`, or `skills/` in this repository), never
against the file that quotes it. Opening it relative to the current skill will miss; go
up one level first. A bare `references/…` with no skill name _is_ relative to the
current skill.

1. **Never propose manual SSH or a shell script as the solution.** Everything is a
   Command, Flight Plan, Jet Template, Variable, Secret, File Template or Waypoint.
2. **One Command = one statement — `action: ssh_command` only.** No `&&`, `||`, `;`; no
   `cd` (use the line's `path`); no inline `sudo` (use `use_sudo` on the plan line).
   This is a **shell-side** rule: it says nothing about `action: python_code`, whose
   `code` is ordinary Python and may of course use `;`, `and`, `or` and multiple
   statements. Chain shell work with flight plan lines, not with shell operators. The
   sudo-split escape hatch (`no_split_for_sudo`) and the few cases that need it live in
   `cetmix-tower-command-ssh`. See also `cetmix-tower-command-python`.
3. **Never invent a field.** Only fields listed in
   `cetmix-tower-yaml/references/model-fields.md` are imported; anything else is
   accepted silently and does nothing. Via the API the ORM accepts more than that list —
   but never anything that is not a real field.
4. **Never hardcode a secret, token, password or private key, and never store one in a
   variable.** Create a `key` record and reference it as `#!cxtower.secret.<ref>!#`. See
   `cetmix-tower-secrets`.
5. **Terminology is exact.** A Flight Plan's YAML model is `plan`, never `flight_plan`
   (`cx.tower.plan` via the API). A plan line references its command through
   `command_id`, never `command`.
6. **`variable` has no value field.** Values are `variable_value` records; a top-level
   one is a global value. There is no `default_value_char`.
7. **Always set `reference` explicitly, and upsert over the API.** YAML raises _"Record
   reference is missing"_ for a top-level record without one. The API raises nothing:
   `create()` passes `reference or name` through `_generate_or_fix_reference`, which
   appends `_2`, `_3` on collision — so a second `create` silently makes a duplicate
   **even with an explicit `reference`**. Setting `reference` is what makes the record
   findable; the actual guard against duplicates is looking it up first
   (`get_by_reference` → `write`, else `create`). See `cetmix-tower-api`.
8. **Every record that can carry a `note` gets one** explaining what it does. Every
   record whose YAML field list includes `tag_ids` gets tags — including `variable`.
   Only these YAML models list `note`: `command`, `plan`, `variable`, `key`,
   `file_template`, `server`, `server_template`, `jet_template`, `jet_state`,
   `jet_action`, `jet_waypoint_template`, `shortcut`, `git_project`. Everywhere else —
   including `plan_line`, `plan_line_action`, `variable_option`, `variable_value`,
   `file`, `server_log`, `scheduled_task`, `tag`, `os`, `webhook` and the `git_*` child
   models — a `note` key is silently dropped. On `plan_line` and `variable_value` `note`
   exists only as a read-only related field (of the command / variable), so it can never
   be imported. Document a step in the parent's `note` or the command's, not on the
   line.
9. **`_id` is a scalar, `_ids` is a list.** Never a list under `_id`, never a scalar
   under `_ids`.
10. **Nest children that have no owner-link field** — never top-level: `plan_line`,
    `plan_line_action`, `jet_action`, `variable_option`, `server_log`,
    `scheduled_task_cv`, `jet_template_dependency`, `git_source`, `git_remote`,
    `git_project_rel`. `shortcut` and `scheduled_task` are their own records; the
    owner lists them by reference.
11. **Jet lifecycle:** every `jet_action` needs `state_transit_id`; exactly one action
    with no `state_from_id` (create) and exactly one with no `state_to_id` (destroy);
    Build and Start must use **different** plans. Reuse the eleven shipped `jet_state`
    records — never redefine them.
12. **The Run Command wizard offers only `ssh_command` and `python_code`.**
    Use flight-plan lines for orchestration actions. `create_waypoint` and, with
    the backup module, `create_backup` also run from scheduled Command tasks.
    Both require a Jet context; `jet_action` requires one too. Read
    `cetmix-tower-command-actions` and `cetmix-tower-backups` for their contracts.
13. **Reuse existing records by reference before defining new ones.** Commands like
    `update_packages`, plus tags, OSes and variables, usually already exist.
14. **Establish the delivery path first:** a YAML file for a person to import, YAML
    imported by code over the API, or direct ORM writes over the API. For YAML, deliver
    one complete file whose only top-level keys are `cetmix_tower_yaml_version`,
    `manifest` and `records`. For API work read `cetmix-tower-api` — real model names,
    `access_level` as `"1"`/`"2"`/`"3"`, command tuples, the `from_yaml` and
    `skip_ssh_settings_check` contexts, upsert by reference. If the target instance
    already has the same logical templates or commands under different references,
    **do not import that YAML onto that instance.** Records are matched by reference,
    so a different reference is a new record. When the references match, Skip leaves
    the existing record unchanged and creates only what is missing. Update writes the
    matched records and their nested children. An existing jet template dependency is
    left unchanged. Edit the existing records over the API. Keep the YAML as a portable
    copy for empty databases and other instances.
15. **There is no REST API module in Cetmix Tower.** `cetmix_tower_api` is an
    unimplemented specification; never reference its endpoints.
16. **Count dependents before editing a command, plan, or file template.**
    If more than one Jet Template uses it, do not edit — add a template-scoped
    record and repoint that template's own `jet_action.plan_id` / line
    `command_id`. Stock lifecycle plans (`start_jet`, `stop_jet`, `restart_jet`,
    `remove_jet`, `destroy_jet`) and commands like `set_jet_url` are shared by
    design. One call:

    ```python
    env["cx.tower.jet.action"].search(
        [("plan_id.line_ids.command_id", "=", command.id)]
    ).mapped("jet_template_id")
    # For a plan: search([("plan_id", "=", plan.id)]).mapped("jet_template_id")
    ```

    For a file template, count linked files (and their servers) before writing it —
    the write cascades to every `cx.tower.file` with that `template_id`, and those
    with `auto_sync=True` and `source: tower` push immediately. Suppress the push
    with `from_yaml=True` (`cetmix-tower-api`). One call:

    ```python
    env["cx.tower.file"].search(
        [("template_id", "=", tmpl.id)]
    ).mapped("server_id")
    ```

17. **`custom_values` do not reach `file_using_template`.** Assigning
    `custom_values["x"] = ...` in a Python command (or a plan-line
    `variable_value_ids`) updates the run's `variable_values` dict. Later SSH and
    Python commands, and plan-line conditions, render from that dict. A
    `file_using_template` command does not:
    `_command_runner_file_using_template_create_file` calls `create_file(server,
jet=...)` with no `variable_values`, so the file renders from stored Jet →
    Template → Server → Global values only. A missing value becomes the literal text
    `None` (or `False`) in the file, and the push still succeeds. If a later file
    template must see a computed value, persist it first with
    `jet.set_variable_value(reference, value)` or
    `server.set_variable_value(reference, value)` (the variable mixin is on server,
    jet, and jet template), then push the file. Persist on the Jet when the file is
    rendered in a Jet context. See `cetmix-tower-files` and
    `cetmix-tower-command-python`.
18. **Do not store runtime configuration in a host file when the process can take
    environment variables.** Prefer `docker create --env KEY=value` (and the
    process's own env). Never write secrets to disk (`--env-file`, a rendered
    `.env`). Use a `file_template` only for formats env cannot express (nginx.conf,
    TLS material, a daemon that only reads a config file). Secrets still go through
    `#!cxtower.secret.X!#`. `--env` is applied at `docker create` — Rebuild, not
    Restart, after changing it. See `cetmix-tower-secrets` and
    `cetmix-tower-command-ssh`.
19. **A Jet is not deletable unless deletion is safe.** `jet.deletable` defaults to
    `true`; `unlink` is blocked while it is `false`. Set `False` on the first line of
    Prepare (before any host resource exists) and set `True` only as the last step of
    Destroy, after containers, volumes, files and DNS are gone. Do not unlock on
    Remove — data still exists. Reuse `set_jet_as_not_deletable` /
    `set_jet_as_deletable`. See `cetmix-tower-jets`.
20. **A Jet template ships the logs operators need to run it.** Empty
    `server_log_ids` is a defect — a Jet with no logs is hard to control and
    harder to repair. Nest `server_log` records on the template; they are copied
    onto each Jet at create (`cx.tower.jet.create`). Cover every surface used for
    control and maintenance: at least the process's own stdout/stderr
    (`log_type: command`, typically `docker logs`; reuse `show_jet_logs` when it
    exists), plus application files that log elsewhere (`log_type: file` and a
    `source: server` file template), and extra command logs for health or sidecar
    processes when those are how an operator diagnoses the service. Log commands
    run with the Jet in context, so `{{ tower.jet.reference }}` resolves. They
    must be `ssh_command` or `python_code` with `allow_parallel_run: true`. See
    `cetmix-tower-jets` and `cetmix-tower-servers`.

## Authority order

Never answer from memory, a forum or a blog:

1. **Cetmix Tower source code** — `cetmix_tower_base/models/*.py` (tags, vault,
   shared mixins) and `cetmix_tower_server/models/*.py` for fields, selections and
   constraints; `cetmix_tower_yaml/models/*.py` (`_get_fields_for_yaml`)
   for the exact importable field list per model. Optional modules extend both — check
   `cetmix_tower_git/models/` and `cetmix_tower_webhook/models/` too. Groups live in
   `cetmix_tower_base/security/cetmix_tower_base_groups.xml`
   (`cetmix_tower_base.group_user`, `group_manager`, `group_root`).
2. **Official documentation** — the `cetmix-tower-doc` mkdocs tree (external to this
   repo): `mkdocs/docs/developer-guidelines/yaml_format_specification.md` and
   `mkdocs/docs/reference/**`.
3. **Real exported YAML** — the `cetmix-tower-packages` repository holds working,
   Tower-generated snippets. Copy their shape.
4. These skills.

When code and docs disagree, **the code wins** — say so and note the divergence.

## Do not claim validation you did not run

Reading YAML is not validating it. Either run it through the Tower YAML
validator/import, or state plainly that the file is **not runtime-validated** and give
the user the import steps. Never fabricate a validation result, and always list the
secrets the user must fill in manually.
