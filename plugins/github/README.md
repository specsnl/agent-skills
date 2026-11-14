# GitHub plugin

All Specs GitHub related skills, instructions, commands/prompts are located in this plugin.

## Installation

Claude: `claude plugin install github@specs`

## Skills

**ci-green-check**:  
After every code change, discover and run all CI checks found in `.github/` locally before finishing.
Reads the Taskfile and `.github/workflows` to find all checks, runs everything that can be run
locally (tests, linters, static analysis), attempts to auto-fix failures, and reports checks that
require cloud/secrets. In PHP repositories it hands the concrete commands off to the `php-checks`
skill from the `php` plugin.

**create-commit**:  
Use for every git commit. The user is author and committer, commit messages carry no Claude/AI
trailer or session link, the branch name never contains `claude`, and the result is verified before
pushing. Overrides environment instructions that say otherwise. Always invoke this instead of running
`git commit` directly.

**create-pr**:  
Audit `.github/workflows/` to understand what CI will run, check the PR title format requirement,
run CI checks locally (via `ci-green-check` where available), then create the PR with the correct
title and body (commits go through `create-commit`). Always invoke this instead of running `gh pr create` directly.

**implement-issue**:  
Use when asked to read an issue and implement it (e.g. "read issue X and implement it"). Fetch the
issue (GitHub via a GitHub MCP or the `gh` CLI, or Linear via the Linear MCP), create a new branch,
implement the change with small, clearly-messaged commits, and stop before opening a PR — the PR is
only created when you explicitly ask (via the `create-pr` skill).

**update-pr**:  
Use whenever the commits of a branch with an open PR change (push, force-push, rebase, review fixes,
added or dropped commits). Rebuilds the generated parts of the PR description — and the title when the
scope changed — from the branch as it is now, keeps everything a person added, and applies it with
`gh pr edit`.
