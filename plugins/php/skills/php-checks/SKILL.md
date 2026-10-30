---
name: php-checks
description: >
  Use this skill to prepare the environment and run the PHP quality tools of a project locally —
  code style (PHP_CodeSniffer / PHP-CS-Fixer / Pint), static analysis (PHPStan / Larastan / Psalm),
  tests (PHPUnit / Pest), Rector and the markdown linter — through the Taskfile when the project has
  one. It is the PHP layer of the `ci-green-check` skill, which invokes it whenever a repository has
  a `composer.json`; that skill owns check discovery, the fix loop, and the final report. Also
  triggers directly when the user says "run checkall", "run phpstan", "run phpcs" or "run the tests"
  in a PHP repository.
---

# PHP checks

> **Prerequisite — Command execution rules apply.**
> The `executing-commands` skill governs how every command in this skill must be run: a project task
> first (run `task --list` to see what this project actually exposes), then its Compose wrapper,
> Docker Compose, a pinned `docker run`, and the host only as a last resort.

This skill is the stack-specific half of `ci-green-check`. That skill discovers which checks exist
(Taskfile + `.github/workflows`), drives the fix loop and writes the final report. This one provides
the environment setup and the exact commands.

When the project has a Taskfile, check that `task` is installed:

```bash
task --version 2>/dev/null || echo "task not installed"
```

If `task` is not installed, follow the "When `task` is not installed" rule of `executing-commands`: run
the command the task would have run through Docker Compose, and recommend installing `task` in the
report (`brew install go-task/tap/go-task` on macOS).

**Laravel only** — Larastan, `ide-helper` and `artisan` apply only when `laravel/framework` is a
dependency in `composer.json`. Skip everything marked Laravel only in other projects.

## Task naming in Specs projects

The Taskfile is split into namespaces (`composer`, `artisan`, `npm`, `db`, `md`, `setup`, `e2e`,
`cleanup`, `worktrees`). Wildcard tasks take the rest of the name as their argument, and everything
after `--` is forwarded to the underlying command:

| Task                          | Runs                                                                                          |
|-------------------------------|-----------------------------------------------------------------------------------------------|
| `task composer:script:<name>` | a composer **script** from `composer.json` (`checkall`, `checkstyle`, `checktype`, `test`, …) |
| `task composer:cmd:<name>`    | a raw **composer command** (`outdated`, `audit`, `why`, …)                                    |
| `task composer:install`       | `composer install` inside the `php` service                                                   |
| `task composer:update`        | `composer update --with-all-dependencies`                                                     |
| `task artisan:run:<command>`  | **Laravel only:** `php artisan <command>` (colons included: `artisan:run:migrate:fresh`)      |
| `task <pm>:script:<name>`     | a **script** from `package.json` (`build`, `test:e2e`, …); `<pm>` is `npm`, `pnpm` or `yarn`  |
| `task <pm>:cmd:<name>`        | a raw **package manager command** (`audit`, `outdated`, …)                                    |
| `task md:checkstyle`          | markdownlint over the repo                                                                    |
| `task md:fixstyle`            | fix table spacing, then markdownlint `--fix`                                                  |
| `task checkall`               | `composer:script:checkall` + `md:checkstyle`                                                  |
| `task dc:run:<service> -- …`  | any command in a Compose service, when no specific task exists                                |

Older projects may still use the previous `composer:run:*` / `npm:run:*` / `composer:do:*` naming,
and non-Specs projects may use their own task names or have no Taskfile at all.
**Always confirm against `task --list` before running anything** and use whatever that project
exposes.

---

## Step 1: Prepare the environment

When the Taskfile has an `up` task:

```bash
task up
```

In Specs projects, `task up` templates `.env` / `.env.testing`, runs the one-time `setup` (auth.json,
build, composer and npm install, `key:generate`, `storage:link`, fresh migrations for `local` and
`testing`, asset build) when the project has never been started, and brings the containers up. It is
idempotent — run it rather than reproducing those steps by hand.

If dependencies drifted after a pull (new migrations, changed lock files), run `task refresh` when
the Taskfile has it.

Without those tasks, prepare the environment through `executing-commands`: start the services when
the project has Compose files, then install the dependencies (`composer install`). Libraries without
services only need the install.

Verify with file checks only — never host commands:

```bash
[ -f vendor/autoload.php ] && echo "vendor: ok" || echo "vendor: MISSING — install the dependencies"
```

Applications that use a `.env` file (when there is a `.env.example`) also need it:

```bash
[ -f .env ] && echo ".env: ok" || echo ".env: MISSING — run task up, or copy .env.example"
```

Projects that require private Composer repositories need credentials: an `auth.json` in the project
root, or Composer's global auth when Composer runs on the host. In Specs projects
`composer:install` has a precondition on `auth.json`; if it is missing, `task setup:auth` creates an
empty one.

---

## Step 2: Run the checks

### Find the tools

Do not assume which tools a project uses. Find them, in this order:

1. **The Taskfile** — an aggregate task such as `checkall` (Specs projects), or per-tool tasks.
2. **The composer scripts** — `composer run-script --list` (or the `scripts` section of
   `composer.json`). Scripts carry the project's own flags and configuration, so prefer them over
   calling a tool's binary directly.
3. **`require-dev` in `composer.json`** — a tool without a script or task runs through its binary
   in `vendor/bin`:

| Purpose         | Package in `require-dev`                                  | Check                                      | Fix                           |
|-----------------|-----------------------------------------------------------|--------------------------------------------|-------------------------------|
| Code style      | `squizlabs/php_codesniffer`                               | `vendor/bin/phpcs`                         | `vendor/bin/phpcbf`           |
| Code style      | `friendsofphp/php-cs-fixer`                               | `vendor/bin/php-cs-fixer fix --dry-run -v` | `vendor/bin/php-cs-fixer fix` |
| Code style      | `laravel/pint`                                            | `vendor/bin/pint --test`                   | `vendor/bin/pint`             |
| Static analysis | `phpstan/phpstan`, `larastan/larastan` (**Laravel only**) | `vendor/bin/phpstan analyse`               | —                             |
| Static analysis | `vimeo/psalm`                                             | `vendor/bin/psalm`                         | —                             |
| Tests           | `phpunit/phpunit`                                         | `vendor/bin/phpunit`                       | —                             |
| Tests           | `pestphp/pest`                                            | `vendor/bin/pest`                          | —                             |
| Refactoring     | `rector/rector`                                           | `vendor/bin/rector process --dry-run`      | `vendor/bin/rector process`   |

Also run `composer validate --strict` and `composer audit`, which every project has. Cross-check the
list against the CI workflows that `ci-green-check` discovered: a tool CI runs is a check, even when
no script or task wraps it.

### The fast path in Specs projects

```bash
task checkall
```

This is what CI effectively gates on: `composer:script:checkall` runs `composer validate --strict`,
`checkstyle` (phpcs), `checktype` (phpstan), `test` (phpunit), `rector-dry` and `composer audit`, and
`md:checkstyle` lints the markdown. Prefer it over running the tools one by one.

### Individual tools in Specs projects

Run these when `checkall` fails and you want a tight feedback loop on one tool.

```bash
# Code style — PHP_CodeSniffer
task composer:script:checkstyle          # phpcs -n
task composer:script:fixstyle            # phpcbf -n — auto-fixes, run this first on style failures

# Static analysis — PHPStan (Larastan in Laravel projects)
task composer:script:checktype
task composer:script:update-type-baseline    # only when the user explicitly agrees to baseline it

# Tests — PHPUnit (not Pest)
task composer:script:test
task composer:script:test-report             # with coverage
task composer:script:update-test-snapshots   # only when a snapshot change is intended

# Rector
task composer:script:rector-dry
task composer:script:rector                  # applies the changes

# Dependency audits
task composer:cmd:audit
task <pm>:cmd:audit                          # e.g. task pnpm:cmd:audit

# Markdown
task md:checkstyle
task md:fixstyle

# Front-end build
task <pm>:script:build                       # e.g. task pnpm:script:build
```

The frontend commands go through the project's Node package manager (`<pm>`), detected by the "Node
package manager" section of `executing-commands`, which also maps each intent to its `<pm>` command. The
tasks are named after the package manager (`npm:*`, `pnpm:*`, `yarn:*`): use the namespace that matches
`<pm>`. When the Taskfile only has another manager's namespace, run the `<pm>` command (e.g. `pnpm audit`,
`pnpm run build`) through `executing-commands` instead.

Pass extra arguments after `--`, e.g. `task composer:cmd:outdated -- --direct --major-only` or
`task composer:script:test -- --filter=SomeTest`.

**Laravel only:** note what CI runs that these tasks do not: the **Model DocBlocks** job regenerates
`php artisan ide-helper:models --write` and fails on a dirty `app/Models/`. When the project uses
`barryvdh/laravel-ide-helper`, reproduce it with `task artisan:run:ide-helper:models -- --write` (or
`php artisan ide-helper:models --write` through `executing-commands`) and commit any resulting diff.

### E2E (only in projects with an `e2e` namespace)

```bash
task e2e:docker:test     # what CI runs, against the running stack
task e2e:test            # Playwright UI on the host
```

---

## Step 3: Hand back

Report per tool what ran and what its result was, so `ci-green-check` can drive the fix loop and
produce the final ✅ / ⚠️ report. Do not declare the work done from here — that is `ci-green-check`'s
Step 6.

Checks that cannot run locally and must be left to CI: the Composer and Node package manager cache-warming jobs and
anything needing `COMPOSER_AUTH_JSON` beyond a local `auth.json`.
