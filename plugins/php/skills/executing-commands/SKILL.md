---
name: executing-commands
description: >
    REQUIRED: Execute this skill before running ANY project commands (composer, npm/pnpm/yarn, php, docker,
    etc.). It decides how each command runs in this project: a project task, the Taskfile's Compose wrapper,
    Docker Compose, a pinned `docker run`, or (last resort) the host. It also detects the project's Node
    package manager. Do not run composer, the Node package manager, node or php directly on the host while a
    container route exists.
---

# Repository Execution Rules

## Execution Model

Resolve every project command (composer, the Node package manager, php, artisan, …) through the tiers
below. Use the **first tier that applies**, and say which tier you used.

| Tier | Route                          | Applies when                                                        | Command                                                     |
|------|--------------------------------|---------------------------------------------------------------------|-------------------------------------------------------------|
| 1    | A specific task                | `task --list` has a task for the intent                             | `task <ns>:<name>`                                          |
| 2    | The Taskfile's Compose wrapper | The Taskfile has a `dc:run:*` (or similar) wildcard task            | `task dc:run:<service> -- <cmd>`                            |
| 3    | Docker Compose directly        | The project has Compose files, but no Taskfile or no `dc:*` wrapper | `docker compose --file … run --rm --user … <service> <cmd>` |
| 4    | Plain `docker run`             | The project has no Compose setup (and no scaffold was added)        | `docker run --rm … <pinned image> <cmd>`                    |
| 5    | The host                       | Tiers 1–4 are all impossible (e.g. Docker is not available)         | `<cmd>`, after the checks in tier 5                         |

No tier ends in "stop": every branch has a way to carry on. Whenever tiers 2–5 were needed, suggest adding a
proper task for the command in the result.

`docker` and `docker compose` are only run through tiers 3 and 4, with the flags described there. Commands only
run on the host under the tier 5 rules.

### Tier 1 — a specific task

```shell
task --list
task <ns>:<name>
```

`task --list` is the source of truth for any project: Specs projects, older projects with different task names,
and third-party projects with their own Taskfile (`Taskfile.yml`, `Taskfile.yaml`, `Taskfile.dist.yml`, …). Only
use tasks it shows. Prefer creating or extending a task over working around a missing one.

### Tier 2 — the Taskfile's Compose wrapper

```shell
task dc:run:php -- <command>
task dc:run:<service> -- <command>
```

Prefer this over raw Compose: the wrapper carries the project's `--file` set (e.g. `compose.yml` +
`compose.mounts.yml` + `compose.ports.yml`), the UID/GID mapping (`FIXUID`/`FIXGID`) and its profiles. Use an
exec wrapper (e.g. `dc:exec:<service>`) instead when the project has one and the service is running.

### Tier 3 — Docker Compose directly

When there is no Taskfile, or it has no `dc:*` wrapper:

- **Compose files:** use all of the project's Compose files — find them with `git ls-files`, matching
  `compose.yml`, `compose.*.yml`, `docker-compose.yml` and `docker-compose.*.yml` (plus `.yaml`), and pass each
  with `--file`. Leave out files that clearly target another environment (e.g. `compose.ci.yml`,
  `compose.prod.yml`) unless the command is for that environment. `docker compose --file … config --services`
  shows which services the set defines.
- **Service:** `php` by default. Otherwise the service that builds `php/Dockerfile` or uses a
  `ghcr.io/specsnl/php*` image. Only use another service when the user or the command explicitly asks for it. Add
  `--profile <name>` when that service sits behind a profile.
- **Run or exec:** `exec` when the service is up (`docker compose --file … ps --services --status running`),
  otherwise `run --rm`:

```shell
FIXUID="$(id -u)" FIXGID="$(id -g)" docker compose --file compose.yml --file compose.mounts.yml \
    run --rm --user "$(id -u):$(id -g)" php <command>
```

Export `FIXUID`/`FIXGID` (as above) when the Compose files reference them.

#### No Taskfile and no Compose setup: offer a scaffold

Before falling through to tiers 4–5, offer to scaffold a Taskfile and a Compose file — but only ask when someone
can answer: an interactive session with a question tool available, and not a headless (`claude -p`), CI (`CI`,
`GITHUB_ACTIONS`), scheduled or background run. If that can't be determined, treat the run as autonomous. Without
an answer, or when the user declines, don't scaffold: continue with tier 4 and include the scaffold suggestion in
the result. Only write the scaffold after the user agreed to it.

The scaffold is a Taskfile with tasks for the common commands (composer, the Node package manager, php), each
running through Docker, and a Compose file with the services those tasks need. Use the `dc` / `dc:run:*` tasks
and the `php-exec` service of the Specs template (`specsnl/specs-laravel-project`) as the reference shape:

- Put the new services in a `compose.yml`.
- If the project already has a Compose file, add the services to it only when that clearly can't break the
  current setup. If that can't be determined, create a separate `compose.taskfile.yml` and pass it with `--file`
  from the Taskfile's `dc` task, so the existing setup is left untouched.
- Run the services as `user: ${FIXUID:-1000}:${FIXGID:-1000}` with `entrypoint: ["fixuid", "-q"]` (Specsnl
  images), mount the project at `/var/www` and a named volume at `/cache`.
- Pin the images to a specific version, chosen as in tier 4.

### Tier 4 — plain `docker run`

When the project has no Compose setup (and no scaffold was added):

- **Image:** prefer the image the project already uses for the same or an equivalent job — look in Dockerfiles,
  CI workflows (e.g. a `php:8.3-cli` or `composer:2` job image) and docs. Fall back to the Specsnl images only
  when the project has none (see [Picking the PHP image](#picking-the-php-image)):
  - PHP / Composer / PHP tools: `ghcr.io/specsnl/php<xy>/builder:<version>`
  - Node / the Node package manager: `ghcr.io/specsnl/php<xy>/builder_nodejs:<version>` — it has corepack, so
    pnpm and yarn follow the `packageManager` field (see [Node package manager](#node-package-manager)).
- **Pull on demand:** `docker pull` a missing image without asking first, and mention which image and tag you
  pulled.
- **Always pin a specific version, never `latest`.** For Specsnl images, use the latest release tag of
  `specsnl/php<xy>` (`gh api repos/specsnl/php<xy>/releases/latest --jq .tag_name`). For other images, use the
  tag the project already uses, or the latest stable tag of the matching flavour.
- **Node version:** compare the image's Node (`node --version`) with `.nvmrc` / `.node-version` /
  `engines.node`, and warn on a mismatch rather than silently using a different major.

The invocation for the Specsnl images:

```shell
docker run --rm \
    --volume "$PWD":/var/www --workdir /var/www \
    --user "$(id -u):$(id -g)" --entrypoint fixuid \
    --volume specs-tooling-cache:/cache \
    ghcr.io/specsnl/php85/builder:<version> -q <command>
```

- The images have no entrypoint of their own: `--entrypoint fixuid` + `-q` maps the container user to your
  UID/GID, so files written to the project stay yours.
- The named volume at `/cache` keeps the Composer, npm and corepack caches between runs.
- Composer picks up an `auth.json` in the project root through the mount. When the credentials only exist as a
  `COMPOSER_AUTH` variable on the host, pass it through by name (`--env COMPOSER_AUTH`) so its value never shows
  up in a command line or output. Never print credentials.

For other images, use the same `--volume`, `--workdir` and `--user` flags, without the `fixuid` entrypoint.

Limits: no database or other services are reachable. Use this tier for standalone tooling only: composer, the Node
package manager, static analysis, unit tests without a DB. Skip the steps that need services and list them in the
result.

### Tier 5 — the host (last resort)

Only when tiers 1–4 are all impossible (e.g. Docker isn't available):

- First check that the tool runs on the host at all (`command -v <tool>`, its version output), and that its
  version matches the project's requirements (the PHP platform in `composer.json`, `engines.node`). If it can't
  run, skip the step that needs it, carry on with the rest of the work, and list the skipped step in the result.
- Before running anything, say clearly that the command will run **locally on the host**. Recommend adding a
  dedicated image or service (and a task) for the operation.

### When `task` is not installed

- **There is a Taskfile:** read the definition of the task that would have run (in the Taskfile and the files it
  includes) and run the same underlying command through tier 3: the same Compose files, service, flags and
  UID/GID mapping. Recommend installing `task` in the result (`brew install go-task/tap/go-task` on macOS).
- **There is no Taskfile:** go straight to tier 3 (or the scaffold offer).

## Picking the PHP image

The `docker:php-images` skill describes the Specsnl image naming and how to find the supported PHP versions. To
choose `<xy>`:

1. Take the PHP constraint from `config.platform.php` in `composer.json`, otherwise `require.php` (and/or the
   `platform` of `composer.lock`).
2. Pick the newest **supported** Specsnl PHP image that satisfies it. The supported set follows the endoflife.date
   rule of the `docker:php-images` skill.
3. Without a `composer.json`, use the newest supported image.

## Node package manager

Projects can use npm, pnpm or yarn. Detect the package manager (`<pm>`) once, and use it for every frontend
command — never assume npm. Skills and commands that write `<pm>` refer to this section.

### Detection

1. **`packageManager` in `package.json`** (`pnpm@10.x`, `yarn@4.x`, `npm@11.x`). This is authoritative, and
   corepack enforces it in the Specsnl `builder_nodejs` image.
2. **The lockfile:**
    - `pnpm-lock.yaml` → pnpm
    - `yarn.lock` → yarn: berry (v2+) when there is a `.yarnrc.yml` or `__metadata` in `yarn.lock`, otherwise
      classic
    - `package-lock.json` / `npm-shrinkwrap.json` → npm
3. **No signal:** npm.

**Conflicting signals** (several lockfiles, or a lockfile that doesn't match `packageManager`): carry on with the
strongest signal — `packageManager` first; otherwise the package manager the CI workflows install with (`npm ci`,
`pnpm install`, `yarn install`, or the `cache:` value of `actions/setup-node`); otherwise the most recently changed
lockfile (`git log -1 --format=%cI -- <lockfile>`). Record the conflict and the choice in the result, and suggest
removing the stray lockfile.

**Bun** (`bun.lock` / `bun.lockb`, or `packageManager: bun@…`) is not supported yet: skip the frontend steps and
report that the project uses Bun.

### Command map

| Intent               | npm            | pnpm                             | yarn classic                     | yarn berry                         |
|----------------------|----------------|----------------------------------|----------------------------------|------------------------------------|
| install (CI, frozen) | `npm ci`       | `pnpm install --frozen-lockfile` | `yarn install --frozen-lockfile` | `yarn install --immutable`         |
| in-range update      | `npm update`   | `pnpm update`                    | `yarn upgrade`                   | `yarn up -R '**'`                  |
| audit                | `npm audit`    | `pnpm audit`                     | `yarn audit`                     | `yarn npm audit --all --recursive` |
| outdated             | `npm outdated` | `pnpm outdated`                  | `yarn outdated`                  | none (only `upgrade-interactive`)  |
| run script           | `npm run <s>`  | `pnpm run <s>`                   | `yarn run <s>`                   | `yarn run <s>`                     |
| one-off binary       | `npx <bin>`    | `pnpm dlx <bin>`                 | `npx <bin>`                      | `yarn dlx <bin>`                   |

`yarn up -R '**'` re-resolves every dependency within its existing range without touching `package.json`; a
single `'*'` misses scoped packages.

### Taskfile interplay

The `npm:*` tasks of the Specs template call `npm` directly:

1. Use `task npm:*` only after checking that the project's npm tasks call the detected package manager (inspect
   `.taskfiles/Taskfile.npm.yml`).
2. Otherwise use a matching namespace when one exists (`pnpm:*`, `yarn:*`, `node:*`).
3. Otherwise run the command through the Compose wrapper (tier 2): `task dc:run:php -- pnpm install
   --frozen-lockfile`.

## Task namespaces (Specs projects)

The Taskfile of a Specs project is split into namespaces that are included from `Taskfile.yml` (`.taskfiles/Taskfile.<ns>.yml`).
The wildcard tasks take the rest of the task name as their argument, and everything after `--` is
forwarded to the underlying command:

| Task                                                   | Runs                                                                                                    |
|--------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `task composer:script:<name>`                          | a composer script from `composer.json` (`checkall`, `checkstyle`, `checktype`, `test`, `rector-dry`, …) |
| `task composer:cmd:<name>`                             | a raw composer command (`outdated`, `audit`, `why`, …)                                                  |
| `task npm:script:<name>`                               | an npm script from `package.json` (`build`, `test:e2e`, …) — npm projects only                          |
| `task npm:cmd:<name>`                                  | a raw npm command (`audit`, `outdated`, …) — npm projects only                                          |
| `task md:checkstyle` / `md:fixstyle` / `md:fix-tables` | markdown lint / fix / table alignment                                                                   |
| `task dc:run:<service> -- <command>`                   | any command in a Compose service (tier 2)                                                               |

Example with arguments: `task composer:cmd:outdated -- --direct --major-only`.

**Laravel only** (when `laravel/framework` is a dependency), the `artisan` and `db` namespaces run Artisan commands:

| Task                         | Runs                                                                        |
|------------------------------|-----------------------------------------------------------------------------|
| `task artisan:run:<command>` | `php artisan <command>` — colons included, e.g. `artisan:run:migrate:fresh` |
| `task db:migrate:<env>`      | migrations for `local` or `testing`                                         |

For example: `task artisan:run:db:seed -- --class='Database\Seeders\E2ETestSeeder'`.

Older projects may still use the previous `composer:run:*` / `npm:run:*` / `composer:do:*` naming, and
non-Specs projects may use entirely different names — `task --list` is always the source of truth.

## Container Context

The default execution service is `php` (in projects that use another name for the PHP service, such as `app`,
use that one).

All standard development commands run inside the Docker Compose service `php`.

Only use another service if:

- the user explicitly instructs it, or
- the command explicitly references that service.

If a command fails because services are not running, run (when the Taskfile has an `up` task):

```shell
task up
```

Then retry the original command. Without an `up` task, start the services through tier 3
(`docker compose --file … up --detach`).

To check if services are running, use `task ps` (or `docker compose --file … ps`).

## Examples

Run tests:

```shell
task composer:script:test
```

Run all checks (in Specs projects: phpcs, phpstan, phpunit, rector, audits, markdown):

```shell
task checkall
```

Install dependencies (`task npm:install` only when the npm tasks call the detected package manager):

```shell
task composer:install
task npm:install
task dc:run:php -- pnpm install --frozen-lockfile
```

Run an Artisan command (Laravel only):

```shell
task artisan:run:migrate
```

Anything without a task:

```shell
task dc:run:php -- <command>
```

A Composer library without a Taskfile or Compose files (tier 4):

```shell
docker run --rm --volume "$PWD":/var/www --workdir /var/www --user "$(id -u):$(id -g)" --entrypoint fixuid \
    --volume specs-tooling-cache:/cache ghcr.io/specsnl/php85/builder:<version> -q composer install
```
