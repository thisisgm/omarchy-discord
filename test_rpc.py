#!/usr/bin/env python3
"""Adversarial cases for rpc.py. Each one failed before the fix it guards.

Run with: python3 test_rpc.py
"""

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
    check("as_number rejects None", rpc.as_number(None) is None)
    check("as_number rejects text", rpc.as_number("loud") is None)
    check("as_number accepts a number", rpc.as_number(80) == 80.0)


def the_public_key_is_refused_as_a_secret():
    check("64 hex characters read as the Public Key",
          rpc.looks_like_public_key("f" * 64))
    check("a real secret does not", not rpc.looks_like_public_key("s3cr3t"))


def a_refusal_is_still_an_rpc_error():
    """Every caller that already catches RpcError must keep catching a refusal."""
    check("RpcRejected subclasses RpcError",
          issubclass(rpc.RpcRejected, rpc.RpcError))


def main():
    for case in (leftover_temporary_cannot_widen_a_secret,
                 a_bad_command_value_never_raises,
                 the_public_key_is_refused_as_a_secret,
                 a_refusal_is_still_an_rpc_error):
        case()
    print("\n%d failed" % len(FAILURES) if FAILURES else "\nall passed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
