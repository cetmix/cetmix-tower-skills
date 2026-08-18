---
name: cetmix-tower-command-ssh
description:
  Write Cetmix Tower SSH commands (command records with action ssh_command) — the
  one-statement rule, why never to use &&, ; , cd or inline sudo, how to use the path
  and use_sudo fields instead, idempotency, OS scoping, variables and secrets inside
  shell code, and server_status side effects. Use when authoring or reviewing any
  shell-side Tower command.
---

# SSH commands

`cetmix_tower_model: command` with `action: ssh_command`. Runs one shell statement on
the remote host over SSH, as the server's SSH user.

## The four hard rules

### 1. One command = one statement

No `&&`, no `||`, no `;`, no newline-separated statements. If you need three things to
happen, that is three commands and three flight plan lines.

```yaml
# Wrong
code: apt-get update && apt-get upgrade -y && apt-get install -y nginx

# Right — three command records
code: DEBIAN_FRONTEND=noninteractive apt-get update
code: DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
code: DEBIAN_FRONTEND=noninteractive apt-get -y install nginx
```

Why:

- **Reuse.** `apt-get update` is used by every plan you will ever write.
- **sudo splitting.** When a command containing `&&` runs under _sudo-with-password_,
  Tower splits on `&&` and executes each part as a separate `exec_command`. Logic that
  depends on the chaining silently changes meaning. (`_prepare_ssh_command` splits on
  `&&` only — `;` and `||` are passed through to the shell intact, which is worse, not
  better: they stay joined under a single `sudo` and give you one opaque exit code.)
- **Flow control.** Exit codes and post-run actions are per line. Chained commands give
  you one opaque code.
- **Logs.** Each line logs separately, so a failure names one step.

A single statement **may** span several physical lines with backslash continuations or
long argument lists — `docker create --name x \` … is one statement and is fine.

`no_split_for_sudo: true` disables the sudo-splitting for a command that genuinely must
stay joined. Reach for it last, and say why in the `note`.

Legitimate cases — the operation is atomic and splitting it across plan lines loses the
guard. Set the flag **and** justify it in `note`:

- **Idempotency guards** — create a CA only if it does not already exist;
  `id -u app || useradd app`.
- **Wait loops** — start a container, then poll until `health=healthy`.
- **Capture-and-branch** — save output and act on it in the same host process.

Those are still one Tower command that happens to contain shell control flow. They are
not a licence to chain `apt-get update && apt-get upgrade`. If the branching is about
Tower records rather than the host, use a `python_code` command instead.

### 2. Never change directory

No `cd`, no `chdir`, no `pushd`. Use the `path` field:

- `command.path` — the command's default directory.
- `plan_line.path` — overrides the command's default for that line.

Both support variables. Tower adjusts the invocation so the directory is applied
correctly whether or not sudo is used.

```yaml
# Wrong
code: cd /home/{{ tower.server.username }}/memes && cat doge.txt

# Right
path: /home/{{ tower.server.username }}/memes
code: cat doge.txt
```

Ensure the SSH user can reach the path even when the command runs via sudo.

### 3. Never write `sudo` in the code

Use `use_sudo: true` on the **flight plan line** (or the checkbox in the run wizard).
Tower then applies the server's `use_sudo` setting — `n` (no password) or `p` (with
password) — which it cannot do if you hardcode `sudo`.

```yaml
# Wrong
code: sudo systemctl restart nginx

# Right
# command:
code: systemctl restart nginx
# plan_line:
use_sudo: true
```

### 4. Never inline a secret's value

Reference it: `#!cxtower.secret.<reference>!#`. Tower substitutes at render time and
masks it in previews and logs. See `cetmix-tower-secrets`.

Be aware that a secret passed as a **command-line argument** is masked in Tower's log
but visible in the host's process list — and a value with a quote, space, `$` or
backtick breaks the surrounding quoting, usually as an authentication error rather than
a syntax error. Never write `-a <secret>`, `--password <secret>` or `-e VAR='<secret>'`.
Render the secret into a file template and have the process read the file. See
`cetmix-tower-secrets`.

## Fields

| Field                | Notes                                                                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`               | Required. Human-readable, e.g. `Redis - create container`.                                                                                 |
| `reference`          | Required at top level. `snake_case`, self-explanatory.                                                                                     |
| `action`             | `ssh_command`                                                                                                                              |
| `code`               | The statement. Supports variables and secrets.                                                                                             |
| `path`               | Default directory. Supports variables.                                                                                                     |
| `access_level`       | `user` / `manager` / `root`. Default `manager`. Use `root` for destructive commands.                                                       |
| `allow_parallel_run` | Default `false`, which means only one copy per server at a time. Keep `false` for anything stateful.                                       |
| `no_split_for_sudo`  | Only when a joined statement must stay joined.                                                                                             |
| `os_ids`             | OSes this command is written for. Empty = all. Warning only, never a block.                                                                |
| `tag_ids`            | Always add something.                                                                                                                      |
| `note`               | Required by convention. Say what it does and any precondition.                                                                             |
| `server_status`      | Sets the **server's** status on success. Only for commands that really change host state (start/stop/restart a VM). Leave empty otherwise. |

`server_ids` cannot be set from YAML — imported commands are available to every server.

## Idempotency

Prefer statements that are safe to re-run, because plans get retried:

| Instead of              | Use                                                                                                                      |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `mkdir /opt/app`        | `mkdir -p /opt/app`                                                                                                      |
| `useradd app`           | `id -u app \|\| useradd app` with `no_split_for_sudo: true` and a note, or a post-run action that allows a non-zero exit |
| `docker rm x`           | `docker rm -f x`, or a post-run action allowing a non-zero code                                                          |
| `ln -s a b`             | `ln -sfn a b`                                                                                                            |
| `apt-get install nginx` | `DEBIAN_FRONTEND=noninteractive apt-get -y install nginx`                                                                |

When a command cannot be made idempotent, make the **plan** tolerant instead: add a
post-run action `if exit_code != 0 → Run next command`, or gate the line with a
`condition` set by a preceding Python command.

Always set `DEBIAN_FRONTEND=noninteractive` for apt, and `-y` for anything that prompts.
There is no TTY.

## Variables in shell code

Rendered with Jinja2 in **generic mode** — values are substituted raw, unquoted:

```bash
current_branch={{ branch }}      # -> current_branch=main
need_update={{ update_available }}  # -> need_update=False
```

Full Jinja2 is available:

```bash
docker run -d -p {{ app_port }}:8069 \
{% if app_workers and app_workers != '0' %}
  --env WORKERS={{ app_workers }} \
{% endif %}
  -v {{ app_data }}:/var/lib/app \
  {{ app_image }}
```

Quote values yourself where the shell needs it: `--name "{{ instance_name }}"`.

`--env-file` on `docker create` is read when the container is **created**. A later
push of that file does nothing until Rebuild runs `docker create` again. Restart is
not enough. Same for image tag and other create-time flags.

`docker run` that must read stdin (`--password-from-stdin`, a piped secret) needs
`-i`. Without it the CLI cannot read stdin; the command fails and may leave the
container stopped.

System values are available as `tower.server.*` and `tower.tools.*` — see
`cetmix-tower-variables`.

`variable_ids` on the command is **computed from `code` and `path`**, `secret_ids` from
`code` only; do not hand-maintain either. But the referenced `variable` and `key`
records must exist, so declare them in the same YAML file.

## Go template braces collide with Tower's renderer

`{{` is consumed by Tower's Jinja rendering.
`docker inspect --format '{{.State.Running}}'`, `docker ps --format`,
`kubectl -o go-template` and anything else using Go templates cannot be written
directly. The same collision applies to `code` you write on
`cx.tower.command.run.wizard` — the wizard still runs Tower's renderer.

Prefer brace-free equivalents:

```bash
# instead of --format '{{.State.Running}}'
docker ps -q --filter name=^NAME$

# instead of --format '{{.State.Health.Status}}'
docker ps -q --filter name=^NAME$ --filter health=healthy
```

If a Go template is unavoidable, wrap it so Jinja leaves it alone:

```bash
docker inspect --format '{% raw %}{{.State.Running}}{% endraw %}' NAME
```

## When an SSH command is the wrong tool

- **Calling an HTTP API and using the result in Tower** → Python command. Parsing `curl`
  output from a shell exit code is not workable.
- **Writing a config file** → File Template + a `file_using_template` command. Never a
  heredoc longer than a few lines inside `code`.
- **Deciding what to do next** → Python command setting `custom_values`, tested in the
  next line's `condition`.
- **Running several statements** → more lines, or a sub-plan. The named
  `no_split_for_sudo` exceptions (idempotency guards, wait loops, capture-and-branch)
  are the other path.

## Review checklist

- [ ] Exactly one statement; no `&&`, `||`, `;` unless `no_split_for_sudo: true` and the
      `note` names a legitimate exception (idempotency guard, wait loop,
      capture-and-branch)
- [ ] No `cd`; directory in `path`
- [ ] No `sudo` in code; `use_sudo` on the plan line
- [ ] No literal credentials; secrets referenced inline and **not** passed as argv
- [ ] No raw `{{.GoTemplate}}` — brace-free filters or `{% raw %}` (also in wizard
      `code` overrides)
- [ ] `--env-file` / create-time Docker flags followed by Rebuild, not Restart, when
      the file or image changes
- [ ] `docker run -i` when the process must read stdin
- [ ] Non-interactive (`-y`, `DEBIAN_FRONTEND`)
- [ ] Idempotent, or the plan tolerates the failure
- [ ] `note` filled in, tags added
- [ ] `allow_parallel_run: false` unless genuinely re-entrant
- [ ] Every `{{ variable }}` has a `variable` record in the file
- [ ] `os_ids` set when the syntax is distribution-specific
