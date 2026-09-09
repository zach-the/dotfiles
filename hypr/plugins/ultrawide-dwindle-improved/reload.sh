#!/bin/bash
set -e
# NOTE: hyprctl plugin unload does NOT fully release the previously loaded
# code for a tiled algorithm registered via HyprlandAPI::addTiledAlgo — the
# first registration of "ultrawide-dwindle-improved" in a given Hyprland
# process stays authoritative no matter how many times you unload/rebuild/
# reload after that (verified: /proc/<hyprland-pid>/maps keeps pointing at
# the original, now-deleted-on-disk inode even after a clean cycle here).
# This script still rebuilds and installs the current code so it's ready to
# go, but you MUST fully restart Hyprland (logout/login or reboot) to
# actually pick up any change — hot-reloading this plugin only works the
# very first time it's ever loaded in a session.

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLED="$HOME/.config/hypr/plugins/ultrawide-dwindle-improved.so"

# Unload from all possible paths that may have been used
hyprctl plugin unload "$INSTALLED" 2>/dev/null || true
hyprctl plugin unload "$PLUGIN_DIR/ultrawide-dwindle-improved.so" 2>/dev/null || true

make -C "$PLUGIN_DIR"
install -Dm755 "$PLUGIN_DIR/ultrawide-dwindle-improved.so" "$INSTALLED"
hyprctl plugin load "$INSTALLED"
