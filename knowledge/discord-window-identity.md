---
type: reference
title: How Discord clients identify themselves to the desktop
description: Window class, desktop entry and process name for the Arch discord package and vesktop, and the one launch path that unhides a tray-hidden instance
tags: [discord, hyprland, wayland]
status: stable
verified:
  - by: hyprctl clients and ps on Omarchy 4.0.0, Arch discord app-1.0.154
    at: 2026-08-15
  - by: hyprctl clients, ps and the vesktop.desktop entry on Omarchy, vesktop 1.6.7-1
    at: 2026-08-20
---

# Window, entry and process identity

The Arch `discord` package publishes exactly one shape, and all three values
agree:

- **Window class is exactly `discord`.** `hyprctl clients` reports both `class`
  and `initialClass` as `discord`, and the desktop entry sets
  `StartupWMClass=discord`.
- **Desktop entry is `discord.desktop`.**
- **Process is `Discord`**, capitalised, so `ps -C Discord` finds it. In a
  running instance there are around eight processes; exactly one has no
  `--type=` argument and that one is the main process. Signalling any of the
  others files a crash report inside Discord.

Vesktop publishes the same three slots under its own name, all lowercase, and
all three were measured the same way:

- **Window class is `vesktop`**, with `StartupWMClass=vesktop` in
  `vesktop.desktop`, and the desktop entry is `vesktop.desktop`.
- **Process is `vesktop`**, so `ps -C vesktop` finds it and `ps -C` accepts
  both names as a comma list. A running instance had eight processes, with the
  one lacking `--type=` as the main process, same shape as the discord package.
- **Window title does not require a `- Discord` suffix.** The observed title read
  `(224) Discord | Amigos`, so title trimming must not assume the suffix.

A Flatpak build or another fork publishes different values for all three.
Supporting those is a real change with a real test rather than a configuration
knob.

## Discord runs windowless

Discord closes to a tray icon rather than exiting. When the shell restarts, that
tray registration is lost and Discord becomes unreachable from the desktop: it
is running, with no window and no icon.

`uwsm-app -- gtk-launch discord.desktop` against a running instance restores the
window, because Electron hands the launch to the existing process rather than
starting a second one. Verified live. Using the launcher's own path also puts
Discord in `app-graphical.slice` rather than in the compositor's slice.

## Urgency is the attention signal

Hyprland raises the toplevel's `urgent` flag from xdg-activation, which Discord
uses for a mention or a DM. It only works while a window exists, so an instance
closed to the tray cannot report that it wants attention.
