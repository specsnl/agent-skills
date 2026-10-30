---
name: e2e-filament-multitenant
description: >
  Use this skill to write, expand, or structure Playwright end-to-end tests for a
  Laravel + Filament (Spatie-permission) application, especially multi-tenant apps
  with several panels/roles. Triggers when the user says "add e2e tests", "cover all
  roles", "write Playwright tests for the panels", "test each role", "e2e coverage per
  role", or asks to set up Playwright against a Filament admin/tenant panel. It covers
  the per-role storageState auth model, shared helpers, a per-role coverage matrix
  (CRUD / state-machine workflows / permission boundaries / tenant isolation), a
  deterministic test-data strategy, the CI job recipe, and Filament-specific selector
  conventions. Use it before scaffolding e2e/ so the suite stays maintainable and the
  role/permission boundaries are actually asserted.
---

# E2E Testing — Laravel + Filament (multi-tenant, per-role)

Build a Playwright E2E suite that proves **each role can do what it should and cannot
do what it shouldn't**, across every Filament panel — including tenant isolation. Work
phase by phase; do not jump to writing specs before the discovery and infrastructure
phases are done.

---

## Phase 1 — Discover the app's shape

Before writing any test, map the surface from source (never guess labels):

1. **Panels & roles** — read `app/Providers/Filament/*PanelProvider.php` to list panels,
   their path prefixes, and whether they are tenant-scoped (`->tenant(...)`). Read the
   roles/permissions source of truth (e.g. `database/permissions.yaml` + the
   `RolesAndPermissionsSeeder`), and the seeders for the test users/workspaces.
2. **Login forms** — there are usually two shapes:
   - *Standard Filament login* (email + password) for the admin panel.
   - *Custom tenant login* (e.g. a workspace `Select` + email + password) for
     tenant-scoped panels. Read the custom `Login` page class to learn the exact field
     label and any post-auth membership check (and its error message).
3. **Resources & actions per panel** — for each role's resource list page and
   `ViewRecord`/`EditRecord` page, read `getHeaderActions()` and the resource's
   `canCreate()/canEdit()/canViewAny()` overrides. **Record the literal `->label()`
   strings, notification titles (`Notification::make()->title(...)`), form field labels,
   and the `->visible(fn () => $state->is(...))` guards.** These literals are the
   contract your assertions check.
4. **State machine** (if using `spatie/laravel-model-states`) — note the state order and
   which transition each action performs. **Watch for cross-role gates**: a single role
   often *cannot* drive the whole lifecycle because the next action is only visible in a
   state that a *different* role produces. Plan to test transitions in isolation, not as
   one long chain.

Summarize findings as a per-role table before proceeding.

---

## Phase 2 — Infrastructure (do this first, keep the pipeline green)

### 2a. Per-role auth via `storageState`

Use one Playwright `setup` project that logs each role in once and saves its session,
then one project per role that reuses it:

```ts
// playwright.config.ts (sketch)
projects: [
  { name: 'setup', testMatch: /auth\.setup\.ts/ },
  { name: 'admin', dependencies: ['setup'],
    use: { ...devices['Desktop Chrome'], storageState: 'e2e/.auth/admin.json' },
    testMatch: /admin\/.*\.spec\.ts/ },
  // ...one per role; roles sharing a panel (e.g. jobcoach vs super-jobcoach)
  // get separate projects pointing at the same spec glob and branch on
  // test.info().project.name
]
```

Config conventions worth adopting:
`forbidOnly: !!process.env.CI`, `retries: process.env.CI ? 2 : 1`,
`workers: process.env.CI ? 1 : undefined`, `fullyParallel: true`,
`use.viewport: { width: 1920, height: 1080 }`, `use.trace: 'on-first-retry'`,
`use.baseURL: process.env.APP_URL ?? 'http://localhost'`.

### 2b. Shared helpers (extract, don't inline)

Create `e2e/helpers/`:

- `auth.ts` — `loginStandard(page, url, email, pw)` and `loginTenant(page, url, email, pw, workspaceName)` (open the `Select`, `getByRole('option', { name })`). The `auth.setup.ts` imports these; spec files never reach into the setup file.
- `panels.ts` — `panelUrl(role, slug, path)` builders + the known workspace slugs.
- `filament.ts` — `clickHeaderAction(label)`, `confirmModal()` (scope to `getByRole('dialog')`), `submitActionForm(fields)`, `expectStateBadge(label)`, `expectActionAbsent(label)` (assert `toHaveCount(0)`), `expectForbidden()` (cross-tenant 403/redirect — confirm the app's actual behavior once and standardize).

### 2c. Folder layout

Split specs by **role**, then by **resource** within the role:

```text
e2e/
  helpers/{auth,panels,filament}.ts
  auth.setup.ts
  <role>/{<resource>,permissions-isolation}.spec.ts
```

### 2d. Deterministic test data

Most seeders only create users — **list pages pass while empty**, so smoke tests give
false confidence. Add a dedicated `E2eSeeder` (factory-built) that creates **one record
per pivotal state** so each workflow test gets a forward-only, single-consumer record
with a stable reference for deep-linking. Guard it behind an env/`--seeder` flag so it
doesn't pollute normal seeds. Three data buckets:

1. **read-only / list / negative / isolation** → seeded fixtures by stable reference.
2. **state-transition workflows** → a dedicated seeded record pre-placed in the required state.
3. **create / duplicate / destructive** → create-in-test with unique suffixes.

---

## Phase 3 — Coverage matrix per role

For **every role**, cover four categories. Add package scripts to `package.json`:
`test:e2e:install` (`playwright install --with-deps chromium`), `test:e2e`,
`test:e2e:ui`, `test:e2e:headed`, `test:e2e:debug`, `test:e2e:report`, `test:e2e:codegen`.

| Category                      | What to assert                                                                                                                                                                                                                                                     |
|-------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **HP** Happy-path CRUD        | Create/edit/view each resource the role may manage; assert the row/toast appears.                                                                                                                                                                                  |
| **WF** State workflows        | One isolated test per transition action — load a record already in the required state, click the action (handle confirm/form modals), assert the **exact notification title** + the new state badge. Required-comment forms ⇒ also assert empty submit is blocked. |
| **NEG** Permission boundaries | For things the role must NOT do, assert the nav item / create button / header action is **absent** (`toHaveCount(0)`), not merely hidden.                                                                                                                          |
| **ISO** Tenant isolation      | Deep-link to another tenant's URL and a record the role shouldn't see ⇒ assert 403/redirect. Plus: logging in with a workspace the user isn't a member of ⇒ assert the membership error.                                                                           |

Roles that share a panel but differ in scope (e.g. a "super" variant with `view-any`):
reuse the spec and branch extra assertions on `test.info().project.name`.

---

## Phase 4 — CI job

`<pm>` is the project's Node package manager (npm, pnpm or yarn), detected as described in the "Node
package manager" section of the `executing-commands` skill (`php` plugin). Never assume npm.

Specs projects run E2E through Docker and Task, against the real stack — not `artisan serve`. Add a
job to the existing CI workflow that mirrors `.taskfiles/Taskfile.e2e.yml`. The task names below are
the Specs template's; in other projects use their equivalents (see "Specs task names and project
equivalents" in `executing-commands`), and name the commands that actually ran in the workflow and
the report.

1. Install Task (`go-task/setup-task`), create `auth.json` from `COMPOSER_AUTH_JSON`, warm the package
   manager cache with `actions/setup-node` (its `cache:` must match the project's package manager:
   `npm`, `pnpm` or `yarn`; pnpm also needs `pnpm/action-setup` before it).
2. `task ci:up`, or the project's equivalent — the CI variant of `task up`: env files, `composer:install`, `<pm>:install`, compose
   up, `key:generate`, `storage:link`, wait for the DB, `db:migrate-fresh:local`, `<pm>:script:build`.
   Filament won't render without that asset build.
3. Seed the deterministic fixture:
   `task 'artisan:run:db:seed' -- --class='Database\Seeders\E2ETestSeeder'`.
4. `task e2e:docker:test` — runs `<pm> run test:e2e` inside the `e2e-playwright` compose service, so
   the browsers come from the image and need no `playwright install` step.
5. Upload `playwright-report/` with `if: always()`; upload traces on failure.

Locally (or with the project's equivalents): `task e2e:setup` once for host browsers, then `task e2e:test` (UI) or
`task e2e:test:headless`; `task e2e:docker:test` reproduces CI exactly.

Start with `--workers=1` for determinism; raise once the data strategy is proven parallel-safe.

---

## Selector & robustness conventions (Filament)

- Prefer `getByRole('link'|'button', { name })`, `getByLabel(...)`, `getByRole('heading', { name })`, `getByRole('option', { name })`. Avoid CSS/XPath and generated `wire:` ids.
- **Assert on the visible (localized) labels and notification titles** — they are the contract. Use route slugs only inside URL regexes.
- Scope modal interactions to `getByRole('dialog')`; for `requiresConfirmation()` actions click the confirm button inside it; for form-modal actions fill the labelled field then submit.
- Negative/absence assertions use `toHaveCount(0)`, never `not.toBeVisible()` on an element that never renders.
- Rely on Playwright web-first auto-waiting; **never** `waitForTimeout`.
- Each mutating test owns its data (seeded single-consumer record or create-in-test); read-only tests target stable seeded references.

---

## Done criteria

- Every role has HP + WF + NEG + ISO specs; all role projects green locally
  (`task e2e:test:headless`, or the project's equivalent) and in CI (`task e2e:docker:test`).
- No false-positive smoke tests against empty lists — workflow/boundary tests run
  against seeded data.
- The coverage matrix from Phase 3 is filled in for each role, with permission
  boundaries and tenant isolation explicitly asserted, not assumed.
