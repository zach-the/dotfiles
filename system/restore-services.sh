#!/bin/bash
# Install custom systemd units and re-enable everything that was enabled
# on the original system. Run after restore-packages.sh and install.sh.
set -euo pipefail

DOTFILES="$HOME/dotfiles"

echo "==> Installing custom systemd units..."
sudo cp "$DOTFILES"/system/systemd-units/*.service /etc/systemd/system/
sudo systemctl daemon-reload

echo "==> Enabling system services..."
while read -r unit; do
  [ -z "$unit" ] && continue
  sudo systemctl enable "$unit" || echo "  (skipped $unit — not installed?)"
done < "$DOTFILES/system/systemd-enabled.txt"

echo "==> Enabling user services..."
while read -r unit; do
  [ -z "$unit" ] && continue
  systemctl --user enable "$unit" || echo "  (skipped $unit — not installed?)"
done < "$DOTFILES/system/systemd-enabled-user.txt"

echo "==> Done. Reboot to start everything (or start units manually)."
echo "NOTE: minecraft.service expects a server at ~/mc-server and geyser.service"
echo "      expects ~/geyser — those directories are data, not covered by dotfiles."
