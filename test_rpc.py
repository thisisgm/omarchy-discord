#!/usr/bin/env python3
"""Adversarial cases for rpc.py. Each one failed before the fix it guards.

Run with: python3 test_rpc.py
"""

import contextlib
import io
import os
import stat
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rpc

FAILURES = []


def check(name, passed, detail=""):
    print("%s %s%s" % ("ok  " if passed else "FAIL", name,
                       "" if passed else "  (%s)" % detail))
    if not passed:
        FAILURES.append(name)


class FakeRpc:
    """Stands in for Rpc so the read loop can be driven without Discord."""

    def __init__(self, frames=()):
        self.frames = list(frames)
        self.commands = []

    def subscribe(self, event, args=None):
        return "0"

    def command(self, cmd, args=None, evt=None):
        self.commands.append((cmd, args))
        return "0"

    def request(self, cmd, args=None, evt=None):
        if cmd == "GET_VOICE_SETTINGS":
            return {"mute": False, "deaf": False, "input": {"volume": 100}}
        return {}

    def readable(self, timeout):
        return True

    # run() ends when the script runs out, which proves it kept looping
    def recv(self):
        if not self.frames:
            raise rpc.RpcError("frames exhausted")
        return self.frames.pop(0)

    def take_deferred(self):
        return []

    def send(self, op, payload):
        return None


@contextlib.contextmanager
def captured_warnings():
    lines = []
    original = rpc.warn
    rpc.warn = lines.append
    try:
        yield lines
    finally:
        rpc.warn = original


def drive(bridge):
    """Run the read loop to frame exhaustion, swallowing the stop and its output."""
    while not rpc.COMMANDS.empty():
        rpc.COMMANDS.get_nowait()
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            bridge.run()
        except rpc.RpcError:
            pass


def leftover_temporary_cannot_widen_a_secret():
    """A .tmp left behind by a crash used to donate its 0644 to the token."""
    with tempfile.TemporaryDirectory() as directory:
        target = os.path.join(directory, "token.json")
        with open(target + ".tmp", "w") as handle:
            handle.write("{}")
        os.chmod(target + ".tmp", 0o644)
        rpc.write_private(target, {"access_token": "not-a-real-token"})
        mode = stat.S_IMODE(os.stat(target).st_mode)
        check("leftover temporary cannot widen a secret", mode == 0o600, oct(mode))


def a_bad_command_value_never_raises():
    """float(None) raised TypeError and killed the command channel for good."""
    fake = FakeRpc()
    with captured_warnings() as warnings:
        rpc.Bridge(fake).handle_command('{"cmd":"inputVolume","value":null}')
    joined = " ".join(warnings)
    # the unknown-command warn also names the command, so pin the wording
    check("a bad inputVolume is named as needing a number",
          "inputVolume needs a number" in joined, joined)
    check("and no command reaches Discord", fake.commands == [], fake.commands)


def a_good_command_value_reaches_discord():
    """Positive control: without it, deleting the branch entirely reads as a pass."""
    fake = FakeRpc()
    rpc.Bridge(fake).handle_command('{"cmd":"inputVolume","value":42}')
    check("a valid inputVolume reaches Discord",
          fake.commands == [("SET_VOICE_SETTINGS", {"input": {"volume": 42.0}})],
          fake.commands)


def as_number_rejects_both_bad_shapes():
    """float(None) raises TypeError but float(\"loud\") raises ValueError."""
    check("as_number rejects None", rpc.as_number(None) is None)
    check("as_number rejects text", rpc.as_number("loud") is None)
    check("as_number accepts a number", rpc.as_number(80) == 80.0)


def an_unknown_command_is_named():
    fake = FakeRpc()
    with captured_warnings() as warnings:
        rpc.Bridge(fake).handle_command('{"cmd":"bogus"}')
    check("an unknown command is named in the warning",
          any("bogus" in line for line in warnings), warnings)


def a_refused_fire_and_forget_command_is_not_silent():
    """Nobody waits on these, so run() used to discard the ERROR frame."""
    frame = (rpc.OP_FRAME, {"cmd": "SET_VOICE_SETTINGS", "evt": "ERROR", "nonce": "7",
                            "data": {"message": "Invalid Channel Id"}})
    bridge = rpc.Bridge(FakeRpc([frame]))
    with captured_warnings() as warnings:
        drive(bridge)
    joined = " ".join(warnings)
    # a generic unexpected-frame warn would quote both, so pin the refusal wording
    check("a refused fire and forget command is reported as a refusal",
          joined.startswith("Discord refused"), joined)
    check("naming the command", "SET_VOICE_SETTINGS" in joined, joined)
    check("and carrying Discord's message", "Invalid Channel Id" in joined, joined)


def the_public_key_is_refused_as_a_secret():
    exact = rpc.PUBLIC_KEY_LENGTH
    check("the right length of hex reads as the Public Key",
          rpc.looks_like_public_key("f" * exact))
    check("the right length of non-hex does not",
          not rpc.looks_like_public_key("g" * exact))
    check("hex one character short does not",
          not rpc.looks_like_public_key("f" * (exact - 1)))
    check("a real secret does not", not rpc.looks_like_public_key("s3cr3t"))


def a_clipped_warning_marks_the_cut():
    """Testing clip() alone leaves a call site free to go back to a bare slice."""
    padding = "9" * (rpc.WARN_INPUT_CHARS + 10)
    with captured_warnings() as warnings:
        rpc.Bridge(FakeRpc()).handle_command("not json " + padding)
    joined = " ".join(warnings)
    check("an over-long command is clipped where it is warned", "..." in joined, joined)
    check("and the whole input is not echoed", padding not in joined, joined)
    check("a short input is left alone",
          rpc.clip(' {"cmd":"mute"} ', rpc.WARN_INPUT_CHARS) == '{"cmd":"mute"}')


def a_refusal_warning_clips_the_command():
    """The other clip call site, on the path a refused command takes."""

    class RefusingRpc(FakeRpc):
        def request(self, cmd, args=None, evt=None):
            raise rpc.RpcRejected("Invalid Channel Id")

    padding = "9" * (rpc.WARN_INPUT_CHARS + 10)
    while not rpc.COMMANDS.empty():
        rpc.COMMANDS.get_nowait()
    rpc.COMMANDS.put('{"cmd":"refresh","pad":"' + padding + '"}')
    with captured_warnings() as warnings:
        rpc.Bridge(RefusingRpc()).drain_commands()
    joined = " ".join(warnings)
    check("a refusal warning clips the command", "..." in joined, joined)
    check("and does not echo the whole input", padding not in joined, joined)


def a_refusal_is_still_an_rpc_error():
    """Every caller that already catches RpcError must keep catching a refusal."""
    check("RpcRejected subclasses RpcError",
          issubclass(rpc.RpcRejected, rpc.RpcError))


def main():
    for case in (leftover_temporary_cannot_widen_a_secret,
                 a_bad_command_value_never_raises,
                 a_good_command_value_reaches_discord,
                 as_number_rejects_both_bad_shapes,
                 an_unknown_command_is_named,
                 a_refused_fire_and_forget_command_is_not_silent,
                 the_public_key_is_refused_as_a_secret,
                 a_clipped_warning_marks_the_cut,
                 a_refusal_warning_clips_the_command,
                 a_refusal_is_still_an_rpc_error):
        case()
    print("\n%d failed" % len(FAILURES) if FAILURES else "\nall passed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
