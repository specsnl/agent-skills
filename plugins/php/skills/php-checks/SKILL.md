---
name: php-checks
description: >
  Use this skill to prepare the environment and run the PHP/Laravel quality tools of a Specs project
  locally — PHP_CodeSniffer, PHPStan/Larastan, PHPUnit, Rector and the markdown linter — all through
  the Taskfile. It is the PHP/Laravel layer of the `ci-green-check` skill, which invokes it whenever
  a repository has a `composer.json`; that skill owns check discovery, the fix loop, and the final
  report. Also triggers directly when the user says "run checkall", "run phpstan", "run phpcs" or
  "run the tests" in a Laravel/PHP repository.
---

# PHP / Laravel checks

> **Prerequisite — Command execution rules apply.**
> The `executing-commands` skill governs how every command in this skill must be run.
> Never run `php`, `composer`, `npm`, `node`, `docker`, or `docker compose` directly on the host.
> Always use `task <task-name>`; run `task --list` first to see what this project actually exposes.

This skill is the stack-specific half of `ci-green-check`. That skill discovers which checks exist
(Taskfile + `.github/workflows`), drives the fix loop and writes the final report. This one provides
the environment setup and the exact commands.

Check that `task` is installed:

```bash
task --version 2>/dev/null || echo "task not installed"
```

If `task` is not installed, do not attempt to run commands directly. Stop and alert the user — `task`
is required. Ask the user to install it first (`brew install go-task/tap/go-task` on macOS).

## Task naming in Specs Laravel projects

The Taskfile is split into namespaces (`composer`, `artisan`, `npm`, `db`, `md`, `setup`, `e2e`,
`cleanup`, `worktrees`). Wildcard tasks take the rest of the name as their argument, and everything
after `--` is forwarded to the underlying command:

| Task                          | Runs                                                                                          |
|-------------------------------|-----------------------------------------------------------------------------------------------|
| `task composer:script:<name>` | a composer **script** from `composer.json` (`checkall`, `checkstyle`, `checktype`, `test`, …) |
| `task composer:cmd:<name>`    | a raw **composer command** (`outdated`, `audit`, `why`, …)                                    |
| `task composer:install`       | `composer install` inside the `php` service                                                   |
| `task composer:update`        | `composer update --with-all-dependencies`                                                     |
| `task artisan:run:<command>`  | `php artisan <command>` (colons included: `artisan:run:migrate:fresh`)                        |
| `task npm:script:<name>`      | an npm **script** from `package.json` (`build`, `test:e2e`, …)                                |
| `task npm:cmd:<name>`         | a raw **npm command** (`audit`, `outdated`, …)                                                |
| `task md:checkstyle`          | markdownlint over the repo                                                                    |
| `task md:fixstyle`            | fix table spacing, then markdownlint `--fix`                                                  |
| `task checkall`               | `composer:script:checkall` + `md:checkstyle`                                                  |
| `task dc:run:<service> -- …`  | last-resort escape hatch into a compose service                                               |

Older projects may still use the previous `composer:run:*` / `npm:run:*` / `composer:do:*` naming.
**Always confirm against `task --list` before running anything** and use whatever that project
exposes.

---

## Step 1: Prepare the environment

```bash
task up
```

`task up` templates `.env` / `.env.testing`, runs the one-time `setup` (auth.json, build, composer
and npm install, `key:generate`, `storage:link`, fresh migrations for `local` and `testing`, asset
build) when the project has never been started, and brings the containers up. It is idempotent — run
it rather than reproducing those steps by hand.

If dependencies drifted after a pull (new migrations, changed lock files), run:

```bash
task refresh
```

Verify with file checks only — never host commands:

```bash
[ -f vendor/autoload.php ] && echo "vendor: ok" || echo "vendor: MISSING — run task up"
[ -f .env ] && echo ".env: ok" || echo ".env: MISSING — run task up"
[ -f auth.json ] && echo "auth.json: ok" || echo "auth.json: MISSING — run task setup:auth"
```

`composer:install` has a precondition on `auth.json`; if it is missing, `task setup:auth` creates an
empty one.

---

## Step 2: Run the checks

### The fast path

```bash
task checkall
```

This is what CI effectively gates on: `composer:script:checkall` runs `composer validate --strict`,
`checkstyle` (phpcs), `checktype` (phpstan), `test` (phpunit), `rector-dry` and `composer audit`, and
`md:checkstyle` lints the markdown. Prefer it over running the tools one by one.

### Individual tools

Run these when `checkall` fails and you want a tight feedback loop on one tool.

```bash
# Code style — PHP_CodeSniffer
task composer:script:checkstyle          # phpcs -n
task composer:script:fixstyle            # phpcbf -n — auto-fixes, run this first on style failures

# Static analysis — PHPStan / Larastan
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
task npm:cmd:audit

# Markdown
task md:checkstyle
task md:fixstyle

# Front-end build
task npm:script:build
```

Pass extra arguments after `--`, e.g. `task composer:cmd:outdated -- --direct --major-only` or
`task composer:script:test -- --filter=SomeTest`.

Note what CI runs that these tasks do not: the **Model DocBlocks** job regenerates
`php artisan ide-helper:models --write` and fails on a dirty `app/Models/`. Reproduce it with
`task artisan:run:ide-helper:models -- --write` and commit any resulting diff.

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

Checks that cannot run locally and must be left to CI: the Composer/NPM cache-warming jobs and
anything needing `COMPOSER_AUTH_JSON` beyond a local `auth.json`.
