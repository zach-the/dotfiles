#!/bin/bash
set -e

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLED="$HOME/.config/hypr/plugins/ultrawide-dwindle-improved.so"

# Unload from all possible paths that may have been used
hyprctl plugin unload "$INSTALLED" 2>/dev/null || true
hyprctl plugin unload "$PLUGIN_DIR/ultrawide-dwindle-improved.so" 2>/dev/null || true

make -C "$PLUGIN_DIR"
install -Dm755 "$PLUGIN_DIR/ultrawide-dwindle-improved.so" "$INSTALLED"
hyprctl plugin load "$INSTALLED"
