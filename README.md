# specsnl/agent-skills

Specs's Claude Code (marketplace) plugins.

## Installation instructions

Claude: `claude plugin marketplace add specsnl/agent-skills`

The marketplace namespace is `specs`. So after adding this marketplace you will be able to install specific plugins using:

- `claude plugin install <plugin>@specs`.

## Plugins

| Plugin Name        | Description                                                                                                    |
|--------------------|----------------------------------------------------------------------------------------------------------------|
| laravel@specs      | A Specs Laravel specific plugin                                                                                |
| docker@specs       | A Specs Docker specific plugin                                                                                 |
| linear@specs       | A Specs plugin for creating Linear issues from raw client input                                                |
| code@specs         | A Specs plugin with cross-language code authoring conventions                                                  |
| github@specs       | A GitHub-specific plugin for Specs                                                                             |
| git-workflow@specs | Atomic-commit Git workflow skills: amend/fixup, conflict resolution, reflog undo, bisect debugging             |
| gh-stack@specs     | Manages stacked PRs and splits multi-part work into reviewable branches with the gh-stack GitHub CLI extension |

## Recommended tools

- **[crit](https://crit.md)** (`crit@specs`) — Review and comment on plans, code diffs, and frontend elements, then send feedback directly to your agent. Requires the `crit` CLI binary to be installed separately:
  - macOS: `brew install crit`
  - See [crit.md](https://crit.md) for other installation methods (Go, Nix, Windows).
- **[gh-stack](https://github.com/github/gh-stack)** (`gh-stack@specs`) — The skill drives the `gh stack` GitHub CLI extension, so both the CLI and the extension must be installed separately:
  - macOS: `brew install gh` — see [cli.github.com](https://cli.github.com/) for other platforms
  - `gh auth login` (once, if you haven't already)
  - `gh extension install github/gh-stack`

## Tasks

Check out the complete list using `task --list`.
