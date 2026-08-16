---
type: reference
title: Matching a bar icon to its neighbours is about ink, not height
description: Every mark on the Omarchy bar is the same height, so weight has to be matched by measuring lit pixels
tags: [omarchy, bar, design]
status: stable
verified:
  - by: grim capture plus a background-delta pixel sum at Style.font.icon
    at: 2026-08-15
---

# Height proves nothing

Every widget mark on the Omarchy bar is 13 pixels tall, so matching height tells
you nothing about whether an icon looks like it belongs. What separates a native
mark from a guest is ink: how many pixels it actually lights.

Measured lit-pixel mass at `Style.font.icon`, by capturing the bar with `grim`
and summing the delta against the background:

| Mark | Ink |
|---|---|
| Discord's Clyde, fitted to full height | 119.4 |
| Agents | 78.5 |
| Volume | 77.5 |
| Wifi | 55.7 |
| Monitor | 48.9 |
| Bluetooth | 31.9 |
| Tailscale | 31.7 |

Clyde carried 2.2 times the average because it is the only solid landscape mark
in the set; everything else is thin line art. An optical scale of 0.85 brings it
to 86.9, alongside Agents and Volume.

First-party makes the same correction: the Dropbox widget sets `scale: 0.95` on
its Shape for the same reason.

Re-measure if the icon path or `Style.font.icon` changes.

# Sizing conventions worth copying

- The bar icon uses `Style.space(11)`, and the panel hero uses
  `Style.font.display`, both taken from Tailscale.
- Panels are `Style.space(380)` wide. Dropbox, Tailscale and Agents all agree,
  and a panel at 360 reads visibly narrow next to them.
- A section is header, then `Style.space(10)`, then rows at `Style.space(6)`.
  The outer column is `Style.space(12)` and rows inset `Style.space(10)`.
- Section headers are ALL CAPS. Row, action and info labels are sentence case,
  keeping proper nouns and acronyms.
- `urgent` is spent on errors and attention, never on labelling a button. The
  power panel draws shutdown in plain foreground.
