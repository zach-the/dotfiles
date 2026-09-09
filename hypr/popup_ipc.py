#!/usr/bin/env python3
"""Wire protocol between popup_client.py (waybar's on-click target) and
popup_daemon.py: newline-delimited JSON over a Unix socket at
$XDG_RUNTIME_DIR/hypr-popup-daemon.sock, one request/response per
connection.

Request: {"cmd": "toggle"|"open"|"close", "target": "audio"}
  ("target": "*" for "close" means "whichever popup is currently open,
  if any". An "args" key is reserved for future consumers — e.g. a wifi
  target prefilling an SSID — but nothing sends it yet.)
Response: {"ok": true} or {"ok": false, "error": "..."}
"""
import json
import os
import socket

SOCKET_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "hypr-popup-daemon.sock")


def send(cmd, target=None, timeout=0.5, **extra):
    """Connect, send one request line, read one response line back.
    Raises OSError (e.g. ConnectionRefusedError, FileNotFoundError) if
    the daemon isn't reachable — callers decide how to surface that."""
    req = {"cmd": cmd, **extra}
    if target is not None:
        req["target"] = target

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(SOCKET_PATH)
        sock.sendall((json.dumps(req) + "\n").encode())

        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
    line, _, _ = buf.partition(b"\n")
    return json.loads(line.decode()) if line else {"ok": False, "error": "no response"}
