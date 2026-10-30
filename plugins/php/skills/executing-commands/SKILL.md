---
name: executing-commands
description: >
    REQUIRED: Execute this skill before running ANY project commands (composer, npm, php, docker, etc.).
    This ensures all commands run safely through the Taskfile when the project has one. Do not run
    docker compose, npm, php, or composer directly on the host.
---

# Repository Execution Rules

## Execution Model

When the project has a Taskfile (`Taskfile.yml`, `Taskfile.yaml`, `Taskfile.dist.yml`, …), all project commands
MUST be executed via the Taskfile. Agents MUST NOT call Docker Compose commands directly.

Never run directly on the host (outside `task`):

- php
- npm
- node
- composer
- docker compose
- docker

Always use:

```shell
task <task-name>
```

To list all available tasks, use:

```shell
task --list
```

`task --list` is the source of truth for any project: Specs projects, older projects with different task names,
and third-party projects with their own Taskfile. Only use tasks it shows.

Projects without a Taskfile have no tasks to go through. Use the commands the project documents (README,
contributing guide, composer scripts, CI workflows), and run them inside the project's containers when it has
Compose files.

## Task namespaces (Specs projects)

The Taskfile of a Specs project is split into namespaces that are included from `Taskfile.yml` (`.taskfiles/Taskfile.<ns>.yml`).
The wildcard tasks take the rest of the task name as their argument, and everything after `--` is
forwarded to the underlying command:

| Task                                                   | Runs                                                                                                    |
|--------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `task composer:script:<name>`                          | a composer script from `composer.json` (`checkall`, `checkstyle`, `checktype`, `test`, `rector-dry`, …) |
| `task composer:cmd:<name>`                             | a raw composer command (`outdated`, `audit`, `why`, …)                                                  |
| `task npm:script:<name>`                               | an npm script from `package.json` (`build`, `test:e2e`, …)                                              |
| `task npm:cmd:<name>`                                  | a raw npm command (`audit`, `outdated`, …)                                                              |
| `task md:checkstyle` / `md:fixstyle` / `md:fix-tables` | markdown lint / fix / table alignment                                                                   |

Example with arguments: `task composer:cmd:outdated -- --direct --major-only`.

**Laravel only** (when `laravel/framework` is a dependency), the `artisan` and `db` namespaces run Artisan commands:

| Task                         | Runs                                                                        |
|------------------------------|-----------------------------------------------------------------------------|
| `task artisan:run:<command>` | `php artisan <command>` — colons included, e.g. `artisan:run:migrate:fresh` |
| `task db:migrate:<env>`      | migrations for `local` or `testing`                                         |

For example: `task artisan:run:db:seed -- --class='Database\Seeders\E2ETestSeeder'`.

Older projects may still use the previous `composer:run:*` / `npm:run:*` / `composer:do:*` naming, and
non-Specs projects may use entirely different names — `task --list` is always the source of truth.

If a task does not exist:

1. Inspect the [Taskfile](./Taskfile.yml) and the files it includes under `.taskfiles/`.
2. Prefer creating or extending a task.
3. As a temporary fallback, use `task dc:run:php -- <command>` unless another service is explicitly
   required (`task dc:run:<service> -- <command>`). This still executes via the Taskfile.

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

Then retry the original command.

To check if services are running, use:

```shell
task ps
```

## Examples

Run tests:

```shell
task composer:script:test
```

Run all checks (in Specs projects: phpcs, phpstan, phpunit, rector, audits, markdown):

```shell
task checkall
```

Install dependencies:

```shell
task composer:install
task npm:install
```

Run an Artisan command (Laravel only):

```shell
task artisan:run:migrate
```

Anything without a task:

```shell
task dc:run:php -- <command>
```
