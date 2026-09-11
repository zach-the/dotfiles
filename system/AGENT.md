# Restoring this system — read this first

You (an AI coding agent) are being asked to help rebuild this machine from
scratch on Arch Linux, using this dotfiles repo. This file is the runbook.
Everything it references lives under `system/` or in the repo root.

Context: the user wiped this machine at some point after 2026-09-10 (e.g. to
run Windows for a while) and is now coming back to Arch. They explicitly do
not care about recovering data/files — only the tool setup: packages,
configs, and services. Don't go looking for backed-up personal files; there
aren't any here on purpose.

## Before touching anything, confirm with the user

- They already have a **base Arch install** done manually (disks, bootloader,
  network, a user account) — this repo does not cover partitioning or the
  base install, only what comes after `pacstrap`/first boot.
- Their **username matches `zach`**. Several paths are hardcoded to
  `/home/zach/...` in symlink targets and the two custom systemd units
  (`system/systemd-units/*.service`). If the username differs, these need
  editing before use, not just the install script.
- Whether they still want the **Minecraft server + Geyser proxy** enabled.
  Those two units (`minecraft.service`, `geyser.service`) reference
  `~/mc-server` and `~/geyser`, which hold actual server data that was never
  backed up. If the user doesn't have that data anymore, skip enabling those
  two units in `restore-services.sh` (or enable them and accept they won't
  start until the user repopulates those directories).

## Restore order — do not reorder

1. `~/dotfiles/system/restore-packages.sh`
   Installs every explicitly-installed package from `pkglist-native.txt` and
   `pkglist-aur.txt`, bootstrapping `yay` first if no AUR helper is present.
2. `~/dotfiles/install.sh`
   Symlinks every tracked config into place (see the table in `README.md`).
   Interactive — walks through each entry and asks skip/pave/backup.
3. `~/dotfiles/system/restore-services.sh`
   Copies the custom systemd units into `/etc/systemd/system/` and enables
   every unit listed in `systemd-enabled.txt` / `systemd-enabled-user.txt`.
4. Reboot.

Package installs must happen before `install.sh`, since some symlink targets
(e.g. `/etc/keyd/default.conf`) belong to packages that must exist first.

## Known failure modes — handle, don't paper over

- **Package install failures.** Package names drift over time (renamed, split,
  dropped from AUR/repos). If `restore-packages.sh` fails on specific
  packages, don't guess a substitute silently — list which ones failed and
  ask the user how to proceed. Most packages should still install fine
  unattended.
- **`70-keychron.rules` has a literal broken placeholder**: `GROUP="$(your
  username)"` is not valid udev syntax — it was already broken on the
  original system. Fix it to the real username (or drop the `GROUP=` clause
  entirely and rely on the `uaccess`/`udev-acl` tags already in the rule,
  which grant the logged-in user access regardless) before relying on it.
- **Ollama, Tailscale, Proton VPN** get their packages/services restored, but
  all three need interactive login or model pulls afterward — that's account
  state, not config, and can't be scripted here.
- **No multilib repo** was enabled on the original system (no Steam/32-bit
  packages installed). If the user wants that later, they need to
  uncomment `[multilib]` in `/etc/pacman.conf` themselves.
- **Greetd autologins straight into Hyprland** via the `start-hyprland`
  binary that ships with the `hyprland` package itself — nothing custom to
  debug there if login works but the session doesn't start; check the
  `hyprland` package installed correctly instead.

## Verification checklist

- `pacman -Qqe | wc -l` should be close to
  `wc -l < system/pkglist-native.txt` + `wc -l < system/pkglist-aur.txt`
  (162 combined as of the snapshot date).
- `systemctl is-enabled <unit>` for a few units from `systemd-enabled.txt`
  (e.g. `NetworkManager.service`, `bluetooth.service`) should say `enabled`.
- `readlink ~/.config/hypr` should point into `~/dotfiles/hypr`.
- `journalctl -u minecraft -u geyser` will show failures until the user
  repopulates `~/mc-server` / `~/geyser` — expected, not a bug to chase.

## Where the source of truth lives

| What | File |
|---|---|
| Packages | `system/pkglist-native.txt`, `system/pkglist-aur.txt` |
| Services | `system/systemd-enabled.txt`, `system/systemd-enabled-user.txt` |
| Custom systemd units | `system/systemd-units/*.service` |
| System-level settings (hostname, locale, kernel, pacman.conf) | `system/notes.md` |
| Config → symlink map | `README.md` table + `install.sh` |

## Snapshot metadata

Captured 2026-09-10 on hostname `monkey`, kernel `linux 7.2.3-arch1-3`. If
you're doing this restore much later, package versions will have moved on —
that's fine, `--needed` installs whatever's current. Don't try to pin the
exact old versions. If a whole category of package (e.g. a Wayland
compositor dependency) has been renamed upstream, that's a real judgment
call — flag it to the user rather than silently substituting.
