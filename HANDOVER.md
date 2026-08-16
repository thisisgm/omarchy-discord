# Handover, 2026-08-16 (second session)

Supersedes the first handover. Read `AGENTS.md` for how to work here, `NOTES.md`
for platform facts, `PROGRESS.md` for what the plugin does.

## Right now

Working tree clean, four commits ahead of where the last session stopped:

```
5155c1a style(discord): one line per comment across the QML and JS
3320896 fix(discord): keyboard-safe setup form, silent bridge re-probe
0714087 fix(discord): bound bridge restarts, stop warnings faking a drop
<head>  fix(discord): drop the phantom mic stop, repair the hero attention colour
```

All authored `GM <gianmarcomorales@icloud.com>`. The live copy is byte-identical,
`omarchy plugin validate` exits 0, `python3 test_rpc.py` is green, and the shell
log is clean after a restart.

The comment sweep the last handover left uncommitted is done: all 21 remaining
stacked blocks in `Panel.qml` and `Service.qml` are one line each.

## What the review found and what happened to it

Two full advloop runs plus one short round. State in
`~/.local/state/advloop/runs/_home_gm_Work_claude_omarchy-discord/`:
`ledger.prev-run.json` (the first session), `ledger.run2.json` (run 2, 17
entries), `round-panel-1-raw.json`.

**Fixed and verified on the box (14):** the setup form's keyboard trap and its
missing reset, enter activating a row the mouse refuses, a dead mic meter, a red
"not set up yet" error flashing on every panel open, an unbounded 4s bridge
respawn, a stderr warning masquerading as a disconnect, an unreachable
`pkill -x Discord` that would have signalled the renderers, a keyboard stop on a
mic row that was not drawn, the hero attention colour resolving against
PanelHero (which has no `urgent`), and two IPC verbs reporting ok while doing
nothing.

**Rebutted, all accepted by an arbiter (7):** the stdin EOF hang (rpc.py uses
`readline`), the silent nonzero exit, `setCursor(-1)` (unreachable: `inVoice`
implies `connected` implies `hasMicControl`), unclamped volume and gain (Service
clamps both), missing setup validation (rpc.py validates, loudly), the dead
`node.type` branch (verbatim copy of Omarchy's own audio `Model.js`), and the
hardcoded `discord.desktop` (one box, one shape).

**Waived:** the redirect URI duplicated between `Panel.qml` and `rpc.py`; a QML
file cannot import a Python constant and the comment is the binding.

**Deferred to the known unknowns:** `findDiscordStream` has no tie-break between
Discord's two playback streams. `pw-dump` shows zero Discord nodes while it is
idle, so this needs a live call, the same blocker as the capture-stream question.

## Where the loop actually stands

**Not approved.** A fresh run was started over the whole QML and JS surface and
its round 1 is **short**: one reviewer of three returned, because relaying a
1900 line bundle three times did not fit the session. A short round never
approves and does not count against the cap.

That one reviewer (broad) found the three defects fixed in the last commit. Its
findings are the only ones outstanding, and they are fixed but unread.

**To finish: run `/advloop` in a fresh session** with a clean context, scoped
`4b825dc642cb6eb9a060e54bf8d69288fbee4904..HEAD -- '*.[jq]*'` and
`ADVLOOP_MAX_DIFF_LINES=1800`. That is 1734 lines, three reviewers, and it needs
room to relay the bundle three times. Nothing else is known to be wrong.

## Lessons this session

**Do not split a review by file.** Six of the first ten findings rested on
premises that are false the moment `Service.qml`, `Rpc.qml` or `rpc.py` is
visible. Reviewers cannot see what the pathspec hides, and they will confidently
infer the wrong invariant. Every later pass paid for that.

**Look at the thing.** The red-error-on-every-open defect was invisible to three
cold readers of `Panel.qml` and obvious in a screenshot taken two seconds after
opening the panel. `grim` over ssh needs
`XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1`, and `omarchy-shell`
also needs `OMARCHY_PATH=/usr/share/omarchy`.

**`wtype` does not reach the layer-shell panel over ssh.** Keys go nowhere: the
panel stays open on `o` and the cursor never highlights. Keyboard behaviour has
to be checked at the machine or by reading.

**The IPC verbs act on live state.** `omarchy-shell discord mute` and `deafen`
really toggle Discord. Toggle back after testing.

**A cold reviewer reasoning about a comment found a real bug.** The claim was
that the trailingControl comment contradicted the sibling iconComponent. Reading
`/usr/share/omarchy/shell/Ui/PanelHero.qml` showed it is `id: root` with no
`urgent` property, so the hero's attention colour had never worked.

## Not done

- Release: README with the captured screenshots, CONTRIBUTING, the OKF bundle
  with a donation link, publishing to the `thisisgm` GitHub account. None started.
- `rpc.py` and `test_rpc.py` have been reviewed only by the first session's run;
  F21 from that run is still open.
- The docs and `LICENSE` have never been in any review set.
- The capture-stream question and the two-playback-stream question both need one
  live call to settle.
- The plugin has still never run on a machine without Discord installed.
