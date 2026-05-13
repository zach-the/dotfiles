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

---

## Keybinds

> **Hyper** = `Ctrl + Alt + Shift + Super/Cmd`

### macOS

#### Karabiner-Elements

| From | To |
|---|---|
| `Caps Lock` (hold) | Hyper (`Ctrl + Opt + Cmd + Shift`) |
| `Caps Lock` (tap) | `Escape` |
| `Ctrl + H` | `←` (Left Arrow) |
| `Ctrl + J` | `↓` (Down Arrow) |
| `Ctrl + K` | `↑` (Up Arrow) |
| `Ctrl + L` | `→` (Right Arrow) |

#### Hammerspoon

**App launching**

| Keybind | Action |
|---|---|
| `Hyper + T` | Open new WezTerm window on current screen |
| `Hyper + N` | Open new Chrome window on current screen |

**Window tiling**

| Keybind | Action |
|---|---|
| `Hyper + F` | Maximize (fill screen with gaps) |
| `Hyper + Return` | Toggle fullscreen |
| `Hyper + C` | Center window |
| `Hyper + A` | Left half |
| `Hyper + D` | Right half |
| `Hyper + S` | Center half |
| `Hyper + G` | Top half |
| `Hyper + B` | Bottom half |
| `Hyper + U` | Top-left quarter |
| `Hyper + I` | Top-right quarter |
| `Hyper + J` | Bottom-left quarter |
| `Hyper + K` | Bottom-right quarter |
| `Hyper + 1` | First third |
| `Hyper + 2` | Center third |
| `Hyper + 3` | Last third |
| `Hyper + W` | First two-thirds |
| `Hyper + E` | Last two-thirds |
| `Hyper + -` | Make window smaller |
| `Hyper + =` | Make window larger |

**Window management**

| Keybind | Action |
|---|---|
| `Hyper + Q` | Minimize focused window |
| `Hyper + R` | Unminimize all windows |
| `Hyper + M` | Minimize all windows except focused |
| `Hyper + O` | Move window to next display |
| `Hyper + Y` | Move window to previous display |

**Focus**

| Keybind | Action |
|---|---|
| `Cmd + Alt + H` | Focus window to the left |
| `Cmd + Alt + L` | Focus window to the right |
| `Cmd + Alt + K` | Focus window above |
| `Cmd + Alt + J` | Focus window below |

**Space/desktop switching**

| Keybind | Action |
|---|---|
| `Hyper + H` | Previous space |
| `Hyper + L` | Next space |

**Scrolling**

| Keybind | Action |
|---|---|
| `Ctrl + Shift + J` | Scroll down (hold to accelerate) |
| `Ctrl + Shift + K` | Scroll up (hold to accelerate) |

**Misc**

| Keybind | Action |
|---|---|
| `Hyper + Z` | Reload Hammerspoon config |
| `Hyper + P` | Debug spaces (X-ray display) |
| `Cmd + H` | Blocked system-wide (prevents accidental window hide) |

---

### Linux (Hyprland)

#### keyd

| From | To |
|---|---|
| `Caps Lock` (hold) | Hyper (`Ctrl + Meta + Alt + Shift`) |
| `Caps Lock` (tap) | `Escape` |

#### Hyprland

**App launching**

| Keybind | Action |
|---|---|
| `Hyper + T` | Open WezTerm |
| `Hyper + N` | Open Chrome (personal profile) |
| `Hyper + M` | Open Chrome (work profile) |
| `Hyper + R` | Open Rofi launcher |
| `Hyper + E` | Open Nautilus file manager |
| `Hyper + Backspace` | Lock screen (hyprlock) |

**Window management**

| Keybind | Action |
|---|---|
| `Hyper + Return` | Toggle fullscreen |
| `Hyper + F` | Toggle floating |
| `Hyper + Q` | Close active window |
| `Hyper + Z` | Screenshot region to clipboard |
| `Hyper + S` | Toggle scratchpad |
| `Super + Shift + S` | Move window to/from scratchpad |

**Focus**

| Keybind | Action |
|---|---|
| `Super + ←` / `Super + H` | Focus left |
| `Super + →` / `Super + L` | Focus right |
| `Super + ↑` / `Super + K` | Focus up |
| `Super + ↓` / `Super + J` | Focus down |

**Workspace switching**

| Keybind | Action |
|---|---|
| `Hyper + L` | Next workspace |
| `Hyper + H` | Previous workspace |
| `Super + Shift + L` | Move window to next workspace |
| `Super + Shift + H` | Move window to previous workspace |

**Mouse**

| Keybind | Action |
|---|---|
| `Hyper + LMB drag` | Move window |
| `Hyper + RMB drag` | Resize window |

**Media / system keys**

| Keybind | Action |
|---|---|
| `XF86AudioRaiseVolume` | Volume +5% |
| `XF86AudioLowerVolume` | Volume -5% |
| `XF86AudioMute` | Toggle mute |
| `XF86AudioMicMute` | Toggle mic mute |
| `XF86MonBrightnessUp` | Brightness +5% |
| `XF86MonBrightnessDown` | Brightness -5% |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |
| `XF86AudioPlay/Pause` | Play/pause |

**Lid**

| Keybind | Action |
|---|---|
| Lid close | Lock, blank display, suspend |
| Lid open | Turn display back on |

---

## Terminal Keybinds

### tmux

Prefix: `Ctrl + B`

**Sessions / misc**

| Keybind | Action |
|---|---|
| `Prefix + d` | Detach session |
| `Prefix + :` | Command prompt |
| `Prefix + [` | Enter copy/scroll mode |
| `Prefix + r` | Reload tmux config |
| `Prefix + R` | Rename session |
| `Prefix + w` | Choose window/session tree |

**Windows (no prefix)**

| Keybind | Action |
|---|---|
| `Ctrl + T` | New window |
| `Ctrl + W` | Close pane/window |
| `Ctrl + H` | Previous window |
| `Ctrl + L` | Next window |
| `Ctrl + R` | Rename window |

**Panes (no prefix)**

| Keybind | Action |
|---|---|
| `Alt + -` | Split horizontal (new pane below) |
| `Alt + \` | Split vertical (new pane right) |
| `Alt + H` | Focus pane left |
| `Alt + J` | Focus pane down |
| `Alt + K` | Focus pane up |
| `Alt + L` | Focus pane right |

**Panes (with prefix)**

| Keybind | Action |
|---|---|
| `Prefix + ←` | Previous window |
| `Prefix + →` | Next window |
| `Prefix + h` | Swap pane up |
| `Prefix + l` | Swap pane down |

---

### kitty

**Navigation**

| Keybind | Action |
|---|---|
| `Alt + H` | Focus window left |
| `Alt + L` | Focus window right |
| `Alt + K` | Focus window up |
| `Alt + J` | Focus window down |

**Arrow key aliases**

| Keybind | Sends |
|---|---|
| `Ctrl + H` | `←` |
| `Ctrl + J` | `↓` |
| `Ctrl + K` | `↑` |
| `Ctrl + L` | `→` |
| `Alt + Shift + H` | `Ctrl + ←` (word left) |
| `Alt + Shift + L` | `Ctrl + →` (word right) |

**Tabs**

| Keybind | Action |
|---|---|
| `Ctrl + Shift + H` | Previous tab |
| `Ctrl + Shift + L` | Next tab |
| `Cmd + W` | Close window |
| `Ctrl + Shift + 1–10` | Go to tab 1–10 |
| `Ctrl + Shift + Alt + T` | Rename tab |

**Layout**

| Keybind | Action |
|---|---|
| `Alt + T` | New window (launch) |
| `Alt + P` | Move window to top |
| `Alt + N` | Move window forward |
| `Alt + B` | Move window backward |
| `Alt + M` | Toggle mirror layout |

---

### WezTerm

**Copy / paste**

| Keybind | Action |
|---|---|
| `Ctrl + Shift + C` | Copy to clipboard |
| `Ctrl + Shift + V` | Paste from clipboard |

**Font size**

| Keybind | Action |
|---|---|
| `Ctrl + Shift + +` | Increase font size |
| `Ctrl + Shift + -` | Decrease font size |
| `Ctrl + Shift + 0` | Reset font size |

**Splits**

| Keybind | Action |
|---|---|
| `Super + Shift + -` | Split pane vertically (new pane below) |
| `Super + Shift + \` | Split pane horizontally (new pane right) |

**Tabs**

| Keybind | Action |
|---|---|
| `Super + T` | New tab |
| `Super + W` | Close current pane |
| `Super + H` | Previous tab |
| `Super + L` | Next tab |
| `Super + 1–9` | Go to tab 1–9 |

**Pane management**

| Keybind | Action |
|---|---|
| `Alt + P` / `Alt + N` / `Alt + B` | Swap pane with active |
| `Alt + M` | Rotate panes clockwise |
| `Ctrl + Shift + D` | Pop current tab out to new window |
| `Ctrl + Shift + I` | Pop pane from another window into current |

**Arrow key aliases (Linux only)**

| Keybind | Sends |
|---|---|
| `Ctrl + H` | `←` |
| `Ctrl + J` | `↓` |
| `Ctrl + K` | `↑` |
| `Ctrl + L` | `→` |
