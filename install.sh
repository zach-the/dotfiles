#!/bin/bash

DOTFILES="$HOME/dotfiles"

# --- Config list ---
# Every 3 elements form one entry: "Name" "source" "destination"
configs=(
  "Neovim"           "$DOTFILES/nvim-init.lua"                "$HOME/.config/nvim/init.lua"
  "Bash RC"          "$DOTFILES/bashrc"                       "$HOME/.bashrc"
  "Bash Aliases"     "$DOTFILES/bash_aliases"                 "$HOME/.bash_aliases"
  "Kitty"            "$DOTFILES/kitty"                        "$HOME/.config/kitty"
  "Waybar"           "$DOTFILES/waybar"                       "$HOME/.config/waybar"
  "MPV"              "$DOTFILES/mpv.conf"                     "$HOME/.config/mpv/mpv.conf"
  "Powerline Shell"  "$DOTFILES/powerline-shell.config.json"  "$HOME/.config/powerline-shell/config.json"
  "Rofi"             "$DOTFILES/rofi-config.rasi"             "$HOME/.config/rofi/config.rasi"
  "Keyd"             "$DOTFILES/keyd-default.conf"            "/etc/keyd/default.conf"
  "WezTerm"          "$DOTFILES/wezterm"                      "$HOME/.config/wezterm"
  "Hammerspoon"      "$DOTFILES/hammerspoon-init.lua"         "$HOME/.hammerspoon/init.lua"
  "Karabiner"        "$DOTFILES/karabiner"                    "$HOME/.config/karabiner"
  "Ghostty"          "$DOTFILES/ghostty-config"               "$HOME/.config/ghostty/config"
  "TMUX"             "$DOTFILES/tmux.conf"                    "$HOME/.tmux.conf"
)

# --- Helpers ---

# Use sudo for paths outside $HOME
maybe_sudo() {
  local path="$1"
  [[ "$path" != "$HOME"* ]] && echo "sudo" || echo ""
}

link_entry() {
  local src="$1" dst="$2" choice="$3"
  local sudo_cmd
  sudo_cmd=$(maybe_sudo "$dst")

  case "$choice" in
    p)
      $sudo_cmd mkdir -p "$(dirname "$dst")"
      $sudo_cmd rm -rf "$dst"
      $sudo_cmd ln -s "$src" "$dst"
      echo "  Linked."
      ;;
    b)
      $sudo_cmd mkdir -p "$(dirname "$dst")"
      if [ -e "$dst" ] || [ -L "$dst" ]; then
        $sudo_cmd mv "$dst" "${dst}.bak"
        echo "  Backed up to ${dst}.bak"
      fi
      $sudo_cmd ln -s "$src" "$dst"
      echo "  Linked."
      ;;
  esac
}

# --- Main loop ---

for (( i=0; i<${#configs[@]}; i+=3 )); do
  name="${configs[i]}"
  src="${configs[i+1]}"
  dst="${configs[i+2]}"

  echo ""
  echo "[$name]"
  echo "  $src"
  echo "  -> $dst"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "  (already linked correctly — skipping)"
    continue
  elif [ -L "$dst" ] && [ ! -e "$dst" ]; then
    echo "  (stale symlink)"
  elif [ -L "$dst" ]; then
    echo "  (symlink to somewhere else: $(readlink "$dst"))"
  elif [ -e "$dst" ]; then
    echo "  (exists as real file/dir)"
  else
    echo "  (not present)"
  fi

  sudo_note=""
  [[ "$dst" != "$HOME"* ]] && sudo_note=" (requires sudo)"

  while true; do
    read -rp "  [s]kip / [p]ave / [b]ackup?${sudo_note} " choice
    case "$choice" in
      s) echo "  Skipping."; break ;;
      p|b) link_entry "$src" "$dst" "$choice"; break ;;
      *) echo "  Please enter s, p, or b." ;;
    esac
  done
done

# --- Post-link steps for entries that need extra setup ---

echo ""
if [ -L "/etc/keyd/default.conf" ] && [ -e "/etc/keyd/default.conf" ]; then
  read -rp "[Keyd] Enable and start keyd service? [y/N] " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed --noconfirm keyd
    sudo systemctl enable --now keyd
    echo "  Done."
  fi
fi
