---
description: Update Specsnl PHP images (the Dockerfile dependencies and tooling) in isolated commits
name: update-php-images
---

# Goal

Perform a full dependency update across all three Dockerfile variants (fpm, apache, frankenphp) in a safe,
reproducible way.

**Critical rule:** Any version that appears in more than one Dockerfile must be updated across all affected
Dockerfiles in a single commit. Never update a shared version in only one Dockerfile.

This command never dead-ends: follow the `autonomous-execution` skill of the `code` plugin. When a phase fails,
**isolate it**: don't commit its changes (restore the Dockerfiles it touched), continue with the next phase, and list
it — with the error — in the PR body's `## Decisions and skipped steps` section. A situation this command doesn't
describe is handled the same way, plus a skill-gap issue.

## Phase 1 --- Repository Safety Checks

Never touch the user's own work: uncommitted changes, the current checkout and branches with unique commits stay as
they are. Record every choice made here in the PR body.

1. Synchronize with remote: `git fetch --prune`
2. Choose the branch name: `updates`, unless that name is taken by work you must not touch:
    - On the remote: reuse `updates` only when it has no commits that aren't in `origin/main` (then the new branch
    fast-forwards it). Otherwise use `updates-<YYYY-MM-DD>` (add `-2`, `-3`, … when that exists too).
    - Locally: when fully merged into `main`, or without unique commits, delete and recreate it from `origin/main`.
    When it contains unique commits, leave it untouched and use the suffixed name.
3. Prepare the branch from `origin/main`:
    - **On `main` with a clean working tree** (no staged, unstaged or untracked changes): create the branch from
    step 2 from `origin/main` and check it out.
    - **Another branch is checked out, or the working tree is dirty:** leave the checkout untouched and run the
    whole update in a fresh worktree instead: `git worktree add -b <branch> <path> origin/main` (e.g. a sibling
    directory `../<repo>-updates`). Run every later phase in that worktree, and remove it
    (`git worktree remove <path>`) once the branch is pushed.

Always branch from latest `origin/main`.

## Phase 2 --- PHP Base Image Updates

The three Dockerfiles use different base images but all track the same PHP 8.5.x patch series:

- `fpm/Dockerfile`: `FROM php:<version>-fpm-trixie`
- `apache/Dockerfile`: `FROM php:<version>-apache-trixie`
- `frankenphp/Dockerfile`: `FROM dunglas/frankenphp:<frankenphp-version>-php<php-version>-trixie`

1. Check Docker Hub for the latest `php:8.5.x-fpm-trixie` tag. Only consider patch updates within the
`8.5.x` series — do not update to a different minor or major PHP version.
2. Check Docker Hub for the latest `dunglas/frankenphp` tag that matches the pattern
`x.x.x-php8.5.x-trixie`. Only consider updates that keep the PHP 8.5.x series.
3. Update the `FROM` lines in all three Dockerfiles if newer versions are available.
4. Check `git status`. Commit all three Dockerfiles together in a single commit if there are any changes.
   Commit message: `chore(deps): Update PHP base image versions`.
5. If there are no changes, skip the commit and move on.

On failure, isolate this phase (see the top of this command).

## Phase 3 --- Pie Tool Update

All three Dockerfiles pin the same Pie version via:

```dockerfile
COPY --from=ghcr.io/php/pie:<version>-bin /pie /usr/bin/pie
```

1. Check the GitHub Releases API for the latest release of `php/pie`.
2. If a newer version is available, update the `ghcr.io/php/pie:<version>-bin` reference in all three
Dockerfiles.
3. Check `git status`. Commit all three Dockerfiles together in a single commit if there are any changes.
   Commit message: `chore(deps): Update Pie version`.
4. If there are no changes, skip the commit and move on.

On failure, isolate this phase (see the top of this command).

## Phase 4 --- PHP Runtime Extension Updates

All three Dockerfiles share the same versions for the following PHP extensions (runtime stage ARGs):

- `PHP_EVENT_VERSION` — `osmanov/pecl-event` on Packagist
- `PHP_IGBINARY_VERSION` — `igbinary/igbinary` on Packagist
- `PHP_REDIS_VERSION` — `phpredis/phpredis` on Packagist
- `PHP_AMQP_VERSION` — `php-amqp/php-amqp` on Packagist

Process each extension individually and in order:

1. Query the Packagist API for the latest stable release of the extension.
2. If a newer version is available, update the corresponding `ARG` in all three Dockerfiles.
3. Commit all three Dockerfiles together in a single commit.
   Commit message: `chore(deps): Update <package-name> to <new-version>`.
   For example: `chore(deps): Update phpredis/phpredis to 6.4.0`.
4. If there is no update for this extension, skip the commit and move on to the next extension.

Repeat for every extension. Each updated extension gets its own commit.

On failure, isolate this phase (see the top of this command).

## Phase 5 --- Builder Stage Tool Updates

All three Dockerfiles share the same versions for the following builder-stage tools:

- `PHIVE_VERSION` — check the GitHub Releases API for `phar-io/phive`
- `COMPOSER_VERSION` — check `https://getcomposer.org/download/` or the GitHub Releases API for
`composer/composer`
- `XDEBUG_VERSION` — `xdebug/xdebug` on Packagist
- `PCOV_VERSION` — `pecl/pcov` on Packagist
- `FIXUID_VERSION` — check the GitHub Releases API for `boxboat/fixuid`

Process each tool individually and in order:

1. Look up the latest stable release of the tool.
2. If a newer version is available, update the corresponding `ARG` in all three Dockerfiles.
3. Commit all three Dockerfiles together in a single commit.
   Commit message: `chore(deps): Update <tool-name> to <new-version>`.
   For example: `chore(deps): Update Composer to 2.10.0`.
4. If there is no update for this tool, skip the commit and move on to the next tool.

Repeat for every tool. Each updated tool gets its own commit.

On failure, isolate this phase (see the top of this command).

## Phase 6 --- Node.js Major Version Update

All three Dockerfiles pin `ARG NODE_MAJOR=<version>` for the `builder_nodejs` stage.

1. Check the Node.js release schedule at `https://nodejs.org/en/about/previous-releases` to find the
current Active LTS major version.
2. Only update `NODE_MAJOR` if a newer **Active LTS** major version is available. Do not update to a
Current (non-LTS) release.
3. If a newer Active LTS major is available, update `NODE_MAJOR` in all three Dockerfiles.
4. Check `git status`. Commit all three Dockerfiles together in a single commit if there are any changes.
   Commit message: `chore(deps): Update Node.js major version to <version>`.
5. If there are no changes, skip the commit and move on.

On failure, isolate this phase (see the top of this command).

## Phase 7 --- Hadolint Version Update

The `Taskfile.dist.yml` pins the Hadolint Docker image version via the `HADOLINT_TAG_VERSION` variable.

1. Check the GitHub Releases API for the latest release of `hadolint/hadolint`.
2. If a newer version is available, update `HADOLINT_TAG_VERSION` in `Taskfile.dist.yml`.
3. Check `git status`. Commit if there are any changes.
   Commit message: `chore(deps): Update Hadolint version`.
4. If there are no changes, skip the commit and move on.

On failure, isolate this phase (see the top of this command).

## Phase 8 --- GitHub Actions Updates

1. Scan the following files for pinned `uses:` action references:
    - `.github/workflows/*.yml`
2. For each external action (e.g. `specsnl/github-actions/.github/workflows/build-php.yml@1.1.1`), use
the GitHub Releases API to find the latest release tag. Check every action individually — do not assume
a version is already current.
   - If the reference uses a floating major-version tag (e.g. `@v6`) and that major version is already
     the latest, leave it as-is.
   - If the reference is pinned to a specific semver tag (e.g. `@1.1.1`, `@v2.5.0`) and a newer version
     exists, update it to the latest release tag.
   - If the reference is pinned to a commit SHA, leave it as-is.
3. Update any outdated action versions in-place across all scanned files.
4. Check `git status`. Commit separately if there are any changes.
   Commit message: `chore(deps): Update GitHub Actions versions`.
5. If there are no changes, skip the commit and move on.

On failure, isolate this phase (see the top of this command).

## Phase 9 --- License Year Update

1. Check if the `LICENSE` file contains a year range (e.g. `2020-2025`) or a single year (e.g. `2024`).
2. If the current year (2026) is not already the end year:
   - Single year (e.g. `2024`) → update to `2026`.
   - Year range (e.g. `2020-2025`) → update the end year to `2026`.
3. Commit separately if there are any changes.
   Commit message: `chore: Update copyright year`.
4. If there are no changes, skip the commit and move on.

------------------------------------------------------------------------

## Final State

When there are no changes after all update steps, the run ends here with a report instead of a PR: everything is
already up to date. The report also lists the skipped phases and decisions. Delete the empty branch (and the
worktree, when one was created).

- There could be up to 14 commits on the `updates` branch:
    1. PHP base image versions
    2. Pie tool version
    3. PHP runtime extension: osmanov/pecl-event
    4. PHP runtime extension: igbinary/igbinary
    5. PHP runtime extension: phpredis/phpredis
    6. PHP runtime extension: php-amqp/php-amqp
    7. Builder tool: Phive
    8. Builder tool: Composer
    9. Builder tool: Xdebug
    10. Builder tool: pcov
    11. Node.js major version
    12. Hadolint version
    13. GitHub Actions versions
    14. Copyright year
- Branch: `updates`, or the suffixed name chosen in Phase 1 step 2.
- Based on latest `origin/main`.
- The working tree should be clean.
- Push the branch to the remote and create a pull request for review and merging targeting `origin/main`.
  The title should be `chore: Update dependencies`.
- Add a Pull Request description that lists the changes based on the commits that were made. Stick to the
  commit messages but remove the "chore" prefix. Add a `## Decisions and skipped steps` section when any phase was
  skipped or isolated, or a non-default branch or worktree was used. For example:

```md
Updated the following dependencies:

- Updated PHP base image versions
- Updated Pie version
- Updated PHP runtime extension versions
- Updated builder stage tool versions
- Updated GitHub Actions versions
```
