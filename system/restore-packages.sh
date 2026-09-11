#!/bin/bash
# Reinstall every package that was explicitly installed on the original system.
# Run this after a base Arch install, before ./install.sh.
set -euo pipefail

DOTFILES="$HOME/dotfiles"

echo "==> Installing native (official repo) packages..."
sudo pacman -S --needed - < "$DOTFILES/system/pkglist-native.txt"

if ! command -v yay >/dev/null && ! command -v paru >/dev/null; then
  echo "==> No AUR helper found. Bootstrapping yay..."
  sudo pacman -S --needed --noconfirm git base-devel
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  (cd "$tmpdir/yay" && makepkg -si --noconfirm)
  rm -rf "$tmpdir"
fi

AUR_HELPER=$(command -v yay || command -v paru)
echo "==> Installing AUR packages with $AUR_HELPER..."
"$AUR_HELPER" -S --needed - < "$DOTFILES/system/pkglist-aur.txt"

echo "==> Done. Package set restored."
