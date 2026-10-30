#!/bin/bash
# Bump the patch version in marketplace.json of every given plugin, unless the plugin is new or its version
# already changed compared to the base marketplace.json read from stdin.
#
# Usage: git show <base-commit>:.claude-plugin/marketplace.json | bump-versions.sh <plugin>...

set -e

MARKETPLACE_FILE=".claude-plugin/marketplace.json"

base_marketplace="$(cat)"

version() {
  jq --raw-output --arg n "$1" '.plugins[] | select(.name == $n) | .version'
}

for plugin in "$@"; do
  current="$(version "$plugin" < "$MARKETPLACE_FILE")"
  base="$(version "$plugin" <<< "$base_marketplace")"
  [ -n "$base" ] && [ "$current" = "$base" ] || continue

  IFS='.' read -r major minor patch <<< "$current"

  jq --indent 4 --arg n "$plugin" --arg v "$major.$minor.$((patch + 1))" \
    '(.plugins[] | select(.name == $n)).version = $v' \
    "$MARKETPLACE_FILE" > "$MARKETPLACE_FILE.tmp"

  mv "$MARKETPLACE_FILE.tmp" "$MARKETPLACE_FILE"
done
