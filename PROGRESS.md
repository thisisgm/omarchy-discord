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

## Phase 2 — Discord RPC: built and wired, awaiting credentials

`rpc.py` is complete and syntax-clean. It owns Discord's binary RPC socket and
speaks line-delimited JSON, giving QML what PipeWire cannot see: the voice
channel name, Discord's own mute and deafen, input/output volume, voice mode,
who is speaking, and hang up. Reconnects on its own and refreshes its token.

**Blocked on credentials.** GM must:

1. Create an app at <https://discord.com/developers/applications>.
2. OAuth2 → add redirect URI `http://localhost/omarchy-discord`.
3. Add himself under App Testers — unapproved apps only work for testers, and
   the owner qualifies. This is what makes the whole tier possible.
4. Put `DISCORD_CLIENT_ID` and `DISCORD_CLIENT_SECRET` into the 1Password
   `claude-skills` Environment, **in the 1Password app directly** so the secret
   never passes through an agent's context.

Then: `python3 rpc.py --probe` should print the logged-in username. First real
run triggers a consent modal inside Discord and caches a token to
`~/.local/state/omarchy-discord/token.json` (0600).

`Rpc.qml` owns the process, parses its lines, and sends commands on stdin.
`Service.qml` prefers it over PipeWire for mute and call state and falls back
automatically. The panel gains the call name in the hero, a speaking line,
deafen, mic gain, and a leave-call row.

**Verified without credentials** by swapping the live `rpc.py` for a stub that
speaks the same protocol (method in `NOTES.md`): every row rendered, all glyphs
were real, the nav order matched, and commands round-tripped. The real file was
restored and `cmp`-checked against the repo afterwards.

**Degradation verified live**: with no credentials `rpc.py` prints one error
line, exits 2, and `Rpc.qml` stops retrying — the panel is pixel-identical to
Phase 1 and shows no error, because a tier nobody set up is not a failure.

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
