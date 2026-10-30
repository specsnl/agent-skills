---
name: update-project
description: Update dependencies of PHP projects using isolated commits.
---

# Goal

Perform a full dependency update of a PHP project: a Laravel or Symfony application, a Composer package, a
plain-PHP service, an older project or a third-party repository.

Specs projects keep the Specs way of working (see Phase 0): `task` targets, the `ilyes512` → `specsnl` package
migration, Specsnl image naming and the `create-pr` title rules. For any other project, use whatever the project
already uses.

Invoke the `executing-commands` skill before running any project command. It decides how commands run in this
project: a `task` target first, then the containers, and the host only as a last resort. Never run composer, the
Node package manager, node, or php directly on the host while a container route exists.

Each phase specifies its own error-handling policy. Some phases allow attempting a fix before
aborting — follow the per-phase instructions rather than a blanket stop rule. A phase that does not apply to the
project (according to Phase 0) is skipped, not failed.

## Commit Strategy

When committing changes at the end of each phase, only stage files that are directly related to that phase's purpose. If other files have changed that are unrelated to the phase (e.g., a markdown file or documentation updated as a side-effect of running a command), commit those separately with a descriptive commit message that reflects what those changes actually are. Never bundle unrelated changes into a phase commit.

## Phase 0 --- Project Detection

Record what the project has before changing anything, so later phases can skip cleanly instead of failing. Use file
checks and `git ls-files` (which skips untracked directories like `vendor/` and `node_modules/`).

1. **Specs project or not.** The project is a Specs project when any of these holds:
    - It has a Taskfile (`Taskfile.yml`, `Taskfile.yaml`, `Taskfile.dist.yml`, …) with the Specs namespaces
    `composer:*` and `dc:run:*`, plus a Node package manager namespace (`npm:*`, `pnpm:*` or `yarn:*`) when there
    is a `package.json` (check `task --list`).
    - It uses `ghcr.io/specsnl/*` images (in a Dockerfile, a Compose file or a workflow).
    - It has a `specsnl` GitHub remote (`git remote -v` shows `github.com[:/]specsnl/`).
2. **Framework:** `laravel/framework`, `symfony/framework-bundle`, or none (check `require` in `composer.json`).
Steps marked **Laravel only** run only when `laravel/framework` is a dependency.
3. **Library or application:** the project is a library when `composer.json` has `"type": "library"` and/or there
is no committed `composer.lock` (`git ls-files composer.lock` prints nothing).
4. **Frontend:** whether there is a tracked `package.json`, and its Node package manager (`<pm>`: npm, pnpm or yarn),
detected as described in the "Node package manager" section of `executing-commands` (`packageManager` first, then
the lock file). Record any conflicting signals and the choice. A Bun project skips the frontend phases (5, 6 and the
frontend audit) and says so in the report.
5. **Compose files:** all Docker Compose files tracked in the repository, not just the root `compose.yml`. Compose
files can live in subdirectories and use variant names such as `compose.override.yml`, `compose.ci.yml` or
`docker/compose.dev.yml`. Find them with `git ls-files`, matching `compose.yml`, `compose.*.yml`,
`docker-compose.yml` and `docker-compose.*.yml`, plus their `.yaml` variants, in any directory.
6. **Dockerfiles:** all Dockerfiles tracked in the repository. Find them with `git ls-files`, matching `Dockerfile`,
`*.Dockerfile` and `Dockerfile.*` in any directory (e.g. `php/Dockerfile`, `nginx/Dockerfile`,
`docker/app.Dockerfile`).
7. **Taskfile:** whether there is one, and which tasks it has (`task --list`). Note in particular whether `up`,
`refresh`, `checkall`, `build`, `reset`, `composer:update`, `<pm>:update`, `<pm>:corepack:update` and
`setup:auth` exist. Older Specs projects may use the previous `composer:run:*` / `npm:run:*` / `composer:do:*`
naming — use whatever `task --list` shows.
8. **Default branch:** `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the `origin/` prefix), or
`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` when the symbolic ref is not set. Every phase
below refers to it as `<default>`; never assume `main`.

Summarize the findings to the user before continuing.

### Command reference

The phases below name the action; use the command that fits the project. In Specs projects, use the `task` target
(when `task --list` has it). Otherwise run the plain command through the `executing-commands` skill, which decides
whether it runs in a container or on the host.

| Action                       | Specs project             | Other projects                                                                        |
|------------------------------|---------------------------|---------------------------------------------------------------------------------------|
| Start the project            | `task up`                 | `docker compose up -d` (only with Compose files)                                      |
| Install from the lock files  | `task refresh`            | `composer install` (+ `<pm>`'s frozen install, e.g. `pnpm install --frozen-lockfile`) |
| Update Composer dependencies | `task composer:update`    | `composer update --with-all-dependencies`                                             |
| Raw Composer command         | `task composer:cmd:<cmd>` | `composer <cmd>`                                                                      |
| Run the project checks       | `task checkall`           | the checks found by the `php-checks` skill                                            |
| Update frontend dependencies | `task <pm>:update`        | `<pm>`'s in-range update (e.g. `pnpm update`)                                         |
| Build frontend assets        | `task <pm>:script:build`  | `<pm> run build`, when `package.json` defines a `build` script                        |
| Frontend audit               | `task <pm>:cmd:audit`     | `<pm>`'s audit (e.g. `pnpm audit`)                                                    |
| Rebuild local Docker images  | `task build`              | `docker compose build --pull`                                                         |
| Reset the environment        | `task reset`              | `docker compose down` followed by `docker compose up -d`                              |

`executing-commands` has the `<pm>` command for each intent. The frontend tasks are named after the package manager
(`npm:*`, `pnpm:*`, `yarn:*`): use the namespace that matches `<pm>`. When the Taskfile only has another manager's
namespace, run the `<pm>` command through `executing-commands` instead.

## Phase 1 --- Repository Safety Checks

1. Ensure the working (git) tree is clean:
    - No staged changes
    - No unstaged changes
    - No untracked files
    - If not clean: Abort immediately
        - Inform the user to commit or stash changes
2. Synchronize with remote: `git fetch --prune`
3. Check if `vendor-updates` already exists on the remote. If it does, abort and inform the user
to delete the remote branch before continuing.
4. Check if local `<default>` branch is up to date with `origin/<default>`:
    - If behind → abort and inform the user to pull the latest changes.
    - If ahead with unique commits → abort and inform the user to push or rebase their commits.
    - If diverged → This can occur when testing locally (e.g., running the project checks) — the local branch may
    have commits not yet pushed to the remote. Ask the user which branch to use as the source for the vendor-updates
    branch in step 5: `origin/<default>` or local `<default>`. **Choosing local `<default>` allows you to test
    iterations without pushing to the remote.**  
    **Warning:** choosing the local `<default>` branch may lead to merge conflicts later if the remote branch has
    commits the local branch doesn't know about (common when you don't push test iterations).
5. Prepare branch `vendor-updates`:
    - If branch does not exist → create from the chosen branch in step 4 (`origin/<default>` by default, or local
    `<default>` if the user selected it in a diverged state)
    - If branch exists:
        - If fully merged into `<default>` → delete locally and recreate from the chosen branch.
        - If behind on `<default>` and has NO unique commits → reset `vendor-updates` to the chosen branch.
        - If it contains unique commits → abort and notify user.
6. If the `composer.json` file contains a repositories section with private repositories (like Filament), make sure
Composer has credentials for them: an `auth.json` file in the project root, or Composer's global auth
(`COMPOSER_AUTH`, `~/.composer/auth.json`) when the project runs Composer on the host. If there are none, abort and
inform the user to create them. When the Taskfile has a `setup:auth` task, suggest running `task setup:auth`.

Always branch from the chosen source (see step 4).

## Phase 2 --- Environment Preparation

1. Invoke the `executing-commands` skill to confirm how commands run in this project (and, with a Taskfile, which
task targets are available) before running any commands.
2. Start the project:
    - When the Taskfile has an `up` task: `task up`.
    - Otherwise, when the project has Compose files: start the services through `executing-commands`.
    - Libraries and projects without services skip this step entirely.
3. Ensure the environment is refreshed, so all dependencies are installed according to their respective lock files
(and the frontend assets are rebuilt):
    - When the Taskfile has a `refresh` task: `task refresh`.
    - Otherwise install from the lock files through `executing-commands`: `composer install`, plus `<pm>`'s frozen
    install when there is a `package.json` (e.g. `npm ci`, `pnpm install --frozen-lockfile`).

Abort if any command fails.

## Phase 3 --- Backend Dependencies

1. Update Composer dependencies with all dependencies (`composer update --with-all-dependencies`; in Specs projects
`task composer:update`, which runs it inside the PHP container).
2. Run the project checks. Invoke the `php-checks` skill to find them: the Taskfile (`task checkall` in Specs
projects), the composer scripts (`composer run-script --list`) and the CI workflows (via `ci-green-check`'s
discovery). If any check fails, attempt to fix the issue, then re-run the checks to confirm resolution before
proceeding. If you cannot fix the issues, abort and report the errors.
    - If there are any style issues, run the project's style fixer (e.g. `task composer:script:fixstyle`, phpcbf,
    `php-cs-fixer fix` or `pint`) to automatically fix them. If that does not work, try to fix style issues
    manually. Re-run the checks after each attempt. If you cannot fix the style issues, abort and report the errors.
    - If there are any static analysis issues (PHPStan, Larastan, Psalm), try to fix them. Do not fix them by adding
    them to a baseline file or by adding annotations like `@phpstan-ignore` or `@psalm-suppress`. Re-run the checks
    after each fix attempt. If you cannot fix the static analysis issues, abort and report the errors.
    - If there are any test failures (PHPUnit, Pest), try to fix them. Do not fix test failures by skipping tests.
    Re-run the checks after each fix attempt. If you cannot fix the test failures, abort and report the errors.
3. **Libraries without a committed `composer.lock`:** the update produces nothing to commit. The checks in step 2
still run, so the test suite runs against the updated dependencies. Also check whether the `composer.json`
constraints still allow the latest major versions (`composer outdated --direct --major-only`, or
`task composer:cmd:outdated -- --direct --major-only`). Do not change the constraints; report every dependency the
constraints exclude to the user as a suggestion. Then skip the commit step and move on to the next phase.
4. Check git status for all changed or newly tracked files resulting from the update. Group them by purpose:
    - Stage only files directly related to the Composer update (e.g., `composer.lock`, `vendor/` when it is
    tracked) and commit. **Laravel only:** package assets republished by the update (e.g. `public/vendor/*`
    refreshed by `vendor:publish` in the composer scripts) belong in this commit too. Commit message:
    `chore(deps): Updated Composer dependencies`.
    - For any remaining unrelated files (e.g., `AGENTS.md`, skill files, markdown docs updated as a side-effect),
    create a separate commit per logical group with a descriptive message that reflects what those changes are
    (e.g., `docs: Updated AGENTS.md`).
5. If there are no changes, skip the commit step and move on to the next phase.

## Phase 4 --- Replace Abandoned `ilyes512` Packages

Some Composer packages formerly published under the `ilyes512` vendor namespace have been abandoned
and superseded by maintained `specsnl` equivalents. This phase migrates any such packages.

1. Inspect the project's `composer.json` (`require` and `require-dev`) for packages under the
`ilyes512/*` vendor namespace. If there are none, skip this phase entirely.
2. For each `ilyes512/*` package found, determine its maintained replacement:
    - The authoritative source is Composer's own abandonment metadata. When Composer resolves an
    abandoned package (during the Composer update in Phase 3) it prints a warning such as:
    `Package ilyes512/foo is abandoned, you should avoid using it. Use specsnl/foo instead.`
    Use the replacement package named in that warning **verbatim**.
    - If the abandonment warning does not name an explicit replacement, fall back to a straight
    vendor-prefix swap: `ilyes512/<name>` → `specsnl/<name>`. Before relying on the fallback, confirm
    the `specsnl/<name>` package actually exists (e.g. via `composer outdated` output or the
    package's Packagist page).
    - If a package is **not** abandoned, or its abandonment notice points to a replacement **outside**
    the `specsnl` namespace, do **not** replace it. Leave it in place and note it in your final report.
3. For each package to migrate, edit `composer.json`: remove the `ilyes512/*` entry and add the
`specsnl/*` replacement, preserving the existing version constraint. Adjust the constraint only if the
replacement's available versions require it.
4. Update the lock file and vendor directory with the Composer update from Phase 3.
5. The replacement package may expose a different PHP namespace or class names than the abandoned one.
Search the codebase for references to the old package's namespace/classes and update any usages to the
replacement's API. Then run the project checks (as in Phase 3). If any check fails, attempt to fix
the issue and re-run the checks to confirm resolution before proceeding (follow the same
style/static analysis/test fix rules described in Phase 3). If you cannot resolve the failures, abort and
report the errors.
6. Check `git status` for all changed files. Stage only files directly related to this migration (e.g.
`composer.json`, `composer.lock`, `vendor/`, and any source files updated for the new package's API)
and commit. Commit message: `chore(deps): Replaced abandoned ilyes512 packages with specsnl equivalents`.
For any remaining unrelated changed files, commit them separately with a descriptive message.
7. If there are no `ilyes512/*` packages or no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 5 --- Node package manager version

Skip this phase when the project has no `package.json`.

1. Update the package manager version with `corepack up`, which handles npm, pnpm and yarn alike:
    - When the Taskfile has a `<pm>:corepack:update` task: `task <pm>:corepack:update`.
    - Otherwise, only when `package.json` pins its package manager in the `packageManager` field: run `corepack up`
    through `executing-commands`. Projects that do not pin a package manager skip this phase.
2. Commit separately if there are any changes. Commit message: `chore(deps): Updated <pm> version` (e.g.
`chore(deps): Updated pnpm version`).
3. If there are no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 6 --- Frontend Dependencies

Skip this phase when the project has no `package.json`.

1. Update the frontend dependencies with `<pm>`'s in-range update (e.g. `pnpm update`): `task <pm>:update` in Specs
projects, otherwise the `<pm>` command through `executing-commands`.
2. Build assets: `task <pm>:script:build` in Specs projects, otherwise `<pm> run build`
when `package.json` defines a `build` script. Skip this step when there is no build script.
3. Check git status for all changed files. Stage only files directly related to the frontend update (e.g., the
lock file of `<pm>`, `node_modules/` when it is tracked, built assets) and commit. Commit message:
`chore(deps): Updated <pm> dependencies` (e.g. `chore(deps): Updated pnpm dependencies`). For any remaining
unrelated changed files, commit them separately with a descriptive message. A new lock file of another package
manager (e.g. a `package-lock.json` next to `pnpm-lock.yaml`) means the wrong manager ran: discard it instead of
committing it.
4. If there are no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 7 --- Docker Image Updates

1. Scan the following files for pinned Docker image references:
    - All Docker Compose files found in Phase 0.
    - All Dockerfiles found in Phase 0 (the `FROM` lines, including every stage of a multi-stage build).
    - `.github/workflows/*.yml` (e.g. service images like `mysql:`)
    - **Specsnl PHP base images** (`ghcr.io/specsnl/php<major><minor>...`, typically the `FROM` lines in
      `php/Dockerfile`) use two naming conventions. The **newer, preferred** convention encodes the variant
      and build target as path segments, with only the version in the tag:
      `ghcr.io/specsnl/php<major><minor>[/<variant>][/<target>]:<version>`
      (e.g. `ghcr.io/specsnl/php85/builder:latest`). The **legacy** convention encoded the variant/target and
      version together in the tag, joined with dashes:
      `ghcr.io/specsnl/php<major><minor>:<variant>-<target>-<version>`
      (e.g. `ghcr.io/specsnl/php85:builder-latest`). If you find a Specsnl image still using the legacy
      dash-in-tag form, **migrate it in-place to the new path-segment form** — move the variant/target
      segments out of the tag into the image path, leaving only the version (e.g. `latest`) as the tag. This
      migration is a change in its own right even when the version (e.g. `latest`) does not change.
2. For each image found, check for a newer version:
    - For images hosted on `ghcr.io/*`: use the GitHub Releases API to find the latest release tag for that
    repository.
    - For Docker Hub images (`mysql`, `redis`, `axllent/mailpit`, etc.): check Docker Hub for the latest stable tag
    matching the current flavour (e.g. `8.0-bookworm`, `7-bookworm`).
    - **Version Comparison:** Compare the found version with the current version. If the new version is **lower** than
    the current version, use the following concrete fallbacks:
        - For Docker Hub images: query the tags endpoint directly sorted by last_updated —
          `GET https://hub.docker.com/v2/repositories/library/<image>/tags?page_size=100&ordering=last_updated`
          (use `/repositories/<namespace>/<image>/tags?...` for non-official images). Pick the latest
          stable tag that matches the current flavour (e.g. `8.0-bookworm`).
        - For `ghcr.io` images: try the GitHub Releases API as the fallback.
        - If you still cannot find a version **equal to or newer** than the current one, inform the user
          about this discrepancy and skip updating that image.
3. Update any outdated image references in-place across all scanned files.
4. After updating, rebuild the local Docker images: `task build` when the Taskfile has a `build` task, otherwise the
Compose equivalent (`docker compose build --pull`) through `executing-commands`. Skip this step when the project has
no Compose files and no `build` task.
5. Reset the environment to make sure it is using the latest images: `task reset` when the Taskfile has a `reset`
task, otherwise the Compose equivalent (`docker compose down`, then `docker compose up -d`) through
`executing-commands`. Skip this step when the project has no Compose files and no `reset` task.
6. Run the project checks (as in Phase 3).
7. Check `git status` for all changed files. Stage only files directly related to Docker image updates (e.g.,
the Compose files and Dockerfiles found in Phase 0, `.github/workflows/*.yml`) and commit.
Commit message:
`chore(deps): Updated Docker image versions`. For any remaining unrelated changed files, commit them separately
with a descriptive message.
8. If there are no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 8 --- GitHub Actions Updates

1. Scan the following files for pinned `uses:` action references:
    - `.github/workflows/*.yml`
    - `.github/actions/**/*.yml`
2. For each external action (e.g. actions/checkout@v6, shivammathur/setup-php@v2), use the GitHub Releases API to find
the latest release tag. Check every action individually — do not assume that a major-version tag (e.g. @v6) is already
current. A newer major version may exist.
    - **Version Comparison:** Compare the found version with the current version. If the new version is **lower** than
    the current version, use the following concrete fallback:
        - Query the Tags API: `GET https://api.github.com/repos/<owner>/<repo>/tags`. Use the highest
          tag that matches the versioning scheme in use (e.g. `v4`, `v4.2.1`).
        - If you still cannot find a version **equal to or newer** than the current one, inform the user
          about this discrepancy and skip updating that action.
3. Update any outdated action versions in-place across all scanned files.
4. Check `git status` for all changed files. Stage only files directly related to GitHub Actions updates (e.g.,
`.github/workflows/*.yml`, `.github/actions/**/*.yml`) and commit. Commit message:
`chore(deps): Updated GitHub Actions versions`. For any remaining unrelated changed files, commit them separately
with a descriptive message.
5. If there are no changes, skip the commit step and continue with the runner images below.
6. Scan the same files for `runs-on:` runner labels. Besides plain labels (`runs-on: ubuntu-latest`), also check
labels in arrays (`runs-on: [ubuntu-latest]`) and in `strategy.matrix` values that `runs-on` references through an
expression (e.g. `runs-on: ${{ matrix.os }}`).
7. Determine the latest **generally available** version of each GitHub-hosted runner image:
    - The authoritative source is the "Available Images" table in the
    [actions/runner-images](https://github.com/actions/runner-images) README
    (`gh api repos/actions/runner-images/readme -H "Accept: application/vnd.github.raw"`). It lists every image
    with its architecture (x64 / arm64) and the YAML labels that select it.
    - Ignore images marked as beta, (public) preview or deprecated — only use stable, generally available labels.
    - Use the architecture column, not the label name, to determine a label's architecture. The naming is not
    consistent across OS families: `ubuntu-26.04-arm` is arm64, but `macos-26` is arm64 and `macos-26-intel` is x64.
8. Update each GitHub-hosted runner label to the latest stable version for its OS family, architecture and size:
    - Replace floating `-latest` labels with an explicit version, even when the `-latest` label already points to
    the newest image (e.g. `ubuntu-latest` → `ubuntu-26.04`, `macos-latest` → `macos-26`,
    `macos-latest-large` → `macos-26-large`).
    - Bump explicitly versioned labels to the latest stable version (e.g. `ubuntu-24.04` → `ubuntu-26.04`).
    - Preserve the architecture, size and variant suffix of the label (e.g. `-arm`, `-intel`, `-large`, `-xlarge`,
    `-vs2026`): `ubuntu-24.04-arm` → `ubuntu-26.04-arm`, `macos-15-intel` → `macos-26-intel`. Arm and other
    variants can lag behind the x64 images, so use the highest version for which that exact variant is generally
    available — never switch a job to a different architecture.
    - Never downgrade: if a label is already on a newer version than the latest stable one (e.g. a beta image),
    leave it as is.
    - Leave self-hosted runners and custom labels (e.g. `self-hosted`, organization-defined larger runner names,
    runner `group:` configurations) untouched.
9. Check `git status` for all changed files. Stage only files directly related to the runner image updates and
commit. Commit message: `chore(ci): Updated GitHub Actions runner images`.
10. If there are no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 9 --- Dependabot Coverage

1. Check whether the project has a Dependabot config: `.github/dependabot.yml` or `.github/dependabot.yaml`. If
there is none, skip this phase entirely — do not create one.
2. Inventory every updatable resource tracked in the repository (use `git ls-files`, so `vendor/` and
`node_modules/` are skipped) and map each one to its Dependabot `package-ecosystem` and directory:
    - `composer.json` → `composer`, in the directory containing the file.
    - `package.json` → `npm`, in the directory containing the file. Dependabot's `npm` ecosystem covers npm, yarn
    **and** pnpm, so do not add or "fix" a separate entry for the detected package manager. Bun has its own `bun`
    ecosystem.
    - Dockerfiles (the same set found in Phase 0, e.g. `php/Dockerfile`, `nginx/Dockerfile`) → `docker`, in the
    directory containing the file.
    - Docker Compose files (the same set found in Phase 0, e.g. `compose.yml`, `compose.*.yml`) →
    `docker-compose`, in the directory containing the file.
    - `.github/workflows/*.yml` → `github-actions`, with directory `/` (Dependabot then scans `.github/workflows`
    itself). Composite actions under `.github/actions/<name>/action.yml` are **not** covered by `/` — each needs its
    own directory (e.g. `/.github/actions/<name>`) or a matching glob.
3. For each resource, check whether an entry under `updates` covers it: the `package-ecosystem` must match, and the
resource's directory must be listed in `directory`, or in `directories` (directly or through a glob such as
`/.github/actions/*`). Report every uncovered resource — for example, a project with `compose.yml` in the root but
no `docker-compose` entry is missing coverage for its Compose images.
4. Add coverage for each uncovered resource:
    - If an entry already exists for that ecosystem, add the missing directory to it. Convert a single `directory`
    key to a `directories` list when needed (e.g. `directory: "/"` → `directories: ["/", "/docker"]`).
    - Otherwise, add a new `updates` entry for the ecosystem. Mirror the conventions of the existing entries
    (`schedule`, `groups`, `labels`, `commit-message`, `open-pull-requests-limit`, `target-branch`, etc.) so the
    new entry behaves like the rest.
    - Do not change settings of existing entries beyond adding directories, and do not remove entries. If an
    entry points to a directory or ecosystem that no longer exists in the project, leave it in place and mention it
    in your final report.
5. Check `git status` for all changed files. Stage only the Dependabot config and commit. Commit message:
`chore(ci): Updated Dependabot configuration`.
6. If there is no Dependabot config or everything is already covered, skip the commit step and move on to the next
phase.

Abort on any failure.

## Phase 10 --- Final Checks

Phase 10 is informational only — findings here do not block the PR. Create the PR first (see Final
State below), then report the Phase 10 summary to the user.

1. Run the following audit commands and create a summary of the results. Suggest to the user to fix any of the issues
that are found:
    1. Run `composer audit` (`task composer:cmd:audit` in Specs projects).
    2. When there is a `package.json`, run `<pm>`'s audit (`task <pm>:cmd:audit` in Specs projects,
    otherwise e.g. `pnpm audit` or `yarn npm audit --all --recursive`).
2. Run `composer outdated --direct --major-only` (`task composer:cmd:outdated -- --direct --major-only` in Specs
projects) to check for any major updates that are available for direct dependencies. If there are any, create a
summary and suggest to the user to update those as well.
3. Keep this phase a short summary. For the full audit and major-version analysis, point the user to the
`/php:project-health-check` command (once the `php` plugin ships it).

------------------------------------------------------------------------

## Final State

Abort if there are no changes after all update steps, and inform the user that dependencies are already up to date.
For a library without a committed `composer.lock`, also report the results of the Phase 3 test run and the major
version suggestions.

- There could be up to 8 commits on the `vendor-updates` branch (more if unrelated side-effect changes were
committed separately per the Commit Strategy):
    1. Composer updates
    2. Replaced abandoned `ilyes512` packages with `specsnl` equivalents
    3. Node package manager (`<pm>`) version update
    4. `<pm>` dependency updates
    5. Docker image version updates
    6. GitHub Actions version updates
    7. GitHub Actions runner image updates
    8. Dependabot configuration updates
- Branch: `vendor-updates`
- Based on the chosen source from Phase 1 step 4 (latest `origin/<default>` by default, or local `<default>` if
selected).
- The working tree should be clean.
- **This skill explicitly authorizes invoking the `create-pr` skill to push the `vendor-updates`
  branch and open the pull request against `<default>` as the final step.** The `create-pr` skill will handle title
  format discovery and branch push. Because the project checks have already run during the update phases,
  you may skip the `ci-green-check` step inside `create-pr` (treat it as already satisfied).

  Pass the following suggested title and body to the `create-pr` skill:

  **Suggested PR title**: `Update dependencies`.

  This is an automated dependency update with **no associated ticket**. Therefore:

  - Do **not** ask the user for a ticket or issue number — none exists for this work.
  - The `create-pr` skill verifies the title format against `.github/pr-title-checker-config.json`.
    Apply whichever format it requires:
    - If the format requires a ticket prefix (e.g. `KLIN`, `ABC`): use the placeholder issue
      number `000`, giving `<PREFIX>-000: Update dependencies` (for example `KLIN-000: Update dependencies`).
      Derive `<PREFIX>` from the checker config's allowed pattern, or from the prefix used by
      existing branches/PRs in the repository.
    - If the format requires a conventional-commit prefix instead: use `chore: Update dependencies`.
  - In a non-Specs project without a title checker config, follow the title conventions of the repository's recent
    pull requests (and its contributing guide, if any); fall back to `Update dependencies`.

  **Suggested PR body**: Include only the bullets for phases that produced actual changes, and replace `<pm>` with
  the detected package manager (`npm`, `pnpm` or `yarn`). If any
  additional side-effect commits were made (e.g. `docs: Updated AGENTS.md`), add them as extra bullets
  under `## Summary`.

  ```md
  ## Summary
  - Updated Composer dependencies
  - Replaced abandoned `ilyes512` packages with `specsnl` equivalents
  - Updated <pm> version
  - Updated <pm> dependencies
  - Updated Docker image versions
  - Updated GitHub Actions versions
  - Updated GitHub Actions runner images
  - Added missing resources to the Dependabot configuration

  ## Test plan
  - [ ] Review the dependency changelog(s) for any breaking changes or notable updates.
  - [ ] Verify the CI workflows pass on the updated runner images.
  ```

  Only include the runner images test plan item when the runner images were updated.
