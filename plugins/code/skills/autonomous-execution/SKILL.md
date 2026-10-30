---
name: autonomous-execution
description: >
  Use this skill whenever a skill or command would stop, abort, wait for confirmation or ask the user —
  a dirty working tree, an existing branch, a failing step, an ambiguous requirement, a missing tool or
  credential — and in every headless, CI, scheduled or background run. It defines the shared "never
  dead-end" convention: resolve the situation safely or skip only the affected part, carry on with the
  rest, ask only when someone can answer, respect the hard limits (never destroy others' work, never
  weaken checks, never publish secrets), record every decision in the result, and file a sanitized
  "skill gap" issue for situations a skill doesn't cover yet.
---

# Autonomous execution — never dead-end

Skills and commands can run without anyone to answer: a scheduled routine, a CI job, a background agent, a
headless `claude -p` run. Stopping is therefore **not a valid end state**. A run always ends with a result — a
commit, a PR, a report — plus a list of the decisions it made, the parts it skipped and the issues it filed.

## Resolution order

When a skill or command hits a situation that would stop it, resolve it in this order:

1. **An explicit rule in the skill** for this situation.
2. **A safe, non-destructive workaround** (see [Workarounds to prefer](#workarounds-to-prefer)).
3. **Skip the affected part** and continue with the rest of the work.
4. **File a skill-gap issue** when the skill didn't describe the situation (see [Skill-gap issues](#skill-gap-issues)).

Steps 2–3 never break the [hard limits](#hard-limits). Every step taken is recorded in the result.

## Ask only when someone can answer

A skill may ask a question only when it can be determined reliably that a person can answer it directly: an
interactive session with a question tool available. Treat the run as **autonomous** when it is headless
(`claude -p`), in CI (`CI` or `GITHUB_ACTIONS` is set), scheduled or in the background, or when it can't be
determined.

- Every question point has an autonomous default written next to it. When asking, offer that default as the
  recommended option.
- Without an answer, follow the default and carry on. Never wait.

## Hard limits

These still apply, whatever the situation:

- Never destroy or overwrite work you didn't create: no `reset --hard` on someone's changes, no stash pops, no
  force pushes, no deleting branches that have unique commits.
- Never weaken checks to get green: no baselines, no `@phpstan-ignore` / `@psalm-suppress`, no skipped tests, no
  weakened assertions.
- Never publish secrets.

When the only way forward would break one of these, skip the affected part.

## Workarounds to prefer

- **Dirty working tree or the wrong branch:** work in a fresh `git worktree` from the source branch
  (`git worktree add -b <branch> <path> origin/<default>`) instead of aborting. The user's checkout stays
  untouched. Remove the worktree when the run is done with it.
- **The branch already exists** (locally or on the remote) with commits of its own: leave it untouched and use a
  suffixed name, e.g. `<branch>-<YYYY-MM-DD>`. Reuse the existing branch only when it has no unique commits.
- **A choice between sources:** take the safe default, e.g. `origin/<default>` over a local `<default>` that is
  behind, ahead or diverged.
- **A failing step in a multi-step run:** isolate it — don't commit (or revert) its changes, continue with the
  next step, and record it.

## Classifying a stop

Use this when writing or updating a skill or command, and when a run meets a stop the skill doesn't cover:

| Class                     | Meaning                                                                                                         | What to do with it                                                                    |
|---------------------------|-----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| **Resolvable**            | There is a safe, non-destructive way to continue                                                                | Replace the stop with that resolution, written out explicitly                         |
| **Guardrail**             | The stop protects something: uncommitted work, unique commits, check integrity (no baselines, no skipped tests) | Keep the prohibition; skip this part, continue with the rest, record it in the result |
| **Intentional end state** | A deliberate scope boundary (e.g. `implement-issue` stops before opening a PR)                                  | Keep it, and end with a complete report rather than a question                        |
| **Unknown**               | No obvious safe resolution                                                                                      | Safe default (skip + record) **and** file a skill-gap issue                           |

## Where decisions go

Into whatever the run produces:

- a PR body: a `## Decisions and skipped steps` section,
- a report file, or
- the final summary.

List each decision (and why), each skipped part (and why), and each skill-gap issue filed or drafted.

## Skill-gap issues

A skill gap is a situation a skill or command didn't describe a solution for. Filing it lets the skill be updated
with an explicit rule, so the next run doesn't meet the same gap.

**Where:** the repository of the marketplace that ships the skill — `specsnl/agent-skills` for the `specs`
plugins. A project can redirect or turn this off in its own instructions (`CLAUDE.md` / `AGENTS.md`), e.g.
"skill gaps: `<owner>/<repo>`" or "skill gaps: off"; follow that.

**How:**

1. Search the open issues with the label first:
   `gh issue list --repo specsnl/agent-skills --label skill-gap --state open --search "<scenario keywords>"`.
   When the scenario was already reported, add a comment with the new occurrence instead of opening a duplicate.
2. Otherwise open an issue with the `skill-gap` label. Create the label when it doesn't exist yet
   (`gh label create skill-gap --repo specsnl/agent-skills --description "A situation a skill doesn't cover yet"`).
3. Title: `Skill gap: <plugin>:<skill-or-command> — <scenario>`.
4. Body:
    - the skill or command, and the plugin version when known,
    - the step where it happened,
    - the scenario, in generic terms,
    - what the agent did instead,
    - a suggested rule to add to the skill.

**This repository is public.** Sanitize every gap: no client or project names, no code from the project, no
internal URLs, no hostnames, no credentials. Describe only the scenario in generic terms (e.g. "the project's
Compose file defines no PHP service" rather than naming the project or pasting the file).

**Can't file it** (no `gh` authentication, no GitHub MCP)? Include the drafted gap — title and body — in the
run's result, so a human can file it.
