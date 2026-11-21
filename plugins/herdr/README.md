# Herdr plugin

Skills for working inside [Herdr](https://herdr.dev), the desktop app for terminals and coding agents, and
its terminal runtime herdr-core (`hc`).

## Installation

Claude: `claude plugin install herdr@specs`

Requires the Herdr app and herdr-core to be installed separately (see [herdr.dev](https://herdr.dev)).

## Skills

**herdr**:  
Drive Herdr from an agent session: show things in the window (spaces, tabs, panes, agent focus) with
`herdr-app`, start and coordinate long-lived terminals and agents with `hc` (background runs, send, read,
wait, clean up, other machines), and customise the app through `~/.config/herdr-app` (layouts, keys,
settings, themes, mods). Herdr's manuals change with every release, so the skill loads the version-matched
one first (`herdr-app --skill`, `hc --skill` or `~/.config/herdr-app/AGENTS.md`) and keeps only the rules
that protect the user's running work: inspect before acting, only show what was asked for, never restart
the user's app or core, clean up only your own terminals, and check every file and mod change.
