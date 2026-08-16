# Working on this repo

An Omarchy shell plugin (Quickshell/QML) putting Discord in the bar. Read
`NOTES.md` before touching PipeWire matching, the window class, or the icon
path — it holds facts verified against this machine, not assumptions.

## Layout: two copies, one direction

| Path | Role |
|---|---|
| `~/Work/claude/omarchy-discord` | source of truth, git, what you commit |
| `~/.config/omarchy/plugins/io.github.thisisgm.discord/` | live copy the shell loads |

The shell only watches the live copy, so a change is not testable until it is
there. Edit here, then push it across:

```bash
cd ~/Work/claude/omarchy-discord
cp -a manifest.json *.qml *.js *.py README.md LICENSE \
  ~/.config/omarchy/plugins/io.github.thisisgm.discord/
omarchy-shell shell rescanPlugins
```

Keep them identical. `cmp -s` each file before committing if you edited the
live copy directly during debugging.

## Testing

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.thisisgm.discord
omarchy plugin list | grep discord
omarchy-shell discord open          # the panel; also `raise`, `mute`, `toggle`
qs log -p "$OMARCHY_PATH/shell" --tail 60 | grep -i thisisgm
```

**Hot reload is unreliable.** Twice during development a saved change logged
"Local plugin changed, reloading" and still rendered the old code. When a change
does not appear, `omarchy restart shell` (wait ~8s) before concluding anything
about your edit.

**The RPC panel is testable without credentials.** Swap the live copy's
`rpc.py` for a stub printing the same JSON-per-line state, restart the shell,
screenshot, then restore and `cmp` against the repo. Details in `NOTES.md`.

**Look at it.** This is a visual component; a screenshot is the test.

```bash
grim -g "0,0 2560x32" /tmp/bar.png      # the bar
grim -g "2130,28 420x420" /tmp/panel.png # the panel, once opened
```

Crop and scale up (`PIL`, `Image.NEAREST`) before judging a 16px icon.

## Reference

- Plugin contract: <https://omarchyplugins.com/develop.html>
- First-party plugins to copy patterns from — read these, do not invent:
  `/usr/share/omarchy/shell/plugins/panels/dropbox/` (closest analogue),
  `.../tailscale/`, `.../audio/` (PipeWire idioms).
- Shared UI: `/usr/share/omarchy/shell/Ui/`, tokens in `.../Commons/Style.qml`.
- Never edit anything under `/usr/share/omarchy/` — reading is encouraged.

## House rules

These come from `/ultrapr` and are binding here.

- **Scope is the spec.** Do the stated job and stop. Knobs with one caller,
  states this machine cannot produce, and modes nobody runs are defects. The
  manifest has exactly one setting on purpose; five were cut.
- **One line per comment.** Two stacked comment lines is a paragraph. State the
  one non-obvious constraint, or move it to `NOTES.md` / `README.md`.
- **Name every magic number**, and put a sample-input line above every parser.
- **Prove platform facts, do not code for hypotheticals.** Every claim in
  `NOTES.md` was checked with `hyprctl`, `pw-dump`, `ps`, or a render. When a
  reviewer raises a case, answer with the platform fact.
- **Fail loud and specific.** `rpc.py --probe` naming the missing variable is the
  standard to match.
- **Git identity:** every commit is authored `GM <gianmarcomorales@icloud.com>`.
  Never any AI attribution — no `Co-Authored-By`, no "Generated with" line.
- Glyphs must exist in the shipped Nerd Font. Only use codepoints already
  present in Omarchy's own QML, or you ship tofu boxes.
