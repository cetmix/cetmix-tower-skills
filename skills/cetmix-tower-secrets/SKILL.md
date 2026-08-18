---
name: cetmix-tower-secrets
description: Handle sensitive data in Cetmix Tower — key records of type Secret and SSH
  Key, the inline reference syntax #!cxtower.secret.ref!#, secret value priority (server+partner, server, partner, global), why YAML can never carry secret values, and the rules against putting credentials in variables, command code or file content. Use whenever a token, password, API key or private key is involved.
---

# Secrets and SSH keys

One model, `cetmix_tower_model: key`, two types:

| `key_type` | Purpose                                                                                  |
| ---------- | ---------------------------------------------------------------------------------------- |
| `s`        | **Secret** — a token, password or any sensitive string used inline in commands and files |
| `k`        | **SSH Key** — a private key selectable in server settings                                |

## Non-negotiable rules

1. **Never hardcode a credential** in command code, file content, a variable value, a
   note, or the YAML you deliver.
2. **Never store a credential as a variable.** Variable values are rendered verbatim
   into command previews and logs. Secrets are masked in both.
3. **Never ask the user to paste a value into the chat.** Create the `key` record, tell
   them the reference, and let them enter it in the UI — or have an API-driven flow read
   it from a real secret store and write it (see rule 4).
4. **YAML cannot carry secret values; the API can.** The `key` model's YAML field list
   is only `reference`, `name`, `key_type`, `note`. But `key.secret_value`,
   `key.value.secret_value`, `server.ssh_password` and `server.host_key` are
   vault-backed fields that `create`/`write` accept over the API — reads always return
   `*****`. So an unattended provisioning flow can set secrets; a YAML import never can.
   Details: `cetmix-tower-api/SKILL.md`.
5. Never use the banned helpers `_get_secret_value(`, `_get_secret_values(`,
   `_set_secret_values(` in Python command code — Tower rejects the command at save
   time.

## Declaring a secret

```yaml
- cetmix_tower_model: key
  reference: redis_password
  key_type: s
  name: Redis Password
  note: Value for Redis 'requirepass'. Must be set manually after import.
```

Put `key` records **first** in a flat file. `key` is **not** one of the
deferred-resolution fields, and a forward reference does **not** raise: the importer
logs a warning, skips the link, and the import **succeeds**. You get a server with an
empty `ssh_key_id`, or a dropped secret link, and no error anywhere in the UI. Server
import also runs with `skip_ssh_settings_check=True`, so even the "Please provide SSH
Key" constraint stays silent. Order the records correctly — nothing will tell you if you
did not.

## Using a secret

Inline, in an SSH command, a Python command, a file, or a file template:

```
#!cxtower.secret.<reference>!#
```

Three dot-separated parts, terminated by the mandatory `!#`:

- `#!cxtower` — the prefix Tower looks for
- `secret` — the type
- `<reference>` — the key's `reference` field

```bash
# SSH command
mkdir /home/#!cxtower.secret.my_secret_dir!#
```

```python
# Python command — never quoted; the value is injected already quoted
api_token = #!cxtower.secret.hetzner_api_token!#
```

```
# File template content
requirepass #!cxtower.secret.redis_password!#
admin_passwd = #!cxtower.secret.odoo_db_manager_password!#
```

The `Reference Code` field on the key form shows the complete inline string to copy.

`secret_ids` on commands, file templates, files, webhooks and authenticators is
**computed from `code`** — Tower discovers which secrets you used. Do not hand-maintain
it; just declare the `key` records.

## Value priority

A secret can hold several values. At render time Tower picks the most specific match:

1. Server **and** partner both match the current context
2. Server matches, partner unset
3. Partner matches, server unset
4. Global — neither set

This is how one `db_password` reference resolves differently per customer or per host
without changing a single command.

## SSH keys

```yaml
- cetmix_tower_model: key
  reference: production_ssh_key
  key_type: k
  name: Production SSH Key
  note: Deploy key for production hosts. Private key must be pasted in the UI.
```

Referenced from `server.ssh_key_id` / `server_template.ssh_key_id`, used when
`ssh_auth_mode: k`. The key value is write-only and inaccessible after saving.

`server.ssh_password` is not importable either — no YAML path exists for it.

## Access

Users have **no access** to keys at all. Managers can read secrets and manage keys they
are listed on; Root can do anything. Access roles (`user_ids` / `manager_ids`) are not
importable — set them in the UI.

## Where a secret is still exposed

Masking covers Tower's previews and logs, not the target system:

- A secret in **argv** (`-a`, `--password`, `-e VAR=`) is readable via host `ps`,
  `docker inspect` and `docker ps --no-trunc`. See the next section — do not put one
  there at all.
- A secret written into a file on the host lives there in plaintext. Set restrictive
  permissions in a following command and consider `keep_when_deleted: false`.
- A secret sent to a third-party API is on the wire. Use HTTPS and a `timeout`.

Mention these where relevant rather than implying secrets are safe everywhere.

## Substitution is verbatim — never a shell argument

`#!cxtower.secret.X!#` is a literal text replacement with **no shell escaping**. A value
containing a quote, space, `$` or backtick breaks whatever quoting you wrapped around
it. The failure looks like an **authentication error** (`WRONGPASS`, `401`), not a
syntax error — you will debug the password before the quoting.

Render the secret into a **file template**. A config file has no shell parsing, so any
byte is safe; have the process read that file. The worked example's `requirepass` line
in `redis.conf` is the pattern.

Never write `-a <secret>`, `--password <secret>`, or `-e VAR='<secret>'`. Anything in
argv is also readable via `docker inspect`, `docker ps --no-trunc` and host `ps`.

Piping a secret on stdin (`docker run … --password-from-stdin`) still needs
`docker run -i`. Without `-i` the process cannot read the pipe; the command fails and
may leave the container stopped.

## Handover

Every delivery that references secrets must list them for the user:

> Before running this, set values for these secrets in
> `Cetmix Tower > Settings > Keys and Secrets`:
>
> - `redis_password` — the Redis `requirepass` value
> - `hetzner_api_token` — a Hetzner Cloud API token with write scope

The import wizard also lists every secret found in the file, so the references you use
must match real `key` records or the user will not know what to fill in.

## Review checklist

- [ ] No literal credential anywhere in the YAML
- [ ] Every `#!cxtower.secret.X!#` has a matching `key` record with `key_type: s`
- [ ] `key` records appear before their first use in a flat file
- [ ] No credential stored as a `variable` or `variable_value`
- [ ] `secret_ids` not hand-maintained
- [ ] Secrets listed in the handover message and in the manifest `description`
- [ ] No secret in a shell argument (`-a`, `--password`, `-e VAR=`); file template
      instead
- [ ] `docker run -i` when a secret is piped on stdin
- [ ] No banned `_get_secret_value(` / `_get_secret_values(` / `_set_secret_values(`
