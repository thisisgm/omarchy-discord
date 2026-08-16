# Platform facts (verified on minipc, Omarchy 4.0.0, 2026-08-15)

Hard-won findings. Re-verify before changing the code that depends on them.

- **Window class is exactly `discord`** — `hyprctl clients` reports both `class`
  and `initialClass` as `discord`. Desktop entry sets `StartupWMClass=discord`.
- **Discord runs windowless.** It closes to a tray icon; when the shell restarts,
  that SNI registration is lost and Discord becomes unreachable from the desktop.
  `uwsm-app -- gtk-launch discord.desktop` on a running instance restores the
  window (Electron single-instance hand-off). Verified live.
- **PipeWire does NOT name the app "Discord".** Call streams publish as
  `application.name = "WEBRTC VoiceEngine"`; only
  `application.process.binary = "Discord"` identifies it. `media.name` is
  `playStream`.
- **No capture stream while the mic is closed.** In a live call with the mic
  muted, only `Stream/Output/Audio` exists. So "in a call" must key off the
  voice-engine streams, not the capture stream. Unverified: whether the capture
  stream appears on unmute (user stayed muted during observation).
- **Qt's SVG path parser mis-reads compact arc flags.** `a19.79 19.79 0 00-4.88-1.51`
  packs large-arc and sweep as `00`; Qt reads that as one number and the geometry
  comes out sheared. Fix: the shipped path has its 17 arcs converted to lines
  (radius <0.08 in a 24-unit box, invisible at bar sizes).
- **Mark ink bounds** measured with rsvg: x 0..24, y 2.85..21.15, aspect 1.3115.
- **RPC needs a registered app.** An unregistered client_id gets
  `{"code":4000,"message":"Invalid Client ID"}`. Docs: unapproved apps work only
  for users on the app's tester list — which the owner is. Token exchange needs
  client_secret at `https://discord.com/api/oauth2/token`.
- **First-party sizing**: Tailscale's bar icon uses `Style.space(11)` and
  `Style.font.display` in the hero. This plugin matches.
- **Bar icons share a height, not a weight.** Every widget mark on this bar is
  13px tall, so height matching proves nothing. Measured lit-pixel mass at
  `Style.font.icon`: Clyde fitted to full height 119.4, Agents 78.5, Volume 77.5,
  Wifi 55.7, Monitor 48.9, Bluetooth 31.9, Tailscale 31.7 — Clyde carried 2.2x
  the average because it is the only solid landscape mark in the set. Dropbox
  makes the same correction with `scale: 0.95` on its Shape. `opticalScale: 0.85`
  brings Clyde to 86.9, alongside Agents and Volume. Re-measure with `grim` plus
  a background-delta sum if the icon path or `Style.font.icon` changes.
- **Discord's own tray item is `discord_status_icon_1`** (lowercase; Slack's is
  `Slack_status_icon_1`, so Electron follows the app's internal name). Omarchy
  suppresses first-party duplicates in `TrayModel.ownedByOmarchy`, but that list
  is hardcoded under `/usr/share` and takes no plugin hook, so this plugin uses
  the shell's own per-item `hidden` list in `shell.json` instead. The tray's
  manage popup writes the same field, so a mismatched id is one right-click to
  fix. Not observable live: Discord registered no SNI item at all during this
  session, window open and 9 processes up, so only the config is proven.
