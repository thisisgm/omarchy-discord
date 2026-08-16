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
- **There is no anonymous route to Discord's RPC socket.** The handshake refuses
  an unregistered client id (`{"code":4000,"message":"Invalid Client ID"}`,
  verified). Client ids are public so the plugin could ship one, but the `rpc`
  scope is approval-gated and, per Discord's docs, an unapproved app only
  authorizes for accounts on its App Testers list — so a shipped id would work
  for the author alone. Documented restriction, not measured here.
- **Accessibility is not a way round it.** at-spi2-core is installed and
  `org.a11y.Bus` runs, but the registry fails to activate
  (`Could not activate remote peer 'org.a11y.atspi.Registry': unit failed`) and
  `org.gnome.desktop.interface toolkit-accessibility` is false, so nothing is
  published to read. Electron would also need `--force-renderer-accessibility`,
  and scraping voice-panel labels would break on any Discord redesign.
- **Test the RPC panel without Discord credentials** by swapping the live copy's
  `rpc.py` for a stub that prints the same one-JSON-object-per-line state and
  echoes commands back. That exercises `Rpc.qml`, every new row, the nav order,
  and the glyphs. Restore the real file afterwards and `cmp` it against the repo.
- **The RPC socket belongs to the Electron binary, not to Discord-the-website.**
  `ss -xlp` shows `/run/user/1000/discord-ipc-0` held by `("Discord",pid=…)`.
  Omarchy webapps are `chromium --app=URL` (see `omarchy-launch-webapp`), which
  never creates that socket — so running Discord as a webapp would delete the
  whole optional tier, and would also break the window class (`discord`), the
  PipeWire match (`application.process.binary == "Discord"`) and the `ps -C
  Discord` footprint, none of which a shared Chromium process can provide.
- **Omarchy spends `urgent` on errors and attention, never on labelling a
  button.** The Dropbox panel colours with it only when `lastError` is set, and
  the power panel draws shutdown and reboot in plain `foreground`. Action rows
  here follow that: state can be urgent (muted, deafened, wants attention), a
  button caption cannot.
- **First-party panel metrics, copied deliberately.** Dropbox, Tailscale and
  Agents all set `contentWidth: Style.space(380)` (this panel was 360) and all
  space a section as header → `Style.space(10)` → rows, with `Style.space(6)`
  between rows; the outer column is `Style.space(12)` and rows inset
  `Style.space(10)` with `Style.spacing.rowPaddingX` height. Verified after the
  change by screenshotting this panel and Tailscale's at the same origin: both
  borders land on x=132.
- **`ipcTarget` is deliberately short.** First-party panels use their module id
  (`omarchy.tailscale`), which would make this `omarchy-shell
  io.github.thisisgm.discord raise`. `discord` is what the README documents and
  what a keybinding wants; the collision risk is worth the usability.
- **`AppLibrary` is not the launch path to use.** `shell.appLibrary.launch()`
  runs exactly the `uwsm-app -- gtk-launch <id>.desktop` this plugin already
  runs, plus a launch OSD, but it is a private injection documented for the
  menu's Apps submenu and no plugin under `plugins/` consumes it. Depending on
  it would be less conventional, not more.
- **A Discord app shows three values and two of them look interchangeable.**
  Client ID (OAuth2 page, also called Application ID on General Information) is
  public and goes in the RPC handshake. Client Secret (OAuth2 page, behind Reset
  Secret) buys the token. Public Key (General Information) is an Ed25519 key for
  verifying interaction webhook signatures — exactly 64 hex characters, useless
  here, and the easy thing to paste by mistake, so `--setup` detects that shape
  and says so instead of failing later inside the token exchange.
