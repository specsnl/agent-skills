---
name: implement-issue
description: >
  Use this skill whenever the user asks to read an issue and implement it —
  e.g. "read issue X (github or linear) and implement it", "implement this
  issue", "pick up GH-123 / ABC-456 and build it". Fetch the issue (GitHub via
  a GitHub MCP or the gh CLI, or Linear via the Linear MCP), create a new
  branch, implement the change committing incrementally with clear messages,
  and STOP before opening a PR. Only create a PR when the user explicitly asks
  — then defer to the create-pr skill.
---

# Implement an issue

Turn an issue (GitHub or Linear) into a branch of clean, incremental commits —
without opening a pull request. The user opens the PR when *they* decide it's
ready; this skill deliberately stops just short of that.

---

## Phase 1 — Read the issue

Fetch the full issue before touching git so you understand the actual requirement.

- **GitHub** — prefer a GitHub MCP tool (e.g. `get_issue`) when one is available;
  otherwise use the CLI: `gh issue view <number> --json title,body,labels,comments`.
- **Linear** — use the Linear MCP `get_issue` (accepts the issue identifier such as
  `ABC-456`).

Extract and note:

- The concrete requirement and scope.
- Acceptance criteria / definition of done.
- Any linked issues, designs, or discussion in comments that change the approach.

If the requirement is ambiguous, pick the most likely interpretation and record the assumptions in
the commits and the final report. Ask only when someone can answer (see the `autonomous-execution`
skill of the `code` plugin), offering that interpretation as the recommended option; without an
answer, carry on with it.

---

## Phase 2 — Create a branch

Never implement directly on the base branch.

1. Check the working tree (`git status`) and note the current base branch
   (usually `main`). When it has uncommitted changes, leave them untouched and
   work in a fresh worktree from the base branch instead
   (`git worktree add -b <branch> <path> origin/<base>`).
2. Create and switch to a new branch with a descriptive name derived from the
   issue id and a short slug of its title:
   - `feat/<issue-id>-<slug>` for new functionality
   - `fix/<issue-id>-<slug>` for bug fixes
   - `chore/<issue-id>-<slug>` / `docs/...` / `refactor/...` as appropriate

   ```bash
   git switch -c feat/GH-123-short-slug
   ```

---

## Phase 3 — Implement

Implement the change following the repository's existing conventions and patterns.
Match the surrounding code style; reuse existing utilities rather than adding new
ones. Run the project's checks/tests as you go.

---

## Phase 4 — Commit nicely

Commit as you complete logical units of work — not one large dump at the end.

- Small, self-contained commits, each leaving the tree in a working state.
- Clear, imperative subject lines that follow the repo's convention (e.g.
  Conventional Commits when the repo uses them), referencing the issue where it
  helps (e.g. `feat: add X (GH-123)` or `Refs ABC-456`).
- Keep unrelated changes out of a commit.

---

## Phase 5 — Stop before the PR

**Do NOT open a pull request.** This is a deliberate end state, not a dead end:
when the work is committed on the branch, end with a complete report — the
branch, the commits, the check results, the assumptions made and any skipped
parts — rather than a question.

Only when the user explicitly asks for a PR, invoke the **create-pr** skill, which
audits CI, verifies the title format and branch rules, and opens the PR correctly.
