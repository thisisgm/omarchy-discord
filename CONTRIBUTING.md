# Contributing

Bug reports, patches and platform facts are all welcome. This file is the short
version; `AGENTS.md` is the same ground in more detail, and `NOTES.md` holds
every fact the code depends on.

## Two copies, one direction

The shell loads the plugin from `~/.config/omarchy/plugins/`, not from your
checkout, so a change is not testable until it is pushed across:

```bash
cp -a manifest.json *.qml *.js *.py README.md LICENSE \
  ~/.config/omarchy/plugins/io.github.thisisgm.discord/
omarchy-shell shell rescanPlugins
```

Hot reload is unreliable. Twice during development a saved change logged
"Local plugin changed, reloading" and still rendered the old code, so when a
change does not appear, run `omarchy restart shell` and wait about eight
seconds before concluding anything about your edit.

## Testing

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.thisisgm.discord
python3 test_rpc.py
qs log -p "$OMARCHY_PATH/shell" --tail 60 | grep -i thisisgm
```

**Look at the thing.** This is a visual component and a screenshot is the test.
The worst defect found in review was invisible to three careful readers of the
source and obvious in a screenshot taken two seconds after opening the panel:

```bash
grim -g "0,0 2560x32" /tmp/bar.png       # the bar
grim -g "2130,28 420x460" /tmp/panel.png # the panel, once opened
```

The RPC panel is testable without Discord credentials. Swap the live copy's
`rpc.py` for a stub that prints the same one-JSON-object-per-line state, restart
the shell, screenshot, then restore it and `cmp` against the repo. That is how
the bridge's failure paths were exercised without a broken Discord.

## House rules

The code is deliberately boring, because boring code survives a 3am page.

- **Scope is the spec.** Do the stated job and stop. Knobs with a single caller,
  states this platform cannot produce, and modes nobody runs are defects wearing
  the costume of thoroughness. The manifest has exactly one setting on purpose.
- **Prove platform facts, do not code for hypotheticals.** Every claim in
  `NOTES.md` was checked with `hyprctl`, `pw-dump`, `ps`, or a render. If a
  review comment describes a state this platform cannot reach, answer it with
  the platform fact rather than with more code.
- **One line per comment.** Two stacked comment lines is a paragraph. State the
  one non-obvious constraint and stop, or move the explanation to a document.
- **Name every magic number**, and put a sample-input line above every parser
  showing the exact text it consumes.
- **Fail loud and specific.** Errors name the failing component and the input.
  `rpc.py --probe` naming the missing variable is the standard to match.
- **Glyphs must already exist in the shipped Nerd Font.** Only use codepoints
  that appear in Omarchy's own QML, or you ship tofu boxes.

## Design

The three first-party plugins are the reference implementations. Read them
before designing anything, and say which one you are copying:

- `/usr/share/omarchy/shell/plugins/panels/dropbox/` is the closest analogue
- `/usr/share/omarchy/shell/plugins/panels/tailscale/`
- `/usr/share/omarchy/shell/plugins/panels/audio/` for the PipeWire idioms

Never edit anything under `/usr/share/omarchy/`. Reading it is encouraged, and
an upgrade overwrites it.

One job per file: `Panel.qml` presents, `Service.qml` is the only thing that
touches the outside world, `Model.js` is pure functions with no QML imports.
Data acquisition belongs in a command or a helper script, not in the panel.

## Commits

Conventional subject, 60 characters or less, with the rationale in the body
rather than in the code comments. No em dashes in prose the repo produces.

## Knowledge

If you learn something the hard way, write it down in `knowledge/` as well as in
the code. Each file is one fact with YAML frontmatter carrying at least a
`type`, which is all Open Knowledge Format requires, and `knowledge/log.md`
records what changed.
