---
name: create-pr
description: >
  Use this skill whenever creating a pull request. Audits .github/workflows/
  to understand what CI will run, checks the PR title format requirement,
  runs CI checks locally (via ci-green-check where available), then creates
  the PR with the correct title and body. Always invoke this instead of
  running gh pr create directly.
---

# Create Pull Request

Audit the repository's PR configuration, verify CI is green, then open the PR.

---

## Phase 1 — Audit PR requirements

Read the repository's PR configuration before touching git.

### 1a. Read all workflow files

```bash
find .github/workflows -name "*.yml" -o -name "*.yaml" | sort
```

For each workflow file, identify:

- Jobs triggered by `pull_request` events
- Any title validation steps (e.g. `pr-title-checker`, `action-semantic-pull-request`)
- Required status checks that must pass

### 1b. Check PR title format

Look for `.github/pr-title-checker-config.json` and read it to extract the allowed prefix pattern.

If not found, check for a workflow step that enforces title format and read its config.

### 1c. Check branch rules

Read `.github/rulesets/*.json` if present. Note:

- Required merge method (Specs projects use merge commits only — no squash/rebase)
- Required status checks

### 1d. Summarise before proceeding

Report:

- What CI jobs will run on this PR
- Required title format / prefix
- Any merge restrictions

---

## Phase 2 — Run CI checks locally

Invoke the `ci-green-check` skill — it runs whatever checks are discovered in Phase 1 that can run
locally, and hands off to `php-checks` (from the `php` plugin) in PHP projects.

If a check fails, run `ci-green-check`'s fix loop first. Never weaken a check to get it green. When
checks still fail after that, continue with the PR as a **draft** (`gh pr create --draft`) and list
the failing checks with their errors in the body, under `## Decisions and skipped steps`. When a
draft PR isn't possible, skip the PR and report the failing checks instead (see the
`autonomous-execution` skill of the `code` plugin).

---

## Phase 3 — Ensure branch and commits are ready

- Check the working tree (`git status`). Uncommitted changes are not part of the PR: leave them
  untouched and mention them in the report, unless they belong to this work and should be committed
- Confirm not on `main`/`master`/`develop` — if so, create a branch first:

  ```bash
  git checkout -b kebab-case-description
  ```

  Use the Linear issue slug as the branch name if one was provided.
- Commit messages lead with a **single subject line**. A body is allowed when it
  adds context the subject can't carry, but keep it succinct — a few lines at most.
- Never add a `Co-Authored-By` trailer or mention Claude in any commit message.

---

## Phase 4 — Create the PR

```bash
git push -u origin HEAD
gh pr create --title "PREFIX: short description" --body "$(cat <<'EOF'
## Summary
- ...
EOF
)"
```

### Title rules

- Match the format discovered in Phase 1
- If a Linear issue number was provided: `PREFIX-543: description`
- If no issue number is available: fall back to `000` as the issue number, e.g. `PREFIX-000: description`.
  This is the standard fallback — do **not** ask the user for an issue number when one wasn't provided.
  Derive `PREFIX` from the title-checker config pattern, or from the prefix used by existing branches/PRs.
- Never omit the colon and space after the prefix

### Body rules

- Keep it short — a few bullets, no paragraphs
- `## Summary`: 2–4 short bullets of what changed
- Never mention Claude, AI, or that the work was done in a Claude session
- When the run made decisions or skipped steps, add a `## Decisions and skipped steps` section listing
  them

After creating: output the PR URL and the list of CI jobs that will run on it (from Phase 1).
