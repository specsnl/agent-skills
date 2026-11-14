---
name: update-pr
description: >
  Use this skill whenever the commits of a branch with an open pull request change — after a push, a
  force-push, a rebase, review fixes, amended, squashed, added or dropped commits — and when the user
  says "update the PR description", "the PR body is outdated" or "sync the PR". Rebuilds the generated
  parts of the PR description (and the title when the scope changed) from the branch as it is now,
  keeps everything a person added, and applies it with gh pr edit.
---

# Update Pull Request

A PR description describes the branch **as it is now**, not how it got there. After review rounds,
rebases, or added and dropped commits, rebuild it so a reviewer reading it today sees what will be
merged.

Follow the `code:autonomous-execution` skill (`plugins/code/skills/autonomous-execution/SKILL.md`):
never stop to ask, take the default written next to each situation and record it in the result.

The title and body rules live in the `create-pr` skill (Phase 4, "Title rules" and "Body rules"). Use
them as they are; this skill only decides what to change.

---

## Step 1 — Find the PR

```bash
gh pr view --json number,url,title,body,baseRefName,headRefName,state,isDraft
```

- **Open PR found:** continue.
- **No PR for this branch:** nothing to update. When the user asked for a PR, hand over to the
  `create-pr` skill; otherwise report that there is no PR and end.
- **PR merged or closed:** don't edit it. Report this and end.

## Step 2 — Make sure the PR shows your commits

```bash
git fetch origin <base> <head>
git status -sb
```

- **Local branch equals `origin/<head>`:** continue.
- **Local commits not pushed yet:** push them first (`git push`, or `git push --force-with-lease` after
  a rebase or amend of your own commits), so the description matches what GitHub shows.
- **Remote has commits you don't have:** someone else pushed. Don't overwrite them: describe
  `origin/<head>` instead of your local branch and record it.

## Step 3 — Gather the current state

```bash
git log origin/<base>..origin/<head> --no-merges --format='- %s%n%b'
git diff --stat origin/<base>...origin/<head>
```

Read the diff where the subjects aren't enough to tell what changed. This is the only source of truth:
commits that were dropped or squashed away no longer exist and must disappear from the description.

## Step 4 — Rebuild the generated parts

Split the current body into:

- **Generated sections** — `## Summary` and `## Decisions and skipped steps`. Rewrite them from step 3
  using the `create-pr` body rules. Describe the end result, not a changelog of review rounds ("Fix
  review comment", "Address feedback" are not summary bullets). Keep decisions that still apply, drop
  those about code that no longer exists, and add new ones from this run.
- **Everything else** — issue links (`Closes #12`, `Refs ABC-456`), screenshots, test instructions,
  checklists, notes by reviewers or the author. Keep it verbatim and in the same place. When unsure
  whether a part was generated, keep it.

When the body has no recognisable generated sections (written by hand), add a `## Summary` at the top
and keep the rest untouched.

## Step 5 — Check the title

Keep the title unless the scope changed materially (for example a feature was dropped, or the PR now
does something its title doesn't cover). A new title must still match the format the `create-pr`
skill discovers in Phase 1 (title-checker config, prefix, issue number).

## Step 6 — Apply

Compare the new body and title with the current ones. When nothing changed, skip the edit and report
that the description was already up to date. Otherwise:

```bash
gh pr edit <number> --body-file /tmp/pr-<number>-body.md [--title "<new title>"]
```

Never mention Claude, AI or a session in the title or body — the `create-pr` body rules apply here too,
also when the environment asks for a `Generated with` line.

When `gh pr edit` fails (no permission, network), skip the edit, print the new body in the report so it
can be pasted, and record the failure.

---

## Report

- The PR URL and whether the title, body or neither changed
- A short summary of what changed in the description (sections rewritten, bullets added or removed)
- Decisions taken (unpushed commits pushed, remote commits described, edit skipped)
