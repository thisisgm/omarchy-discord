# Progress

Last updated 2026-08-16.

## Phase 1 — bar widget: DONE, verified live

Installed, enabled, and confirmed on screen. All state comes from services the
shell already runs; nothing polls Discord's servers and no account is involved.

| Signal | Source | Verified |
|---|---|---|
| installed | `DesktopEntries`, `StartupWMClass=discord` | yes |
| wants attention | Hyprland toplevel `urgent` | by construction |
| window, title, workspace | `Hyprland.toplevels` | yes, live |
| in a call | PipeWire WebRTC voice streams | yes, live |
| Discord volume | PipeWire playback stream | yes, live |
| memory + processes | one `ps -C Discord` poll | yes, 1.1 GiB / 8 procs |
| raise / start / quit | `uwsm-app -- gtk-launch`, `Hyprland.dispatch` | yes, live |

Panel confirmed rendering: hero "IN A CALL · MIC CLOSED", footprint row, volume
slider, window row `#general | GM's Server` on workspace 4, quit row.

## Phase 1.1 — bar integration polish: DONE, verified live

Two fixes so the widget sits in the bar as a native, not a guest.

**Icon weight.** Every mark on this bar is 13px tall, so matching height had
proven nothing: Clyde is the only solid landscape mark in the set and carried
119.4 lit pixels against 78.5 for Agents and 31.7 for Tailscale — 2.2x the
average. `DiscordIcon.opticalScale: 0.85` brings it to 86.9, level with the
heaviest first-party icons. Dropbox makes the same correction (`scale: 0.95`).
Measurements and method in `NOTES.md`; the panel hero was re-checked after.

**Stock tray icon.** Discord registers `discord_status_icon_1` of its own, so
the bar showed two Discord icons. Moved that id from the tray's `pinned` to its
`hidden` list in `~/.config/omarchy/shell.json` (backup:
`shell.json.bak.discord-dedup`). Omarchy's own fix for this — the Dropbox rule
in `TrayModel.ownedByOmarchy` — is hardcoded under `/usr/share` with no plugin
hook, and forking a 29KB first-party widget to add one line would cost the
user every upstream tray fix. The `hidden` list is the shell's own affordance
for exactly this and is one right-click to undo. README documents the manual
route so the plugin is correct for anyone else installing it.

## Phase 1.2 — first-party polish pass: DONE, verified live

Measured against Dropbox, Tailscale and Agents rather than guessed:

- Panel width 360 → **380**, the constant all three first-party panels use.
  Confirmed by screenshotting this panel and Tailscale's at one origin: both
  borders land on x=132.
- Section rhythm now matches theirs — header, `Style.space(10)`, then rows at
  `Style.space(6)` — where this panel had a flat 6 and read cramped.
- The hand-measured `Footprint` row became an `InfoPair`, the label/value shape
  Dropbox uses, dropping a `parent.children[0].implicitWidth` calculation. The
  speaking line lost the same kind of arithmetic for a `RowLayout`.
- The quit row drew a filled close-circle in `urgent`, the only saturated shape
  in a panel of thin line art. Omarchy spends `urgent` on errors and attention
  and draws shutdown in plain `foreground`, so it is now the power glyph in
  `foreground`. State keeps its colour; captions do not.

Kept on purpose: the single `hideWhenStopped` setting (both first-party panels
expose a `refreshIntervalSec` knob; this one polls on a named 20s constant and
does not need it), and the short `ipcTarget`. Both noted in `NOTES.md`.

## Phase 2 — Discord RPC: LIVE, verified against a real call

`rpc.py` is complete and syntax-clean. It owns Discord's binary RPC socket and
speaks line-delimited JSON, giving QML what PipeWire cannot see: the voice
channel name, Discord's own mute and deafen, input/output volume, voice mode,
who is speaking, and hang up. Reconnects on its own and refreshes its token.

**Working since 2026-08-16.** Authorized as thisisgm with exactly three
scopes (`rpc`, `rpc.voice.read`, `rpc.voice.write`), token cached 0600 with a
refresh token. The panel shows the live channel, deafen, mic gain and leave
call. Three bugs had to be fixed against a real Discord to get there — the
SUBSCRIBE frame shape, the missing User-Agent, and the AUTHORIZE redirect_uri
misreading — all recorded in `NOTES.md`.

The voice section now follows Discord's own panel: the call named on the left,
mute/deafen/hang-up as `PanelActionButton` icons on the right, with the mic
meter under the name. That replaced four stacked full-width rows.

### Next steps, in order

1. Run `python3 rpc.py --setup` with Discord running. It opens the portal,
   takes the two values, writes them 0600, and authorizes in the same run.
   Both failure paths are already tested: a non-numeric Application ID is
   rejected before anything is written, and an unregistered one comes back
   `Invalid Client ID` with the redirect-URI and App-Testers hints.
2. Confirm the token lands in `~/.local/state/omarchy-discord/token.json` at
   0600. Opening the panel re-tries the bridge, so no shell restart is needed.
3. Re-check the panel against a real call: channel and guild names, deafen,
   mic gain, leave call, and that the mic row now moves Discord's own mute.
4. Confirm the bar dot follows Discord's mute rather than the capture stream.

## Phase 3 — setup without a terminal, and call quality: DONE

- **Setup moved into the panel.** With no credentials the panel grows one
  discreet `Set up voice controls` row; opening it reveals the redirect URI,
  a Client ID field and a masked Client Secret field, plus *Open portal* and
  *Connect*. `Connect` runs `rpc.py --save`, which reads the pair from **stdin**
  so the secret never touches argv, then retries the bridge — no shell restart.
  Verified by staging the credentials away, screenshotting both states, and
  restoring through the same `--save` path the button drives.
- **Call quality indicator.** The bridge subscribes to
  `VOICE_CONNECTION_STATUS` and reports the average ping. Discord draws that
  green/yellow/red; Omarchy has no green, so it is drawn as signal-strength
  arcs (full → outline) coloured `foreground` → `dim` → `urgent`, sitting where
  Discord puts it — left of the call buttons. The ping in milliseconds only
  appears in the subtitle when the connection is not good.
- **Cleanups**: `Footprint` → `RAM usage`; the quit row is gone because the
  hero switch already did that job and its subtitle repeated the RAM figure, so
  the hero switch became a keyboard stop the way Dropbox's is; window titles
  drop the ` - Discord` suffix every one of them carries; the "Show Discord"
  row lost a subtitle the hero meta already said.

## Known unknowns

- **Does a capture stream appear when the mic is unmuted?** Observed for ~5
  minutes during a live call with the mic closed and it never appeared, so
  `hasMicControl` is written to simply hide the mic row when there is no stream.
  If unmuting does create one, the row and the bar dot light up as designed —
  worth confirming, since it decides whether the PipeWire mic path is useful at
  all once RPC lands (RPC's own mute is better anyway).
- Attention (`urgent`) has not been seen fire yet; it needs an incoming mention
  while Discord is unfocused.
- The plugin has never run on a machine without Discord installed.
- **Discord's tray item never registered during the 2026-08-16 session**, with a
  window open and 9 processes up, so the `hidden` entry is proven only as
  config. If a stock Discord icon ever reappears beside this widget, check the
  id it registers under against `discord_status_icon_1` and hide it from the
  tray's Manage popup, which writes the field correctly whatever the id.

## Ideas deliberately not built

- **Restart Discord** — cut. Quit plus start is two clicks, and the relaunch
  race (Electron handing a launch to a still-dying instance) could not be
  verified.
- **Running Discord as an Omarchy webapp** — rejected 2026-08-16. It would
  remove the RPC socket (owned by the Electron binary, proven with `ss -xlp`)
  and break the window class, the PipeWire match and the footprint poll, all of
  which depend on a process actually called `Discord`. It only solves the
  duplicate tray icon, which is already solved. See `NOTES.md`.
- **Discord's own output volume slider** — cut, though `rpc.py` implements the
  command. The panel already has a "Discord volume" slider (PipeWire, desktop
  level) that answers the same question the same way and keeps working outside
  a call. Two sliders both meaning "how loud is Discord" is worse than one.
  Mic gain was kept because nothing else exposes it.
- **`desktopId` / `windowClass` / `processName` settings** — cut. This machine
  runs the Arch `discord` package, one shape. A Flatpak or a fork is a real
  change with a real test, not a config knob.
