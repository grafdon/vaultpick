#!/usr/bin/env python3
"""End-to-end test: drive the real fzf UI of vaultpick in a pseudo-terminal.

rbw and the clipboard are the stand-ins from tests/stubs; fzf is the real
one. Skipped (exit 0) when fzf is missing or older than 0.63.
"""
import fcntl
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ID = "00000000-0000-4000-8000-%012d"
TIMEOUT = 15


def fzf_ok():
    fzf = shutil.which("fzf")
    if not fzf:
        return False
    out = subprocess.run([fzf, "--version"], capture_output=True, text=True).stdout
    m = re.match(r"(\d+)\.(\d+)", out)
    return bool(m) and (int(m.group(1)), int(m.group(2))) >= (0, 63)


class Session:
    """vaultpick running in a pty, with helpers to type and to wait for text."""

    def __init__(self, tmp, args=(), env=None, cols=140, rows=40):
        self.clip = os.path.join(tmp, "clipboard")
        open(self.clip, "w").close()
        full_env = {
            "PATH": os.path.join(ROOT, "tests", "stubs") + os.pathsep + os.environ["PATH"],
            "HOME": os.path.join(tmp, "home"),
            "XDG_STATE_HOME": os.path.join(tmp, "state"),
            "XDG_CACHE_HOME": os.path.join(tmp, "cache"),
            "XDG_CONFIG_HOME": os.path.join(tmp, "config"),
            "STUB_CLIP": self.clip,
            "WAYLAND_DISPLAY": "test",
            "TERM": "xterm-256color",
            "LANG": "C.UTF-8",
            "VAULTPICK_ASCII": "0",
            # A login shell that is not a POSIX shell must not matter.
            "SHELL": "/nonexistent/fish",
        }
        full_env.update(env or {})
        os.makedirs(full_env["HOME"], exist_ok=True)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvpe(os.path.join(ROOT, "vaultpick"), ["vaultpick", *args], full_env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.output = ""
        self.seen = 0
        self.status = None

    def read(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.05)
            if not ready:
                continue
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                return False
            if not data:
                return False
            self.output += data.decode("utf-8", "replace")
        return True

    def wait_for(self, text, what):
        """Wait until text shows up after the last text that was waited for."""
        end = time.time() + TIMEOUT
        while True:
            at = self.output.find(text, self.seen)
            if at >= 0:
                self.seen = at + len(text)
                return
            if time.time() > end or not self.read(0.1):
                break
        if self.output.find(text, self.seen) >= 0:
            return
        raise AssertionError(f"{what}: never saw {text!r}\n--- screen ---\n{self.output[-3000:]}")

    def send(self, keys):
        os.write(self.fd, keys.encode())

    def wait_clip(self, expected, what):
        end = time.time() + TIMEOUT
        while time.time() < end:
            self.read(0.1)
            if open(self.clip).read() == expected:
                return
        raise AssertionError(f"{what}: clipboard is {open(self.clip).read()!r}, expected {expected!r}")

    def finish(self):
        end = time.time() + TIMEOUT
        while time.time() < end:
            self.read(0.1)
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.status = os.waitstatus_to_exitcode(status)
                return self.status
        os.kill(self.pid, 9)
        raise AssertionError("vaultpick did not exit")


def check(name, fn):
    with tempfile.TemporaryDirectory() as tmp:
        try:
            fn(tmp)
        except AssertionError as error:
            print(f"  FAIL {name}\n{error}", file=sys.stderr)
            return False
    print(f"  ok   {name}")
    return True


def copy_keeps_list_open(tmp):
    s = Session(tmp, ["github"])
    s.wait_for("octo-demo", "list")
    s.send("\r")
    s.wait_clip("demo-pw-github", "enter copies the password")
    s.wait_for("PASSWORD", "status line")
    s.send("\x0f")  # ctrl-o
    s.wait_clip("123456", "ctrl-o copies the TOTP code")
    s.wait_for("TOTP", "status line")
    s.send("\x15")  # ctrl-u
    s.wait_clip("octo-demo", "ctrl-u copies the username")
    s.wait_for("USERNAME", "status line")
    assert "demo-pw" not in s.output, "the password showed up on screen"
    s.send("\x1b")
    assert s.finish() == 0, f"esc should exit 0, got {s.status}"
    history = open(os.path.join(tmp, "state", "vaultpick", "history")).read().split()
    assert history == [ID % 1], f"history is {history}"


def show_prints_entry(tmp):
    s = Session(tmp, ["nas"])
    s.wait_for("jane", "list")
    s.send("\x13")  # ctrl-s
    s.wait_for("Username: jane", "ctrl-s prints the entry")
    assert s.finish() == 0, f"show should exit 0, got {s.status}"


def edit_option(tmp):
    s = Session(tmp, ["-e", "router"])
    s.wait_for("admin", "list")
    s.send("\r")
    s.wait_for("would edit Home router", "enter edits with -e")
    assert s.finish() == 0, f"edit should exit 0, got {s.status}"


def no_match_narrow_terminal(tmp):
    s = Session(tmp, ["no-such-entry"], env={"VAULTPICK_THEME": "mocha"}, cols=70, rows=24)
    s.wait_for("0/12", "match counter")
    s.send("\r")  # nothing to act on: fzf ignores it
    s.read(0.5)
    assert open(s.clip).read() == "", "something was copied from an empty list"
    s.send("\x1b")
    assert s.finish() == 0, f"esc should exit 0, got {s.status}"


def ascii_no_color(tmp):
    s = Session(tmp, ["apple"], env={"VAULTPICK_ASCII": "1", "NO_COLOR": "1", "LANG": "C"})
    s.wait_for("appleid.apple.com", "list")
    s.send("\r")
    s.wait_clip("demo-pw-apple", "enter copies the password")
    s.wait_for("ok PASSWORD", "plain status line")
    s.send("\x1b")
    assert s.finish() == 0, f"esc should exit 0, got {s.status}"


def theme_key(tmp):
    s = Session(tmp, ["-o", "github"])
    s.wait_for("octo-demo", "list")
    s.send("\x14")  # ctrl-t
    s.wait_for("THEME", "status line after ctrl-t")
    s.wait_for("amber", "the new theme is named")
    saved = open(os.path.join(tmp, "config", "vaultpick", "theme")).read()
    assert saved == "amber\n", f"saved theme is {saved!r}"
    s.send("\r")  # same query, same action as before
    s.wait_clip("123456", "enter still copies the TOTP code")
    s.send("\x14")
    s.wait_for("mocha", "ctrl-t again")
    s.send("\x1b")
    assert s.finish() == 0, f"esc should exit 0, got {s.status}"


def main():
    if not fzf_ok():
        print("  skip end-to-end tests: fzf 0.63+ not found")
        return 0
    tests = [copy_keeps_list_open, show_prints_entry, edit_option, no_match_narrow_terminal, ascii_no_color,
             theme_key]
    # The rbw cache the TOTP markers come from is not needed here.
    failed = [t.__name__ for t in tests if not check(t.__name__.replace("_", " "), t)]
    print(f"{len(tests)} end-to-end tests, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
