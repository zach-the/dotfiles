#!/bin/bash

# --- Argument parsing ---
mode=""
case "$1" in
  -u|--update) mode="update" ;;
  -f|--fill)   mode="fill" ;;
  *)
    echo "Usage: $0 --update|-u | --fill|-f"
    echo "  --fill   (-f): link config only if the path file does not exist"
    echo "  --update (-u): link config only if the path file differs from the dot file"
    exit 1
    ;;
esac

# Returns 0 if the block should run based on the mode
should_process() {
  local path="$1"
  local dot="$2"
  if [ "$mode" = "fill" ]; then
    [ ! -e "$path" ]
  elif [ "$mode" = "update" ]; then
    [ -e "$path" ] && ! diff -rq "$path" "$dot" > /dev/null 2>&1
  fi
}

# --- Config paths ---
nvim_path=~/.config/nvim/init.lua
nvim_dot=~/dotfiles/nvim-init.lua

bashrc_path=~/.bashrc
bashrc_dot=~/dotfiles/bashrc

bash_aliases_path=~/.bash_aliases
bash_aliases_dot=~/dotfiles/bash_aliases

kitty_path=~/.config/kitty/kitty.conf
kitty_dot=~/dotfiles/kitty.conf

waybar_path=~/.config/waybar
waybar_dot=~/dotfiles/waybar

mpv_path=~/.config/mpv/mpv.conf
mpv_dot=~/dotfiles/mpv.conf

powerline_path=~/.config/powerline-shell/config.json
powerline_dot=~/dotfiles/powerline-shell.config.json

keyd_path=/etc/keyd/default.conf
keyd_dot=~/dotfiles/keyd-default.conf

rofi_path=~/.config/rofi/config.rasi
rofi_dot=~/dotfiles/rofi-config.rasi

# --- Links ---

if should_process "$nvim_path" "$nvim_dot"; then
  echo "linking nvim init.lua"
  mkdir -p ~/.config/nvim
  [ -f "$nvim_path" ] && mv "$nvim_path"{,.old}
  ln -s "$nvim_dot" "$nvim_path"
fi

if should_process "$bashrc_path" "$bashrc_dot"; then
  echo "linking bashrc"
  [ -f "$bashrc_path" ] && mv "$bashrc_path"{,.old}
  ln -s "$bashrc_dot" "$bashrc_path"
fi

if should_process "$bash_aliases_path" "$bash_aliases_dot"; then
  echo "linking bash_aliases"
  [ -f "$bash_aliases_path" ] && mv "$bash_aliases_path"{,.old}
  ln -s "$bash_aliases_dot" "$bash_aliases_path"
fi

if should_process "$kitty_path" "$kitty_dot"; then
  echo "linking kitty conf"
  mkdir -p ~/.config/kitty
  [ -f "$kitty_path" ] && mv "$kitty_path"{,.old}
  ln -s "$kitty_dot" "$kitty_path"
  git clone https://github.com/kovidgoyal/kitty-themes.git ~/kitty-themes > /dev/null 2>&1
  rm -rf ~/.config/kitty/themes
  mv ~/kitty-themes/themes ~/.config/kitty/themes
  [ -f ~/.config/kitty/theme.conf ] && mv ~/.config/kitty/theme.conf{,.old}
  ln -s ~/.config/kitty/themes/Molokai.conf ~/.config/kitty/theme.conf
  rm -rf ~/kitty-themes
fi

if should_process "$waybar_path" "$waybar_dot"; then
  echo "linking waybar"
  [ -d "$waybar_path" ] && mv "$waybar_path"{,.old}
  ln -s "$waybar_dot" "$waybar_path"
fi

if should_process "$mpv_path" "$mpv_dot"; then
  echo "linking mpv conf"
  mkdir -p ~/.config/mpv
  [ -f "$mpv_path" ] && mv "$mpv_path"{,.old}
  ln -s "$mpv_dot" "$mpv_path"
fi

if should_process "$powerline_path" "$powerline_dot"; then
  echo "installing powerline-shell"
  sudo pacman -S python-setuptools
  git clone https://github.com/b-ryan/powerline-shell ~/powerline-shell > /dev/null 2>&1
  cd ~/powerline-shell
  sudo python setup.py install > /dev/null 2>&1
  mkdir -p ~/.config/powerline-shell
  [ -f "$powerline_path" ] && mv "$powerline_path"{,.old}
  ln -s "$powerline_dot" "$powerline_path"
  sudo rm -rf ~/powerline-shell
fi

if should_process "$keyd_path" "$keyd_dot"; then
  echo "setting up keyd"
  sudo pacman -S keyd
  sudo mkdir -p /etc/keyd/
  [ -f "$keyd_path" ] && sudo mv "$keyd_path"{,.old}
  sudo ln -s "$keyd_dot" "$keyd_path"
  sudo systemctl enable --now keyd
fi

if should_process "$rofi_path" "$rofi_dot"; then
  echo "setting up rofi drun config"
  mkdir -p ~/.config/rofi
  [ -f "$rofi_path" ] && mv "$rofi_path"{,.old}
  ln -s "$rofi_dot" "$rofi_path"
fi
