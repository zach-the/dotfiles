#!/usr/bin/env bash
# Keeps a NoInputNoOutput Bluetooth pairing agent registered as bluetoothd's
# default for the whole Hyprland session. Without this, connecting to any
# not-yet-paired device that needs SSP confirmation fails outright ("No
# agent available for request type 2" in bluetoothd's log) — bluetoothctl
# only holds an agent while its own process/D-Bus connection is alive, and
# a one-shot `bluetoothctl connect <mac>` used by bluetooth_menu.py exits
# the instant it issues the connect command, typically before the async
# confirmation request even arrives. A full desktop environment normally
# has something like this running in the background already; this
# Hyprland setup doesn't, so bluetooth_menu.py needs one of its own.
#
# Feeding bluetoothctl its setup commands and then never closing stdin
# (sleep infinity holds the pipe's write end open) keeps it — and its
# agent registration — alive indefinitely. NoInputNoOutput forces pairing
# method negotiation down to Just Works, which skips confirmation
# entirely rather than needing anything to actually answer a prompt.
exec bash -c '{ printf "agent NoInputNoOutput\ndefault-agent\n"; sleep infinity; } | bluetoothctl >/dev/null 2>&1'
