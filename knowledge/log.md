---
type: log
title: Knowledge bundle history
description: What changed in this bundle and when
---

# Log

## 2026-08-16, during a live call

`discord-pipewire-streams` gained a measurement rather than a recollection: one
Discord node, `Stream/Output/Audio` WEBRTC VoiceEngine, no capture node while
muted, and no second playback stream. The first of its two open questions is now
answered for the muted case.

## 2026-08-16

Bundle created for the first public release. Seven facts carried over from the
project's `NOTES.md`, each one measured on minipc, an Omarchy 4.0.0 machine
running the Arch `discord` package version app-1.0.154.

Two questions are recorded as open rather than answered, because settling them
needs a live call that had not happened yet: whether Discord publishes a capture
stream when the microphone is unmuted, and how to tie-break between the two
playback streams Discord publishes during a call. Both are named in
`discord-pipewire-streams.md`.
