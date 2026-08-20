---
type: reference
title: How Discord clients appear in PipeWire
description: Streams publish as WEBRTC VoiceEngine, so only the process binary identifies them, and no capture stream exists while the microphone is closed
tags: [discord, pipewire, audio]
status: stable
verified:
  - by: pw-dump during a live call on Omarchy 4.0.0
    at: 2026-08-15
---

# PipeWire naming

**PipeWire does not name the app "Discord".** Call streams publish as
`application.name = "WEBRTC VoiceEngine"`, and `media.name` is `playStream`.
Only `application.process.binary` identifies the owner: `Discord` for the
discord package, `vesktop` for vesktop (measured with `pw-dump` on an idle
vesktop 1.6.7-1, 2026-08-20), so any match on the friendly name finds nothing.

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

## Vesktop, measured during a live call, 2026-08-20

**Vesktop publishes no `WEBRTC VoiceEngine` name.** Every vesktop stream
carries `application.process.binary = "vesktop"` and
`application.name = "vesktop"`, so the discord package's name match finds
nothing. With a call connected and the microphone open, `pw-dump` reported
exactly two vesktop nodes:

```text
id=114  Stream/Output/Audio  application.name=vesktop  media.name=Playback       state=running
id=128  Stream/Input/Audio   application.name=vesktop  media.name=RecordStream  state=running
```

Only the capture stream is an unambiguous call signal: notification sounds are
output-only, so `Stream/Input/Audio` owned by vesktop means a call with the
microphone open. The playback stream cannot carry that meaning, because a
notification sound publishes the same name.

Vesktop keeps that capture stream under its own mute. Sampled twice a second
for 53 seconds, covering a mute and unmute pressed inside vesktop, the capture
node never left and never left the running state. The discord package releases
the capture stream in the same situation, so the clients differ here and the
call signal survives vesktop's mute button.

And the playback stream does outlive the call: after leaving, `pw-dump` showed
the same `Stream/Output/Audio` still present and running with the capture node
gone. The playback stream therefore cannot be the call signal twice over, by
name and by lifetime, and the panel verified the call state dropping while the
volume row stayed.

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
