---
name: project-health-check
description: >
    Analyse the dependency health of a PHP project without changing it: security audits, available minor and patch
    updates, a deep analysis of major upgrades (version path, usage, blockers, replacements) and dependency
    reduction, for both Composer and the Node packages. Writes a Markdown report.
---

# Goal

Give a complete picture of a PHP project's dependencies — what is vulnerable, what is outdated, what a major upgrade
would take, and which dependencies can go — **without changing the project**. It is the deep dive behind the short
audit overview at the end of `/php:update-project` (Phase 10). The two stay separate: this command never runs an
update, and `update-project` never repeats this analysis.

Every phase covers **both** ecosystems: Composer and the Node packages (when there is a `package.json`).

## Ground rules

- **Read-only.** No branch, no commits, and no edits to `composer.json`, `composer.lock`, `package.json` or any Node
  lock file. Never run `composer require` / `update` / `remove` or `<pm> add` / `update` / `remove` in the project,
  except for the dry-runs named below. The report file is the only file this command writes.
- **Installing from the lock files is allowed** (`vendor/`, `node_modules/`): it only restores the locked state. See
  Phase 0 for a library without a `composer.lock`.
- **Guard the manifests.** Before Phase 0, copy `composer.json`, `composer.lock`, `package.json` and the Node lock file
  to a scratch directory outside the project (`mktemp -d`). After every command that resolves dependencies, compare
  them with the copies. If one changed, restore it from the copy (which holds the user's uncommitted edits too) and
  record which command changed it.
- **Commands.** Invoke the `executing-commands` skill before running any project command, and run every command
  through its tiers: a project task first, then the containers, the host only as a last resort. The analysis tools of
  Phase 4 run through the docker tiers too, without being added to the project.
- **Node package manager.** Detect `<pm>` (npm, pnpm or yarn) as described in the "Node package manager" section of
  `executing-commands`, and use its column of the command map. A Bun project skips the Node parts and says so in the
  report.
- **Never dead-end.** Follow the `autonomous-execution` skill of the `code` plugin. A check that can't run (no
  network, missing credentials for a private repository, a tool that fails) is skipped: continue with the rest, and
  list it — with the error — under "Decisions and skipped checks" in the report. A situation this command doesn't
  describe is handled the same way, plus a skill-gap issue.

## Phase 0 --- Preparation

A clean working tree is not required: nothing is committed.

1. **Project detection.** Run steps 1–4 and 7 of the `update-project` Phase 0 ("Project Detection", in
   `update-project.md` next to this file): Specs project or not, framework, library or application, frontend and
   `<pm>`, and the Taskfile.
2. **Lock file sync.** Warn when a lock file is out of sync with its manifest, and continue with the lock file as it
   is:
    - Composer: `composer validate --no-check-publish` reports "The lock file is not up to date".
    - Node: the frozen install of step 3 fails on an out-of-sync lock file. Without an install, compare the direct
      dependencies of `package.json` with the lock file.
3. **Installed dependencies.** The Composer commands below use `--locked`, so they don't need `vendor/`. A library
   without any `composer.lock` (not even an untracked one) gets one from `composer install`: like `vendor/`, it is
   untracked state. Delete it at the end when this run created it, and note in the report that the library's versions
   are the latest its constraints allow today. When `node_modules/` is missing, run `<pm>`'s frozen install (`<pm>`'s "install (CI, frozen)" in `executing-commands`).
   When that fails, compare against the registry instead (see Phase 2) and record it.
4. **Record the platform:**
    - **PHP:** `config.platform.php` and `require.php` of `composer.json`, and the runtime PHP of the image or container
      the commands run in (`php --version` through `executing-commands`). Note when they disagree.
    - **Node:** `engines.node`, `.nvmrc` / `.node-version`, and the runtime `node --version`. Note `<pm>` and its
      version (`packageManager`).
    - **Framework:** `laravel/framework`, `symfony/framework-bundle` (or the `symfony/*` packages) and their locked
      versions; the main frontend framework (`vue`, `react`, `svelte`, …) and build tool (`vite`, `webpack`, …).

Summarize these findings in the conversation and continue; don't wait for a reply.

## Phase 1 --- Security Audits

1. **Composer:** `composer audit --locked --abandoned=report` (`task composer:cmd:audit -- --locked --abandoned=report`
   in Specs projects). Add `--format=json` when the output needs parsing. This also lists abandoned packages.
2. **Node:** `<pm>`'s audit from the command map (`npm audit`, `pnpm audit`, `yarn audit`, or
   `yarn npm audit --all --recursive` for yarn berry). Add `--json` when the output needs parsing.
3. Summarize the findings **by severity**. For each one, record:
    - the package, the advisory (ID and title) and the affected range,
    - whether it is a **direct** or a **transitive** dependency (`composer why <package> --locked`; `npm explain`,
      `pnpm why`, `yarn why`), and through which direct dependency it comes in,
    - whether a fixed version exists **inside the current constraints**. If it does, the fix is "run
      `/php:update-project`". If not, the fix is a constraint change or a major upgrade: add the package (or the
      direct dependency that pins it) to the Phase 3 candidates with the "security" priority.

Composer 2.9+ refuses to install versions with known advisories by default (`policy.advisories.block`). When a
resolution in a later phase fails on an advisory, that is a security finding too, not a tool failure.

## Phase 2 --- Minor and Patch Updates

List what is available within the current major. The recommendation for all of them is the same — "run
`/php:update-project`" — so there is no per-package analysis here.

1. **Composer:** `composer outdated --locked --direct --minor-only` (minor and patch updates).
2. **Node:** `<pm>`'s outdated (`npm outdated --json`, `pnpm outdated --format json`, `yarn outdated --json`) for the
   direct dependencies. Keep only the updates within the current major; the others go to Phase 3. Note the packages
   whose constraint excludes the newer minor (an exact pin or `~`), because `update-project` won't pick those up.
   - **Yarn berry** has no non-interactive `outdated`. Compare each direct dependency's locked version
     (`yarn info <pkg> --json`, or the lock file) with the registry: `npm view <pkg> versions --json` and
     `npm view <pkg> dist-tags.latest`. Use the same registry comparison whenever `<pm>`'s outdated can't run.

## Phase 3 --- Major Updates

This is the deep analysis. It reads code and changelogs, so it is the slow part of the run.

### Collect the candidates

- **Composer:** `composer outdated --locked --direct --major-only`.
- **Node:** the direct dependencies from Phase 2 (or the registry comparison) whose latest version is a new major.
- Add the candidates Phase 1 found (a vulnerability without a fix inside the current constraints).

### Select (soft limit: 10 per run)

Analyse at most **10 major version bumps per run**, counted across Composer and Node together. A few over the limit
is fine: with 11 or 12 candidates, analyse them all. With many more, select the 10 most important:

1. security-related (Phase 1),
2. packages that block other upgrades (a quick `composer why-not` / peer-dependency check is enough to rank them),
3. by usage footprint (the number of files that use the package).

A group (see below) counts as **one** bump only when its packages really must move together.

Only when someone can answer (see `autonomous-execution`), show the full candidate list and ask which packages or
groups to analyse, with this selection as the recommended option. Without an answer, use the selection. The report
lists every candidate that wasn't analysed under "Not analysed" — current → latest, and the number of majors in
between — so a follow-up run can pick them up.

### Group related majors

Suggest upgrading related packages together:

- packages of the same family that release together (e.g. `symfony/*`, `phpunit/phpunit` + `brianium/paratest`,
  `@vitejs/*` + `vite`, `eslint` + its plugins and configs),
- packages that block each other (found in step 3 below),
- packages that need the same PHP or Node version bump.

Order the groups so that each one unblocks the next (e.g. the PHP or Node bump first, then the group that needed it).

### Analyse each package or group

1. **Version path.** List every major between the current and the latest version (e.g. `2.x → 3.x → 4.x`). For each
   hop, read the upgrade guide (`UPGRADE*.md`), the CHANGELOG or the GitHub release notes (`gh release view` /
   `gh api repos/<owner>/<repo>/releases`; Packagist and the npm registry name the source repository). Decide whether
   the hops must be **phased** — e.g. major N introduces a deprecation layer that N+1 removes, so the code has to move
   off the deprecated API while still on N — or whether a direct jump is safe. Propose the phases with a rough effort
   estimate per hop (small: config or a few call sites; medium: a codemod plus manual fixes; large: an API redesign
   across many files).
2. **Usage footprint.** Search the tracked code (`git ls-files`, so `vendor/` and `node_modules/` are skipped):
    - **PHP:** imported namespaces and classes (`use Vendor\Package\…`), config files (`config/*.php`), service
      providers and bundles, facade and helper calls.
    - **Node:** `import` / `require` statements, the Vite / PostCSS / ESLint / TypeScript config, and the scripts in
      `package.json`.

    Count the files and call sites. Map the documented breaking changes to the call sites they actually affect, and
    note the ones that don't affect this project. Note where a codemod exists for the jump: Rector rule sets for PHP
    (`rector/rector`'s and the framework's sets), official codemods for JS.
3. **Compatibility with the rest of the tree.**
    - **Composer:**
        - `composer why-not --locked <package> <target-version>` lists the installed packages that block the target.
          The first line (`__root__ - requires …`) is the project's own constraint; the blockers are the lines after
          it.
        - Check the PHP requirement of the target (`composer show <package> <target-version> --available`, the `php`
          entry of its `requires`) against the platform from Phase 0. When it needs a newer PHP,
          `composer why-not --locked php <required-php>` lists the packages that keep the project on the current PHP.
        - Confirm the resolution without writing anything:
          `composer require <package>:^<N> --dry-run --with-all-dependencies --no-scripts`. Add `--dev` for a
          `require-dev` package, and list every package of a group in one command. Composer reverts `composer.json`
          itself; the manifest guard checks it.
    - **Node:**
        - Check the target's `peerDependencies` and the peer dependencies other packages declare on it:
          `npm view <pkg>@<N> peerDependencies engines --json`, plus `npm explain <pkg>` / `npm ls <pkg>`,
          `pnpm why <pkg>` or `yarn why <pkg>` for the packages that depend on it.
        - Compare the target's `engines.node` with the project's Node version from Phase 0.
        - Confirm the resolution without writing to the project:

          | `<pm>`       | Where          | Command                                                | Peer conflicts show up as                                           |
          |--------------|----------------|--------------------------------------------------------|---------------------------------------------------------------------|
          | npm          | the project    | `npm install <pkg>@^<N> --dry-run`                     | `npm warn ERESOLVE overriding peer dependency` (the exit code is 0) |
          | pnpm         | a scratch copy | `pnpm add <pkg>@^<N> --lockfile-only --ignore-scripts` | unmet peer warnings; `pnpm peers check` on recent pnpm versions     |
          | yarn berry   | a scratch copy | `yarn add <pkg>@^<N> --mode=update-lockfile`           | `YN0060`; `yarn explain peer-requirements` marks them with `✘`      |
          | yarn classic | a scratch copy | `yarn add <pkg>@^<N> --ignore-scripts`                 | `warning … has incorrect peer dependency`                           |

          pnpm and yarn have no dry-run: these commands rewrite `package.json` and the lock file, so run them in a
          scratch copy outside the project, never in the project itself. The scratch copy holds `package.json`, the
          lock file and the package manager config (`.npmrc`, `.yarnrc.yml`, `.yarn/releases/`), and is removed
          afterwards. Never print the contents of `.npmrc` (it may hold registry tokens).
4. **Each blocker.**
    - Does a newer release of the blocker support the target? Then it moves along: record it as part of the phase or
      group.
    - If not, is the blocker abandoned or unmaintained? Check Packagist's `abandoned` flag (`composer audit
      --abandoned=report`, `composer show <package> --available`), npm's `deprecated` field
      (`npm view <pkg> deprecated`), the date of the last release, and whether there is an open issue or PR for
      support of the target. **Suggest a maintained replacement**: the one named in the abandonment or deprecation
      notice first, then a framework built-in, then a well-maintained alternative.
    - If there is no replacement, **measure its usage** (as in step 2) and assess whether it can be dropped or inlined.
5. **Recommendation** per package or group, with the reason:
    - **upgrade** — with the phased path,
    - **upgrade after the blockers** — naming them,
    - **replace** — with the suggested replacement,
    - **drop** — when it is unused or easily inlined,
    - **hold** — e.g. the target needs a PHP version the project can't move to yet.

### Framework and PHP majors

Don't analyse `laravel/framework`, the `symfony/*` framework packages or the `php` constraint in depth here. Record
the current and latest versions and the number of majors in between, then hand off:

- **Laravel:** to the `laravel:upgrade-laravel` skill when it is available; otherwise recommend a dedicated Laravel
  upgrade (one major at a time, following the official upgrade guide) in the next steps.
- **Symfony and PHP:** recommend a dedicated upgrade in the next steps.

Packages that only block because of the framework or PHP version join that hand-off ("moves with the Laravel
upgrade").

## Phase 4 --- Dependency Reduction

Fewer dependencies is better: dropping a dependency is always a valid option. Check at least the blockers and the
abandoned or deprecated packages from Phases 1 and 3; check every direct dependency when the run has the time. For
each, report:

- its **usage footprint** (as in Phase 3, step 2),
- whether it is **unused** (zero references). Optionally confirm this with a tool run through the docker tiers of
  `executing-commands`, without adding it to the project:
  - **PHP:** `shipmonk/composer-dependency-analyser` or `icanhazstring/composer-unused`, installed in a scratch
      directory inside the container (e.g. `composer --working-dir=/tmp/tools require --dev <tool>`, then run
      `/tmp/tools/vendor/bin/<tool>` from the project). Both need an installed `vendor/`: when there is none, skip
      the tool and rely on the search.
  - **Node:** `knip` or `depcheck` as a one-off binary (`npx`, `pnpm dlx` or `yarn dlx`, as in the command map).

    Tools miss dynamic usage (config strings, service container bindings, Blade or Twig templates, CLI scripts):
    confirm each "unused" result with a search before reporting it.
- whether it **duplicates a built-in** of the framework, native PHP or native JS / browser APIs. For example:
  `symfony/polyfill-php8x` when the platform PHP already provides those functions, helper or collection libraries next
  to Laravel, `lodash` helpers that have a native equivalent, `axios` where `fetch` is enough, `moment` where
  `Intl` / `Temporal` or a lighter library would do.

## Phase 5 --- Other Observations

Cheap extra checks. Each one is optional: skip it when it can't run, and say so.

- **End-of-life status** of PHP, the framework and Node, from the endoflife.date API (the source the
  `docker:php-images` skill uses): `https://endoflife.date/api/v1/products/<product>/` with `php`, `laravel`,
  `symfony` and `nodejs`. Report the active-support and security-support end dates of the versions in use.
- **Abandoned and deprecated packages** that weren't covered in Phase 3 or 4, including `ilyes512/*` packages that
  have a `specsnl/*` replacement (as in `update-project` Phase 4; `update-project` migrates them).
- **Staleness.** Report, without changing anything, what `update-project` would bump: Docker images (Phase 7),
  GitHub Actions and runner images (Phase 8). Use the detection and version rules of those phases in
  `update-project.md`; don't duplicate them here.
- **Dependabot coverage gaps:** the inventory of `update-project` Phase 9, step 2 and 3, reported only.

## Report

Write the report to `.ai/reports/project-health-check-<YYYY-MM-DD>.md` in the project root (add `-2`, `-3`, … when
the file already exists), **and** summarize it in the conversation. Don't commit the file; tell the user its path.
When `.ai/` isn't ignored by git, mention that too (adding it to `.gitignore` is up to the user).

Sections in priority order, each split into **Composer** and **Node** (leave out Node when there is no
`package.json`):

```md
# Project health check — <project> — <YYYY-MM-DD>

PHP <platform> (runtime <version>), <framework> <version>, Node <version>, <pm> <version>.

## 1. Security
### Composer
| Severity | Package | Advisory | Direct / via | Fixed within constraints | Fix |
### Node

## 2. Major upgrades
### Suggested groups and order
1. <group>: <packages> — <why together> — unblocks <next group>
### Composer
#### <package> <current> → <latest>
- Path: 2.x → 3.x → 4.x (phased: …), effort per hop
- Usage: <files> files, <call sites> call sites; affected breaking changes: …; codemods: …
- Blockers: … (moves along / abandoned → replace with … / no replacement, usage …)
- Recommendation: upgrade / upgrade after blockers / replace / drop / hold — <reason>
### Node
### Framework and PHP
### Not analysed
| Package | Current | Latest | Majors skipped |

## 3. Drop / replace candidates
### Composer
### Node

## 4. Minor and patch updates (→ `/php:update-project`)
### Composer
### Node

## 5. Other observations
EOL status, abandoned packages, staleness, Dependabot coverage, lock file sync, platform mismatches.

## Decisions and skipped checks

## Suggested next steps
- Run `/php:update-project` for the security fixes within constraints and the minor/patch updates.
- One suggested issue per upgrade group: title, scope, phased path, effort.
```

Leave out an empty section's table and write "Nothing found" instead. End with the "Suggested next steps": one
suggested issue per upgrade group (title, scope, phased path and effort). Only create those issues on GitHub or
Linear when the user asks for it.

## Final State

- The project is unchanged: no branch, no commits, and `composer.json`, `composer.lock`, `package.json` and the Node
  lock file are identical to the copies made at the start (`vendor/` and `node_modules/` may have been installed from
  the lock files). A `composer.lock` this run created for a library is deleted.
- The scratch directories are removed.
- The report file exists at the path given to the user, and the conversation has a summary of it: the security
  findings, the upgrade groups in their order, the drop/replace candidates, the skipped checks and the suggested next
  steps.
