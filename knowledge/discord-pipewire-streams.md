---
type: reference
title: How Discord appears in PipeWire
description: Discord's streams publish as WEBRTC VoiceEngine, so only the process binary identifies them, and no capture stream exists while the microphone is closed
tags: [discord, pipewire, audio]
status: stable
verified:
  - by: pw-dump during a live call on Omarchy 4.0.0
    at: 2026-08-15
---

# PipeWire naming

**PipeWire does not name the app "Discord".** Call streams publish as
`application.name = "WEBRTC VoiceEngine"`, and `media.name` is `playStream`.
Only `application.process.binary = "Discord"` identifies the owner, so any match
on the friendly name finds nothing.

The voice engine holds streams only while connected to a call, which makes
"is in a call" answerable without touching Discord's own state: the WebRTC
streams exist, or they do not. Notification sounds do not create them.

## No capture stream while the microphone is closed

In a live call with the microphone muted, only `Stream/Output/Audio` exists.
Discord releases the capture stream when it closes the microphone, so there is
nothing to mute at the PipeWire level until it comes back.

This is why "in a call" keys off the voice-engine streams rather than off the
capture stream, and why a microphone row that depends on a capture node has to
hide itself rather than render an empty meter.

## Measured again during a live call, 2026-08-16

With a call connected and the microphone muted, `pw-dump` reported exactly one
Discord-owned node:

```
id=71  Stream/Output/Audio  application.name=WEBRTC VoiceEngine  media.name=playStream  state=running
```

No capture node, which confirms the paragraph above against live state rather
than a remembered session, and only one playback node, so the two-stream case
below did not occur.

## Two questions still open

Both need a live call to settle, and `pw-dump` shows zero Discord nodes while
Discord is idle, so neither can be answered from a quiet machine:

- Does a capture stream appear when the microphone is unmuted? Observed for
  about five minutes during a live call with the microphone closed and it never
  appeared. If unmuting does create one, the microphone row and the bar dot
  light up as designed.
- Discord publishes both a WebRTC output stream and its app-sound stream during
  a call, both owned by the same process binary. Picking the first match is
  therefore node-order dependent, and no tie-break has been measured.
