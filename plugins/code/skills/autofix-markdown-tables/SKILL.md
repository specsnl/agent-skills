---
name: autofix-markdown-tables
description: >
  Use this skill to automatically fix misaligned markdown tables in .md files. Triggers after editing
  any markdown file that contains a table, before finishing documentation work, or when the user says
  "fix the tables", "align the markdown tables", or "format the markdown". Uses the project's own task
  (`md:fix-tables` in Specs projects) or markdown formatter (e.g. Prettier) when it has one, and
  otherwise runs markdown-table-formatter via Docker, so columns are properly padded and aligned. After
  running, always review the diff to confirm only formatting changed — no content should be altered.
---

# Auto-fix Markdown Tables

Automatically detect and fix misaligned markdown tables across all `.md` files in the project.

---

## Step 1: Run the formatter

Align the tables with `task md:fix-tables`, or the project's equivalent. Use the first of these that
the project has.

### Preferred — the project's own task

Specs projects ship a task for this. Check first:

```bash
task --list | grep -E 'md:(fix-tables|fixstyle)'
```

Projects with another task name for it (e.g. `lint:md:fix`, `docs:format`) use that one.

```bash
task md:fix-tables    # tables only
task md:fixstyle      # tables + markdownlint --fix
```

Use `md:fixstyle` when the project also lints markdown in CI (a `Markdown` workflow running
`markdownlint-cli2`) — aligning tables alone can still leave the linter red.

### The project's own markdown formatter

When the project formats markdown with another tool, use that tool instead, so two formatters don't
fight over the same tables. For example Prettier (a `prettier` dependency or a `.prettierrc*` config,
and markdown not excluded in `.prettierignore`) also aligns tables: run the project's format script
(e.g. `<pm> run format`) or `prettier --write` on the changed `.md` files. Look for it in the
`package.json` and composer scripts, `Makefile` targets and the CI workflows. Run it the way the
project runs its tools (in PHP projects: through the `executing-commands` skill of the `php` plugin).

### Fallback — no task and no formatter

```bash
docker run --rm --volume $(pwd):/app --workdir /app node:24.15.0-bookworm bash -c "shopt -s globstar && npx --yes markdown-table-formatter **/*.md"
```

This command:

- Mounts the current directory into a Node.js 24 container
- Uses `shopt -s globstar` to enable recursive `**` glob expansion in bash
- Runs `markdown-table-formatter` on every `.md` file found recursively
- Modifies files in-place — no output is written elsewhere

## Step 2: Review the changes

After the formatter runs, check what was changed:

```bash
git diff --stat
```

For a detailed view of the actual table changes:

```bash
git diff
```

Verify that only whitespace/padding inside table cells changed — no content, wording, or structure should be altered. If unexpected changes appear, investigate before proceeding.

## Step 3: Confirm

If the diff looks correct, the tables are properly aligned and the files are ready to commit. No further action is needed.
