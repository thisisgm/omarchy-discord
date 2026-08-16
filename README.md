# Discord for the Omarchy bar

A bar widget for the Discord desktop app, built the way the first-party
Dropbox and Tailscale plugins are built: vector icon, keyboard-navigable
panel, and no configuration.

![The widget in the bar](preview.png)

## What it tells you

| Question | Answered by | How |
|---|---|---|
| Is Discord installed? | `DesktopEntries` | the shell's own desktop entry index, matched on `StartupWMClass=discord` |
| Does it want you? | Hyprland | the window's urgency flag, which Discord raises on a mention or a DM |
| Where is the window? | Hyprland | `toplevels`, with title and workspace |
| Are you in a call? | PipeWire | Discord's WebRTC voice streams exist only while connected |
| Can the call hear you? | PipeWire | the capture stream, and whether it is muted |
| What does it cost? | `ps` | resident memory and process count |

Nothing polls Discord's servers, and no account, token, or developer
application is involved.

## Install

```bash
omarchy plugin add https://github.com/thisisgm/omarchy-discord.git --enable
```

Or, from a local checkout:

```bash
cp -r omarchy-discord ~/.config/omarchy/plugins/io.github.thisisgm.discord
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.thisisgm.discord
```

## Replace Discord's own tray icon

Discord registers a tray item of its own, so out of the box you get two Discord
icons in the bar. Omarchy already solves this for its bundled plugins — the tray
hides Dropbox's item when the Dropbox widget is loaded — but that list lives in
the shell and takes no plugin hook, so hide Discord's item once by hand:

right-click the tray > **Manage** > untick Discord.

That writes `discord_status_icon_1` into the tray's `hidden` list in
`~/.config/omarchy/shell.json`, and it stays hidden across restarts. Untick it
again if you ever remove this widget.

## Using it

The bar icon dims when Discord is not running, turns the theme's urgent
color when Discord wants your attention, and grows a dot while you are in a
voice call. The dot is urgent-colored whenever the call cannot hear you.

| Input | Does |
|---|---|
| Left click | open the panel |
| Middle click | raise Discord, or start it |
| Right click | mute the call mic, or refresh when not in a call |
| Scroll | Discord's volume |
| `o` / `m` / `r` | raise / mute mic / refresh |
| `j` `k`, `Enter` | move and activate; `h` `l` set volume on the volume row |

### Keybindings

The panel is not the only way in. Bind these anywhere:

```bash
omarchy-shell discord raise    # focus the window, or start Discord
omarchy-shell discord mute     # toggle the call microphone
omarchy-shell discord toggle   # the panel
```

`mute` is the interesting one: it mutes Discord's microphone at the PipeWire
level, so it works from any workspace without focusing Discord, and it holds
whatever Discord's own mute button is doing.

## Settings

One, in Setup > Plugins: **hide the icon when Discord is not running**.

## Limits worth knowing

- **Attention needs a window.** Hyprland can only flag a window that exists,
  so an instance closed to the tray reports nothing. The widget shows
  "Running in the background" and can raise it.
- **Mic control needs an open capture stream.** Discord releases the stream
  when it closes the microphone, and there is nothing to mute at the PipeWire
  level until it comes back. The row appears when the stream does.
- **Muting here is not Discord's mute button.** Discord's own UI will still
  show you as unmuted while PipeWire feeds it silence.

## Why not Discord's RPC socket

Discord opens `$XDG_RUNTIME_DIR/discord-ipc-0`, which can report the voice
channel you are in and toggle Discord's own mute and deafen. It refuses any
client id that is not a registered Discord application:

```
{"code":4000,"message":"Invalid Client ID"}
```

Reading voice state on top of that needs the `rpc` OAuth scope, which is
whitelisted per-application. So the feature costs every user a trip to the
developer portal, and this plugin stays zero-setup instead. The state above
is enough to answer the questions a bar is for.

## Uninstall

```bash
omarchy plugin remove io.github.thisisgm.discord
```

## License

MIT.
