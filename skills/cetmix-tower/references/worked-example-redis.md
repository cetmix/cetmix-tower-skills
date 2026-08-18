# Worked example — "create a flight plan to deploy Redis"

The same request, delivered two ways. Read variant A first; variant B reuses all of it.

Assumptions stated up front (always do this): Docker is already installed on the target
host; Redis runs as a container; the host is Debian/Ubuntu family.

One deliberate divergence from `cetmix-tower-yaml`: this example spells out keys that
equal their defaults (`access_level: manager`, `variable_type: s`,
`keep_when_deleted: false`, `on_error_action: e`) so each record reads as a complete
picture. In a file you hand to a user, follow _Omit defaults_ in `cetmix-tower-yaml` and
drop them. The `note`, `reference` and lifecycle keys are **not** optional — copy those.

---

## Variant A — Flight Plan (what was literally asked for)

Shape decision: a single Redis per host, deployed once, managed by Docker afterwards → a
plain Flight Plan is right. Note to the user that a Jet Template would add
start/stop/backup from the UI.

### Element inventory

| Element       | Records                                                                          |
| ------------- | -------------------------------------------------------------------------------- |
| Secret        | `redis_password`                                                                 |
| Variables     | `redis_instance_name`, `redis_port`, `redis_data_dir`, `redis_version` (options) |
| File template | `redis_conf`                                                                     |
| Commands      | 7 — 2× mkdir, 1× push config, 1× pull, 1× create, 1× start, 1× ping              |
| Flight plan   | `deploy_redis`                                                                   |
| Tags          | `redis`, `docker`                                                                |

### The file

```yaml
# Deploy Redis as a Docker container.
cetmix_tower_yaml_version: 1
manifest:
  name: Deploy Redis (Docker)
  summary: Flight Plan that deploys a password-protected Redis container
  description: |
    Deploys a single Redis container on a host that already has Docker installed.

    Technology stack:
    - Debian/Ubuntu host
    - Docker Engine
    - Redis (image tag chosen by the redis_version variable)

    Configuration required before use:
    1. Set a value for the 'redis_password' secret
       (Cetmix Tower > Settings > Keys and Secrets).
    2. Review the global values of redis_port, redis_data_dir,
       redis_instance_name and redis_version, or override them per server.
    3. Ensure Docker is installed on the target server.

    How to use:
    1. Open the Server form.
    2. Run Flight Plan > Deploy Redis (Docker).
    3. Check the Flight Plan log; the last line runs 'redis-cli ping'.

    Troubleshooting:
    - "permission denied ... docker.sock": enable Use Sudo on the docker plan lines,
      or add the SSH user to the 'docker' group.
    - Container starts then exits: check {{ redis_data_dir }}/conf/redis.conf on the host.
  author: Cetmix
  version: 1.0.0
  license: agpl-3
records:
  # ---------------------------------------------------------------- tags
  - cetmix_tower_model: tag
    reference: redis
    name: Redis
    color: 1
  - cetmix_tower_model: tag
    reference: docker
    name: Docker
    color: 4

  # ---------------------------------------------------------------- secret
  # Secret VALUES are never carried by YAML. This creates the placeholder only.
  - cetmix_tower_model: key
    reference: redis_password
    key_type: s
    name: Redis Password
    note: Value for Redis 'requirepass'. Must be set manually after import.

  # ---------------------------------------------------------------- variables
  - cetmix_tower_model: variable
    reference: redis_instance_name
    name: Redis Instance Name
    variable_type: s
    note: Docker container name for this Redis instance.
    # The pattern is checked against the value as STORED, before rendering, so the
    # second branch has to let a '{{ ... }}' value through - variant B sets this
    # variable to 'redis_{{ tower.jet.reference }}'. A plain Docker-name pattern
    # would reject that value at import time.
    validation_pattern: '^([a-zA-Z0-9][a-zA-Z0-9_.-]*|.*\{\{.+\}\}.*)$'
    validation_message:
      Must be a valid Docker container name, or a template producing one.
  - cetmix_tower_model: variable
    reference: redis_port
    name: Redis Port
    variable_type: s
    note: Host port published for Redis.
    validation_pattern: ^[0-9]{1,5}$
    validation_message: Must be a port number.
  - cetmix_tower_model: variable
    reference: redis_data_dir
    name: Redis Data Directory
    variable_type: s
    note: Root directory on the host holding the 'data' and 'conf' subdirectories.
  - cetmix_tower_model: variable
    reference: redis_version
    name: Redis Version
    variable_type: o
    note: Redis image tag.
    option_ids:
      - reference: redis_version_7_4
        sequence: 10
        name: "7.4"
        value_char: "7.4"
      - reference: redis_version_7_2
        sequence: 20
        name: "7.2"
        value_char: "7.2"

  # --------------------------------------------------- global default values
  # A top-level variable_value has no owner, which makes it a GLOBAL value.
  # Override per server or per jet where needed.
  - cetmix_tower_model: variable_value
    reference: redis_instance_name_global
    variable_id: redis_instance_name
    value_char: redis
  - cetmix_tower_model: variable_value
    reference: redis_port_global
    variable_id: redis_port
    value_char: "6379"
  - cetmix_tower_model: variable_value
    reference: redis_data_dir_global
    variable_id: redis_data_dir
    value_char: /opt/{{ redis_instance_name }}
  - cetmix_tower_model: variable_value
    reference: redis_version_global
    variable_id: redis_version
    value_char: "7.4"

  # ---------------------------------------------------------------- file template
  - cetmix_tower_model: file_template
    reference: redis_conf
    name: Redis configuration
    source: tower
    file_type: text
    server_dir: "{{ redis_data_dir }}/conf"
    file_name: redis.conf
    keep_when_deleted: false
    tag_ids:
      - redis
    note: redis.conf rendered from Tower variables and the redis_password secret.
    code: |
      bind 0.0.0.0
      port 6379
      protected-mode yes
      requirepass #!cxtower.secret.redis_password!#
      appendonly yes
      appendfsync everysec
      dir /data

  # ---------------------------------------------------------------- commands
  # One statement per command. No '&&', no ';', no 'cd', no inline 'sudo'.
  - cetmix_tower_model: command
    reference: redis_create_data_dir
    name: Redis - create data directory
    action: ssh_command
    access_level: manager
    note: Creates the Redis persistent data directory on the host.
    tag_ids:
      - redis
    code: mkdir -p {{ redis_data_dir }}/data

  - cetmix_tower_model: command
    reference: redis_create_conf_dir
    name: Redis - create config directory
    action: ssh_command
    access_level: manager
    note: Creates the directory the rendered redis.conf is pushed into.
    tag_ids:
      - redis
    code: mkdir -p {{ redis_data_dir }}/conf

  - cetmix_tower_model: command
    reference: redis_push_conf
    name: Redis - push redis.conf
    action: file_using_template
    access_level: manager
    note: >-
      Renders the redis_conf template and uploads it to the server. Only usable inside a
      Flight Plan.
    tag_ids:
      - redis
    file_template_id: redis_conf
    if_file_exists: overwrite

  - cetmix_tower_model: command
    reference: redis_pull_image
    name: Redis - pull image
    action: ssh_command
    access_level: manager
    note: Pulls the Redis image. Idempotent.
    tag_ids:
      - redis
      - docker
    code: docker pull redis:{{ redis_version }}

  - cetmix_tower_model: command
    reference: redis_create_container
    name: Redis - create container
    action: ssh_command
    access_level: manager
    note: >-
      Creates (does not start) the Redis container. Belongs to Build, never to Start —
      re-running it on an existing container fails.
    tag_ids:
      - redis
      - docker
    code: |-
      docker create --name {{ redis_instance_name }} \
        --restart unless-stopped \
        -p {{ redis_port }}:6379 \
        -v {{ redis_data_dir }}/data:/data \
        -v {{ redis_data_dir }}/conf/redis.conf:/usr/local/etc/redis/redis.conf:ro \
        redis:{{ redis_version }} \
        redis-server /usr/local/etc/redis/redis.conf

  - cetmix_tower_model: command
    reference: redis_start_container
    name: Redis - start container
    action: ssh_command
    access_level: manager
    note: Starts the existing Redis container. Idempotent.
    tag_ids:
      - redis
      - docker
    code: docker start {{ redis_instance_name }}

  - cetmix_tower_model: command
    reference: redis_ping
    name: Redis - ping
    action: ssh_command
    access_level: manager
    note: >-
      Health check. Returns PONG when Redis is up and the password is accepted. Reads
      requirepass from the mounted redis.conf so the secret never enters the outer shell
      or the container argv.
    tag_ids:
      - redis
    code: >-
      docker exec {{ redis_instance_name }} sh -c 'REDISCLI_AUTH=$(sed -n
      "s/^requirepass //p" /usr/local/etc/redis/redis.conf) redis-cli --no-auth-warning
      ping'

  # ---------------------------------------------------------------- flight plan
  - cetmix_tower_model: plan
    reference: deploy_redis
    name: Deploy Redis (Docker)
    access_level: manager
    allow_parallel_run: false
    color: 1
    tag_ids:
      - redis
      - docker
    note: >-
      Creates directories, pushes redis.conf, pulls the image, creates and starts the
      container, then verifies with a ping. Requires Docker on the host.
    on_error_action: e
    line_ids:
      - reference: deploy_redis_line_10
        sequence: 10
        command_id: redis_create_data_dir
      - reference: deploy_redis_line_20
        sequence: 20
        command_id: redis_create_conf_dir
      - reference: deploy_redis_line_30
        sequence: 30
        command_id: redis_push_conf
      - reference: deploy_redis_line_40
        sequence: 40
        command_id: redis_pull_image
      - reference: deploy_redis_line_50
        sequence: 50
        command_id: redis_create_container
        action_ids:
          - reference: deploy_redis_line_50_action_10
            sequence: 10
            condition: "!="
            value_char: "0"
            action: ec
            custom_exit_code: 21
      - reference: deploy_redis_line_60
        sequence: 60
        command_id: redis_start_container
      - reference: deploy_redis_line_70
        sequence: 70
        command_id: redis_ping
```

### Why it looks like that

- `key` first, then variables, then the file template, then commands, then the plan —
  every reference is defined before it is used.
- Global `variable_value` records give sane defaults without touching any server.
- `redis_data_dir`'s value uses `{{ redis_instance_name }}`: variables may compose.
- `requirepass` in `redis.conf` is how the secret reaches Redis. The ping command reads
  that file inside the container (`/usr/local/etc/redis/redis.conf` is where this
  example mounts it) so the secret never enters the outer shell or argv. A
  `-a #!cxtower.secret…!#` form breaks on any metacharacter in the password and shows up
  as WRONGPASS.
- `docker create` and `docker start` are **separate** commands. That separation is what
  makes variant B possible without rewriting anything.
- `allow_parallel_run: false` — two concurrent runs would fight over the same container.
- The post-run action on line 50 turns "container already exists" into a distinct exit
  code 21, so the log says which step failed.
- No `variable_ids` / `secret_ids` on the commands: those fields are **computed from
  `code`**, so Tower fills them itself. Declaring the `variable` and `key` records
  explicitly (as above) is what actually matters.

---

## Variant B — Jet Template (managed instances)

Shape decision: the user wants several Redis instances per host, each startable,
stoppable and snapshottable → Jet Template.

Everything from variant A is reused. Only the plans and the template are new: the seven
commands are split across lifecycle plans instead of one long plan.

**Several instances per host means the per-instance values must actually differ.**
Variant A's global values are a single instance's values — `redis_instance_name: redis`,
`redis_data_dir: /opt/{{ redis_instance_name }}`, `redis_port: '6379'`. Left as they
are, a second Jet on the same host reuses the container name, the data directory and the
host port, and Build fails (or worse, succeeds against the first instance's data). Two
things have to change:

- **Container name and data directory** — overridden on the jet template with
  `{{ tower.jet.reference }}`, which is unique per Jet. `redis_data_dir` is composed
  from `redis_instance_name`, so overriding the name alone moves the directory too.
- **Host port** — there is nothing to derive it from, so it must be entered per Jet in
  the Create Jet wizard (_custom settings_). Tower will not force this: `required: true`
  on a `variable_value` is honoured by the Server Template create wizard and the Command
  Run wizard, but the Create Jet wizard neither pre-fills its variable lines nor checks
  them. So no template-level default is given for `redis_port`. A variable with no value
  anywhere renders as the literal `None` (it is passed to Jinja as `None`, not left
  undefined), so a forgotten port produces `-p None:6379` and Build fails on that line —
  noisy, but far better than a second Jet silently fighting the first over 6379.

Say this to the user; it is the part of the request that the YAML cannot enforce on its
own.

```yaml
cetmix_tower_yaml_version: 1
manifest:
  name: Redis Jet Template (Docker)
  summary:
    Managed Redis instances with a full Prepare/Build/Start/Stop/Remove/Destroy
    lifecycle
  description: |
    Monolithic Jet Template running one Redis container per Jet.

    Configuration required before use:
    1. Import the "Deploy Redis (Docker)" snippet first — this file references its
       commands, variables and secret by reference.
    2. Set the 'redis_password' secret value.
    3. Install this Jet Template on the target server(s).

    How to use:
    Create Jet from template. The Create Jet wizard can target state "Running" to
    run Prepare -> Build -> Start in one go.

    IMPORTANT - one value per Jet:
    Each Jet publishes its own host port, and Tower cannot pick one for you.
    In the Create Jet wizard choose "custom settings" and add a redis_port line
    with a port that is free on the target host (6379, 6380, 6381, ...).
    The container name and data directory are derived from the Jet reference
    automatically, so those need no input.
  author: Cetmix
  version: 1.0.0
  license: agpl-3
records:
  # Extra commands the lifecycle needs beyond variant A
  - cetmix_tower_model: command
    reference: redis_stop_container
    name: Redis - stop container
    action: ssh_command
    access_level: manager
    note: Stops the running Redis container. Does not remove it.
    tag_ids:
      - redis
      - docker
    code: docker stop {{ redis_instance_name }}

  - cetmix_tower_model: command
    reference: redis_remove_container
    name: Redis - remove container
    action: ssh_command
    access_level: manager
    note: Removes the stopped container. Leaves the data directory intact.
    tag_ids:
      - redis
      - docker
    code: docker rm {{ redis_instance_name }}

  - cetmix_tower_model: command
    reference: redis_remove_data_dir
    name: Redis - remove data directory
    action: ssh_command
    access_level: manager
    note: Destroys all Redis data for this instance. Irreversible.
    tag_ids:
      - redis
    code: rm -rf {{ redis_data_dir }}

  # One plan per lifecycle action. Never share a plan between Build and Start.
  - cetmix_tower_model: plan
    reference: redis_jet_prepare
    name: Redis Jet - Prepare
    access_level: manager
    tag_ids: [redis, docker]
    note: Creates the directory structure and pushes redis.conf.
    on_error_action: e
    line_ids:
      - reference: redis_jet_prepare_line_10
        sequence: 10
        command_id: redis_create_data_dir
      - reference: redis_jet_prepare_line_20
        sequence: 20
        command_id: redis_create_conf_dir
      - reference: redis_jet_prepare_line_30
        sequence: 30
        command_id: redis_push_conf

  - cetmix_tower_model: plan
    reference: redis_jet_build
    name: Redis Jet - Build
    access_level: manager
    tag_ids: [redis, docker]
    note:
      Pulls the image and creates the container. Creates resources; never reused by
      Start.
    on_error_action: e
    line_ids:
      - reference: redis_jet_build_line_10
        sequence: 10
        command_id: redis_pull_image
      - reference: redis_jet_build_line_20
        sequence: 20
        command_id: redis_create_container

  - cetmix_tower_model: plan
    reference: redis_jet_start
    name: Redis Jet - Start
    access_level: manager
    tag_ids: [redis, docker]
    note: Starts the existing container and verifies it answers PING.
    on_error_action: e
    line_ids:
      - reference: redis_jet_start_line_10
        sequence: 10
        command_id: redis_start_container
      - reference: redis_jet_start_line_20
        sequence: 20
        command_id: redis_ping

  - cetmix_tower_model: plan
    reference: redis_jet_stop
    name: Redis Jet - Stop
    access_level: manager
    tag_ids: [redis, docker]
    note: Stops the container. Does not remove anything.
    on_error_action: e
    line_ids:
      - reference: redis_jet_stop_line_10
        sequence: 10
        command_id: redis_stop_container

  - cetmix_tower_model: plan
    reference: redis_jet_remove
    name: Redis Jet - Remove
    access_level: manager
    tag_ids: [redis, docker]
    note: >-
      Removes the container. The data directory is left on the host, so a Destroy is
      still needed to reclaim the disk.
    on_error_action: e
    line_ids:
      - reference: redis_jet_remove_line_10
        sequence: 10
        command_id: redis_remove_container

  - cetmix_tower_model: plan
    reference: redis_jet_destroy
    name: Redis Jet - Destroy
    access_level: manager
    tag_ids: [redis, docker]
    note: Final teardown. Deletes the data directory. Irreversible.
    on_error_action: n
    line_ids:
      - reference: redis_jet_destroy_line_10
        sequence: 10
        command_id: redis_remove_data_dir

  # ---------------------------------------------------------------- jet template
  - cetmix_tower_model: jet_template
    reference: redis_jet
    name: Redis (Docker)
    # No access_level here: it is not in jet_template's YAML field list and would be
    # silently dropped. Per-action access is set on each jet_action below.
    show_in_create_wizard: true
    limit_per_server: 0
    tag_ids: [redis, docker]
    note: >-
      Runs one password-protected Redis container per Jet. Requires Docker on the
      server. Data lives in {{ redis_data_dir }} on the host. Set redis_port per Jet in
      the Create Jet wizard - it is the one value that must be unique per host and Tower
      cannot pick it for you.
    variable_value_ids:
      - reference: redis_jet_version_value
        variable_id: redis_version
        value_char: "7.4"
      # Overrides variant A's global 'redis'. tower.jet.reference is unique per Jet, so
      # this is what makes several instances per host possible. redis_data_dir is
      # '/opt/{{ redis_instance_name }}', so it follows without a second override.
      - reference: redis_jet_instance_name_value
        variable_id: redis_instance_name
        value_char: redis_{{ tower.jet.reference }}
    # No redis_port value here on purpose - see the note above. A template-level
    # default would silently collide on the second Jet.
    # jet_action has no jet_template_id in YAML, so actions MUST be nested here.
    # Lifecycle states below are the ones shipped with Tower — never redefine them.
    action_ids:
      - reference: redis_jet_action_prepare
        name: Prepare
        priority: 10
        access_level: manager
        state_transit_id: preparing
        state_to_id: draft
        plan_id: redis_jet_prepare
        note: Entry action - no From State, so the Create Jet wizard uses it.
      - reference: redis_jet_action_build
        name: Build
        priority: 20
        access_level: manager
        state_from_id: draft
        state_transit_id: building
        state_to_id: stopped
        state_error_id: draft
        plan_id: redis_jet_build
        note: Pulls the image and creates the container. Leaves the Jet stopped.
      - reference: redis_jet_action_start
        name: Start
        priority: 30
        access_level: user
        state_from_id: stopped
        state_transit_id: starting
        state_to_id: running
        state_error_id: stopped
        plan_id: redis_jet_start
        note: Starts the existing container and verifies it answers PING.
      - reference: redis_jet_action_stop
        name: Stop
        priority: 40
        access_level: user
        state_from_id: running
        state_transit_id: stopping
        state_to_id: stopped
        state_error_id: running
        plan_id: redis_jet_stop
        note: Stops the container. Data and the container itself are kept.
      - reference: redis_jet_action_remove
        name: Remove
        priority: 50
        access_level: manager
        state_from_id: stopped
        state_transit_id: removing
        state_to_id: removed
        state_error_id: stopped
        plan_id: redis_jet_remove
        note: >-
          Removes the container, leaving the data directory on the host. Note that
          'removed' is a one-way door in this graph - Destroy is the only action out of
          it. To make the kept data reusable, add a Rebuild action (removed -> building
          -> stopped) running the Build plan.
      - reference: redis_jet_action_destroy
        name: Destroy
        priority: 60
        access_level: manager
        state_from_id: removed
        state_transit_id: destroying
        plan_id: redis_jet_destroy
        note: Terminal action - no To State, so it destroys the Jet.
```

### Lifecycle audit

| Action  | From    | Transit    | To      | Role                      |
| ------- | ------- | ---------- | ------- | ------------------------- |
| Prepare | —       | preparing  | draft   | single entry (create)     |
| Build   | draft   | building   | stopped | creates resources         |
| Start   | stopped | starting   | running | starts existing resources |
| Stop    | running | stopping   | stopped |                           |
| Remove  | stopped | removing   | removed |                           |
| Destroy | removed | destroying | —       | single exit (destroy)     |

Reachable from the entry, `running` is both entered and left, no dead ends, exactly one
entry and one exit. The `stopped ⇄ running` loop is intended, not a defect.

Read the _From_ column before writing any `note` that promises a rebuild: the only
action whose `state_from_id` is `removed` is Destroy, so `removed` leads nowhere else.
Keeping the data directory in Remove buys a cheaper Destroy and a manual recovery path,
**not** a second Build. If the lifecycle should support re-building in place, that is
one more action — `Rebuild: removed → building → stopped`, reusing `redis_jet_build` —
and it does not disturb the one-create / one-destroy rule because it has both a From and
a To state.

### Orchestration example — stopping dependents first

If an app Jet depends on this Redis Jet, Redis's Stop plan should stop the apps first.
That is what `action: jet_action` is for. Note the wrapper: `jet_action` commands cannot
be run ad hoc, and the fan-out targets _dependent Jets_, not a Jet you name.

```yaml
- cetmix_tower_model: command
  reference: stop_dependent_app_jets
  name: Stop dependent App Jets
  action: jet_action
  access_level: manager
  note: >-
    Triggers the App template's Stop action on every App Jet linked to the current Jet
    by a dependency. Succeeds as a no-op when there are none.
  jet_template_id: app_jet
  jet_action_id: app_jet_action_stop

- cetmix_tower_model: plan
  reference: redis_jet_stop
  name: Redis Jet - Stop
  access_level: manager
  tag_ids: [redis, docker]
  note: Stops dependent App Jets first, then the Redis container.
  on_error_action: e
  line_ids:
    - reference: redis_jet_stop_line_05
      sequence: 5
      command_id: stop_dependent_app_jets
    - reference: redis_jet_stop_line_10
      sequence: 10
      command_id: redis_stop_container
```

This requires `app_jet` to declare `template_requires_ids` pointing at `redis_jet`, and
the concrete Jets to be linked. Without that the line quietly does nothing — see
`cetmix-tower-command-actions/SKILL.md`.

### What to add for production

- `plan_install_id` — a plan that installs Docker when the template is installed on a
  server, so the Jet cannot be created on an unprepared host.
- A `jet_waypoint_template` for backup/restore (`redis-cli BGSAVE` + copy the dump on
  create, restore on arrive). See `cetmix-tower-waypoints`.
- Python commands in Prepare/Build setting `jet.write({"deletable": False})` and in
  Destroy setting it back to `True`, so a half-built Jet cannot be deleted.
- `template_requires_ids` if you split Docker out into its own Jet Template (atomized
  shape).
