---
name: executing-commands
description: >
    REQUIRED: Execute this skill before running ANY project commands (composer, npm, php, docker, etc.). 
    This ensures all commands run safely through the Taskfile. Do not run docker compose, npm, php, 
    or composer directly on the host.
---

# Repository Execution Rules

## Execution Model

All project commands MUST be executed via the Taskfile. Agents MUST NOT call Docker Compose commands directly.

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

## Task namespaces

The Taskfile is split into namespaces that are included from `Taskfile.yml` (`.taskfiles/Taskfile.<ns>.yml`).
The wildcard tasks take the rest of the task name as their argument, and everything after `--` is
forwarded to the underlying command:

| Task                                                   | Runs                                                                                                    |
|--------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `task composer:script:<name>`                          | a composer script from `composer.json` (`checkall`, `checkstyle`, `checktype`, `test`, `rector-dry`, …) |
| `task composer:cmd:<name>`                             | a raw composer command (`outdated`, `audit`, `why`, …)                                                  |
| `task artisan:run:<command>`                           | `php artisan <command>` — colons included, e.g. `artisan:run:migrate:fresh`                             |
| `task npm:script:<name>`                               | an npm script from `package.json` (`build`, `test:e2e`, …)                                              |
| `task npm:cmd:<name>`                                  | a raw npm command (`audit`, `outdated`, …)                                                              |
| `task db:migrate:<env>`                                | migrations for `local` or `testing`                                                                     |
| `task md:checkstyle` / `md:fixstyle` / `md:fix-tables` | markdown lint / fix / table alignment                                                                   |

Examples with arguments: `task composer:cmd:outdated -- --direct --major-only`,
`task artisan:run:db:seed -- --class='Database\Seeders\E2ETestSeeder'`.

Older projects may still use the previous `composer:run:*` / `npm:run:*` / `composer:do:*` naming —
`task --list` is always the source of truth.

If a task does not exist:

1. Inspect the [Taskfile](./Taskfile.yml) and the files it includes under `.taskfiles/`.
2. Prefer creating or extending a task.
3. As a temporary fallback, use `task dc:run:php -- <command>` unless another service is explicitly
   required (`task dc:run:<service> -- <command>`). This still executes via the Taskfile.

## Container Context

The default execution service is `php`.

All standard development commands run inside the Docker Compose service `php`.

Only use another service if:

- the user explicitly instructs it, or
- the command explicitly references that service.

If a command fails because services are not running, run:

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

Run all checks (phpcs, phpstan, phpunit, rector, audits, markdown):

```shell
task checkall
```

Install dependencies:

```shell
task composer:install
task npm:install
```

Anything without a task:

```shell
task dc:run:php -- <command>
```
