---
description: Update Specsnl PHP images (the Dockerfile dependencies and tooling) in isolated commits
name: update-php-images
---

See skill @../skills/php-images/SKILL.md for general information about the PHP images, their repository structure
(including how the Dockerfiles are generated from `Dockerfile.tmpl`), and the differences between PHP versions.

# Goal

Perform a full dependency update of one Specsnl PHP image repository (any `php<NN>` repository, e.g. `php85` or
`php74`) across all of its variants, in a safe, reproducible way.

**Critical rules:**

- Any version that appears in more than one variant must be updated across all of them in a single commit. Never
  update a shared version in only one variant.
- Everything except the `FROM` images is edited in `Dockerfile.tmpl`, never in a `<variant>/Dockerfile`. After every
  change, run `task generate` and commit `Dockerfile.tmpl` together with the regenerated Dockerfiles — the pull
  request workflow fails when they are out of sync.
- Only pick versions that support **this repository's PHP version**. Never move the PHP base image to another
  minor or major PHP version, and never change the Debian release of an existing tag (e.g. `trixie`, `bullseye`).

This command never dead-ends: follow the `autonomous-execution` skill of the `code` plugin. When an update fails,
**isolate it**: don't commit its changes (restore the files it touched), continue with the next one, and list it —
with the error — in the PR body's `## Decisions and skipped steps` section. Isolate the smallest unit that failed:
in a phase with one commit per item (Phases 3--6), only that item; the items already committed stay. A situation
this command doesn't describe is handled the same way, plus a skill-gap issue.

When a version source can't be reached (rate limit, outage, no network), try the other source named for that item
(Docker Hub ↔ the project's GitHub releases). PECL has no substitute: `install-php-extensions` downloads extensions
from PECL, so a version found elsewhere (e.g. on Packagist) can't be installed until PECL has it. When no source
answers, isolate that item and record it as "not checked".

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
4. Determine the context of this repository and record it for the later phases:
    - **PHP version**: from the repository name (`php85` → `8.5`, `php74` → `7.4`), confirmed by the
      `FROM ... AS runtime` line of the Dockerfiles.
    - **Variants**: every `<variant>/Dockerfile` that exists (e.g. `fpm`, `apache`, `frankenphp`; `php74` has no
      `frankenphp`). "All Dockerfiles" below always means all Dockerfiles of these variants.
    - **Debian release**: the suffix of the current base image tags (e.g. `trixie`, `bullseye`).
5. Check that `task generate` works (it needs Task and Docker) and leaves the working tree clean. When it can't
   run, use the fallbacks of the PHP images skill ("When `task generate` can't run") and use the working one
   wherever this command says `task generate`. When none works, the template-based phases (4, 5 and the Gomplate
   part of 6) can't be verified: skip them and record that, and still run the `FROM`-only phases (2 and 3), whose
   changes don't depend on the template. When it changes
   files on a clean `origin/main`, the repository was already out of sync: commit that separately first as
   `chore: Regenerate Dockerfiles from template` and record it.

## Phase 2 --- PHP Base Image Updates

The `FROM ... AS runtime` line of each variant uses a different base image, but all track the same PHP
`<major>.<minor>.x` patch series:

- `fpm/Dockerfile`: `FROM php:<php-version>-fpm-<debian> AS runtime`
- `apache/Dockerfile`: `FROM php:<php-version>-apache-<debian> AS runtime`
- `frankenphp/Dockerfile` (when present): `FROM dunglas/frankenphp:<frankenphp-version>-php<php-version>-<debian> AS runtime`

1. Check Docker Hub for the latest `php:<major>.<minor>.x-fpm-<debian>` tag. Only consider patch updates within
   this repository's `<major>.<minor>.x` series and with the same Debian release. End-of-life PHP versions usually
   have no newer patch release: then there is nothing to update.
2. When the repository has a `frankenphp` variant, check Docker Hub for the latest `dunglas/frankenphp` tag that
   matches `x.x.x-php<major>.<minor>.x-<debian>`. Prefer the tag with the same PHP patch version as the `php`
   image of step 1. When FrankenPHP has no tag for that patch yet, take the newest tag in the series and record
   the mismatch.
3. Update the `FROM ... AS runtime` line in all Dockerfiles when newer versions are available.
4. Run `task generate` to confirm the output is stable (it must not change anything else).
5. Check `git status`. Commit all Dockerfiles together in a single commit if there are any changes.
   Commit message: `chore(deps): Update PHP base image versions`.
6. If there are no changes, skip the commit and move on.

On failure, isolate this phase (see the top of this command).

## Phase 3 --- Shared Build Image Updates

All Dockerfiles share these `FROM` images. Each has a `# Latest version of ...` comment with its source above it:

- `FROM mlocati/php-extension-installer:<version> AS php_extension_installer`
- `FROM composer/composer:<version>-bin AS composer`
- `FROM node:<version>-<debian>-slim AS node`

Process each image individually and in order:

1. Look up the latest stable tag on Docker Hub (or the project's GitHub releases), keeping the existing tag suffix
   (e.g. `-bin`, `-trixie-slim`).
    - **php-extension-installer** and **Composer**: the latest stable release. Check its release notes for dropped
      support of this repository's PHP version; when it was dropped, keep the newest release that still supports it.
    - **Node.js**: the latest release of the newest **Active LTS** major, found in the release schedule at
      `https://nodejs.org/en/about/previous-releases`. Never move to a Current (non-LTS) major. See
      [Moving Node.js to a new major](#moving-nodejs-to-a-new-major) before changing the major.
2. If a newer version is available, update the `FROM` line in all Dockerfiles.
3. Run `task generate` to confirm the output is stable.
4. Commit all Dockerfiles together in a single commit.
   Commit message: `chore(deps): Update <image> to <new-version>`, using `php-extension-installer`, `Composer` or
   `Node.js` as `<image>`. For example: `chore(deps): Update Composer to 2.11.0`.
5. If there is no update for this image, skip the commit and move on to the next image.

On failure, isolate only the failing item and continue with the next one (see the top of this command).

### Moving Node.js to a new major

The `builder_nodejs` stage doesn't install Node.js: it copies `/usr/local/bin/node` and `/usr/local/lib/node_modules`
from the `node` image, and links `corepack/dist/corepack.js` from it to install npm, Yarn and pnpm. A new major can
drop something the stage relies on — e.g. the Node.js 25+ images no longer bundle corepack. Before moving to a new
major:

1. Check that the new image still provides every path the `builder_nodejs` stage of `Dockerfile.tmpl` copies or
   links: `docker run --rm node:<new-tag> ls /usr/local/lib/node_modules` must list `npm` and `corepack`.
2. When it does, update to the new major as usual.
3. When it doesn't, the stage needs a structural change (e.g. installing corepack with
   `npm install --global corepack@<version>`), which doesn't belong in a dependency update. Don't change the major:
   update to the latest release of the **current** major instead (when that major is still supported), and record
   in the PR body which major is blocked, what is missing and the change it needs. This is an expected outcome, not
   a failure: no skill-gap issue is needed for it.
4. When the check can't run (no Docker), keep the current major, update within it and record the new major as "not
   verified".
5. When the current major has reached end-of-life, say so prominently at the top of the `## Decisions and skipped
   steps` section, so the structural change gets prioritised.

## Phase 4 --- PHP Runtime Extension Updates

`Dockerfile.tmpl` pins the following PHP extensions in the runtime stage. Each `ARG` has a `# Latest version of ...`
comment pointing at its PECL page:

- `PHP_EVENT_VERSION` — `https://pecl.php.net/package/event`
- `PHP_IGBINARY_VERSION` — `https://pecl.php.net/package/igbinary`
- `PHP_REDIS_VERSION` — `https://pecl.php.net/package/redis`
- `PHP_AMQP_VERSION` — `https://pecl.php.net/package/amqp`

Process each extension individually and in order:

1. Look up the releases **on PECL**, the source `install-php-extensions` downloads from:
   `https://pecl.php.net/rest/r/<extension>/allreleases.xml` lists every version with its stability (newest first).
   Packagist can list a release days before it is published on PECL; such a version can't be installed yet. When
   Packagist (or the project's GitHub releases) is ahead of PECL, keep the PECL version and record the newer version
   as "not on PECL yet" — this is not a failure and needs no skill-gap issue.
2. Check the release's PHP version requirement: the `<php><min>`/`<max>` of
   `https://pecl.php.net/rest/r/<extension>/package.<version>.xml`, or the `require.php` constraint of the matching
   Packagist package (more accurate, when it exists). Pick the newest PECL release that supports this repository's
   PHP version.
   When the release doesn't state which PHP versions it supports, update only within the current `<major>.<minor>`
   series (e.g. `6.3.0` → `6.3.1`); skip a newer series and record it as "PHP support unknown".
3. Prefer stable releases. A pre-release (e.g. `3.2.17RC1`) is only acceptable when the current pin is already a
   pre-release because no stable release supports this PHP version yet; move to a stable release as soon as one
   does.
4. If a newer version is available, update the corresponding `ARG` in `Dockerfile.tmpl` and run `task generate`.
5. Commit `Dockerfile.tmpl` and all Dockerfiles together in a single commit.
   Commit message: `chore(deps): Update <extension> extension to <new-version>`.
   For example: `chore(deps): Update redis extension to 6.4.0`.
6. If there is no update for this extension, skip the commit and move on to the next extension.

Repeat for every extension. Each updated extension gets its own commit.

On failure, isolate only the failing item and continue with the next one (see the top of this command).

## Phase 5 --- Builder Stage Tool Updates

`Dockerfile.tmpl` pins the following tools in the builder stage, each with a `# Latest version of ...` comment:

- `XDEBUG_VERSION` — `https://pecl.php.net/package/xdebug`
- `PCOV_VERSION` — `https://pecl.php.net/package/pcov`
- `FIXUID_VERSION` — the GitHub releases of `boxboat/fixuid`

Process each tool individually and in order:

1. Look up the newest stable release that supports this repository's PHP version: for Xdebug and pcov with the same
   PECL rules as Phase 4, for fixuid on its GitHub releases. For
   example, Xdebug 3.1.x is the last series that supports PHP 7.4, so `php74` only receives 3.1.x patch releases.
2. If a newer version is available, update the corresponding `ARG` in `Dockerfile.tmpl` and run `task generate`.
3. Commit `Dockerfile.tmpl` and all Dockerfiles together in a single commit.
   Commit message: `chore(deps): Update <tool-name> to <new-version>`.
   For example: `chore(deps): Update Xdebug to 3.5.4`.
4. If there is no update for this tool, skip the commit and move on to the next tool.

Repeat for every tool. Each updated tool gets its own commit.

Any other `ARG` or `FROM` image in `Dockerfile.tmpl` or the Dockerfiles with a `# Latest version of ...` comment that
isn't listed in Phases 2--5 is handled the same way, in its own commit, and recorded in the PR body (and as a
skill-gap issue, so it gets listed here).

On failure, isolate only the failing item and continue with the next one (see the top of this command).

## Phase 6 --- Taskfile Tool Updates

`Taskfile.dist.yml` pins the Docker images of two tools:

- `HADOLINT_TAG_VERSION` — the GitHub releases of `hadolint/hadolint`
- `GOMPLATE_TAG_VERSION` — the GitHub releases of `hairyhenderson/gomplate`

Process each tool individually and in order:

1. Look up the latest stable release.
2. If a newer version is available, update the variable in `Taskfile.dist.yml`.
3. Verify the new version:
    - **Hadolint**: run `task lint`. When the new version reports new findings, fix them in `Dockerfile.tmpl` (run
      `task generate`) in the same commit, or isolate this tool when they can't be fixed safely.
    - **Gomplate**: run `task generate`. The output must not change; when it does or generation fails, isolate
      this tool.
4. Commit `Taskfile.dist.yml` (and any files changed in step 3) together in a single commit.
   Commit message: `chore(deps): Update <tool-name> to <new-version>`.
   For example: `chore(deps): Update Hadolint to v2.15.2`.
5. If there is no update for this tool, skip the commit and move on to the next tool.

On failure, isolate only the failing item and continue with the next one (see the top of this command).

## Phase 7 --- GitHub Actions Updates

1. Scan the following files for pinned `uses:` action references:
    - `.github/workflows/*.yml`
2. For each external action (e.g. `specsnl/github-actions/.github/workflows/build-php.yml@2.4.4`), use
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

## Phase 8 --- License Year Update

1. Check if the `LICENSE` file contains a year range (e.g. `2020-2025`) or a single year (e.g. `2024`).
2. If the current year is not already the end year (e.g. the current year is `2026`):
   - Single year (e.g. `2024`) → update to the current year (`2026`).
   - Year range (e.g. `2020-2025`) → update the end year to the current year (`2020-2026`).
3. Commit separately if there are any changes.
   Commit message: `chore: Update copyright year`.
4. If there are no changes, skip the commit and move on.

------------------------------------------------------------------------

## Final State

When there are no changes after all update steps, the run ends here with a report instead of a PR: everything is
already up to date. The report also lists the skipped phases and decisions. Delete the empty branch (and the
worktree, when one was created).

- The `updates` branch contains one commit per update that was found, in phase order:
    1. Regenerated Dockerfiles (only when `main` was out of sync, see Phase 1)
    2. PHP base image versions
    3. php-extension-installer, Composer and Node.js images (one commit each)
    4. PHP runtime extensions: event, igbinary, redis, amqp (one commit each)
    5. Builder tools: Xdebug, pcov, fixuid (one commit each)
    6. Taskfile tools: Hadolint, Gomplate (one commit each)
    7. GitHub Actions versions
    8. Copyright year
- Branch: `updates`, or the suffixed name chosen in Phase 1 step 2.
- Based on latest `origin/main`.
- `task generate` leaves the working tree clean: the Dockerfiles match the template.
- The working tree should be clean.
- Push the branch to the remote and create a pull request for review and merging targeting `origin/main`.
  The title should be `chore: Update dependencies`. When the branch already has an open pull request (a reused
  `updates` branch), don't open a second one: update the existing pull request's description so it lists all its
  commits.
- When pushing or creating the pull request fails (e.g. no GitHub authentication), keep the branch locally and end
  with a report that contains the branch name and the drafted pull request title and description.
- Add a Pull Request description that lists the changes based on the commits that were made. Stick to the
  commit messages but remove the "chore" prefix. Add a `## Decisions and skipped steps` section when any phase was
  skipped or isolated, a version was held back for PHP compatibility, or a non-default branch or worktree was used.
  For example:

```md
Updated the following dependencies:

- Updated PHP base image versions
- Updated Composer to 2.11.0
- Updated redis extension to 6.4.0
- Updated Xdebug to 3.5.4
- Updated GitHub Actions versions
```

To update the other PHP image repositories, run this command in each of them: it checks every version against
that repository's PHP version, which `/sync-sibling-php-repos` only does by adjusting the copied changes.
