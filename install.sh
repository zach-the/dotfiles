#!/bin/bash

# --- SSH mode config ---
# These dotfile keys (from the configs map below) are included when running --ssh
ssh_configs=(
  "$HOME/.bash_aliases"
  "$HOME/.bashrc"
  "$HOME/.config/nvim/init.lua"
  "$HOME/.config/powerline-shell/config.json"
)

# --- Argument parsing ---
mode=""
ssh_only=false
case "$1" in
  -u|--update) mode="update" ;;
  -f|--fill)   mode="fill" ;;
  --ssh)
    mode="fill"
    ssh_only=true
    ;;
  *)
    echo "Usage: $0 --update|-u | --fill|-f | --ssh"
    exit 1
    ;;
esac

# Returns 0 if the block should run
should_process() {
  local path="$1"
  local dot="$2"

  # Case 1: Broken/stale symlink (always process/fix these)
  if [ -L "$path" ] && [ ! -e "$path" ]; then
    return 0
  fi

  if [ "$mode" = "fill" ]; then
    # Process only if it doesn't exist at all
    [ ! -e "$path" ]
  elif [ "$mode" = "update" ]; then
    # Process if it exists but differs from the dotfile
    [ -e "$path" ] && ! diff -rq "$path" "$dot" > /dev/null 2>&1
  fi
}

# --- Config paths ---
# (Paths remain the same as your current setup)
declare -A configs=(
  ["$HOME/.config/nvim/init.lua"]="$HOME/dotfiles/nvim-init.lua"
  ["$HOME/.bashrc"]="$HOME/dotfiles/bashrc"
  ["$HOME/.bash_aliases"]="$HOME/dotfiles/bash_aliases"
  ["$HOME/.config/kitty/kitty.conf"]="$HOME/dotfiles/kitty/kitty.conf"
  ["$HOME/.config/kitty/theme.conf"]="$HOME/dotfiles/kitty/theme.conf"
  ["$HOME/.config/waybar"]="$HOME/dotfiles/waybar"
  ["$HOME/.config/mpv/mpv.conf"]="$HOME/dotfiles/mpv.conf"
  ["$HOME/.config/powerline-shell/config.json"]="$HOME/dotfiles/powerline-shell.config.json"
  ["$HOME/.config/rofi/config.rasi"]="$HOME/dotfiles/rofi-config.rasi"
)

# --- Execution ---

for path in "${!configs[@]}"; do
  dot="${configs[$path]}"

  # Skip entries not in ssh_configs when running --ssh
  if $ssh_only; then
    match=false
    for ssh_path in "${ssh_configs[@]}"; do
      [ "$path" = "$ssh_path" ] && match=true && break
    done
    $match || continue
  fi

  if should_process "$path" "$dot"; then
    echo "Linking $path"
    
    # Ensure parent directory exists
    mkdir -p "$(dirname "$path")"

    # If it's a stale link or a real file, get it out of the way
    # We use -L to catch the stale link and -e for real files
    if [ -L "$path" ] || [ -e "$path" ]; then
      # If it's a real file (not a link), maybe you want a backup? 
      # Otherwise, just rm -rf to clear the path.
      rm -rf "$path"
    fi

    ln -s "$dot" "$path"
  fi
done

# --- Special cases for Keyd (requires sudo) ---
keyd_path="/etc/keyd/default.conf"
keyd_dot="$HOME/dotfiles/keyd-default.conf"

if ! $ssh_only && should_process "$keyd_path" "$keyd_dot"; then
  echo "Setting up keyd..."
  sudo pacman -S --needed --noconfirm keyd
  sudo mkdir -p /etc/keyd/
  [ -L "$keyd_path" ] || [ -e "$keyd_path" ] && sudo rm -f "$keyd_path"
  sudo ln -s "$keyd_dot" "$keyd_path"
  sudo systemctl enable --now keyd
fi
