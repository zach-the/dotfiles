# TODO: live-tracked 3-finger up/down for the special workspace

**2026-10-26.** Left/right 3-finger swipe now uses Hyprland's native
`hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })`
(1:1 finger-tracked drag, cancel mid-swipe, built-in slide animation).

Up/down (special workspace enter/exit) still use discrete,
swipe-complete-triggers-a-toggle gestures, in `hyprland.lua`:

```lua
hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "special" })
hl.gesture({ fingers = 3, direction = "down", action = function() hl.exec_cmd("~/.config/hypr/special_gesture.sh exit") end })
```

The resulting slide is already smooth (`specialWorkspace` animation leaf,
`slidevert` style, set in `hyprland.lua`'s animations section) — but the
*trigger* isn't finger-tracked the way the new left/right gesture is.
Hyprland has no native live-tracked equivalent for the special workspace;
`action = "special"` is documented as a discrete toggle, same category as
`close`/`float`/`fullscreen`, not the interactive-drag mode `workspace` gets.

## What it'd take

Hand-roll it with Hyprland's "live Lua gesture" API — pass a table with
`start`/`update`/`finish` callbacks instead of a plain action, and react to
the swipe's raw `delta.y` yourself:

```lua
hl.gesture({
    fingers = 3,
    direction = "vertical",
    action = {
        start = function(e) ... end,
        update = function(e) ... end,  -- e.delta.y each frame
        finish = function(e) ... end,  -- e.cancelled if aborted
    },
})
```

Docs: `wiki.hypr.land/configuring/core/binds/gestures/` → "Live Lua gestures".

Real work involved, not a config flip:

- Decide how to represent "partially revealed" visually — the special
  workspace doesn't have a native partial-reveal state the way a window
  drag does; this likely means animating something directly (e.g. driving
  a layer/window's position) rather than just calling the existing
  `toggle_special` dispatcher mid-gesture.
- Pick an open/close distance or velocity threshold ourselves on `finish`
  (mirroring what `workspace_swipe_cancel_ratio` /
  `workspace_swipe_min_speed_to_force` do natively for the horizontal case,
  but there's no off-the-shelf equivalent for this).
- Handle `cancelled` gestures (e.g. interrupted by another input) cleanly
  so the special workspace doesn't get stuck half-open.
- Needs actual on-device testing to get the feel right — not something to
  sign off on from code review alone.

Current discrete version is correct and shipped; this is a nice-to-have
polish pass, not a bug.
