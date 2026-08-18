---
name: cetmix-tower
description:
  Design and author Cetmix Tower entities — flight plans, commands, jet templates,
  variables, secrets, file templates, servers, server templates, waypoints, scheduled
  tasks, webhooks — usually delivered as an importable YAML file. Use whenever the
  request is to deploy, install, provision, configure, back up, start/stop or otherwise
  automate something with Cetmix Tower ("create a flight plan to deploy Redis", "make a
  jet template for WordPress", "add a command that…"), or to review/fix existing Tower
  YAML. Start here; it routes to the per-element skills.
---

# Cetmix Tower — authoring entities

Cetmix Tower is an Odoo-based DevOps platform. You automate infrastructure by **creating
records** (commands, flight plans, jet templates, variables, …), not by writing scripts
and not by SSH-ing anywhere yourself.

Entities are delivered in one of three ways — a YAML file someone imports, YAML built
and imported by code over the API, or direct ORM writes over the API. Establish which
one this project uses before you start; `references/decision-guide.md` §5 covers the
trade-offs, and `cetmix-tower-api` covers the API mechanics. When nothing indicates
otherwise, produce **one importable YAML file**.

## How to read the pointers below

A pointer that starts with a skill name — `cetmix-tower-yaml/references/model-fields.md`
— is relative to the **skills root** (the directory holding all the `cetmix-tower*`
directories: `.claude/skills/`, `.cursor/skills/`, or `skills/` in this repository),
not to this file. Reading it as written from inside this skill will not find it; go up
one level first. A bare `references/…` _is_ relative to this skill. A bare skill name
with no file after it means that skill's `SKILL.md`.

## Non-negotiable rules

The complete list is `references/hard-rules.md` — **seventeen rules, maintained in that
one file**, plus the authority order and the validation-honesty rule. Read it before
writing anything; the five below are only the highest-frequency ones.

1. **Never propose manual SSH or a shell script as the solution.** Everything is a
   Command, Flight Plan, Jet Template, Variable, Secret, File Template or Waypoint.
2. **One Command = one statement — `ssh_command` only.** No `&&`, `||`, `;`, no `cd`, no
   inline `sudo`; use flight plan lines instead. Shell-side only: `python_code` is
   ordinary Python and may use `;`. See `cetmix-tower-command-ssh`.
3. **Never invent fields.** Only fields listed in
   `cetmix-tower-yaml/references/model-fields.md` are imported; anything else is
   silently dropped. If unsure, read the source (see _Sources of truth_). Via the API
   the ORM accepts more than that list — but never anything that is not a real field.
4. **Never hardcode secrets, tokens, passwords or private keys.** Create `key` records
   and reference them inline. See `cetmix-tower-secrets`.
5. **Terminology is exact.** The YAML model for a Flight Plan is `plan`, never
   `flight_plan` — via the API it is `cx.tower.plan`. A plan line references a command
   via `command_id`, never `command`.

## Workflow

0. **Read `references/hard-rules.md`.** All seventeen rules, the authority order, and what
   you may and may not claim about validation.
1. **Understand the target.** What software, which OS, one instance or many, does it
   need to be started/stopped/backed up, does it depend on other services?
2. **Decide the shape.** Read `references/decision-guide.md` — it answers: Jet Template
   vs plain Flight Plan, one command vs many, SSH vs Python, monolithic vs atomized,
   what goes in a Variable vs a Secret vs metadata.
3. **Pick the elements.** Read `references/entity-map.md` for the full entity list, what
   each is for, and which model must be nested inside which parent.
4. **Reuse before creating.** Ask for (or grep) existing references first — commands
   like `update_packages`, tags, OSes and variables usually already exist. Referencing
   an existing record by reference is always better than defining a near-duplicate.
5. **Author the YAML.** Follow `cetmix-tower-yaml` for file structure and relational
   syntax, plus the per-element skill for each record type.
6. **Self-review against the checklist** below, then hand over the file with import
   instructions and the list of secrets the user must fill in manually.

A complete, verified example of both shapes for the same request ("deploy Redis") is in
`references/worked-example-redis.md`. Read it before writing your first file.

## Element skills

| Skill                          | Covers                                                                                                                             |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `cetmix-tower-yaml`            | File structure, model names, relational syntax, embed vs reference, import procedure, allowed-field reference                      |
| `cetmix-tower-api`             | Creating entities from code — `execute_kw`, ORM vs importer differences, contexts, access rights, upsert, running things           |
| `cetmix-tower-command-actions` | Choosing the `action`; the four orchestration actions (`plan`, `jet_action`, `create_waypoint`, `file_using_template`); exit codes |
| `cetmix-tower-command-ssh`     | `action: ssh_command` — the shell-side rules                                                                                       |
| `cetmix-tower-command-python`  | `action: python_code` — eval context, `result`, `custom_values`, metadata, provider APIs                                           |
| `cetmix-tower-flight-plan`     | `plan`, `plan_line`, conditions, post-run actions, error handling, sub-plans                                                       |
| `cetmix-tower-variables`       | `variable`, `variable_option`, `variable_value`, resolution order, rendering modes, `tower.*`                                      |
| `cetmix-tower-secrets`         | `key` — secrets and SSH keys, inline syntax, what YAML cannot carry                                                                |
| `cetmix-tower-files`           | `file_template`, `file`, `action: file_using_template`                                                                             |
| `cetmix-tower-jets`            | `jet_template`, `jet_state`, `jet_action`, lifecycle graph, dependencies                                                           |
| `cetmix-tower-waypoints`       | `jet_waypoint_template` — snapshots and backups                                                                                    |
| `cetmix-tower-servers`         | `server`, `server_template`, `server_log`, `os`, `tag`, `shortcut`                                                                 |
| `cetmix-tower-automation`      | `scheduled_task`, `webhook`, `webhook_authenticator`, `git_project`                                                                |

## Delivery checklist

Design rules below the first six items apply to **every** delivery path. The
YAML-specific items are marked; when delivering API code instead, swap them for the
checklist in `cetmix-tower-api/SKILL.md`.

_YAML-specific:_

- [ ] Top-level keys are only `cetmix_tower_yaml_version`, `manifest`, `records`.
- [ ] Every item in `records` has `cetmix_tower_model` **and** `reference`.
- [ ] Every field used appears in `cetmix-tower-yaml/references/model-fields.md` for
      that model.
- [ ] Child records that have no owner-link field are **nested**, not top-level
      (`plan_line`, `plan_line_action`, `jet_action`, `variable_option`, `server_log`,
      `shortcut`, `scheduled_task`, `scheduled_task_cv`, `jet_template_dependency`,
      `git_source`, `git_remote`, `git_project_rel`).
- [ ] Flat records are ordered so that every reference is defined before it is used;
      `key` records come first.
- [ ] `_id` fields are scalars; `_ids` fields are lists.

_Every path:_

- [ ] No `action: ssh_command` code contains `&&`, `||`, `;`, `cd` or `sudo` (the
      one-statement rule is shell-side only — `python_code` may of course use `;`).
- [ ] Every plan has at least one `line_ids` entry, and every line has a `command_id`.
- [ ] Each command's `action` has its required companion field set, and commands with
      action `plan`, `jet_action`, `create_waypoint` or `file_using_template` are
      reached through a flight plan (they have no ad-hoc run path).
- [ ] For jet templates: exactly one action with no `state_from_id` (create), exactly
      one with no `state_to_id` (destroy), every action has `state_transit_id`, and
      Build and Start use **different** plans (hard rule 11). Actions that do different
      things — Stop vs Remove vs Destroy — need the same separation; actions that do the
      **same** thing in different contexts may share a plan. See `cetmix-tower-jets`.
- [ ] Values a `file_using_template` must see are stored with `set_variable_value` on
      the jet or server, not only in `custom_values` (hard rule 17).
- [ ] Secrets referenced as `#!cxtower.secret.<reference>!#`, declared as `key` records,
      and listed for the user to fill in.
- [ ] Every record whose YAML field list includes `note` has one (child rows like
      `plan_line`, `plan_line_action`, `variable_option` and `server_log` do not — see
      hard rule 8).
- [ ] Every record whose YAML field list includes `tag_ids` has tags, including
      `variable` (hard rule 8).
- [ ] Commands are idempotent where the target allows it.

## Verifying your work

You cannot validate a definition by reading it.

**YAML path:**

1. `Cetmix Tower > Tools > Import YAML`, upload the file, **Process**. Structural errors
   (bad model, missing reference, unparseable YAML) surface here.
2. Choose _If Record Exists_ → `Skip record` on a first import into an **empty**
   database. Do not import onto an instance that already has the same logical
   templates under other references (hard rule 14). `Update existing record` is not
   a sync — see `cetmix-tower-yaml`.
3. **Import**. Field-level errors (bad selection value, failed constraint) surface here.
4. Fill in secret values manually (`Settings > Keys and Secrets`).
5. Run the plan from a server or jet form (`Run Flight Plan`) and read the plan log.

**API path:** run the script against a non-production database, then **run it a second
time** — that is the only way to prove the upsert logic is idempotent and that you are
not creating `_2`-suffixed duplicates. Check the created records in the UI, confirm no
unintended SSH transfer happened (file records), then exercise one plan and read its
log.

If the user has the Tower API/validator available, run the YAML through it and fix
reported errors before presenting; the validator is more authoritative than these docs.

## Sources of truth

Source code beats docs, docs beat these skills, and nothing comes from memory, a forum
or a blog. The full ordering, with the exact paths to grep, is in
`references/hard-rules.md`.

When code and docs disagree, **the code wins** — say so and note the divergence.
