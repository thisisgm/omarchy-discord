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
