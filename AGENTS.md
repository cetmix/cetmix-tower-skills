# Cetmix Tower — agent digest

Always-on summary for agents that read `AGENTS.md` / `CLAUDE.md`. It is deliberately
short: the detail lives in the skills, which you should open before writing anything.

## What Tower work looks like

Cetmix Tower is an Odoo-based DevOps platform. You automate infrastructure by **creating
records**, not by writing scripts and not by connecting to hosts yourself.

Records reach the database one of three ways — a YAML file a person imports, YAML built
and imported by code over the API, or direct ORM writes over the API. Establish which
the project uses before starting. A YAML file has exactly three possible top-level keys:
`cetmix_tower_yaml_version`, `manifest`, `records`. For API work read `cetmix-tower-api`
first — model names, `access_level` encoding, command tuples and the `from_yaml` /
`skip_ssh_settings_check` contexts all differ from YAML, and there is **no REST API
module** (`cetmix_tower_api` is an unimplemented spec).

## Read these first

Names below are **skill names**, not paths relative to this file. Each is a directory
under the installed skills root (`.claude/skills/`, `.cursor/skills/`, or
`skills/` in this repository), holding a `SKILL.md` and sometimes a `references/`
folder.

The same convention applies **inside** the skills. A cross-skill pointer is written
skill-name-first — `cetmix-tower-yaml/references/model-fields.md` — and is resolved
against the skills root, never against the file quoting it. Only a bare `references/…`
with no skill name is relative to the current skill.

Start with `cetmix-tower` (hard rules, workflow, decision guide, entity map, worked
example) — its `references/hard-rules.md` is the canonical rule list — then
`cetmix-tower-yaml` (format) or `cetmix-tower-api` (code path), then the skill for each
element you are authoring: `cetmix-tower-command-actions`, `cetmix-tower-command-ssh`,
`cetmix-tower-command-python`, `cetmix-tower-flight-plan`, `cetmix-tower-variables`,
`cetmix-tower-secrets`, `cetmix-tower-files`, `cetmix-tower-jets`,
`cetmix-tower-waypoints`, `cetmix-tower-servers`, `cetmix-tower-automation`.

## Hard rules

The complete list of seventeen rules, the authority order, and the validation-honesty rule
live in **one canonical file**: `references/hard-rules.md` inside the **`cetmix-tower`
skill**. Depending on how the assets were installed, that is
`.claude/skills/cetmix-tower/references/hard-rules.md`,
`.cursor/skills/cetmix-tower/references/hard-rules.md`, or
`skills/cetmix-tower/references/hard-rules.md` in this repository. **Open it before
writing anything.** It is the only place rules are maintained — everything below is a
shortlist, not a substitute.

The five that catch the most mistakes:

1. No manual SSH, no shell scripts — Commands, Flight Plans, Jet Templates, Variables,
   Secrets, File Templates, Waypoints.
2. One Command = one statement, for `action: ssh_command`. No `&&`, `||`, `;`; no `cd`
   (use `path`); no inline `sudo` (use `use_sudo` on the plan line). Shell-side only —
   `python_code` is ordinary Python.
3. Never invent a field. Unknown keys import silently and do nothing. Check
   `cetmix-tower-yaml/references/model-fields.md`.
4. Never hardcode credentials and never put them in a variable. Use a `key` record and
   `#!cxtower.secret.<ref>!#`.
5. Flight Plan's YAML model is `plan`, not `flight_plan`. Plan lines use `command_id`,
   not `command`.

Never answer from memory, a forum or a blog. When code and docs disagree, the code wins
— and say so. Reading YAML is not validating it: either run the import, or say plainly
that the file is **not runtime-validated**.
