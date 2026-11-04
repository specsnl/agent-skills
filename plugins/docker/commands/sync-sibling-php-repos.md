---
description: Synchronize sibling PHP repositories by propagating relevant commits from the current repository
name: sync-sibling-php-repos
---

See skill @../skills/php-images/SKILL.md for general information about the PHP images, their repository structure, and
how to find sibling images.

# Goal

Propagate relevant changes from the current PHP image repository to all sibling repositories. Each sibling receives
its own branch, commit history, and pull request that mirrors the original — adjusted where necessary for PHP version
differences.

This command is run from a PHP image repository on a feature branch, usually one that has a pull request. The
siblings are **all other** PHP image repositories in the `specsnl` organisation, including end-of-life versions. For
example, if you are in the `php85` repository with updates on a branch and the organisation contains `php85`,
`php84`, `php83` and `php74`, run this command to propagate the applicable changes to `php84`, `php83` and `php74`.

This command never dead-ends: follow the `autonomous-execution` skill of the `code` plugin. A failure in one sibling
skips only that sibling (or that commit): continue with the others and record it in the Final State summary. A
situation this command doesn't describe is handled the same way, plus a skill-gap issue.

## Phase 1 --- Safety Checks

1. Synchronize with the remote: `git fetch --prune`. Compare against `origin/main` everywhere below, never against
   a local `main`, which can be behind or diverged.
2. Confirm the current branch is **not** `main`. If it is, there is nothing to propagate: end with a report saying
   so (run it again from the feature branch).
3. Check the working tree. This command only reads the branch's commits, so uncommitted changes don't block it —
   but they are not propagated: leave them untouched and mention them in the summary.
4. Find the pull request of the current branch (any status). When there is none, continue without it: derive the
   sibling PR title from the branch's commits (following the repository's title convention, e.g.
   `chore: Update dependencies`) and record that in the summary.

## Phase 2 --- Context Gathering

1. Identify the current repository name (e.g., `php85`) and the active branch name — this branch name will be
   reused in every sibling.
2. List all commits on the current branch that are not yet on `origin/main`, without merge commits:
   `git log --no-merges --reverse --oneline origin/main..HEAD`
   For each commit, also retrieve its full diff: `git show <sha>`. Merge commits (e.g. `main` merged into the
   branch) are not propagated; record them in the summary when there are any.
3. Record the **title** of the pull request found in Phase 1 (or the derived title) — this will be reused for the
   sibling PRs, with the same version adjustments as the commit messages (see Phase 4).
4. Locate the sibling repositories using the PHP images skill: list every `php<NN>` repository in the `specsnl`
   organisation (see "Maintained PHP versions") and exclude the current one. Check locally first (sibling
   directories alongside the current repository) and confirm each one by verifying its git remote URL or README.
   Clone a sibling that only exists on GitHub next to the others. Record the local path of every sibling.
5. For every sibling, record its PHP version, its variants (the `<variant>/Dockerfile` files it has) and its
   Debian release, as described in the PHP images skill.
6. For every located sibling, check whether its working tree is clean (no staged changes, no unstaged changes, no
   untracked files). A dirty sibling is left untouched: work in a fresh worktree of that sibling instead (see
   Phase 4). When that isn't possible either, skip only that sibling and list it, with what it has outstanding, in
   the summary. A sibling that can't be found (locally or on GitHub) is skipped the same way.

## Phase 3 --- Change Analysis

For every commit identified in Phase 2, decide whether it applies to each sibling and what adjustments are needed:

- **Applies as-is**: the change is version-agnostic (e.g., a tooling update that supports all PHP versions).
- **Applies with adjustments**: the change is relevant but version strings must be adapted (e.g., a base image
  bump from `php:8.5.x` must become `php:8.4.x` in `php84`).
- **Applies partially**: the change touches a variant the sibling doesn't have (e.g. `frankenphp` in `php74`):
  apply only the parts for the variants it does have, and drop the rest (including `{{ if .is_frankenphp }}` blocks
  and `files/frankenphp` changes when the sibling has no FrankenPHP variant).
- **Node.js lives in another stage**: the source and the sibling differ in where Node.js lives (a standalone
  `builder_nodejs` target in one, inside `builder` in the other; see "Where Node.js lives" in the PHP images skill).
  Port a change to the Node.js setup into the stage that holds Node.js in the sibling. A commit that moves Node.js
  into `builder` (removing the standalone target) is ported as a whole, including the Taskfile, workflow and
  ruleset changes that come with it; when it is already done in the sibling, skip it as "already applied".
- **Does not apply**: the change is specific to the source PHP version and cannot or should not be ported (e.g., a
  new dependency that only supports PHP 8.5, or an extension version that dropped support for the sibling's PHP
  version). For a version bump, check whether a newer version that does support the sibling's PHP version exists
  (e.g. the latest Xdebug 3.1.x for PHP 7.4) and apply that instead, as an adjusted change. Pick it with the version
  rules of the `update-php-images` command: extensions only from PECL, and the Node.js major check before moving a
  sibling to a new Node.js major.

Keep the sibling's own Debian release and version-specific workarounds (e.g. `DEBIAN_SECURITY_SNAPSHOT` in `php74`)
intact: a change from the source repository never removes them.

Remember how the Dockerfiles are made (see the PHP images skill): a change in a `<variant>/Dockerfile` other than a
`FROM` image comes from `Dockerfile.tmpl`, so port the template change, not the generated output.

Write down the per-sibling plan — which commits apply, what adjustments are needed, and in what order they should be
applied (preserve the original commit order) — and include it in the Final State summary. Don't wait for approval of
the plan: continue with Phase 4.

## Phase 4 --- Sibling Synchronization

Repeat the following steps for each sibling, working through them one sibling at a time:

1. `cd` into the sibling directory.
2. Fetch all remote changes and prune stale tracking branches: `git fetch --prune`
3. Choose the branch, in this order:
    - **The branch doesn't exist** in the sibling (locally or on the remote): use the source branch name.
    - **It exists from an earlier run of this command** — every commit it has on top of `origin/main` matches a
      source commit by subject (with this sibling's version adjustments) — continue on it: base the work on the
      remote branch (`origin/<branch-name>`), apply only the source commits it doesn't have yet, and push without
      force. Its open pull request is updated instead of opening a new one (step 9).
    - **It exists with other commits:** leave it untouched and use `<branch-name>-<YYYY-MM-DD>`; add `-2`, `-3`, …
      when that name is taken too.
4. Prepare the branch without changing the user's checkout, unless it is a clean `main`:
    - **Clean sibling on `main`** (no staged, unstaged or untracked changes): create the branch directly from the
      remote: `git checkout -b <branch-name> origin/main` (or `git checkout -b <branch-name> origin/<branch-name>`
      when continuing an earlier run). Don't pull into the local `main`.
    - **Any other state** (another branch checked out, or a dirty working tree): leave the checkout untouched and
      create a fresh worktree: `git worktree add -b <branch-name> <path> origin/main` (or `origin/<branch-name>`
      when continuing; e.g. `<path>` = `../<sibling>-<branch-name>`), and run the remaining steps there. Remove the
      worktree (`git worktree remove <path>`) once the branch is pushed.
5. When applying a commit fails for this sibling, skip that commit (list it under "Skipped commits") and continue
   with the next one. When a commit results in no changes in this sibling (the change is already there, e.g. made
   by Dependabot or an earlier run), don't create an empty commit: skip it as "already applied". When pushing or
   creating the PR fails (e.g. no GitHub authentication), keep the branch locally, put the drafted PR title and
   description in the summary, and move on to the next sibling. When no commit applies to this sibling, don't push a
   branch or open a PR for it.
6. Apply the relevant changes identified in Phase 3. **Do not use `git cherry-pick`** — manually replicate each
   change so that PHP version strings and any other version-specific values are correctly adapted for this sibling.
   Apply the changes in the original commit order. Edit `Dockerfile.tmpl` for template changes and the `FROM` lines
   of the sibling's `<variant>/Dockerfile` files for image changes.
7. After applying the changes for each logical commit, run `task generate` and check that the regenerated
   Dockerfiles only contain the expected changes. When `task generate` can't run, use the fallbacks of the PHP images
   skill; when none works, only commit changes that don't touch the template (e.g. `FROM` images, workflows) and
   skip the rest, recording it. Commit `Dockerfile.tmpl` together with the regenerated Dockerfiles, using the commit
   message of the corresponding source commit. When a version in that message was adjusted for this sibling, use the
   adjusted version.
8. Push the branch: `git push -u origin <branch-name>`
9. Create a pull request from `<branch-name>` to `main`, or — when continuing an earlier run — update the
   description of its existing pull request. For the PR title, reuse the source PR title, with version strings
   adjusted for this sibling the same way as the commit messages (e.g. `Update PHP to 8.5.12` becomes
   `Update PHP to 8.4.15` in `php84`). For the body, do not copy the source PR description verbatim — instead, derive it from the commits that were actually
   applied to this sibling:
   - Include one bullet per applied commit, using the commit subject line as the bullet text (reworded to sentence
     case if needed).
   - Omit any skipped commits entirely.
   - If a commit was applied with adjustments (e.g. version strings adapted), include it as-is — the bullet describes
     intent, not the exact change.
   The result must accurately reflect what this sibling actually received, even if that differs from the source PR
   description.

------------------------------------------------------------------------

## Final State

After processing all siblings, provide a summary table listing the following. Below it, list the decisions and
skipped parts: skipped siblings (and why), the per-sibling plan, suffixed or continued branches, worktrees used, a
derived PR title, skipped merge commits, commits skipped as "already applied", drafted PRs that couldn't be created,
uncommitted changes in the source repository, and any skill-gap issue filed.

| Sibling repository | Branch created  | Pull request URL | Skipped commits (reason)          |
|--------------------|-----------------|------------------|-----------------------------------|
| `php84`            | `<branch-name>` | `<PR URL>`       | e.g., none                        |
| `php83`            | `<branch-name>` | `<PR URL>`       | e.g., `abc1234` (PHP 8.5+ only)   |
| `php74`            | `<branch-name>` | `<PR URL>`       | e.g., `def5678` (FrankenPHP only) |
