# Laravel plugin

All Specs Laravel related skills, instructions, commands/prompts are located in this plugin.

## Installation

Claude: `claude plugin install laravel@specs`

The PHP-generic `update-project` command and the `executing-commands` and `php-checks` skills live in
the [`php@specs`](../php/README.md) plugin (`claude plugin install php@specs`).

## Skills

**fix-translations**:  
Find, fix, or translate source-language values in the Laravel translation files (`lang/{locale}/*.php`
and `lang/{locale}.json`). Scans them for untranslated values, translates them to the target
language, fixes errors and typos, commits the changes, and opens a PR — preserving `|` plural
syntax, `:placeholder` tokens, Blade fragments, and array/JSON keys.

**coding-style**:  
The Specs Laravel coding style for writing or changing PHP: `declare(strict_types=1)`, typed
parameters, returns and properties, `final`/`readonly` classes (with `dg/bypass-finals` for mocking,
and testability over the keyword), dependency injection over facades over helpers, and PHPUnit
instead of Pest. Ends with a sweep of the diff before finishing.

**e2e-filament-multitenant**:  
Write, expand, or structure Playwright end-to-end tests for a Laravel + Filament
(Spatie-permission) application, especially multi-tenant apps with several panels/roles. Covers the
per-role storageState auth model, shared helpers, a per-role coverage matrix (CRUD / state-machine
workflows / permission boundaries / tenant isolation), a deterministic test-data strategy, the CI
job recipe, and Filament-specific selector conventions.
