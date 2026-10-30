---
name: linear-intake
description: |
    Use this skill to convert raw client input (email, WhatsApp, verbal, or a Linear issue URL) into a properly structured Linear issue in Specs style. Provide the raw text or a Linear issue URL and this skill will draft a developer-ready ticket with IST/SOLL structure, acceptance criteria, and QA steps.
---

# Linear Intake Skill — {{CLIENT_NAME}} ({{OUTPUT_TEAM}})

Converts raw {{INPUT_LANGUAGE}} client input (WhatsApp, email, verbal, or a Linear issue URL) into a properly structured Linear issue in {{OUTPUT_LANGUAGE}} for the **{{CLIENT_NAME}}** development team.

## Fixed context

- **Source team**: `{{INPUT_TEAM}}`
- **Destination team**: `{{OUTPUT_TEAM}}`
- **Language**: {{PRESERVED_TERMS_NOTE}}
- **Audience**: the developer reading the ticket should be able to start immediately

---

## Specs rules

### General rules

- Short and dense. No fluff, no preamble.
- Markdown. Use `code` for field/table/column/UI names. Use **bold** for key constraints.

### Feature request → IST/SOLL (small) or Current/Want (larger)

**Small change — IST/SOLL:**

```md
IST:
- [what exists now]

SOLL:
- [what should happen]

[1-2 sentences of context only if non-obvious]

## Acceptance criteria
- [ ] [specific, testable condition]
- [ ] [specific, testable condition]

## QA
- [how to verify the result — steps a tester should follow]
- [edge cases to check]
```

**Larger feature — structured sections:**

```md
## Current situation
- [what exists now]
- [relevant context]

## What we want
- [desired behavior]
- [scope or constraints]
  - sub-detail if needed

## Why / context
[1-2 sentences, skip if obvious]

## Acceptance criteria
- [ ] [specific, testable condition]
- [ ] [specific, testable condition]

## QA
- [how to verify the result — steps a tester should follow]
- [edge cases to check]
```

### Bug report

```md
[One-line summary of what's wrong]

Steps / context:
- [where to look or how to reproduce]
- [what happens]
- [what should happen instead]

## Acceptance criteria
- [ ] [condition that confirms the bug is fixed]

## QA
- [how to verify the fix]
- [regression checks if relevant]

## Screenshots
[attach any relevant screenshots here]
```

### Operational task (content, newsletter, images)

```md
[Short imperative title: "Prepare April newsletter for sending"]

Deliverables:
- [list attachments/content/actions]
- Deadline: [if mentioned]
```

*Operational tasks don't need acceptance criteria or QA sections.*

### Title format

- Verb-first, concise: `Add payment deadline to order confirmation email`
- Bugs: `Fix [thing] in [location]` or `[Thing] not working in [location]`
- No user story format ("Als gebruiker wil ik...")
- No ticket numbers in the title

### Priority

{{PRIORITY_TABLE}}

---

## Cross-team rules

These rules always apply, regardless of the source:

- **Never** edit or add a comment to the source issue
- **Always** add a `related to` relation in both the source issue and the new issue
- **Never** refer to the source issue in the text — do not mention it in the title, description, or body (including references like "see original ticket", "as mentioned in the source issue", or "screenshot from original")
- **Never** mention the source team code (`{{INPUT_TEAM}}`) in the title or description of the new issue
- **Always** copy screenshots from the source into a `## Screenshots` section at the bottom of the new issue
- **When unclear which project to pick**: pick the best match from the selection logic, otherwise the default project ({{DEFAULT_PROJECT}}), and name the choice in your reply — not in the issue. Only ask when someone can answer (see the `autonomous-execution` skill of the `code` plugin): list all available project options, with your pick as the recommended one

---

## Projects

Always assign to one of these {{OUTPUT_TEAM}} projects:

{{PROJECTS_TABLE}}

**Selection logic:**
{{SELECTION_LOGIC}}

---

## Workflow

1. **Identify the input:**
   - Raw text (WhatsApp, email, verbal) → proceed directly
   - Linear issue URL → fetch the issue content from team `{{INPUT_TEAM}}`; treat its content as raw input
2. **One or multiple issues?** Always create NEW issue(s) in team `{{OUTPUT_TEAM}}`. If the input covers multiple distinct topics or work areas, split into separate tickets.
3. Classify each issue: **feature**, **bug**, or **operational task**.
4. Draft the **title** ({{OUTPUT_LANGUAGE}}, verb-first).
5. Draft the **description** using the correct format above — including acceptance criteria and QA sections for features and bugs.
6. Infer **priority** from language signals.
7. Select the **project** (default: {{DEFAULT_PROJECT}}).
8. Create the new issue(s) in Linear under team `{{OUTPUT_TEAM}}` with the correct project.
9. Reply with all new issue URL(s), plus any choice you made on your own (project, priority, split into several issues).
10. Learn from this process and propose improvements to this skill if you spot them.

> **Always create NEW issues in `{{OUTPUT_TEAM}}`.** Never edit or comment on the source issue.

---

## Notes

- Never add Specs internal commentary to the Linear description.
- When input is ambiguous, pick the most likely interpretation and draft — don't over-ask.
- Default priority when uncertain: Normal (3).
- Default project when uncertain: {{DEFAULT_PROJECT}}.
