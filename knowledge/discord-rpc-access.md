---
type: reference
title: Why Discord's local RPC socket cannot be used anonymously
description: The rpc scope is approval-gated and the token exchange needs a client secret, so a shipped client id would work for its author alone
tags: [discord, rpc, oauth]
status: stable
verified:
  - by: live handshake against the local socket, plus Discord's OAuth2 documentation
    at: 2026-08-16
---

# There is no anonymous route

Discord's local RPC socket lives at `$XDG_RUNTIME_DIR/discord-ipc-0` and is held
by the Electron binary itself, confirmed with `ss -xlp` showing
`("Discord",pid=...)`. It is the only source of the channel name, Discord's own
mute and deafen, and hang up. Nothing outside Discord knows those.

The handshake refuses any client id that is not a registered application:

```
{"code":4000,"message":"Invalid Client ID"}
```

Client ids are public, so a plugin could ship one. That does not help:

- The `rpc` scope is **approval-gated**. Until Discord approves an application
  for general RPC access, only the owner and up to 50 accounts on its
  **App Testers** list may authorize. A shipped client id would therefore work
  for its author and for nobody else.
- The OAuth2 token exchange requires the client secret. Discord's documentation
  is explicit that all OAuth2 endpoint calls need either HTTP Basic auth or
  `client_id` and `client_secret` in the form body. There is no PKCE and no
  public-client flag that drops the secret.

Borrowing an already-approved application's client id with the implicit grant
does avoid the secret, and several are public. It was rejected here: it puts
somebody else's application in the user's Authorized Apps list, returns no
refresh token so it expires silently, and breaks whenever that application
changes.

The conclusion for a plugin is that this tier is opt-in, per user, and the
plugin has to be complete without it.

## Scopes and token

Three scopes are needed and granted: `rpc`, `rpc.voice.read`,
`rpc.voice.write`. The token carries a refresh token and a seven day expiry.

## Accessibility is not a way round it

at-spi2-core is installed and `org.a11y.Bus` runs, but the registry fails to
activate (`Could not activate remote peer 'org.a11y.atspi.Registry': unit
failed`) and `org.gnome.desktop.interface toolkit-accessibility` is false, so
nothing is published to read. Electron would also need
`--force-renderer-accessibility`, and scraping voice-panel labels would break on
any Discord redesign.

## Vesktop keeps the socket

Vesktop creates the same `$XDG_RUNTIME_DIR/discord-ipc-0` while running
(measured 2026-08-20, vesktop 1.6.7-1, no other Discord client installed), so
the bridge has a socket to reach. The handshake against it was not exercised,
because that needs a registered application with the `rpc` scope.

## Running Discord as a web app removes the socket

Omarchy web apps are `chromium --app=URL`, which never creates the RPC socket.
It would also break the window class, the PipeWire match and the process
footprint, none of which a shared Chromium process can provide.
