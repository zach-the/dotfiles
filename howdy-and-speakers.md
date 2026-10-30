# 2026-10-25: speakers + Howdy outage and recovery

## Speakers

**Symptom:** `pw-play` hung indefinitely; no sound. First noticed ~09:42, on a
kernel/firmware combo (`linux 7.2.6.arch2-1`, `sof-firmware 2025.12.2-1`) that
had been unchanged since 2026-09-18 — so it wasn't a package regression at
first. A prior session suspected a SoundWire "bus clash" but never confirmed
it recurred, and a plain `reboot` didn't fix it.

**What didn't help:** a `pacman -Syu` to `linux 7.2.11.arch1-1` +
`sof-firmware 2026.09.2-1` did not fix it — it just swapped the symptom for a
different, confirmed upstream kernel bug: 7.2.11 shipped a half-backported
patch where the SoundWire machine driver looks for a codec DAI named
`cs35l56-ot25`, but the codec-side change that registers a DAI with that name
was left out of the backport. Result: `ASoC: CODEC DAI cs35l56-ot25 not
registered`, no sound card at all. Confirmed via upstream reports
([thesofproject/linux#5984](https://github.com/thesofproject/linux/issues/5984)),
fixed in kernel 7.2.12 (not yet packaged by Arch as of this date).

Downgrading back to the original 7.2.6 + sof-firmware 2025.12.2 *also* didn't
fix it on the first few attempts — it hit a different, intermittent failure
(`cs35l56 ... error -EBUSY: Failed to get spk-id-gpios`, a race between the 4
Cirrus CS35L57 amp instances over a shared GPIO line). Across ~10 reboots that
day, every single one was a quick warm reboot (~8–25s gap) — never an actual
full power-off.

**Root cause / fix:** the SoundWire bus state was wedged in a way a warm
reboot doesn't clear. The actual fix was:
1. Downgrade back to `linux 7.2.6.arch2-1` + `sof-firmware 2025.12.2-1`
   (undoes the confirmed 7.2.11 kernel regression).
2. A real full power-off (`systemctl poweroff`), wait ~15-20s, power back on —
   not a warm reboot. This cleared the wedge.

Confirmed working afterward: `sof-soundwire` card registered, PipeWire sinks
present for Speaker/Headphones/HDMI, no bus-clash or EBUSY errors in the
post-fix boot's kernel log.

## Howdy (IR face unlock)

**Symptom:** after the kernel downgrade above, Howdy started failing lock-screen
auth with `pam_howdy: Failure, not possible to open camera at configured path`.

**Root cause:** IR face unlock on this machine comes from a real third-party
project, [`svp7500-camera-fix-pack`](https://github.com/jibsta210/svp7500-camera-fix-pack)
(cloned to `~/src/svp7500-camera-fix-pack`), which supplies DKMS kernel
modules (`hm1092`, `ipu-bridge-patched`, `intel-cvs`, `int3472-patched`,
`ov05c10`) needed for the Himax HM1092 IR sensor behind the Synaptics SVP7500
bridge. DKMS modules are built per kernel version. These had only ever been
built against `7.2.11-arch1-1` (the kernel in use when that work was done,
earlier the same day) — never against `7.2.6-arch2-1`. Downgrading the kernel
for the speaker fix left the IR stack with no matching build, so the kernel
no longer recognized the HIMX1092 sensor at all.

**Fix:**
1. `linux-headers` was also stuck on `7.2.11` (pacman only keeps the latest);
   downgraded it to `7.2.6.arch2-1` to match the running kernel, from the
   pacman package cache. (Headers are build-time only — this step has no
   effect on which kernel boots or on audio.)
2. That triggered pacman's own DKMS pacman-hook, which ran a blind
   `dkms install` for every registered module against the new headers. This
   got most modules built but left a real landmine: `int3472-patched` isn't
   needed on `7.2.6` (mainline already has the in-tree fix,
   `skl_int3472_register_led`), but the blind hook installed it anyway,
   shadowing the in-tree driver in `updates/dkms` and removing the
   `/sys/class/leds/*::ir_flood_led` node the illuminator needs.
3. Ran the fix pack's own `sudo ./install.sh` properly, which detected and
   refused to re-shadow the in-tree driver — but on the first run it still
   flagged the leftover shadow from the pacman hook as needing manual cleanup:
   `sudo dkms remove int3472-patched/1.0 -k 7.2.6-arch2-1`.
4. Re-ran `sudo ./install.sh` — clean `==> Done`. All 4 real modules
   (`hm1092`, `intel-cvs`, `ipu-bridge-patched`, `ov05c10`) installed for
   `7.2.6-arch2-1`; `int3472-patched` correctly skipped as not needed;
   initramfs regenerated.
5. Rebooted (required — `hm1092` can't be hot-swapped, per the project's own
   README).

**Verified post-reboot** via the project's `tools/verify.sh`: IR sensor
streaming (`SOF on csi2-2: 9 <-- STREAMING`), correct `link_frequency`
(180480000), IR flood LED present, `device_path` in
`/etc/howdy/config.ini` (`/dev/video16`) already matches the real capture
node. IR face unlock confirmed working.

## Known remaining gap (pre-existing, unrelated)

`verify.sh` reports the RGB webcam path as `BROKEN`: `intel_ipu7_psys` isn't
loaded and isn't installed for this kernel. That module comes from a
different DKMS package, `ipu7-drivers`, which was never installed on this
machine (`dkms status` confirms no `ipu7-drivers` tree exists) — the fix pack
only *patches* that package if present, it doesn't provide the base module.
`libcamera` still enumerates both sensors (`cam --list` → 2 cameras), but with
no psys/hardware ISP, PipeWire exposes zero camera devices, so ordinary
webcam use (Zoom, browser video calls) doesn't work. This predates today's
changes and is unrelated to the speaker/Howdy fixes above — not yet
addressed.
