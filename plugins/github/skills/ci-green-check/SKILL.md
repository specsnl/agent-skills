---
name: ci-green-check
description: >
  Use this skill after every code change in a repository to discover and run all CI checks locally before finishing work. Triggers automatically after completing any code edit, bug fix, refactor, or feature implementation. Also triggers when the user says "run the checks", "make sure everything is green", "verify the build", or "are the tests passing?". This skill reads .github/workflows and the Taskfile to discover what checks exist, runs everything that can be run locally (tests, linters, static analysis), attempts to auto-fix any failures, and reports checks that require cloud/secrets so the user is aware. For PHP repositories it hands off the concrete commands to the `php-checks` skill from the `php` plugin. Never consider a task done until all locally runnable checks pass.
---

# CI Green Check

After every code change, discover and run all CI checks found in `.github/` and get them green
before finishing.

## Stack hand-off

This skill owns *discovery, ordering, the fix loop, and reporting*. The concrete commands depend on
the stack:

- **PHP** (a `composer.json` exists at the repo root) → invoke the `php-checks` skill from the `php`
  plugin for environment setup and the exact tool commands, then come back here for Steps 4–6.
- **Anything else** → derive the commands from the Taskfile and the workflow steps you discovered in
  Step 1, following the runner rules in Step 3.

---

## Step 1: Discover checks

### 1a. Check for a Taskfile first

```bash
ls Taskfile.yml Taskfile.yaml taskfile.yml taskfile.yaml 2>/dev/null
```

If a Taskfile exists, read it fully and extract:

- **Setup tasks**: anything that installs dependencies, prepares config, runs migrations, seeds —
  common names: `setup`, `install`, `init`, `bootstrap`
- **Check tasks**: anything that runs tests or linters — common names: `checkall` (the aggregate task
  in Specs projects), `test`, `lint`, `analyse`, `check`, `ci`
- **Utility tasks**: whatever else is useful during environment setup

List all discovered tasks with their description. **Prefer Task commands over raw tool invocations**
when an equivalent Task exists — they often handle the right flags and order automatically.

Check that `task` is installed:

```bash
task --version 2>/dev/null || echo "task not installed"
```

If a Taskfile exists but `task` is not installed, stop and ask the user to install it
(`brew install go-task/tap/go-task` on macOS) rather than running the underlying commands directly.
If there is no Taskfile, run the workflow's commands directly.

### 1b. Scan GitHub workflows

```bash
find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | head -20
```

For each workflow file found, read it and extract:

- **Test jobs**: unit tests, feature tests, integration tests
- **Static analysis**: type checkers and analysers
- **Code style**: formatters and style linters
- **Other linters**: anything else that gates the build
- **Skippable jobs**: jobs that use secrets, deploy steps, cloud runners (SonarCloud, Codecov
  uploads, etc.)

Cross-reference workflow steps against Taskfile tasks — if a workflow step runs `task test`, that
maps to the Task you already found.

Group everything into two lists:

1. ✅ **Runnable locally** — document the exact command to run (Task command preferred, raw command
   as fallback)
2. ⚠️ **Requires cloud/secrets** — note name and why it's skipped

---

## Step 2: Check environment

Before running, verify the environment is ready.

For PHP repos, the `php-checks` skill handles this — hand off now.

Otherwise: if a setup/install/init task was found in Step 1, run it — it likely handles dependency
installation and config setup.

```bash
task setup    # or: task install / task init / task bootstrap
```

If no setup task exists, install dependencies the way the workflow does (the workflow's setup steps
are the source of truth) and make sure any required config files exist.

---

## Step 3: Run checks in order

Run in this priority order — stop and fix before moving to the next group.

1. **Code style** — fastest, and usually auto-fixable. Note which files changed, continue.
2. **Static analysis** — if it fails → **Step 4 (Fix loop)**.
3. **Tests** — if they fail → **Step 4 (Fix loop)**.
4. **Other checks** — any remaining linters found in Step 1.

### Runner order

Always resolve a command in this order:

1. **Task (preferred):** `task <name>` — check `task --list` first
2. **Workflow command:** the exact command the workflow step runs
3. **Raw tool invocation:** only when neither of the above exists

---

## Step 4: Fix loop

When a check fails:

1. **Read the error output carefully** — identify the exact file, line, and type of failure.
2. **Classify the failure**:
   - Type error / wrong return type → fix the code
   - Missing import / undefined symbol → add the import or fix the namespace
   - Test assertion failed → fix the code logic (not the test, unless the test is clearly wrong)
   - Undefined variable / null safety → fix the code
   - Style issue that wasn't auto-fixed → fix manually
3. **Apply the fix** — edit the relevant file(s).
4. **Re-run only the failing check** to verify the fix.
5. **If the fix causes a new failure** elsewhere, fix that too.
6. Repeat until the check is green, then continue to the next check.

**Never "fix" a test by weakening its assertions** unless the test was testing the wrong thing and
you can explain why.

---

## Step 5: Report skipped checks

After all local checks pass, report checks that were skipped:

```text
⚠️  The following CI checks cannot be run locally and will be verified in CI:
- [job name]: requires secret `SONAR_TOKEN` (SonarCloud scan)
- [job name]: deploys to production (deploy step)
- [job name]: uploads coverage to Codecov
```

---

## Step 6: Done

When all locally runnable checks are green, confirm:

```text
✅ All local checks passed:
- [style tool]: clean (N files reformatted)
- [analysis tool]: no errors
- [test runner]: N tests, N assertions — all green

⚠️ N cloud-only checks skipped (see above).

Ready to commit / push.
```
