#!/usr/bin/env bash
# PostToolUse hook: after a `git push` to a branch with an open PR, remind Claude to refresh the PR
# description. Never blocks the tool call and never edits the PR itself.

command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")

grep -qE '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)' <<<"$cmd" || exit 0

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

pr=$(gh pr view --json number,state --jq 'select(.state == "OPEN") | .number' 2>/dev/null) || exit 0
[ -n "$pr" ] || exit 0

jq -n --arg pr "$pr" '{
    hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: ("PR #" + $pr + " is open for this branch. Run the github:update-pr skill so its title and description match the pushed commits.")
    }
}'
