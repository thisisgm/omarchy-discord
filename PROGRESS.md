# Progress

Last updated 2026-08-15.

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

## Phase 2 — Discord RPC: written, inert, BLOCKED

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

### Next steps, in order

1. Probe, authorize once, confirm the token cache.
2. Wire the bridge into QML: a `Process` running `rpc.py`, parsing one JSON
   object per line into a `Rpc.qml` service. Commands go in on stdin as
   `{"cmd":"mute","value":true}`.
3. Panel additions: hero meta becomes `General / GM's Server`; mute and deafen
   toggles; hang-up row; input/output volume sliders; speaking list.
4. **Degrade cleanly.** With no credentials the panel must look exactly as it
   does today. The RPC tier is additive, never a prerequisite.

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

## Ideas deliberately not built

- **Restart Discord** — cut. Quit plus start is two clicks, and the relaunch
  race (Electron handing a launch to a still-dying instance) could not be
  verified.
- **`desktopId` / `windowClass` / `processName` settings** — cut. This machine
  runs the Arch `discord` package, one shape. A Flatpak or a fork is a real
  change with a real test, not a config knob.
