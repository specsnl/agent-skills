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

This command is run from a PHP image repository on a feature branch, usually one that has a pull request. If you
are in the `php85` repository with updates on a branch, run this command to propagate the applicable changes to
`php84` and `php83`.

This command never dead-ends: follow the `autonomous-execution` skill of the `code` plugin. A failure in one sibling
skips only that sibling (or that commit): continue with the others and record it in the Final State summary. A
situation this command doesn't describe is handled the same way, plus a skill-gap issue.

## Phase 1 --- Safety Checks

1. Confirm the current branch is **not** `main`. If it is, there is nothing to propagate: end with a report saying
   so (run it again from the feature branch).
2. Check the working tree. This command only reads the branch's commits, so uncommitted changes don't block it —
   but they are not propagated: leave them untouched and mention them in the summary.
3. Find the pull request of the current branch (any status). When there is none, continue without it: derive the
   sibling PR title from the branch's commits (following the repository's title convention, e.g.
   `chore: Update dependencies`) and record that in the summary.

## Phase 2 --- Context Gathering

1. Identify the current repository name (e.g., `php85`) and the active branch name — this branch name will be
   reused in every sibling.
2. List all commits on the current branch that are not yet on `main`:
   `git log main..HEAD --oneline`
   For each commit, also retrieve its full diff: `git show <sha>`.
3. Record the **title** of the pull request found in Phase 1 (or the derived title) — this will be reused verbatim
   when creating sibling PRs.
4. Locate the sibling repositories using the PHP images skill. Check locally first (sibling directories alongside
   the current repository). Confirm each sibling by verifying its git remote URL or README. Record the local path
   of every sibling that exists.
5. For every located sibling, check whether its working tree is clean (no staged changes, no unstaged changes, no
   untracked files). A dirty sibling is left untouched: work in a fresh worktree of that sibling instead (see
   Phase 4). When that isn't possible either, skip only that sibling and list it, with what it has outstanding, in
   the summary. A sibling that can't be found (locally or on GitHub) is skipped the same way.

## Phase 3 --- Change Analysis

For every commit identified in Phase 2, decide whether it applies to each sibling and what adjustments are needed:

- **Applies as-is**: the change is version-agnostic (e.g., a tooling update that supports all PHP versions).
- **Applies with adjustments**: the change is relevant but version strings must be adapted (e.g., a base image
  bump from `php:8.5.x` must become `php:8.4.x` in `php84`).
- **Does not apply**: the change is specific to the source PHP version and cannot or should not be ported (e.g., a
  new dependency that only supports PHP 8.5).

Document the per-sibling plan before proceeding: which commits apply, what adjustments are needed, and in what
order they should be applied (preserve the original commit order).

## Phase 4 --- Sibling Synchronization

Repeat the following steps for each sibling, working through them one sibling at a time:

1. `cd` into the sibling directory.
2. Fetch all remote changes and prune stale tracking branches: `git fetch --prune`
3. Choose the branch name: the same name as the source branch. When that branch already exists in the sibling
   (locally or on the remote) with commits of its own, leave it untouched and use `<branch-name>-<YYYY-MM-DD>`
   instead.
4. Create the branch from the latest `origin/main`:
    - **Clean sibling:** `git checkout main`, `git pull origin main`, then `git checkout -b <branch-name>`.
    - **Dirty sibling:** leave its checkout untouched and create a fresh worktree:
      `git worktree add -b <branch-name> <path> origin/main` (e.g. `../<sibling>-<branch-name>`), and run the
      remaining steps there. Remove the worktree (`git worktree remove <path>`) once the branch is pushed.
5. When applying a commit fails for this sibling, skip that commit (list it under "Skipped commits") and continue
   with the next one. When pushing or creating the PR fails, record it and move on to the next sibling. When no
   commit applies to this sibling, don't push a branch or open a PR for it.
6. Apply the relevant changes identified in Phase 3. **Do not use `git cherry-pick`** — manually replicate each
   change so that PHP version strings and any other version-specific values are correctly adapted for this sibling.
   Apply the changes in the original commit order.
7. After applying the changes for each logical commit, verify the result looks correct. Then commit with the exact
   same commit message as the corresponding commit in the source repository.
8. Push the branch: `git push -u origin <branch-name>`
9. Create a pull request from `<branch-name>` to `main`. For the PR title, reuse the source PR title verbatim. For
   the body, do not copy the source PR description verbatim — instead, derive it from the commits that were actually
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
skipped parts: skipped siblings (and why), suffixed branch names, worktrees used, a derived PR title, uncommitted
changes in the source repository, and any skill-gap issue filed.

| Sibling repository | Branch created  | Pull request URL | Skipped commits (reason)        |
|--------------------|-----------------|------------------|---------------------------------|
| `php84`            | `<branch-name>` | `<PR URL>`       | e.g., none                      |
| `php83`            | `<branch-name>` | `<PR URL>`       | e.g., `abc1234` (PHP 8.5+ only) |
