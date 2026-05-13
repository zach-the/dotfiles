# dotfiles

Personal configuration files for macOS and Linux, managed via symlinks.

## Structure

Each top-level file or directory is a config that gets symlinked into the appropriate location on the system. Nothing is copied — the repo files are the live configs, so editing them in place changes behavior immediately.

| Config | Source | Destination |
|---|---|---|
| Neovim | `nvim-init.lua` | `~/.config/nvim/init.lua` |
| Bash RC | `bashrc` | `~/.bashrc` |
| Bash Aliases | `bash_aliases` | `~/.bash_aliases` |
| Powerline Shell | `powerline-shell.config.json` | `~/.config/powerline-shell/config.json` |
| WezTerm | `wezterm/` | `~/.config/wezterm` |
| TMUX | `tmux.conf` | `~/.tmux.conf` |
| **macOS only** | | |
| Hammerspoon | `hammerspoon-init.lua` | `~/.hammerspoon/init.lua` |
| Karabiner | `karabiner/` | `~/.config/karabiner` |
| **Linux only** | | |
| Waybar | `waybar/` | `~/.config/waybar` |
| Rofi | `rofi-config.rasi` | `~/.config/rofi/config.rasi` |
| Keyd | `keyd-default.conf` | `/etc/keyd/default.conf` |
| MPV | `mpv/` | `~/.config/mpv` |
| Synopsys PT | `synopsys_pt.setup` | `~/.synopsys_pt.setup` |

## Setup

Run `install.sh` to create all symlinks:

```bash
./install.sh
```

The script auto-detects the OS (macOS or Linux) and only processes the relevant configs. For each entry it shows the source, destination, and current state, then prompts:

- **s** — skip
- **p** — pave (remove whatever is at the destination and link)
- **b** — backup (move the existing file to `<destination>.bak`, then link)

Destinations outside `$HOME` (e.g. `/etc/keyd/default.conf`) are handled with `sudo` automatically.

After linking, the script optionally enables and starts the `keyd` service on Linux if that config was linked.
