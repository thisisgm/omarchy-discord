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
    bridge = rpc.Bridge(fake)
    with captured_warnings() as warnings:
        bridge.handle_command('{"cmd":"inputVolume","value":null}')
    check("a bad inputVolume warns rather than raising",
          any("inputVolume" in line for line in warnings), warnings)
    check("and no command reaches Discord", fake.commands == [], fake.commands)


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
    check("a refused fire and forget command names the command",
          "SET_VOICE_SETTINGS" in joined, joined)
    check("and carries Discord's message", "Invalid Channel Id" in joined, joined)


def the_public_key_is_refused_as_a_secret():
    check("64 hex characters read as the Public Key",
          rpc.looks_like_public_key("f" * 64))
    check("64 non-hex characters do not", not rpc.looks_like_public_key("g" * 64))
    check("63 hex characters do not", not rpc.looks_like_public_key("f" * 63))
    check("a real secret does not", not rpc.looks_like_public_key("s3cr3t"))


def a_clipped_warning_marks_the_cut():
    long_line = '{"cmd":"inputVolume","value":' + "9" * 90 + "}"
    clipped = rpc.clip(long_line, rpc.WARN_INPUT_CHARS)
    check("an over-long input is marked as clipped", clipped.endswith("..."), clipped)
    check("a short input is left alone", rpc.clip(' {"cmd":"mute"} ', 80) == '{"cmd":"mute"}')


def a_refusal_is_still_an_rpc_error():
    """Every caller that already catches RpcError must keep catching a refusal."""
    check("RpcRejected subclasses RpcError",
          issubclass(rpc.RpcRejected, rpc.RpcError))


def main():
    for case in (leftover_temporary_cannot_widen_a_secret,
                 a_bad_command_value_never_raises,
                 an_unknown_command_is_named,
                 a_refused_fire_and_forget_command_is_not_silent,
                 the_public_key_is_refused_as_a_secret,
                 a_clipped_warning_marks_the_cut,
                 a_refusal_is_still_an_rpc_error):
        case()
    print("\n%d failed" % len(FAILURES) if FAILURES else "\nall passed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
