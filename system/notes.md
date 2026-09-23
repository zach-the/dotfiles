# System snapshot (Arch install, captured 2026-09-10)

Everything needed to rebuild the current Arch setup from scratch, aside from
personal data/files. See the main README for what `install.sh` does.

> **Using an AI agent to do this restore?** Have it read
> [`AGENT.md`](AGENT.md) first — it's a runbook aimed specifically at that,
> with the questions to confirm up front and how to handle failures.

## Restore order

1. Install Arch (base system + network + a `zach` user).
2. Clone this repo to `~/dotfiles`.
3. `./system/restore-packages.sh` — installs all native + AUR packages (bootstraps `yay` if needed).
4. `./install.sh` — symlinks all configs, including the `system/` ones below.
5. `./system/restore-services.sh` — installs the two custom systemd units and re-enables every service that was enabled.
6. Reboot.

## What's captured here

| File | What it is |
|---|---|
| `pkglist-native.txt` | Explicitly-installed official repo packages (`pacman -Qqe` minus foreign) |
| `pkglist-aur.txt` | Explicitly-installed AUR packages (`pacman -Qqem`) |
| `systemd-enabled.txt` | Enabled system-level systemd units |
| `systemd-enabled-user.txt` | Enabled `--user` systemd units |
| `systemd-units/*.service` | Custom unit files not owned by any package (Minecraft server, Geyser bedrock proxy) |
| `greetd-config.toml` | Greeter config — logs straight into Hyprland via `start-hyprland` |
| `udev-rules/70-keychron.rules` | Keychron keyboard hidraw permissions (for QMK/Vial tools) |
| `udev-rules/99-vial.rules` | Vial keyboard hidraw permissions |
| `udev-rules/60-i2c-uaccess.rules` | User access to `/dev/i2c-*` so `ddcutil` can set external monitor brightness (`hypr/brightness.py`) |
| `modules-load.d/i2c-dev.conf` | Load `i2c-dev` at boot (needed for `/dev/i2c-*`) |
| `modprobe.d/webcam-late-load.conf` | Blacklist `intel_cvs`/`ov08x40`/`intel_ipu7_isys` from autoload (see quirk below) |
| `networkmanager-conf.d/20-connectivity.conf` | Custom NetworkManager connectivity-check setting |
| `mimeapps.list` | Default application associations (Firefox for web, evince for PDF, qimgv for images, etc.) |

## System-level facts (not files, just settings to redo manually)

- **Hostname:** `monkey`
- **Timezone:** `America/Denver`
- **Locale:** `en_US.UTF-8`
- **Console keymap:** `us`
- **Kernel:** `linux` (stock, not LTS/zen)
- **Bootloader:** systemd-boot (`/boot/loader/entries/arch.conf`)
- **mkinitcpio HOOKS:** `base systemd autodetect microcode modconf kms keyboard keymap sd-vconsole block filesystems fsck`
- **pacman.conf:** stock except `ParallelDownloads = 5`. No multilib, no extra repos (no chaotic-aur etc.) — everything outside official repos comes from the AUR list above.
- **Session flow:** `greetd` autologins `zach` straight into Hyprland via the `start-hyprland` wrapper that ships with the `hyprland` package (nothing custom there).
- **GTK/icon theme:** `adw-gtk3` / `Adwaita` (default cursor)

## Known quirks worth knowing about before you copy these back

- **Dell XPS 14 (Panther Lake) audio vs. webcam load order.** The four `cs35l56` speaker amps need a GPIO at probe time that the webcam stack (`intel_cvs`, `ov08x40`, `intel_ipu7_isys`, built from `~/.local/share/webcam-fix`, see its README) also grabs. If the camera modules win the race, the amps fail with `-EBUSY: Failed to get spk-id-gpios`, `sof_sdw` never builds a card, and PipeWire shows only "Dummy Output". Fix: `modprobe.d/webcam-late-load.conf` blacklists the three modules from autoload, and `systemd-units/webcam-late-load.service` loads them (CVS → sensor → ISYS) once `sof-soundwire` appears in `/proc/asound/cards` (60s timeout, then loads anyway). Manual recovery if it ever happens again: unload the three camera modules, rebind the amps (`echo sdw:0:2:01fa:3557:01:2 > /sys/bus/soundwire/drivers/cs35l56/bind`, likewise `:2:...:3`, `:3:...:0`, `:3:...:1`), then `echo sof_sdw > /sys/bus/platform/drivers/sof_sdw/{unbind,bind}`. Which of the three modules actually holds the pin was not isolated.

- `udev-rules/70-keychron.rules` has `GROUP="$(your username)"` literally in the file — that looks like an unexpanded placeholder from wherever the rule was originally copied from, not something this project introduced. Worth fixing to your actual username (or dropping GROUP and relying on the `uaccess`/`udev-acl` tags, which already grant the logged-in user access) when you restore it.
- `minecraft.service` / `geyser.service` reference `~/mc-server` and `~/geyser` — those directories (server jars, worlds, configs) are data and intentionally **not** backed up here, per your instructions. The service files will fail to start until you put something back in those paths.
- `ollama.service`, `tailscaled.service`, and `proton.VPN.service` are enabled but any account login/state for Tailscale, Proton VPN, or Ollama models is data, not config — you'll need to log back in / re-pull models after reinstalling those AUR packages.
- `.gitconfig` is *not* included here since dotfiles conventionally leave that as a separate, personal file — set `git config --global user.name/user.email` again after reinstalling, or ask to have it added if you want it tracked too.
