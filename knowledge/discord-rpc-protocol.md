---
type: reference
title: Discord RPC frame shape and the three calls that fail unhelpfully
description: Binary framing, the SUBSCRIBE argument order, the AUTHORIZE redirect_uri rule, and the user agent the token endpoint requires
tags: [discord, rpc, protocol]
status: stable
verified:
  - by: live socket session, each error observed rather than inferred
    at: 2026-08-16
---

# Framing

Every message is a binary `<II` header, little-endian opcode and little-endian
length, followed by a JSON body. A sample frame therefore begins with eight
bytes that are not text.

This is why the bridge cannot live in QML. Quickshell's `Socket` can open the
unix socket, but `write()` takes a QString and the parsers emit QString, and
pushing those header bytes through UTF-8 corrupts anything above 0x7F. A
binary-capable process is a requirement, not a shortcut.

# Three calls that fail in non-obvious ways

**Subscribing is `{"cmd":"SUBSCRIBE","evt":"<EVENT>"}`**, not the event as the
command. Getting it backwards returns `Invalid command:
VOICE_SETTINGS_UPDATE`, which reads like the event is unsupported.

**RPC AUTHORIZE must not carry a `redirect_uri`.** Passing one answers
`Redirect URI cannot be used in the RPC OAuth2 Authorization flow`. Discord uses
the one registered on the application instead, which means `Missing
"redirect_uri" in request` from AUTHORIZE says the application has **none
registered**, not that the call omitted it. The HTTP token exchange still has to
send it.

**The token endpoint 403s the default Python user agent.** `urllib` sends
`Python-urllib/3.x` and Discord's edge answers a bare `403 Forbidden` with no
body hint. Setting any identifying `User-Agent` fixes it. This was the last
thing standing between a working AUTHORIZE and a token.

# Call quality

`VOICE_CONNECTION_STATUS` yields `{"state": "VOICE_CONNECTED", "average_ping":
36, "last_ping": 35, "hostname": "...", "pings": [...]}`. It fires several times
a second, so a consumer should re-emit only when the state or the rounded ping
changes.

# Refusals are per command

A command Discord turns down comes back as an ERROR frame while the connection
stays good. Telling an auth-fatal refusal (expired or revoked token) from an
ordinary one would mean keying on Discord's numeric error codes, and none of
those were verified against the live socket here, so this project does not guess
at them. It warns on stderr naming the command instead.
