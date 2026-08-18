# Cetmix Tower skills

Agent skills and Cursor rules for **creating [Cetmix Tower](https://tower.cetmix.com) entities** — flight plans,
commands, jet templates, variables, secrets, file templates, servers, waypoints,
scheduled tasks, webhooks — correctly, from a plain-language request such as _"create a
new flight plan to deploy Redis"_.

It is not tied to a particular machine: every path is resolved at install time. The same
source works with **Claude Code** and **Cursor**. You can adapt it to any other agentic tool as well.

## Quick start

```bash
git clone https://github.com/cetmix/cetmix-tower-skills.git
cd cetmix-tower-skills
./install.sh --user                  # every project on this machine
# or
./install.sh /path/to/your/project   # one project only
```

Or ask your agent to install the skills using this prompt:

> Clone https://github.com/cetmix/cetmix-tower-skills into a temporary directory, run
> `./install.sh /path/to/this/project` (or `./install.sh --user` to install for every
> project on this machine), then remove the clone. Restart the agent session when done.

Then restart the agent session. In Cursor the rule is **Agent Requested** by default.
Ask something like: _Create a flight plan to deploy Redis on Ubuntu 24.04._

## Layout

Source files sit at the repository root. `install.sh` links them into the agent
directories the tools actually read (`.claude/skills/`, `.cursor/skills/`,
`.cursor/rules/`). Do not put skills under `.cursor/` or `.claude/` in this repo —
those names are install destinations, not the source tree.

```
cetmix-tower-skills/
├── README.md                 this file
├── AGENTS.md                 short always-on digest for agents that read AGENTS.md
├── install.sh                symlink or copy skills into a project or your user config
├── rules/
│   └── cetmix-tower.mdc      Cursor rule: rule shortlist + index of the skills
└── skills/                   shared by Claude Code and Cursor (SKILL.md format)
    ├── cetmix-tower/                     START HERE — workflow, decisions, entity map
    │   └── references/
    │       ├── hard-rules.md             THE canonical rule list — edit rules only here
    │       ├── decision-guide.md         Jet vs plan, one command vs many, SSH vs Python, …
    │       ├── entity-map.md             every entity, its purpose, nesting rules
    │       └── worked-example-redis.md   the same request delivered two ways, validated
    ├── cetmix-tower-yaml/                file format, model names, relational syntax
    │   └── references/
    │       ├── model-fields.md           authoritative allowed fields per model
    │       └── selection-values.md       every selection key
    ├── cetmix-tower-api/                 creating entities from code (execute_kw / ORM)
    │   └── references/
    │       ├── yaml-vs-api.md            what each path can and cannot do
    │       └── access-matrix.md          per-model ACL, generated from security CSVs
    ├── cetmix-tower-command-actions/     the six actions; plan, jet_action,
    │   │                                 create_waypoint, file_using_template
    │   └── references/exit-codes.md      every Tower exit code and how to branch on it
    ├── cetmix-tower-command-ssh/         action: ssh_command
    ├── cetmix-tower-command-python/      action: python_code
    │   └── references/eval-context.md    injected objects, libraries, helper methods
    ├── cetmix-tower-flight-plan/         plan, plan_line, post-run actions
    ├── cetmix-tower-variables/           variable, variable_option, variable_value
    ├── cetmix-tower-secrets/             key — secrets and SSH keys
    ├── cetmix-tower-files/               file_template, file
    ├── cetmix-tower-jets/                jet_template, jet_state, jet_action
    │   └── references/lifecycle-patterns.md
    ├── cetmix-tower-waypoints/           jet_waypoint_template
    ├── cetmix-tower-servers/             server, server_template, server_log, shortcut, os, tag
    └── cetmix-tower-automation/          scheduled_task, webhook, git_*
```

### What belongs where

| Path | Role |
| ---- | ---- |
| `skills/<name>/SKILL.md` | One skill. Frontmatter `name` + `description`; body is the agent instructions. |
| `skills/<name>/references/` | Detail the agent should open only when needed (fields, exit codes, examples). |
| `rules/*.mdc` | Cursor-only index that points at the skills. Keep it a shortlist. |
| `AGENTS.md` | Digest for agents that auto-read `AGENTS.md` / `CLAUDE.md`. Shortlist + pointers. |

**Authoring rules live in one file:** `skills/cetmix-tower/references/hard-rules.md`.
`AGENTS.md`, `rules/cetmix-tower.mdc` and `skills/cetmix-tower/SKILL.md` each carry a
five-rule shortlist and a pointer to that file. Do not duplicate the full list.

Cross-skill pointers are skill-name-first — `cetmix-tower-yaml/references/model-fields.md`
— and resolve against the **skills root** (this repo's `skills/`, or
`.claude/skills/` / `.cursor/skills/` after install). A bare `references/…` is relative
to the current skill.

## Install

```bash
./install.sh --user
./install.sh /path/to/project
```

That links every directory under `skills/` into `.claude/skills/` and `.cursor/skills/`,
and every `rules/*.mdc` file into `.cursor/rules/`.

| Command                          | Effect                                                               |
| -------------------------------- | -------------------------------------------------------------------- |
| `install.sh --user`              | Install into `~/.claude` and `~/.cursor`, available in every project |
| `install.sh /path/to/project`    | Install into one project                                             |
| `install.sh --copy /path`        | Copy instead of symlink — for Windows, CI or containers              |
| `install.sh --agents /path`      | Also link `AGENTS.md` at the target root                             |
| `install.sh --uninstall --user`  | Remove a user install                                                |
| `install.sh --uninstall /path`   | Remove a project install                                             |
| `install.sh --force /path`       | Also replace real (non-symlink) destinations                         |

Symlinks are relative when `python3` is available, so a linked checkout stays portable.
A destination that is already a real file or directory is left untouched unless you pass
`--force`. Run `./install.sh --help` for the full comment block.

### Manual install

If you would rather not run the script, or you keep your agent config in a shared
directory:

- **Claude Code** — copy or symlink each `skills/<name>/` directory into
  `.claude/skills/` (project) or `~/.claude/skills/` (user). Optionally add a line to
  `CLAUDE.md` pointing at this repository's `AGENTS.md`.
- **Cursor** — copy or symlink each `skills/<name>/` directory into `.cursor/skills/`,
  and `rules/cetmix-tower.mdc` into `.cursor/rules/`.
- **Anything else** — point the agent at `AGENTS.md`, which links onward to the skills.

## Usage

Ask in plain language. The router skill (`cetmix-tower`) decides the shape of the answer
and pulls in the element skills it needs.

```
Create a flight plan to deploy Redis on Ubuntu 24.04.
Make a jet template for WordPress with Traefik and MariaDB.
Add a command that rotates the Odoo filestore backups to S3.
Review this Tower YAML for schema and lifecycle problems.
Why does my jet template fail to import?
```

In Cursor the rule is **Agent Requested** — Cursor loads it when the request matches its
description. To make it always-on, set `alwaysApply: true` in
`.cursor/rules/cetmix-tower.mdc` after install.

### Working against a live Tower instance (API)

To create or update entities directly in your Odoo database, give the agent connection
details and a task. The agent uses Odoo's external API (`execute_kw`) or the YAML import
wizard over the API — see the `cetmix-tower-api` skill.

**Connection (use placeholders — never paste real secrets into chat logs or git):**

| Setting | Value |
| ------- | ----- |
| Server  | `<odoo_instance_url>` |
| DB      | `<odoo_db_name>` |
| Login   | `<odoo_user_login>` |
| Pass    | `<API_token>` |

**Important:** Always rotate the API token after use. Never share tokens publicly or
commit them to version control.

**Example prompt:**

> Create a setup to run Odoo together with n8n on `<server_reference>`. It will serve 20
> internal and 40 portal users. It must have dev, staging, and prod environments.
>
> Server: `<odoo_instance_url>`  
> DB: `<odoo_db_name>`  
> Login: `<odoo_user_login>`  
> Pass: `<API_token>`

The agent will design the Tower entities (servers, variables, flight plans, jet
templates, secrets to fill in manually, and so on) and apply them through the API or
deliver importable YAML, depending on what the task needs.

## Delivery paths

Entities reach the database three ways, and the skills cover all three:

| Path                            | Use when                                                                                                         | Skill                      |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------- |
| YAML file, imported by a person | A human applies the change, or it belongs in git                                                                 | `cetmix-tower-yaml`        |
| YAML built and imported by code | Bulk creation from a script — keeps the importer's reference resolution, dedup, translation and single savepoint | `cetmix-tower-api` §Hybrid |
| Direct ORM writes over the API  | Reads, updates, operations, and fields YAML cannot carry                                                         | `cetmix-tower-api`         |

**The paths are not equivalent.** Only the API can set secret values, delete x2m
children, create Jets and waypoints, or query state; only YAML gives reference linking,
deferred forward references and one atomic transaction per file. YAML `update` is
additive — it never removes children you dropped from the file. The full asymmetry table
is `skills/cetmix-tower-api/references/yaml-vs-api.md`.

"The API" means Odoo's external API (`execute_kw`) or in-process Python.

## What the agent will and will not do

It will produce a single importable YAML file — or API code, when that is the project's
path — list the secrets you must fill in manually, and give you the steps to apply it.

It will **not** claim the file is validated unless it actually ran it through the Tower
YAML validator or the import wizard. Reading YAML is not validating it.

## Adding or changing a skill

1. Create `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`) and a
   concise body. Put long tables and examples in `skills/<name>/references/`.
2. Name the skill `cetmix-tower-<topic>` so install destinations stay grouped and the
   router can find it.
3. Link it from `skills/cetmix-tower/SKILL.md` (element-skills table) and from
   `rules/cetmix-tower.mdc`.
4. If you are adding an authoring **rule**, edit
   `skills/cetmix-tower/references/hard-rules.md` and nothing else.

Keep `SKILL.md` files short. Progressive disclosure: the agent opens `references/` only
when the task needs that detail.

## Maintenance

The field and selection references are derived from Tower's source, not from prose, so
they go stale when Tower changes. After a Tower upgrade, regenerate them from a
Cetmix Tower checkout:

```bash
find cetmix_tower_yaml/models cetmix_tower_git/models cetmix_tower_webhook/models -name '*.py' -exec awk '/def _get_fields_for_yaml/,/return/ {print FILENAME": "$0}' {} +
```

(The `awk` range stops at each method's `return`, so nothing is truncated when a model
gains fields — unlike a fixed `grep -A <n>` window.)

and update:

- `skills/cetmix-tower-yaml/references/model-fields.md` — allowed fields per model
- `skills/cetmix-tower-yaml/references/selection-values.md` — selection keys
- `skills/cetmix-tower-command-python/references/eval-context.md` — injected objects,
  libraries and `cetmix.tower` helper methods
- `skills/cetmix-tower-command-actions/references/exit-codes.md` — from
  `cetmix_tower_server/models/constants.py`
- `skills/cetmix-tower-api/references/access-matrix.md` — from every
  `cetmix_tower_*/security/ir.model.access.csv`, plus the group implication chain in
  `cetmix_tower_server/security/cetmix_tower_server_groups.xml`
- `skills/cetmix-tower-jets/references/lifecycle-patterns.md` — shipped `jet_state`
  records, from `cetmix_tower_server/data/cx_tower_jet_state.xml`

Known divergences between the shipped documentation and the code are flagged inside the
skills — notably that most `cetmix.tower` helper methods are deprecated in favour of the
model methods, and that the Git reference page predates the `cx.tower.git.repo` model.

## Sources

Built from, in authority order: the Cetmix Tower source code (`cetmix_tower_server`,
`cetmix_tower_yaml`, `cetmix_tower_webhook`, `cetmix_tower_git`), the public
documentation at [tower.cetmix.com](https://tower.cetmix.com), and real exported YAML in
`cetmix-tower-packages`.

## License

AGPL-3 — Cetmix OU

## Author

Ivan Sokolov
