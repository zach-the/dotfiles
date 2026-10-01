#!/usr/bin/env python3
"""
Mac-Mouse-Fix-style inertial scroll for a regular clicky mouse wheel.

libinput/Hyprland pass wheel clicks through as discrete steps -- there's no
"custom curve" for scroll the way there is for pointer accel (see
mac_accel_curve.py). We grab the mouse exclusively, absorb its raw wheel
clicks ourselves, and replay them through a virtual device with momentum +
decay so a single click becomes a short animated glide instead of one jump.

Two output modes:

  wheel     Replay as REL_WHEEL_HI_RES on a virtual mouse. libinput forwards
            hi-res deltas to Wayland clients as continuous wl_pointer.axis
            values, so fine-grained ticks already animate smoothly -- but
            libinput reports axis_source=WHEEL, and some toolkits layer
            their own wheel-specific animation on top of that, which can
            fight with ours.

  touchpad  (default) Translate each click into a synthetic two-finger
            swipe on a second virtual device that looks like a real
            multitouch touchpad (ABS_MT_* slots). libinput then does its
            own two-finger-scroll gesture recognition and kinetic coasting
            on it -- the same code path your real touchpad's
            natural_scroll uses -- instead of our decay loop. We only drive
            the "finger" while actively scrolling; once velocity settles we
            lift the touch and let libinput's own momentum take over from
            there.

            This depends on libinput actually classifying the virtual
            device as a touchpad. Verify with `sudo libinput list-devices`
            after starting it, and watch `libinput debug-events` for
            GESTURE_SCROLL / axis_source=finger. If the scroll direction is
            backwards, flip INVERT below -- that's a real per-setup
            unknown, not a bug.

NOT measured from macOS -- tune the knobs below by feel.

Usage:
  sudo ./smooth_scroll.py                 # touchpad mode, foreground
  sudo ./smooth_scroll.py --mode wheel    # old REL_WHEEL_HI_RES behavior
  sudo ./smooth_scroll.py --list          # print matching devices and exit

Needs root (or membership in the `input` + a uinput-granting group) since it
opens /dev/input/eventN and /dev/uinput directly. Exiting (even via crash)
closes the grabbed fd, so the OS releases the real mouse automatically --
the physical wheel just goes back to normal, ungrabbed scrolling.
"""
import math
import sys
import threading
import time

import evdev
from evdev import ecodes as e

DEVICE_NAME_SUBSTR = "Keychron"   # matched against evdev device name
KICK_PER_NOTCH = 120              # hi-res units (120 = one physical notch) added per click

# scroll acceleration: same logistic-gain shape as mac_accel_curve.py, but
# driven by time between clicks (clicks/sec) instead of pointer speed. A lone,
# deliberate click still lands at ACCEL_MIN so single-notch scrolling is
# unaffected; clicks arriving faster than ACCEL_RATE_MID/sec ramp toward
# ACCEL_MAX, so a fast flick covers disproportionately more distance.
ACCEL_MIN = 1.0
ACCEL_MAX = 3.0
ACCEL_RATE_MID = 6.0              # clicks/sec at the midpoint of the ramp
ACCEL_RATE_WIDTH = 2.0            # smaller = sharper transition
TICK_HZ = 240                     # higher = finer-grained motion, less visible stepping

# velocity is a critically-damped chase of a decaying target, not a single
# exponential -- ATTACK is how fast actual motion ramps up to a new kick
# (ease-in, avoids a hard jump the instant a click lands), DECAY is how fast
# the target itself fades (ease-out, the long gradual tail). Because ATTACK
# lags behind, the ease-out is smoothed twice over -- once by the target's
# own decay, once by the chase -- so there's no discontinuity at either end.
ATTACK = 0.12                     # per-tick close rate toward target velocity
DECAY = 0.952                     # per-tick target decay -- closer to 1 = longer glide
STOP_THRESHOLD = 0.3              # both current & target below this -> fully stopped

# touchpad-mode only
TOUCHPAD_UNITS_PER_HIRES = 0.025  # ABS position units moved per hi-res momentum unit
TOUCH_LIFT_IDLE = 0.4             # seconds of settled velocity before lifting the touch
INVERT = False                    # flip if scroll direction comes out backwards
PAD_X_MAX, PAD_Y_MAX = 2000, 4000 # virtual pad size in ABS units (100mm x 200mm --
                                   # tall on purpose: with the longer glide above, a
                                   # single notch travels further, and hitting the edge
                                   # means an abrupt recenter, which feels like a jump)
PAD_RESOLUTION = 20               # ABS units per mm
PAD_MARGIN = 200                  # recenter the virtual fingers once within this of an edge
FINGER_SPACING = 150              # ABS units between the two synthetic contacts


def find_device():
    candidates = []
    for path in evdev.list_devices():
        d = evdev.InputDevice(path)
        if DEVICE_NAME_SUBSTR not in d.name:
            continue
        caps = d.capabilities()
        rel = caps.get(e.EV_REL, [])
        key = caps.get(e.EV_KEY, [])
        if (e.REL_WHEEL in rel or e.REL_WHEEL_HI_RES in rel) and e.BTN_LEFT in key:
            candidates.append(d)
        else:
            d.close()
    return candidates


class Axis:
    """One scroll axis: absorbs discrete clicks, drains them as momentum.

    `target` jumps on each kick and decays every tick (the ease-out).
    `current` -- what we actually emit -- chases `target` with a lag (the
    ease-in), so neither a new kick nor the eventual stop is a discontinuity.
    """

    def __init__(self):
        self.target = 0.0
        self.current = 0.0
        self.carry = 0.0
        self.last_kick_time = None
        self.lock = threading.Lock()

    def kick(self, hires_value):
        now = time.monotonic()
        with self.lock:
            if self.last_kick_time is None:
                gain = ACCEL_MIN
            else:
                rate = 1.0 / max(now - self.last_kick_time, 1e-6)
                gain = ACCEL_MIN + (ACCEL_MAX - ACCEL_MIN) / (
                    1 + math.exp(-(rate - ACCEL_RATE_MID) / ACCEL_RATE_WIDTH))
            self.last_kick_time = now
            self.target += hires_value * gain

    def drain_tick(self):
        with self.lock:
            self.current += (self.target - self.current) * ATTACK
            self.target *= DECAY
            if abs(self.current) < STOP_THRESHOLD and abs(self.target) < STOP_THRESHOLD:
                self.current = 0.0
                self.target = 0.0
                self.carry = 0.0
                return 0
            self.carry += self.current
            emit = int(self.carry)
            self.carry -= emit
            return emit


def make_mouse_uinput(src_caps, mode):
    ui_caps = {k: v for k, v in src_caps.items() if k in (e.EV_KEY, e.EV_REL, e.EV_MSC)}
    rel = set(ui_caps.get(e.EV_REL, []))
    rel.discard(e.REL_WHEEL)
    rel.discard(e.REL_HWHEEL)
    if mode == "wheel":
        rel.add(e.REL_WHEEL_HI_RES)
        if e.REL_HWHEEL in src_caps.get(e.EV_REL, []) or e.REL_HWHEEL_HI_RES in src_caps.get(e.EV_REL, []):
            rel.add(e.REL_HWHEEL_HI_RES)
    ui_caps[e.EV_REL] = list(rel)
    return evdev.UInput(ui_caps, name="smooth-scroll mouse")


def make_touchpad_uinput():
    caps = {
        e.EV_KEY: [e.BTN_TOUCH, e.BTN_TOOL_FINGER, e.BTN_TOOL_DOUBLETAP],
        e.EV_ABS: [
            (e.ABS_MT_SLOT, evdev.AbsInfo(0, 0, 1, 0, 0, 0)),
            (e.ABS_MT_TRACKING_ID, evdev.AbsInfo(-1, 0, 65535, 0, 0, 0)),
            (e.ABS_MT_POSITION_X, evdev.AbsInfo(0, 0, PAD_X_MAX, 0, 0, PAD_RESOLUTION)),
            (e.ABS_MT_POSITION_Y, evdev.AbsInfo(0, 0, PAD_Y_MAX, 0, 0, PAD_RESOLUTION)),
        ],
    }
    return evdev.UInput(caps, name="smooth-scroll virtual touchpad")


class TouchpadEmitter:
    """Drives a synthetic two-finger swipe on a virtual touchpad device."""

    def __init__(self, ui):
        self.ui = ui
        self.touching = False
        self.next_id = 0
        self.cx = PAD_X_MAX // 2
        self.cy = PAD_Y_MAX // 2

    def _slot(self, slot, tracking_id=None, x=None, y=None):
        self.ui.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
        if tracking_id is not None:
            self.ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tracking_id)
        if x is not None:
            self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_X, x)
        if y is not None:
            self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_Y, y)

    def touch_down(self):
        self.cx, self.cy = PAD_X_MAX // 2, PAD_Y_MAX // 2
        self._slot(0, tracking_id=self._alloc_id(), x=self.cx - FINGER_SPACING, y=self.cy)
        self._slot(1, tracking_id=self._alloc_id(), x=self.cx + FINGER_SPACING, y=self.cy)
        self.ui.write(e.EV_KEY, e.BTN_TOUCH, 1)
        self.ui.write(e.EV_KEY, e.BTN_TOOL_DOUBLETAP, 1)
        self.ui.syn()
        self.touching = True

    def touch_up(self):
        self._slot(0, tracking_id=-1)
        self._slot(1, tracking_id=-1)
        self.ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
        self.ui.write(e.EV_KEY, e.BTN_TOOL_DOUBLETAP, 0)
        self.ui.syn()
        self.touching = False

    def _alloc_id(self):
        self.next_id = (self.next_id + 1) % 65535
        return self.next_id

    def move(self, dx, dy):
        dx, dy = round(dx), round(dy)
        if not self.touching:
            self.touch_down()
        nx = self.cx + dx
        ny = self.cy + dy
        if not (PAD_MARGIN < nx < PAD_X_MAX - PAD_MARGIN and PAD_MARGIN < ny < PAD_Y_MAX - PAD_MARGIN):
            self.touch_up()
            self.touch_down()
            return
        self.cx, self.cy = nx, ny
        self._slot(0, x=self.cx - FINGER_SPACING, y=self.cy)
        self._slot(1, x=self.cx + FINGER_SPACING, y=self.cy)
        self.ui.syn()


def main():
    mode = "touchpad"
    if "--mode" in sys.argv:
        mode = sys.argv[sys.argv.index("--mode") + 1]
    assert mode in ("wheel", "touchpad")

    devices = find_device()
    if "--list" in sys.argv or not devices:
        for path in evdev.list_devices():
            d = evdev.InputDevice(path)
            print(path, repr(d.name))
        if not devices:
            print(f"\nNo device matched name substring {DEVICE_NAME_SUBSTR!r} with a wheel.",
                  file=sys.stderr)
            sys.exit(1)
        return
    if len(devices) > 1:
        print("Multiple matching devices, using the first:", file=sys.stderr)
        for d in devices:
            print(" ", d.path, d.name, file=sys.stderr)
    src = devices[0]
    print(f"Grabbing {src.path} ({src.name!r}) in {mode!r} mode")

    mouse_ui = make_mouse_uinput(src.capabilities(), mode)
    pad_ui = make_touchpad_uinput() if mode == "touchpad" else None
    pad = TouchpadEmitter(pad_ui) if pad_ui else None
    src.grab()

    vertical = Axis()
    horizontal = Axis()
    stop = threading.Event()
    last_active = time.monotonic()
    lock = threading.Lock()

    def ticker():
        nonlocal last_active
        period = 1.0 / TICK_HZ
        while not stop.is_set():
            t0 = time.monotonic()
            dy = vertical.drain_tick()
            dx = horizontal.drain_tick()
            if mode == "wheel":
                if dy:
                    mouse_ui.write(e.EV_REL, e.REL_WHEEL_HI_RES, dy)
                if dx:
                    mouse_ui.write(e.EV_REL, e.REL_HWHEEL_HI_RES, dx)
                if dy or dx:
                    mouse_ui.syn()
            else:
                with lock:
                    if dy or dx:
                        last_active = t0
                        sign = -1 if INVERT else 1
                        pad.move(dx * TOUCHPAD_UNITS_PER_HIRES * sign,
                                 dy * TOUCHPAD_UNITS_PER_HIRES * sign)
                    elif pad.touching and (t0 - last_active) > TOUCH_LIFT_IDLE:
                        pad.touch_up()
            time.sleep(max(0.0, period - (time.monotonic() - t0)))

    threading.Thread(target=ticker, daemon=True).start()

    # one physical click often reports both REL_WHEEL_HI_RES and the legacy
    # REL_WHEEL for the same notch in one SYN frame -- only kick once per frame
    pending_v_hires = False
    pending_h_hires = False
    try:
        for ev in src.read_loop():
            if ev.type == e.EV_REL and ev.code == e.REL_WHEEL_HI_RES:
                vertical.kick(ev.value)
                pending_v_hires = True
            elif ev.type == e.EV_REL and ev.code == e.REL_WHEEL:
                if not pending_v_hires:
                    vertical.kick(ev.value * 120)
            elif ev.type == e.EV_REL and ev.code == e.REL_HWHEEL_HI_RES:
                horizontal.kick(ev.value)
                pending_h_hires = True
            elif ev.type == e.EV_REL and ev.code == e.REL_HWHEEL:
                if not pending_h_hires:
                    horizontal.kick(ev.value * 120)
            elif ev.type == e.EV_SYN and ev.code == e.SYN_REPORT:
                pending_v_hires = False
                pending_h_hires = False
                mouse_ui.syn()
            else:
                mouse_ui.write(ev.type, ev.code, ev.value)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        src.ungrab()
        mouse_ui.close()
        if pad_ui:
            pad.touch_up() if pad.touching else None
            pad_ui.close()


if __name__ == "__main__":
    main()
