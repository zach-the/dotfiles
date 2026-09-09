#!/usr/bin/env python3
"""waybar on-click target for any popup_daemon.py consumer, e.g.:
    popup_client.py toggle audio

Replaces the old per-consumer launch scripts (audio_menu_launch.sh's
role) now that there's a persistent daemon to talk to instead of a
process to spawn. Fails visibly (a low-priority notification) rather
than silently if the daemon isn't running, since a plain on-click
command gives no other feedback channel."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_ipc


def main():
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <cmd> <target>", file=sys.stderr)
        return 2

    try:
        result = popup_ipc.send(sys.argv[1], sys.argv[2])
    except OSError:
        subprocess.run(["notify-send", "-u", "low", "popup daemon not running"], check=False)
        return 1

    if not result.get("ok"):
        subprocess.run(["notify-send", "-u", "low", f"popup error: {result.get('error', 'unknown')}"], check=False)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
