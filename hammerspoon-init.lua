--   ===============================================================================   --
--    _    _          __  __ __  __ ______ _____   _____ _____   ____   ____  _   _    --
--   | |  | |   /\   |  \/  |  \/  |  ____|  __ \ / ____|  __ \ / __ \ / __ \| \ | |   --
--   | |__| |  /  \  | \  / | \  / | |__  | |__) | (___ | |__) | |  | | |  | |  \| |   --
--   |  __  | / /\ \ | |\/| | |\/| |  __| |  _  / \___ \|  ___/| |  | | |  | | . ` |   --
--   | |  | |/ ____ \| |  | | |  | | |____| | \ \ ____) | |    | |__| | |__| | |\  |   --
--   |_|  |_/_/    \_\_|  |_|_|  |_|______|_|  \_\_____/|_|     \____/ \____/|_| \_|   --
--                                                                                     --
--   ===============================================================================   --

-- =====================================================================
-- HYPER (^⌥⌘⇧) KEYBIND MAP  —  [X] = bound   [ ] = free
-- =====================================================================
--
--  [ ][ ][ ][ ][4][5][6][7][8][9][0][-][=]
--    [Q][W][E][ ][T][Y][U][I][O][P]
--      [A][S][D][F][G][H][J][K][L]
--         [Z][X][C][ ][ ][N][M]
--
--                                         [ RETURN ]
--
-- Legend:
--   Q          → minimize
--   W E        → two-thirds(1) / two-thirds(2)
--   T Y        → launch WezTerm / prev display
--   U I        → top-left / top-right quarter
--   O P        → next display / debug spaces
--   A S D      → third(1) / third(2) / third(3) window snap
--   F          → maximize
--   G          → center window
--   H L        → prev space / next space
--   J K        → bottom-left / bottom-right quarter
--   Z X C      → half-split (context-aware: portrait vs. landscape)
--   N M        → launch Chrome / launch Safari
--   V          → restore all minimized windows (skips hidden apps)
--   RETURN     → fullscreen
--   - =        → resize smaller / larger
--   0          → reload Hammerspoon config
--   4 5 6      → sixths: upper-left / upper-middle / upper-right
--   7 8 9      → sixths: lower-left / lower-middle / lower-right
--   DELETE     → lock screen
--
--   FREE: 1 2 3, R, B

-- =====================================================================
-- INSTRUCTIONS
-- =====================================================================
-- cd ~/ ; ln -s ~/manual-sync-dotfiles/hammerspoon-init.lua ~/.hammerspoon/init.lua

-- =====================================================================
-- DEFINE HYPER : CTRL + OPT + CMD + SHIFT
-- =====================================================================
require("hs.ipc")

local hyper = {"ctrl", "alt", "cmd", "shift"}


--==============================================================================--
--  _   _      _                   _____                 _   _                  --
-- | | | | ___| |_ __   ___ _ __  |  ___|   _ _ __   ___| |_(_) ___  _ __  ___  --
-- | |_| |/ _ \ | '_ \ / _ \ '__| | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __| --
-- |  _  |  __/ | |_) |  __/ |    |  _|| |_| | | | | (__| |_| | (_) | | | \__ \ --
-- |_| |_|\___|_| .__/ \___|_|    |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/ --
--              |_|                                                             --
--==============================================================================--


-- =====================================================================
-- DIRECTIONAL FOCUS
-- =====================================================================
local function moveMouseToWindow(win)
    if win then
        local frame = win:frame()
        local centerPoint = {
            x = frame.x + (frame.w / 2),
            y = frame.y + (frame.h / 2)
        }
        hs.mouse.absolutePosition(centerPoint)
    end
end

-- Pure single-axis match: H/L only ever compares X position, J/K only ever
-- compares Y position. No cone/dominant-axis check against the other axis,
-- so a window doesn't get skipped just because it's also offset vertically
-- (for H/L) or horizontally (for J/K).
local function directionalMatch(deltaX, deltaY, direction)
    if direction == "West" then
        if deltaX < 0 then return true, math.abs(deltaX) end
    elseif direction == "East" then
        if deltaX > 0 then return true, math.abs(deltaX) end
    elseif direction == "North" then
        if deltaY < 0 then return true, math.abs(deltaY) end
    elseif direction == "South" then
        if deltaY > 0 then return true, math.abs(deltaY) end
    end
    return false, nil
end

local function smartFocus(direction)
    local win = hs.window.focusedWindow()
    -- Safety check: If a tab closed and focus is "lost" to the OS, try to grab the frontmost app's window
    if not win then win = hs.window.frontmostWindow() end
    if not win then return end

    local winFrame = win:frame()
    local winScreen = win:screen()

    -- Use mouse position as origin if it's on a different screen than the focused window.
    -- This makes "empty screen" hops work: after landing on an empty screen,
    -- the next keypress navigates from the mouse location, not the still-focused window.
    local mousePos = hs.mouse.absolutePosition()
    local mouseScreen = nil
    for _, s in ipairs(hs.screen.allScreens()) do
        local sf = s:frame()
        if mousePos.x >= sf.x and mousePos.x < sf.x + sf.w and
           mousePos.y >= sf.y and mousePos.y < sf.y + sf.h then
            mouseScreen = s
            break
        end
    end
    local origin
    if mouseScreen and mouseScreen:id() ~= winScreen:id() then
        origin = mousePos
        winScreen = mouseScreen
    else
        origin = {x = winFrame.x + winFrame.w/2, y = winFrame.y + winFrame.h/2}
    end
    local winCenter = origin

    -- FIX: Use visibleWindows() instead of filters.
    -- Filters cache state and can "lose" Ghostty after a tab close.
    -- This queries the OS directly for the current truth.
    local allWindows = hs.window.visibleWindows()
    local candidates = {}

    -- Track which screens have at least one visible standard window on them
    local screensWithWindows = {}
    for _, w in ipairs(allWindows) do
        if w:isVisible() and w:isStandard() then
            local s = w:screen()
            if s then screensWithWindows[s:id()] = true end
        end
    end

    -- J/K (vertical) stay on the current monitor only; H/L (horizontal) can
    -- cross to adjacent monitors, matching the physical left-to-right layout.
    local verticalOnly = (direction == "North" or direction == "South")

    for _, w in ipairs(allWindows) do
        if w:isVisible() and w:isStandard() then
            if not verticalOnly or w:screen():id() == winScreen:id() then
                local f = w:frame()
                local c = {x = f.x + f.w/2, y = f.y + f.h/2}

                -- Calculate deltas
                local deltaX = c.x - winCenter.x
                local deltaY = c.y - winCenter.y

                local isCandidate, distance = directionalMatch(deltaX, deltaY, direction)

                if isCandidate then
                    table.insert(candidates, {window = w, dist = distance})
                end
            end
        end
    end

    -- Also add empty screens as virtual candidates (H/L only — J/K never
    -- leaves the current monitor, so there's no "empty screen" to hop to)
    if not verticalOnly then
        for _, screen in ipairs(hs.screen.allScreens()) do
            if screen:id() ~= winScreen:id() and not screensWithWindows[screen:id()] then
                local sf = screen:frame()
                local sc = {x = sf.x + sf.w/2, y = sf.y + sf.h/2}
                local deltaX = sc.x - winCenter.x
                local deltaY = sc.y - winCenter.y

                local isCandidate, distance = directionalMatch(deltaX, deltaY, direction)

                if isCandidate then
                    -- virtual candidate: no window field, just a point to move the mouse to
                    table.insert(candidates, {point = sc, dist = distance})
                end
            end
        end
    end

    -- Sort by distance (closest first)
    if #candidates > 0 then
        table.sort(candidates, function(a, b)
            return a.dist < b.dist
        end)

        local best = candidates[1]
        if best.window then
            local targetWindow = best.window
            targetWindow:focus()
            moveMouseToWindow(targetWindow)
            -- Known Hammerspoon/macOS bug (hammerspoon#370, #2978): for apps with multiple
            -- windows (e.g. Chrome), :focus() races the app's own window activation when
            -- switching from a different app, so the wrong window ends up focused even
            -- though the mouse lands in the right place. Re-assert focus shortly after
            -- to win the race.
            hs.timer.doAfter(0.1, function()
                targetWindow:focus()
            end)
        else
            -- Empty screen: just move the mouse, don't change focus
            hs.mouse.absolutePosition(best.point)
        end
    end
end

-- =====================================================================
-- WINDOW THROWING FUNCTIONS
-- =====================================================================

-- Configuration
local gap = 8
hs.window.animationDuration = 0.25

-- Helper Functions

local windowHistory = {}

-- Function to save window state before moving
local function snapshot(win)
    if not win then return end
    local id = win:id()
    if not windowHistory[id] then
        windowHistory[id] = win:frame()
    end
end

-- Core function to move windows with SMART GAPS (Inner gap is 1/2 size)
local function move(x, y, w, h)
    return function()
        local win = hs.window.focusedWindow()
        if not win then return end

        snapshot(win)

        local f = win:frame()
        local screen = win:screen()
        local max = screen:frame()

        -- Calculate base frame based on unit (0.0 - 1.0)
        f.x = max.x + (max.w * x)
        f.y = max.y + (max.h * y)
        f.w = max.w * w
        f.h = max.h * h

        -- GAP LOGIC ---------------------------------------------------
        -- Outer Gap = gap
        -- Inner Gap = gap / 2 (We subtract gap/2 from each window to achieve this)

        local outerGap = gap
        local innerWindowPadding = gap / 2

        -- 1. Horizontal Gaps
        -- Left Edge
        if x == 0 then
            f.x = f.x + outerGap
            f.w = f.w - outerGap
        else
            f.x = f.x + innerWindowPadding
            f.w = f.w - innerWindowPadding
        end

        -- Right Edge (check if x + w is approximately 1)
        if (x + w) >= 0.99 then
            f.w = f.w - outerGap
        else
            f.w = f.w - innerWindowPadding
        end

        -- 2. Vertical Gaps
        -- Top Edge (Preserving your "Flush Top" preference)
        if y == 0 then
            f.y = f.y + 2
            f.h = f.h - 2
            -- If touching top, no top gap (f.y unchanged)
            -- Only adjust height based on bottom condition
            if (y + h) >= 0.99 then
                f.h = f.h - outerGap -- Touching bottom
            else
                f.h = f.h - innerWindowPadding -- Touching another window below
            end
        else
            -- Not touching top (so it's below something)
            f.y = f.y + innerWindowPadding
            f.h = f.h - innerWindowPadding

            -- Bottom adjustment
            if (y + h) >= 0.99 then
                f.h = f.h - outerGap -- Touching bottom
            else
                f.h = f.h - innerWindowPadding -- Touching another window below
            end
        end
        -- -------------------------------------------------------------

        win:setFrame(f)
        moveMouseToWindow(win) -- UPDATE: Move mouse to center
    end
end

-- Function to handle Next/Prev Display
local function moveDisplay(direction)
    return function()
        local win = hs.window.focusedWindow()
        if not win then return end
        snapshot(win)

        if direction == "next" then
            win:moveOneScreenEast()
        else
            win:moveOneScreenWest()
        end

        -- Optional: Center mouse after moving display as well
        hs.timer.doAfter(0.1, function() moveMouseToWindow(win) end)
    end
end

-- =====================================================================
-- WINDOW MOVEMENT
-- =====================================================================

-- Unminimize All Windows (skips windows belonging to hidden apps)
local function unMinimizeAll()
    local windows = hs.window.allWindows()
    local count = 0

    for _, win in ipairs(windows) do
        local app = win:application()
        if win:isMinimized() and not (app and app:isHidden()) then
            win:unminimize()
            count = count + 1
        end
    end

    if count == 0 then
        hs.alert.show("No minimized windows found")
    end
end

-- Minimize Focused Window
local function minimizeFocused()
    local win = hs.window.focusedWindow()
    if win then
        win:minimize()
    end
end

-- Maximize Focused Window
local function maximize()
    local win = hs.window.focusedWindow()
    if win then
        snapshot(win)
        move(0,0,1,1)()
        -- Note: move() now handles the mouse centering
    end
end

-- Center Focused Window
local function center()
    local win = hs.window.focusedWindow()
    if win then
        snapshot(win)
        win:centerOnScreen()
        moveMouseToWindow(win) -- UPDATE: Move mouse to center
    end
end

-- Resize Focused Window (smaller/larger)
local function resize(action)
    return function()
        local win = hs.window.focusedWindow()
        if not win then return end
        snapshot(win)

        local f = win:frame()
        local step = 40

        if action == "larger" then
            f.x = f.x - step / 2
            f.y = f.y - step / 2
            f.w = f.w + step
            f.h = f.h + step
        else
            f.x = f.x + step / 2
            f.y = f.y + step / 2
            f.w = f.w - step
            f.h = f.h - step
        end
        win:setFrame(f)
        moveMouseToWindow(win) -- UPDATE: Move mouse to center
    end
end

local function fullscreen()
    local win = hs.window.focusedWindow()
    if win then
        win:toggleFullScreen()
    end
end

local function third(n)
    return function()
        local win = hs.window.focusedWindow()
        if not win then return end
        local sf = win:screen():frame()
        if sf.h > sf.w then
            move(0, (n-1)/3, 1, 1/3)()
        else
            move((n-1)/3, 0, 1/3, 1)()
        end
    end
end

local function sixth(row, col)
    return function()
        move(col/3, row/2, 1/3, 1/2)()
    end
end

local function twoThirds(n)
    return function()
        local win = hs.window.focusedWindow()
        if not win then return end
        local sf = win:screen():frame()
        local offset = (n == 1) and 0 or 1/3
        if sf.h > sf.w then
            move(0, offset, 1, 2/3)()
        else
            move(offset, 0, 2/3, 1)()
        end
    end
end

-- =====================================================================
-- HELPER FUNCTION FOR GHOSTTY/CHROME LAUNCH FUNCTIONS
-- =====================================================================
local function moveSpecificWindow(win)
    if not win then return end

    local mouseScreen = hs.mouse.getCurrentScreen()
    if mouseScreen then
        win:moveToScreen(mouseScreen)
        win:focus()
    end
end


-- =====================================================================
-- LAUNCH GHOSTTY
-- =====================================================================

local function launchGhostty()
    local app = hs.application.get("Ghostty")

    if not app then
        -- If Ghostty isn't running at all, just launch it
        hs.application.launchOrFocus("Ghostty")
    else
        -- If it is running, focus it and trigger a new window keystroke
        app:activate()
        hs.eventtap.keyStroke({"cmd"}, "n")
    end

    -- Give the window a split second to exist, then move it to the mouse screen
    hs.timer.doAfter(0.15, function()
        local win = hs.window.focusedWindow()
        if win and win:application():title() == "Ghostty" then
            moveSpecificWindow(win)
        end
    end)
end


-- =====================================================================
-- LAUNCH CHROME
-- =====================================================================

local function launchChrome()
    -- Snapshot existing Chrome windows so we can identify the new one later
    local existingIds = {}
    local chromeApp = hs.application.get("Google Chrome")
    if chromeApp then
        for _, w in ipairs(chromeApp:allWindows()) do
            existingIds[w:id()] = true
        end
    end

    local targetScreen = hs.mouse.getCurrentScreen()
    local f = targetScreen:frame()
    -- AppleScript bounds are {left, top, right, bottom}
    local left   = math.floor(f.x)
    local top    = math.floor(f.y)
    local right  = math.floor(f.x + f.w)
    local bottom = math.floor(f.y + f.h)

    if not chromeApp then
        -- Chrome isn't running: open in background without stealing focus
        hs.task.new("/usr/bin/open", nil, {"-g", "-a", "Google Chrome"}):start()
    else
        -- Create the window and immediately position it on the target screen so it
        -- never visually appears on the wrong monitor before being moved.
        hs.osascript.applescript(string.format([[
            tell application "Google Chrome"
                set newWin to make new window
                set bounds of newWin to {%d, %d, %d, %d}
            end tell
        ]], left, top, right, bottom))
    end

    hs.timer.doAfter(0.4, function()
        local app = hs.application.get("Google Chrome")
        if not app then return end

        for _, w in ipairs(app:allWindows()) do
            if not existingIds[w:id()] then
                moveSpecificWindow(w)
                return
            end
        end
    end)
end

-- =====================================================================
-- LAUNCH WEZTERM
-- =====================================================================

local function launchWezterm()
    -- Snapshot existing WezTerm windows so we can identify the new one later
    local existingIds = {}
    local weztermApp = hs.application.get("WezTerm")
    if weztermApp then
        for _, w in ipairs(weztermApp:allWindows()) do
            existingIds[w:id()] = true
        end
    end

    -- Find the wezterm CLI binary (hs.task does not inherit shell PATH)
    local bin
    for _, p in ipairs({
        "/opt/homebrew/bin/wezterm",
        "/usr/local/bin/wezterm",
        "/Applications/WezTerm.app/Contents/MacOS/wezterm",
    }) do
        if hs.fs.attributes(p) then
            bin = p
            break
        end
    end

    if not bin then
        hs.alert.show("wezterm CLI not found")
        return
    end

    -- `wezterm start` talks to the running WezTerm process via Unix socket IPC.
    -- A new OS window is created without stealing focus from whatever you're in.
    -- Run via a detached shell so wezterm is not a child of Hammerspoon and
    -- survives config reloads (which terminate Hammerspoon's child processes).
    hs.execute("nohup " .. bin .. " start </dev/null >/dev/null 2>&1 &")

    -- After WezTerm opens the window, move it to the screen under the mouse
    hs.timer.doAfter(0.4, function()
        local targetScreen = hs.mouse.getCurrentScreen()
        local app = hs.application.get("WezTerm")
        if not app then return end

        for _, w in ipairs(app:allWindows()) do
            if not existingIds[w:id()] then
                w:moveToScreen(targetScreen)
                w:focus()
                return
            end
        end
    end)
end

-- =====================================================================
-- SCROLL
-- =====================================================================
-- Hold: ramps from 1x to MAX_MULT over RAMP_SECS on an exponential curve
-- Repeated tap within TAP_WINDOW: uses REPEAT_TAP_SPEED instead of BASE_SPEED
local scrollTimer = nil
local scrollStartTime = nil
local scrollGen = 0  -- incremented on each new scroll; stops stale doAfter callbacks
local BASE_SPEED = 20
local REPEAT_TAP_SPEED = 100
local MAX_MULT = 60
local RAMP_SECS = 3
local TAP_WINDOW = 0.2
local TERMINAL_DIVISOR = 2
local lastTapTime = 0
local lastTapDir = 0

local TERMINAL_APPS = { WezTerm = true, iTerm2 = true, Terminal = true, Ghostty = true, Alacritty = true, kitty = true }

local function isTerminalFocused()
    local app = hs.application.frontmostApplication()
    return app and TERMINAL_APPS[app:name()] or false
end

local function startScroll(dy)
    local now = hs.timer.secondsSinceEpoch()
    local isRepeat = dy * lastTapDir > 0 and (now - lastTapTime) < TAP_WINDOW
    local speed = isRepeat and REPEAT_TAP_SPEED or BASE_SPEED
    local terminalDivisor = isTerminalFocused() and TERMINAL_DIVISOR or 1
    lastTapTime = now
    lastTapDir = dy

    scrollGen = scrollGen + 1  -- invalidate any pending stopScroll doAfter
    if scrollTimer then scrollTimer:stop() end
    scrollStartTime = now
    scrollTimer = hs.timer.doEvery(0.016, function()
        local elapsed = math.min(hs.timer.secondsSinceEpoch() - scrollStartTime, RAMP_SECS)
        local mult = MAX_MULT ^ (elapsed / RAMP_SECS)
        hs.eventtap.scrollWheel({0, math.floor(dy * mult * (speed / BASE_SPEED) / terminalDivisor)}, {}, "pixel")
    end)
end

local MIN_SCROLL_DURATION = 0.15  -- taps animate for at least this long

local function stopScroll()
    if not scrollTimer then return end
    local elapsed = hs.timer.secondsSinceEpoch() - (scrollStartTime or 0)
    local remaining = MIN_SCROLL_DURATION - elapsed
    local gen = scrollGen
    if remaining > 0 then
        hs.timer.doAfter(remaining, function()
            if scrollGen ~= gen then return end  -- a new scroll started; don't interfere
            if scrollTimer then scrollTimer:stop() end
            scrollTimer = nil
            scrollStartTime = nil
        end)
    else
        scrollTimer:stop()
        scrollTimer = nil
        scrollStartTime = nil
    end
end

-- =====================================================================
-- FAST MULTI-MONITOR SPACE SWITCHING (yabai-backed, per-display, no wrap)
-- =====================================================================
-- Previously this sent ctrl+<mission-control index>, computed from a
-- Hammerspoon-side guess at global space ordering. That guess could drift
-- from reality (yabai/macOS re-numbering), and because ctrl+N targets a
-- space by *global* number rather than "the next space on this display",
-- a stale guess could end up switching the wrong monitor entirely.
-- yabai's `--display mouse` queries are always live, so there's nothing
-- to drift: this asks "what are the spaces on the screen under my mouse,
-- right now" every time, then tells yabai to focus that exact space.

local YABAI = "/opt/homebrew/bin/yabai"

-- Forward-declared so switchSpace's closure captures this local (not a
-- stray global) even though hs.menubar.new() runs further down the file.
local spacesMenubar

local function switchSpace(direction)
    local output, ok = hs.execute(YABAI .. " -m query --spaces --display mouse")
    if not ok or not output or output == "" then return end

    local success, spaces = pcall(hs.json.decode, output)
    if not success or not spaces then return end

    local currentIndex = nil
    for i, s in ipairs(spaces) do
        if s["is-visible"] then
            currentIndex = i
            break
        end
    end
    if not currentIndex then return end

    local targetIndex = currentIndex + (direction == "next" and 1 or -1)

    -- Hard Wall: no wrap-around past this display's own spaces
    if targetIndex < 1 or targetIndex > #spaces then return end

    local targetSpace = spaces[targetIndex]
    hs.execute(YABAI .. " -m space --focus " .. tostring(targetSpace.index))
    -- We already know exactly which space we just switched to, so set it
    -- directly instead of re-querying yabai (which can race the still-in-
    -- progress space transition and read back the stale, pre-switch space).
    if spacesMenubar then
        spacesMenubar:setTitle(tostring(targetSpace.index))
    end
end

-- =====================================================================
-- MENU BAR SPACE INDICATOR
-- =====================================================================
-- Shows the active space index of whichever display the mouse is
-- currently on, e.g. "7"

spacesMenubar = hs.menubar.new()

function updateSpacesMenubar()
    if not spacesMenubar then return end

    local output, ok = hs.execute(YABAI .. " -m query --spaces --display mouse")
    if not ok or not output or output == "" then return end
    local success, spaces = pcall(hs.json.decode, output)
    if not success or not spaces then return end

    for _, s in ipairs(spaces) do
        if s["is-visible"] then
            spacesMenubar:setTitle(tostring(s.index))
            return
        end
    end
end

updateSpacesMenubar()

-- Instant update whenever the active space changes anywhere (hotkey,
-- trackpad swipe, Mission Control click, etc) instead of waiting on a poll.
-- Deliberately global (no `local`) so they're rooted in _G and don't get
-- garbage collected once the top-level chunk finishes running -- a bare
-- top-level local here is nobody's upvalue, so Hammerspoon silently GCs it
-- and the timer/watcher stop firing after the first run.
spacesWatcher = hs.spaces.watcher.new(updateSpacesMenubar)
spacesWatcher:start()

-- Fallback poll: catches the one case the watcher above can't, moving the
-- mouse to a different display without changing any space.
spacesMenubarTimer = hs.timer.doEvery(0.3, updateSpacesMenubar)

--==========================================--
--  _  __          _     _           _      --
-- | |/ /___ _   _| |__ (_)_ __   __| |___  --
-- | ' // _ \ | | | '_ \| | '_ \ / _` / __| --
-- | . \  __/ |_| | |_) | | | | | (_| \__ \ --
-- |_|\_\___|\__, |_.__/|_|_| |_|\__,_|___/ --
--           |___/                          --
--==========================================--

-- Space Switching
hs.hotkey.bind(hyper, "H", function() switchSpace("prev") end)
hs.hotkey.bind(hyper, "L", function() switchSpace("next") end)
hs.hotkey.bind(hyper, "Left", function() switchSpace("prev") end)
hs.hotkey.bind(hyper, "Right", function() switchSpace("next") end)

-- Halves (portrait monitor: horizontal splits; landscape: vertical splits)
hs.hotkey.bind(hyper, "Z", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local sf = win:screen():frame()
    if sf.h > sf.w then move(0, 0, 1, 0.5)()    -- Top Half
    else             move(0, 0, 0.5, 1)() end    -- Left Half
end)
hs.hotkey.bind(hyper, "C", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local sf = win:screen():frame()
    if sf.h > sf.w then move(0, 0.5, 1, 0.5)()  -- Bottom Half
    else             move(0.5, 0, 0.5, 1)() end  -- Right Half
end)
hs.hotkey.bind(hyper, "X", function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local sf = win:screen():frame()
    if sf.h > sf.w then move(0, 0.25, 1, 0.5)() -- Center Half (vertical)
    else             move(0.25, 0, 0.5, 1)() end -- Center Half (horizontal)
end)

-- Corners (Quarters)
hs.hotkey.bind(hyper, "U", move(0, 0, 0.5, 0.5))    -- Top Left
hs.hotkey.bind(hyper, "I", move(0.5, 0, 0.5, 0.5))  -- Top Right
hs.hotkey.bind(hyper, "J", move(0, 0.5, 0.5, 0.5))  -- Bottom Left
hs.hotkey.bind(hyper, "K", move(0.5, 0.5, 0.5, 0.5))-- Bottom Right

-- Thirds (portrait monitor: horizontal thirds; landscape: vertical thirds)
hs.hotkey.bind(hyper, "A", third(1))
hs.hotkey.bind(hyper, "S", third(2))
hs.hotkey.bind(hyper, "D", third(3))

-- Two Thirds (portrait monitor: horizontal; landscape: vertical)
hs.hotkey.bind(hyper, "W", twoThirds(1))             -- First Two Thirds
hs.hotkey.bind(hyper, "E", twoThirds(2))             -- Last Two Thirds

-- Sixths (2 rows x 3 columns)
hs.hotkey.bind(hyper, "4", sixth(0, 0))             -- Upper Left
hs.hotkey.bind(hyper, "5", sixth(0, 1))             -- Upper Middle
hs.hotkey.bind(hyper, "6", sixth(0, 2))             -- Upper Right
hs.hotkey.bind(hyper, "7", sixth(1, 0))             -- Lower Left
hs.hotkey.bind(hyper, "8", sixth(1, 1))             -- Lower Middle
hs.hotkey.bind(hyper, "9", sixth(1, 2))             -- Lower Right

-- Sizing & Restoration
hs.hotkey.bind(hyper, "F", maximize)                -- Maximize
hs.hotkey.bind(hyper, "G", center)                  -- Center
hs.hotkey.bind(hyper, "Q", minimizeFocused)         -- Minimize
hs.hotkey.bind(hyper, "V", unMinimizeAll)           -- Restore All Minimized
hs.hotkey.bind(hyper, "return", fullscreen)         -- Fullscreen

hs.hotkey.bind(hyper, "-", resize("smaller"))       -- Make Smaller
hs.hotkey.bind(hyper, "=", resize("larger"))        -- Make Larger

-- Displays
hs.hotkey.bind(hyper, "O", moveDisplay("next"))     -- Next Display
hs.hotkey.bind(hyper, "Y", moveDisplay("prev"))     -- Previous Display

-- Focus Shifting
hs.hotkey.bind({"cmd", "alt"}, "H", function() smartFocus("West") end)
hs.hotkey.bind({"cmd", "alt"}, "L", function() smartFocus("East") end)
hs.hotkey.bind({"cmd", "alt"}, "K", function() smartFocus("North") end)
hs.hotkey.bind({"cmd", "alt"}, "J", function() smartFocus("South") end)

hs.hotkey.bind({"cmd", "alt"}, "Left", function() smartFocus("West") end)
hs.hotkey.bind({"cmd", "alt"}, "Right", function() smartFocus("East") end)
hs.hotkey.bind({"cmd", "alt"}, "Up", function() smartFocus("North") end)
hs.hotkey.bind({"cmd", "alt"}, "Down", function() smartFocus("South") end)

hs.hotkey.bind({"cmd", "ctrl"}, "H", function() smartFocus("West") end)
hs.hotkey.bind({"cmd", "ctrl"}, "L", function() smartFocus("East") end)
hs.hotkey.bind({"cmd", "ctrl"}, "K", function() smartFocus("North") end)
hs.hotkey.bind({"cmd", "ctrl"}, "J", function() smartFocus("South") end)

hs.hotkey.bind({"cmd", "ctrl"}, "Left", function() smartFocus("West") end)
hs.hotkey.bind({"cmd", "ctrl"}, "Right", function() smartFocus("East") end)
hs.hotkey.bind({"cmd", "ctrl"}, "Up", function() smartFocus("North") end)
hs.hotkey.bind({"cmd", "ctrl"}, "Down", function() smartFocus("South") end)


-- Scroll
hs.hotkey.bind({"ctrl", "shift"}, "J", function() startScroll(-BASE_SPEED) end, stopScroll)
hs.hotkey.bind({"ctrl", "shift"}, "K", function() startScroll(BASE_SPEED) end, stopScroll)

-- Terminal and Browser
hs.hotkey.bind(hyper, "T", launchWezterm)
hs.hotkey.bind(hyper, "N", launchChrome)
hs.hotkey.bind(hyper, "M", function()
  hs.osascript.applescript('tell application "Safari" to make new document')
  hs.application.launchOrFocus("Safari")
end)

-- Lock screen
hs.hotkey.bind(hyper, "delete", function()           -- Lock Screen
  hs.caffeinate.lockScreen()
end)

-- Block cmd+h everywhere except TigerVNC
local stopCmdH = hs.hotkey.new({"cmd"}, "h", function() end)
hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function(win)
    local appName = win:application():title()
    if appName:find("TigerVNC") then
        stopCmdH:disable()
    else
        stopCmdH:enable()
    end
end)


-- =====================================================================
-- CONFIG LOADED MESSAGE
-- =====================================================================
hs.hotkey.bind(hyper, "0", function()               -- Reload Config
  hs.reload()
end)

hs.alert.show("Hammerspoon Config Loaded")
