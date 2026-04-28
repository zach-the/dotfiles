#!/bin/bash
set -e

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SO="$PLUGIN_DIR/ultrawide-dwindle.so"

hyprctl plugin unload "$SO" 2>/dev/null || true
make -C "$PLUGIN_DIR"
hyprctl plugin load "$SO"
