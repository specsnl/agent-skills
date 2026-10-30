# PHP plugin

PHP-generic skills, instructions, commands/prompts are located in this plugin. They work for any PHP
project — Laravel and Symfony apps, Composer packages, plain-PHP services — and follow the Specs
conventions (Taskfile, `ghcr.io/specsnl/*` images) when the project is a Specs project.

## Installation

Claude: `claude plugin install php@specs`

## Skills

**executing-commands**:  
REQUIRED: Execute this skill before running ANY project commands (composer, npm/pnpm/yarn, php, docker,
etc.). It decides how each command runs in this project: a project task, the Taskfile's Compose wrapper,
Docker Compose, a pinned `docker run`, or (last resort) the host. It also detects the project's Node
package manager. Do not run composer, the Node package manager, node or php directly on the host while a
container route exists.

**php-checks**:  
Prepare the environment and run the PHP quality tools of a project locally — code style
(PHP_CodeSniffer / PHP-CS-Fixer / Pint), static analysis (PHPStan / Psalm), tests (PHPUnit / Pest),
Rector, the dependency audits and the markdown linter — discovered from the Taskfile, the
`composer.json` scripts and `require-dev`. Laravel-only tools (Larastan, `ide-helper`, `artisan`)
are used only when `laravel/framework` is a dependency. This is the PHP layer of the
`ci-green-check` skill in the `github` plugin, which owns check discovery, the fix loop, and the
final report.

## Commands

**update-project**:  
Update dependencies of PHP projects using isolated commits: Composer, frontend dependencies, Docker
images, GitHub Actions and runner images, and Dependabot coverage. Specs projects additionally get
the Specs conventions (Taskfile targets, the `ilyes512` → `specsnl` package migration, Specsnl image
naming).

Claude: `/update-project`
