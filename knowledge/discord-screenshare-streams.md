---
type: reference
title: How Discord screensharing streams appear in PipeWire and Hyprland
description: Native video streams omit application.process.binary, quickshell flags them with isStream false, and Hyprland window focusing requires a 0x hex address
tags: [discord, pipewire, hyprland, screenshare]
status: stable
verified:
  - by: pw-dump and hyprctl dispatch during a live call on Omarchy 4.0.3
    at: 2026-09-15
---

# PipeWire video stream properties

When Discord shares a screen or window on Wayland via `xdg-desktop-portal-hyprland`,
it creates a video stream node in PipeWire linked to the portal's screencopy source.

Measured via `pw-dump` on Discord 1.0.158 with PipeWire 1.6.8:

```text
id=172  Stream/Input/Video  media.name=discord  media.role=Screen  media.type=Video  node.name=Discord
```

## No `application.process.binary` on native video streams

Unlike Discord's PulseAudio audio streams (`WEBRTC VoiceEngine`), which publish
`application.process.binary = "Discord"`, native Wayland video capture streams
do not populate `application.process.binary` on node properties.

Instead, the owner is identified by `node.name = "Discord"` and `media.name = "discord"`.
Any matcher looking only at `application.process.binary` therefore misses video streams.

## Quickshell reports `isStream = false` for video nodes

Quickshell's PipeWire service exposes `isStream = true` only for audio streams.
A video capture node publishes `isStream = false`.

Because `PwNode.properties` is populated only after a `PwObjectTracker` binds the node,
filtering candidates solely by `node.isStream` drops video nodes before the tracker
ever sees them. Checking `node.isStream || isAppId(node.name)` matches the native C++
property `node.name` immediately, allowing `PwObjectTracker` to bind the node and load
its properties.

## Hyprland window focus requires `0x` prefix and Lua dispatch

Omarchy Quattro evaluates Hyprland window dispatches via its Lua engine.
Calling `Hyprland.dispatch("focuswindow address:" + target.address)` fails with a Lua
syntax error.

The working dispatch is `hl.dsp.focus({ window = "address:0x..." })`. Furthermore,
Quickshell's `toplevel.address` exposes hex without the `0x` prefix (e.g. `5580f18e78f0`).
Hyprland's window finder requires the `0x` prefix (`address:0x5580f18e78f0`), otherwise
it warns `window not found`.
