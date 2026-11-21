---
name: coding-style
description: >
  Use this skill whenever writing or changing PHP in a Laravel project — implementing a feature,
  fixing a bug, refactoring, or scaffolding a class, controller, job, command, listener, service,
  Action, Form Request or test. Also triggers when the user says "use DI", "no facades", "no
  helpers", "add strict types", "make it final", "write a test", "no Pest", or "follow our Laravel
  style". Covers `declare(strict_types=1)`, typed parameters, returns and properties, `final` and
  `readonly` classes (and how they combine with `dg/bypass-finals` and mocking), the order
  dependency injection > facades > helpers, PHPUnit instead of Pest, and a pre-finish sweep of the
  diff.
---

# Laravel coding style

## Scope

These rules govern the code **you write and the code you change**. They are not a mandate to rewrite
untouched code in a file you happen to open, and a style sweep never rides along with an unrelated
change. When you rewrite a method anyway, bring that method in line.

The baseline is the Specs Laravel template (`specsnl/specs-laravel-project`): strict types in every
file, PHPUnit with Mockery, and `dg/bypass-finals` registered as a PHPUnit extension.

## Strict types

- Every new PHP file starts with `declare(strict_types=1);`. Add it to an existing file you touch
  only when the project already uses it elsewhere — it changes how loosely typed calls behave at
  runtime.
- Every parameter and every return has a native type, including `void`, `never`, `static`, nullable
  and union types.
- Every property is typed. Use constructor property promotion where possible.
- Docblock types only for what native types cannot express: generics, array shapes, `list<…>`. The
  `code:code-comments` skill owns the rest of the docblock rules.

```php
<?php

class InvoiceCalculator                                   // ✗
{
    private $vat;

    public function total($lines)
    {
        // ...
    }
}
```

```php
<?php

declare(strict_types=1);

final readonly class InvoiceCalculator                    // ✓
{
    public function __construct(
        private VatRate $vat,
    ) {}

    /**
     * @param list<InvoiceLine> $lines
     */
    public function total(array $lines): Money
    {
        // ...
    }
}
```

## `final` and `readonly`

- Classes are `final` by default. The exception is a class meant to be extended (an abstract base).
- Make a class `readonly` (or its promoted properties) when every property is immutable: DTOs, value
  objects, Actions and services that only hold injected dependencies. Never on Eloquent models,
  Livewire components, Filament resources or pages, or other classes the framework hydrates or
  mutates.
- Test classes follow the project's existing tests; the template's test classes are not `final`.

### Mocking and `dg/bypass-finals`

Before deciding on `final`/`readonly` for a class that tests mock, check whether the project has
`dg/bypass-finals` in `composer.json` **and** its extension registered in `phpunit.xml`:

```xml
<extensions>
    <bootstrap class="DG\BypassFinals\PHPUnitExtension"/>
</extensions>
```

- **Present** — `final` and `readonly` stay, even on classes the tests mock with Mockery;
  bypass-finals strips both keywords at load time during the test run. Don't add workarounds such as
  interfaces that exist only for mocking.
- **Absent** — don't make a class `final` or `readonly` when tests mock or partial-mock it. Keep the
  default for everything else, and don't add the package as a side effect of another change.
- When a test fails with a "final" or "readonly" mocking error, first check that the extension is
  registered — requiring the package alone does nothing.

**Testability wins.** If mocking a class still fails because of `final`/`readonly` — bypass-finals
absent, not registered, or clashing — drop the keyword from **that class** so it can be tested.
Never keep the keyword at the cost of skipping, weakening or deleting a test. Every other class keeps
the `final` default.

## Dependency injection > facades > helpers

A strict order of preference:

1. **Inject.** Constructor injection for services and Actions; method injection wherever Laravel
   resolves the method — controller actions, `handle()` of jobs, commands and listeners, Form
   Requests in controllers.
2. **Facade**, only where injection is not possible.
3. **Helper**, only where neither works or no facade exists.

| Helper / facade          | Inject instead                                                                         |
|--------------------------|----------------------------------------------------------------------------------------|
| `request()`, `Request::` | `Illuminate\Http\Request $request`, or a Form Request                                  |
| `auth()`, `Auth::`       | `$request->user()`, or `Illuminate\Contracts\Auth\Guard`                               |
| `config()`, `Config::`   | `Illuminate\Contracts\Config\Repository`, or pass the value in from a service provider |
| `cache()`, `Cache::`     | `Illuminate\Contracts\Cache\Repository`                                                |
| `event()`, `Event::`     | `Illuminate\Contracts\Events\Dispatcher`                                               |
| `dispatch()`, `Bus::`    | `Illuminate\Contracts\Bus\Dispatcher`                                                  |
| `logger()`, `Log::`      | `Psr\Log\LoggerInterface`                                                              |
| `Http::`                 | `Illuminate\Http\Client\Factory`                                                       |
| `DB::`                   | `Illuminate\Database\ConnectionInterface`                                              |

```php
final class ExportController extends Controller                      // ✗
{
    public function store()
    {
        $user = auth()->user();
        Cache::forget("exports.{$user->id}");
        // ...
    }
}
```

```php
use Illuminate\Contracts\Cache\Repository as Cache;

final class ExportController extends Controller                      // ✓
{
    public function __construct(
        private readonly Cache $cache,
    ) {}

    public function store(StoreExportRequest $request): RedirectResponse
    {
        $user = $request->user();
        $this->cache->forget("exports.{$user->id}");
        // ...
    }
}
```

### Where injection is not possible: the facade

Blade views, route files, migrations, model internals (scopes, casts, accessors), static contexts and
tests (`Queue::fake()`, `Http::fake()`) use the facade, not the helper:

| Helper      | Facade              |
|-------------|---------------------|
| `auth()`    | `Auth::`            |
| `cache()`   | `Cache::`           |
| `config()`  | `Config::get()`     |
| `event()`   | `Event::dispatch()` |
| `logger()`  | `Log::`             |
| `now()`     | `Date::now()`       |
| `session()` | `Session::`         |

Time is always this fallback — there is no injectable clock — so write `Date::now()`, not `now()`
or `Carbon::now()`. Tests control it with `$this->travelTo()` / `$this->freezeTime()`.

```php
$expiresAt = now()->addDay();             // ✗
$expiresAt = Date::now()->addDay();       // ✓
```

### Where only a helper fits

Helpers without a practical facade stay: `__()` / `trans()`, `route()`, `asset()` and `url()` in
Blade, `env()` **only** inside `config/*.php`.

## Tests: PHPUnit, never Pest

- Write PHPUnit test classes. Never Pest syntax (`it()`, `test()`, `expect()`, `beforeEach()`),
  never add `pestphp/pest`, never convert existing tests to Pest.
- Unit tests extend `Tests\Unit\UnitTestCase`, feature tests `Tests\Feature\FeatureTestCase` (or
  the project's own base classes).
- `declare(strict_types=1)`, `public function testSomething(): void` method names — match the
  project if it uses `#[Test]` instead — and assertions via `self::assert…()`.
- Mockery for mocks; PHPUnit attributes (`#[DataProvider]`, `#[Group]`, …) instead of docblock
  annotations.
- A project that already uses Pest still gets PHPUnit classes for new tests (Pest runs them); say so
  in your response.

```php
it('marks the invoice as paid', function () {                        // ✗
    expect($invoice->markPaid()->isPaid())->toBeTrue();
});
```

```php
<?php

declare(strict_types=1);

namespace Tests\Unit\Invoices;

use Tests\Unit\UnitTestCase;

class InvoiceTest extends UnitTestCase                               // ✓
{
    public function testMarkPaidMarksTheInvoiceAsPaid(): void
    {
        $invoice = InvoiceFactory::unpaid();

        self::assertTrue($invoice->markPaid()->isPaid());
    }
}
```

## Conflicts with the project

Never stop to ask about a style conflict (see `code:autonomous-execution`,
`plugins/code/skills/autonomous-execution/SKILL.md`). When the project's own convention or its
Pint, PHPStan or Rector config contradicts a rule here: follow the project in existing files, these
rules in new files, and mention the deviation in your response.

## Before you finish

Sweep the diff (`git diff`) for:

- a new PHP file without `declare(strict_types=1)`;
- an untyped parameter, return or property;
- a new class that is not `final` without a reason (extended, or untestable otherwise);
- a facade or helper call in a class that could have injected the dependency;
- a helper where a facade exists, including `now()`;
- Pest syntax in a test.

Then run the project's checks with the `php:php-checks` skill.
