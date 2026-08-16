---
type: reference
title: Discord's own tray item, and why the plugin cannot hide it for you
description: Omarchy suppresses first-party duplicates through a hardcoded list under /usr/share that takes no plugin hook, so the shell's own hidden list is the supported route
tags: [omarchy, tray, sni]
status: stable
verified:
  - by: reading TrayModel.ownedByOmarchy and the shell.json schema; the item id itself was not observed live
    at: 2026-08-16
---

# The duplicate icon

Discord registers a StatusNotifierItem of its own, so a bar carrying this widget
shows two Discord icons.

Omarchy already solves this for its own plugins: `TrayModel.ownedByOmarchy`
hides Dropbox's tray item when the Dropbox widget is loaded. That list is
hardcoded under `/usr/share/omarchy/`, which an upgrade overwrites and which
takes no plugin hook. Forking a 29 KB first-party widget to add one line would
cost the user every upstream tray fix, so it is the wrong trade.

The supported route is the shell's own per-item `hidden` list in
`~/.config/omarchy/shell.json`. The tray's own Manage popup writes that field,
so the whole fix is one right-click, and it is one right-click to undo.

# The item id

**Discord's tray item is `discord_status_icon_1`**, lowercase. Slack's is
`Slack_status_icon_1`, so Electron follows the application's own internal name
rather than a fixed convention.

This one is documented as unproven: Discord registered no StatusNotifierItem at
all during the session that wrote it down, with a window open and nine processes
up, so only the configuration is verified rather than the id. If a stock Discord
icon ever appears beside the widget, read the id it registers and hide that,
which the Manage popup does correctly whatever the id turns out to be.
