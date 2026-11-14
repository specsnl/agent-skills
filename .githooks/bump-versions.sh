#!/bin/bash
# Bump the patch version in .claude-plugin/plugin.json of every given plugin, unless the plugin is new or its
# version already changed compared to the base plugin.json files read from stdin (concatenated, as a JSON stream).
#
# Usage: for p in <plugin>...; do git show <base-commit>:plugins/$p/.claude-plugin/plugin.json 2>/dev/null; done \
#          | bump-versions.sh <plugin>...

set -e

base_manifests="$(cat)"

for plugin in "$@"; do
  manifest="plugins/$plugin/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || continue

  current="$(jq --raw-output '.version // empty' "$manifest")"
  base="$(jq --raw-output --slurp --arg n "$plugin" '.[] | select(.name == $n) | .version // empty' <<< "$base_manifests")"
  [ -n "$base" ] && [ "$current" = "$base" ] || continue

  IFS='.' read -r major minor patch <<< "$current"

  jq --indent 4 --arg v "$major.$minor.$((patch + 1))" '.version = $v' "$manifest" > "$manifest.tmp"

  mv "$manifest.tmp" "$manifest"
done
