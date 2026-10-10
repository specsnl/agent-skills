---
name: update-project
description: Update dependencies of Specs projects based on Laravel using isolated commits.
---

# Goal

Perform a full dependency update of the project.

All commands MUST be executed via `task`. Never run composer, npm, node, or php directly on the host.

Each phase specifies its own error-handling policy. Some phases allow attempting a fix before
aborting — follow the per-phase instructions rather than a blanket stop rule.

## Commit Strategy

When committing changes at the end of each phase, only stage files that are directly related to that phase's purpose. If other files have changed that are unrelated to the phase (e.g., a markdown file or documentation updated as a side-effect of running a command), commit those separately with a descriptive commit message that reflects what those changes actually are. Never bundle unrelated changes into a phase commit.

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
4. Check if local `main` branch is up to date with `origin/main`:
    - If behind → abort and inform the user to pull the latest changes.
    - If ahead with unique commits → abort and inform the user to push or rebase their commits.
    - If diverged → This can occur when testing locally (e.g., running `task checkall`) — the local branch may have commits
    not yet pushed to the remote. Ask the user which branch to use as the source for the vendor-updates branch in step
    5: `origin/main` or local `main`. **Choosing local `main` allows you to test iterations without pushing to the
    remote.**  
    **Warning:** choosing the local main branch may lead to merge conflicts later if the remote main has commits the local
    branch doesn't know about (common when you don't push test iterations).
5. Prepare branch `vendor-updates`:
    - If branch does not exist → create from the chosen branch in step 4 (`origin/main` by default, or local `main` if
    the user selected it in a diverged state)
    - If branch exists:
        - If fully merged into `main` → delete locally and recreate from the chosen branch.
        - If behind on `main` and has NO unique commits → reset `vendor-updates` to the chosen branch.
        - If it contains unique commits → abort and notify user.
6. Make sure that there is an `auth.json` file in the project root with correct credentials for private repositories if
the composer.json file contains a repositories section with private repositories like filament.
If not, abort and inform the user to create it. Suggest to the user to run `task setup:auth`.

Always branch from the chosen source (see step 4).

## Phase 2 --- Environment Preparation

1. Invoke the `executing-commands` skill to confirm which task targets are available in this
project's Taskfile before running any commands.
2. Start project: `task up`.
3. Ensure environment is refreshed. This makes sure all dependencies are installed according to their respective lock
files. It will also rebuild the frontend assets. Run the command: `task refresh`.

Abort if any command fails.

## Phase 3 --- Backend Dependencies

1. Update Composer dependencies: `task composer:update` (This task must internally run `composer update -W` inside the
PHP container).
2. Run full backend checks: `task checkall`. If any check fails, attempt to fix the issue, then
re-run `task checkall` to confirm resolution before proceeding. If you cannot fix the issues,
abort and report the errors.
    - If there are any style issues, run `task composer:script:fixstyle` to automatically fix them.
    If that does not work, try to fix style issues manually. Re-run `task checkall` after each
    attempt. If you cannot fix the style issues, abort and report the errors.
    - If there are any PHPStan issues, try to fix them. Do not fix PHPStan issues by adding them to
    the PHPStan baseline file or by adding annotations like `@phpstan-ignore`. Re-run `task checkall`
    after each fix attempt. If you cannot fix the PHPStan issues, abort and report the errors.
    - If there are any PHPUnit test failures, try to fix them. Do not fix test failures by skipping
    tests. Re-run `task checkall` after each fix attempt. If you cannot fix the test failures, abort
    and report the errors.
3. Check git status for all changed or newly tracked files resulting from the update. Group them by purpose:
    - Stage only files directly related to the Composer update (e.g., `composer.lock`, `vendor/`, published package
    assets) and commit. Commit message: `chore(deps): Updated Composer dependencies`.
    - For any remaining unrelated files (e.g., `AGENTS.md`, skill files, markdown docs updated as a side-effect),
    create a separate commit per logical group with a descriptive message that reflects what those changes are
    (e.g., `docs: Updated AGENTS.md`).
4. If there are no changes, skip the commit step and move on to the next phase.

## Phase 4 --- Replace Abandoned `ilyes512` Packages

Some Composer packages formerly published under the `ilyes512` vendor namespace have been abandoned
and superseded by maintained `specsnl` equivalents. This phase migrates any such packages.

1. Inspect the project's `composer.json` (`require` and `require-dev`) for packages under the
`ilyes512/*` vendor namespace. If there are none, skip this phase entirely.
2. For each `ilyes512/*` package found, determine its maintained replacement:
    - The authoritative source is Composer's own abandonment metadata. When Composer resolves an
    abandoned package (during the `task composer:update` run in Phase 3) it prints a warning such as:
    `Package ilyes512/foo is abandoned, you should avoid using it. Use specsnl/foo instead.`
    Use the replacement package named in that warning **verbatim**.
    - If the abandonment warning does not name an explicit replacement, fall back to a straight
    vendor-prefix swap: `ilyes512/<name>` → `specsnl/<name>`. Before relying on the fallback, confirm
    the `specsnl/<name>` package actually exists (e.g. via `task composer:cmd:outdated` output or the
    package's Packagist page).
    - If a package is **not** abandoned, or its abandonment notice points to a replacement **outside**
    the `specsnl` namespace, do **not** replace it. Leave it in place and note it in your final report.
3. For each package to migrate, edit `composer.json`: remove the `ilyes512/*` entry and add the
`specsnl/*` replacement, preserving the existing version constraint. Adjust the constraint only if the
replacement's available versions require it.
4. Update the lock file and vendor directory: `task composer:update`.
5. The replacement package may expose a different PHP namespace or class names than the abandoned one.
Search the codebase for references to the old package's namespace/classes and update any usages to the
replacement's API. Then run full backend checks: `task checkall`. If any check fails, attempt to fix
the issue and re-run `task checkall` to confirm resolution before proceeding (follow the same
style/PHPStan/PHPUnit fix rules described in Phase 3). If you cannot resolve the failures, abort and
report the errors.
6. Check `git status` for all changed files. Stage only files directly related to this migration (e.g.
`composer.json`, `composer.lock`, `vendor/`, and any source files updated for the new package's API)
and commit. Commit message: `chore(deps): Replaced abandoned ilyes512 packages with specsnl equivalents`.
For any remaining unrelated changed files, commit them separately with a descriptive message.
7. If there are no `ilyes512/*` packages or no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 5 --- NPM package manager version

1. Update NPM package manager version: `task npm:corepack:update`.
2. Commit separately if there are any changes. Commit message: `chore(npm): Updated NPM package manager version`.
3. If there are no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 6 --- Frontend Dependencies

1. Update NPM dependencies: `task npm:update`.
2. Build assets: `task npm:script:build`.
3. Check git status for all changed files. Stage only files directly related to the NPM update (e.g.,
`package-lock.json`, `node_modules/`, built assets) and commit. Commit message: `chore(deps): Updated NPM
dependencies`. For any remaining unrelated changed files, commit them separately with a descriptive message.
4. If there are no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 7 --- Docker Image Updates

1. Scan the following files for pinned Docker image references:
    - `compose.yml`
    - `php/Dockerfile`
    - `nginx/Dockerfile`
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
4. After updating, rebuild the local Docker images: `task build`.
5. Reset the environment to make sure it is using the latest images: `task reset`.
6. Run full backend checks: `task checkall`.
7. Check `git status` for all changed files. Stage only files directly related to Docker image updates (e.g.,
`compose.yml`, `php/Dockerfile`, `nginx/Dockerfile`, `.github/workflows/*.yml`) and commit. Commit message:
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

## Phase 9 --- Final Checks

Phase 9 is informational only — findings here do not block the PR. Create the PR first (see Final
State below), then report the Phase 8 summary to the user.

1. Run the following audit commands and create a summary of the results. Suggest to the user to fix any of the issues
that are found:
    1. Run `task composer:cmd:audit`.
    2. Run `task npm:cmd:audit`.
2. Run `task composer:cmd:outdated -- --direct --major-only` to check for any major updates that are available for direct
dependencies. If there are any, create a summary and suggest to the user to update those as well.

------------------------------------------------------------------------

## Final State

Abort if there are no changes after all update steps, and inform the user that dependencies are already up to date.

- There could be up to 7 commits on the `vendor-updates` branch (more if unrelated side-effect changes were
committed separately per the Commit Strategy):
    1. Composer updates
    2. Replaced abandoned `ilyes512` packages with `specsnl` equivalents
    3. NPM package manager version update
    4. NPM dependency updates
    5. Docker image version updates
    6. GitHub Actions version updates
    7. GitHub Actions runner image updates
- Branch: `vendor-updates`
- Based on the chosen source from step 4 (latest `origin/main` by default, or local `main` if selected).
- The working tree should be clean.
- **This skill explicitly authorizes invoking the `create-pr` skill to push the `vendor-updates`
  branch and open the pull request as the final step.** The `create-pr` skill will handle title
  format discovery and branch push. Because `task checkall` has already run during the update phases,
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

  **Suggested PR body**: Include only the bullets for phases that produced actual changes. If any
  additional side-effect commits were made (e.g. `docs: Updated AGENTS.md`), add them as extra bullets
  under `## Summary`.

  ```md
  ## Summary
  - Updated Composer dependencies
  - Replaced abandoned `ilyes512` packages with `specsnl` equivalents
  - Updated NPM package manager version
  - Updated NPM dependencies
  - Updated Docker image versions
  - Updated GitHub Actions versions
  - Updated GitHub Actions runner images

  ## Test plan
  - [ ] Review the dependency changelog(s) for any breaking changes or notable updates.
  - [ ] Verify the CI workflows pass on the updated runner images.
  ```

  Only include the runner images test plan item when the runner images were updated.
