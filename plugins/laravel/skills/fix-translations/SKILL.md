---
name: fix-translations
description: |
    Use this skill to find, fix, or translate source-language values in the Laravel translation files of a project — the PHP arrays under `lang/<locale>/` and the JSON catalogues `lang/<locale>.json`. Scans them for untranslated values, translates them to the target language, fixes errors and typos, commits the changes, and opens a PR. Laravel-specific: it preserves `|` plural syntax, `:placeholder` tokens and Blade fragments, and never translates array keys or JSON source keys.
---

# Fix {{TARGET_LANGUAGE}} Laravel Translations — {{REPOSITORY}}

Scan all {{TARGET_LANGUAGE}} Laravel translation files for values still in the source language,
translate them, fix errors and typos, commit the changes, and open a PR.

## Fixed context

- **Repository**: `{{REPOSITORY}}`
- **Translation files**: {{TRANSLATION_FILES_INLINE}}
  — when not specified, default to Laravel's conventional locations:
  `lang/{{TARGET_LOCALE}}/**/*.php` and `lang/{{TARGET_LOCALE}}.json`
  (older projects: `resources/lang/...`)
- **PR title format**: `{{PR_TITLE_PREFIX}}: <short description>`

---

## Workflow

Execute these phases in order. Never dead-end (see the `autonomous-execution` skill of the `code`
plugin): a value whose translation stays unclear after using its context is left as it is and listed
in the PR body, and the rest of the work carries on.

### Phase 1 — Scan for untranslated values

Read every file matching {{TRANSLATION_FILES_SCAN}} — when that is not supplied, scan
`lang/{{TARGET_LOCALE}}/**/*.php` and `lang/{{TARGET_LOCALE}}.json` (fall back to
`resources/lang/...` on older Laravel versions). For each file, identify values that are still in
the source language. A value needs translation if it:

- Uses source-language words as the primary language (e.g. "Save", "Cancel", "Overview")
- Contains a full source-language sentence or phrase
- Is a mix of {{TARGET_LANGUAGE}} and the source language
- Contains a typo that is clearly not {{TARGET_LANGUAGE}}

Do **not** flag:

- Keys (array keys are in the source language by convention). In JSON catalogues the key *is* the
  source string — translate the value, leave the key byte-for-byte untouched.
- Technical/universal strings like email addresses, URLs, currency symbols
- Values that are intentionally the same in both languages (e.g. `'Logo'`, `'URL'`)
- Placeholder variables like `:count`, `:name`

### Phase 2 — Translate and fix

For each identified value, produce the correct {{TARGET_LANGUAGE}} translation. Apply these rules:

- Translate naturally — not word-for-word. Use the tone of the surrounding context.
- {{FORMALITY_NOTE}}
- Plural forms using Laravel's `|` syntax must be preserved: `'{\1'}in :count day|[2,*]in :count days'` → translate each segment, keep the `|` syntax intact.
- Never rename or translate `:placeholder` tokens (`:count`, `:name`, `:Name`, `:NAME`) — the casing
  carries Laravel's capitalisation behaviour, so copy them through verbatim.
- Leave Blade and HTML fragments inside a value alone (`{{ $var }}`, `@lang(...)`, `<a href="...">`)
  — translate only the surrounding prose.
- Fix typos
- Fix wrong translations
- Fix mixed-language values

Edit each file directly using precise string replacements. Do not reformat or reorder any surrounding code.

### Phase 3 — Commit

Stage all modified translation files by name (never `git add -A`). Commit with a **single subject line**:

```text
Translate remaining source-language strings in {{TARGET_LANGUAGE}} translation files
```

### Phase 4 — Create PR

Invoke the `create-pr` skill to push the branch and open the PR. It runs `ci-green-check`, which
hands off to `php-checks` (from the `php` plugin) for this project's PHP tooling — translation files are checked by
`composer:script:checkstyle` (phpcs) too, so let that run rather than skipping it.

Provide the following title and body:

**PR title** (required — CI will fail without it):

```text
{{PR_TITLE_PREFIX}}: Translate remaining source-language strings in {{TARGET_LANGUAGE}} translation files
```

- If the user provided a Linear issue number, use it: e.g. `{{PR_TITLE_EXAMPLE}}`
- If no issue number was provided, use: `{{PR_TITLE_PREFIX_ZERO}}`

**PR body**:

```md
## Summary
- Translated remaining source-language strings in {{TARGET_LANGUAGE}} translation files

## Test plan
- [ ] Verify translations look correct in the UI
```

---

## Rules

- **Never use `git add -A` or `git add .`** — stage only the translation files that were actually modified.
- **Never skip the colon in the PR title** — the format is `{{PR_TITLE_PREFIX}}:` (with colon and space).
- **Do not reformat files** — only change the specific string values that need translating.
- **Do not translate keys** — only values (right-hand side of `=>`) are ever changed.
- **Verify each translation** — if a value's correct translation is unclear, use surrounding context (file name, key name, neighbouring keys) to infer intent before translating.
