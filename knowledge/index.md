---
type: index
title: Platform facts behind omarchy-discord
description: Machine-readable index of the measured facts this plugin depends on
tags: [omarchy, discord, quickshell]
---

# Knowledge bundle

An [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
bundle. One file per fact, each carrying YAML frontmatter with a `type`.

Every fact here was measured on a running machine, Omarchy 4.0.0 with the Arch
`discord` package, rather than inferred from documentation. Where a fact was not
observable, the file says so in its own words instead of guessing. `log.md`
records what changed and when.

| Fact | Why it matters |
|---|---|
| [discord-window-identity](discord-window-identity.md) | how the plugin recognises Discord's window and desktop entry |
| [discord-pipewire-streams](discord-pipewire-streams.md) | PipeWire does not name the app "Discord", so matching keys off the process binary |
| [discord-rpc-access](discord-rpc-access.md) | why the voice tier is opt-in and cannot ship a client id |
| [discord-rpc-protocol](discord-rpc-protocol.md) | the frame shape and the three calls that fail in non-obvious ways |
| [discord-tray-item](discord-tray-item.md) | the duplicate tray icon, and why the fix is one manual step |
| [qt-svg-arc-flags](qt-svg-arc-flags.md) | why the shipped icon path has no arcs left in it |
| [omarchy-bar-icon-weight](omarchy-bar-icon-weight.md) | matching a bar icon to its neighbours is about ink, not height |
