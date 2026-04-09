#!/bin/bash

if [ ! -f ~/.config/nvim/init.lua ]; then
  echo "linking nvim init.lua"
  mkdir -p ~/.config/nvim
  [ -f ~/.config/nvim/init.lua ] && mv ~/.config/nvim/init.lua{,.old}
  ln -s ~/dotfiles/nvim-init.lua ~/.config/nvim/init.lua
fi

echo "linking bash stuff"
[ -f ~/.bashrc ] && mv ~/.bashrc{,.old}
[ -f ~/.bash_aliases ] && mv ~/.bash_aliases{,.old}
ln -s ~/dotfiles/bashrc ~/.bashrc
ln -s ~/dotfiles/bash_aliases ~/.bash_aliases

echo "linking kitty conf"
mkdir -p ~/.config/kitty
[ -f ~/.config/kitty/kitty.conf ] && mv ~/.config/kitty/kitty.conf{,.old}
ln -s ~/dotfiles/kitty.conf ~/.config/kitty/kitty.conf
git clone https://github.com/kovidgoyal/kitty-themes.git ~/kitty-themes > /dev/null 2>&1
rm -rf ~/.config/kitty/themes
mv ~/kitty-themes/themes ~/.config/kitty/themes
[ -f ~/.config/kitty/theme.conf ] && mv ~/.config/kitty/theme.conf{,.old}
ln -s ~/.config/kitty/themes/Molokai.conf ~/.config/kitty/theme.conf
rm -rf ~/kitty-themes

echo "linking waybar"
[ -d ~/.config/waybar ] && mv ~/.config/waybar{,.old}
ln -s ~/dotfiles/waybar ~/.config/waybar

echo "linking mpv conf"
mkdir -p ~/.config/mpv
[ -f ~/.config/mpv/mpv.conf ] && mv ~/.config/mpv/mpv.conf{,.old}
ln -s ~/dotfiles/mpv.conf ~/.config/mpv/mpv.conf

echo "installing powerline-shell"
sudo pacman -S python-setuptools
git clone https://github.com/b-ryan/powerline-shell ~/powerline-shell > /dev/null 2>&1
cd ~/powerline-shell
sudo python setup.py install > /dev/null 2>&1
mkdir -p ~/.config/powerline-shell
[ -f ~/.config/powerline-shell/config.json ] && mv ~/.config/powerline-shell/config.json{,.old}
ln -s ~/dotfiles/powerline-shell.config.json ~/.config/powerline-shell/config.json
sudo rm -rf ~/powerline-shell

echo "setting up keyd, so you can have caps lock = hyper"
sudo pacman -S keyd
sudo mkdir -p /etc/keyd/
[ -f /etc/keyd/default.conf ] && sudo mv /etc/keyd/default.conf{,.old}
sudo ln -s ~/dotfiles/keyd-default.conf /etc/keyd/default.conf
sudo systemctl enable --now keyd

echo "setting up rofi drun config"
mkdir -p ~/.config/rofi
[ -f ~/.config/rofi/config.rasi ] && mv ~/.config/rofi/config.rasi{,.old}
    ln -s ~/dotfiles/rofi-config.rasi ~/.config/rofi/config.rasi
