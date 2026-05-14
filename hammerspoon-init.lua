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
-- INSTRUCTIONS
-- =====================================================================
-- cd ~/ ; ln -s ~/manual-sync-dotfiles/hammerspoon-init.lua ~/.hammerspoon/init.lua

-- =====================================================================
-- DEFINE HYPER : CTRL + OPT + CMD + SHIFT
-- =====================================================================
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

    for _, w in ipairs(allWindows) do
        -- Check: Not current window + Visible + Standard (avoids tooltips/popups)
        if w:id() ~= win:id() and w:isVisible() and w:isStandard() then
            local f = w:frame()
            local c = {x = f.x + f.w/2, y = f.y + f.h/2}

            -- Calculate deltas
            local deltaX = c.x - winCenter.x
            local deltaY = c.y - winCenter.y

            local isCandidate = false

            -- Geometric "Cone" Check
            -- We ensure the window is mostly in the target direction (avoids diagonals)
            if direction == "West" then
                if deltaX < 0 and math.abs(deltaX) > math.abs(deltaY) then isCandidate = true end
            elseif direction == "East" then
                if deltaX > 0 and math.abs(deltaX) > math.abs(deltaY) then isCandidate = true end
            elseif direction == "North" then
                if deltaY < 0 and math.abs(deltaY) > math.abs(deltaX) then isCandidate = true end
            elseif direction == "South" then
                if deltaY > 0 and math.abs(deltaY) > math.abs(deltaX) then isCandidate = true end
            end

            if isCandidate then
                local distance = deltaX^2 + deltaY^2
                table.insert(candidates, {window = w, dist = distance})
            end
        end
    end

    -- Also add empty screens as virtual candidates
    for _, screen in ipairs(hs.screen.allScreens()) do
        if screen:id() ~= winScreen:id() and not screensWithWindows[screen:id()] then
            local sf = screen:frame()
            local sc = {x = sf.x + sf.w/2, y = sf.y + sf.h/2}
            local deltaX = sc.x - winCenter.x
            local deltaY = sc.y - winCenter.y

            local isCandidate = false
            if direction == "West" then
                if deltaX < 0 and math.abs(deltaX) > math.abs(deltaY) then isCandidate = true end
            elseif direction == "East" then
                if deltaX > 0 and math.abs(deltaX) > math.abs(deltaY) then isCandidate = true end
            elseif direction == "North" then
                if deltaY < 0 and math.abs(deltaY) > math.abs(deltaX) then isCandidate = true end
            elseif direction == "South" then
                if deltaY > 0 and math.abs(deltaY) > math.abs(deltaX) then isCandidate = true end
            end

            if isCandidate then
                local distance = deltaX^2 + deltaY^2
                -- virtual candidate: no window field, just a point to move the mouse to
                table.insert(candidates, {point = sc, dist = distance})
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
            best.window:focus()
            moveMouseToWindow(best.window)
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

-- Unminimize All Windows
local function unMinimizeAll()
    local windows = hs.window.allWindows()
    local count = 0

    for _, win in ipairs(windows) do
        if win:isMinimized() then
            win:unminimize()
            count = count + 1
        end
    end

    if count > 0 then
    else
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

-- Function to minimize all windows except the focused one
local function isolateActiveWindow()
    local activeWindow = hs.window.focusedWindow()
    if not activeWindow then return end

    -- Get all visible windows across all screens
    local allWindows = hs.window.visibleWindows()

    for _, win in ipairs(allWindows) do
        -- Check if the window is NOT the active one and is NOT already minimized
        if win:id() ~= activeWindow:id() then
            win:minimize()
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
local TAP_WINDOW = 0.15
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
-- FAST MULTI-MONITOR SPACE SWITCHING (Primary -> Externals -> Built-in)
-- =====================================================================

local function getMacOSScreenOrder()
    local screens = hs.screen.allScreens()
    local primary = hs.screen.primaryScreen()

    local orderedScreens = { primary }
    local externals = {}
    local builtIns = {}

    -- Separate the secondary screens into Externals and Built-ins
    for _, screen in ipairs(screens) do
        if screen:id() ~= primary:id() then
            -- We identify the laptop screen by its standard macOS naming convention
            if string.match(screen:name(), "Built%-in") then
                table.insert(builtIns, screen)
            else
                table.insert(externals, screen)
            end
        end
    end

    -- Sort multiple externals geometrically (just in case you add a 3rd external monitor later)
    table.sort(externals, function(a, b) return a:frame().x < b:frame().x end)

    -- Construct the final list: Primary -> Externals -> Built-ins
    for _, screen in ipairs(externals) do table.insert(orderedScreens, screen) end
    for _, screen in ipairs(builtIns) do table.insert(orderedScreens, screen) end

    return orderedScreens
end

-- =====================================================================
-- THE SWITCHING LOGIC (Hard Boundaries, No Wrap-Around)
-- =====================================================================

local function switchSpace(direction)
    local focusedScreen = hs.mouse.getCurrentScreen()
    local orderedScreens = getMacOSScreenOrder()
    local activeSpace = hs.spaces.activeSpaceOnScreen(focusedScreen)
    local localSpaces = hs.spaces.spacesForScreen(focusedScreen)

    local globalSpaces = {}
    for _, screen in ipairs(orderedScreens) do
        local screenSpaces = hs.spaces.spacesForScreen(screen)
        if screenSpaces then
            for _, spaceID in ipairs(screenSpaces) do
                table.insert(globalSpaces, spaceID)
            end
        end
    end

    local localIndex = nil
    for i, spaceID in ipairs(localSpaces) do
        if spaceID == activeSpace then
            localIndex = i
            break
        end
    end
    if not localIndex then return end

    local targetLocalIndex = localIndex + (direction == "next" and 1 or -1)

    -- Hard Wall
    if targetLocalIndex < 1 or targetLocalIndex > #localSpaces then return end

    local targetSpaceID = localSpaces[targetLocalIndex]
    local targetGlobalIndex = nil
    for i, spaceID in ipairs(globalSpaces) do
        if spaceID == targetSpaceID then
            targetGlobalIndex = i
            break
        end
    end

    if targetGlobalIndex and targetGlobalIndex <= 9 then
        hs.eventtap.keyStroke({"ctrl"}, tostring(targetGlobalIndex))
    end
end

-- =====================================================================
-- SPACES X-RAY DEBUGGER
-- =====================================================================

local function debugSpaces()
    local orderedScreens = getMacOSScreenOrder()
    local focusedScreen = hs.mouse.getCurrentScreen()

    local msg = "=== SPACES X-RAY ===\n\n"
    local globalCounter = 1

    for screenIndex, screen in ipairs(orderedScreens) do
        local isPrimary = (screen:id() == hs.screen.primaryScreen():id()) and " [PRIMARY]" or ""
        local isFocused = (screen:id() == focusedScreen:id()) and " [FOCUSED]" or ""

        msg = msg .. "Screen " .. screenIndex .. isPrimary .. isFocused .. "\n"
        msg = msg .. "Name: " .. screen:name() .. "\n"

        local screenSpaces = hs.spaces.spacesForScreen(screen)
        local activeSpace = hs.spaces.activeSpaceOnScreen(screen)

        if screenSpaces then
            for _, spaceID in ipairs(screenSpaces) do
                local activeMark = (spaceID == activeSpace) and "  <-- ACTIVE" or ""
                msg = msg .. "  -> Space ID: " .. spaceID .. "  |  Maps to: ^" .. globalCounter .. activeMark .. "\n"
                globalCounter = globalCounter + 1
            end
        else
            msg = msg .. "  -> No spaces found.\n"
        end
        msg = msg .. "\n"
    end

    print(msg)
    hs.alert.show(msg, 8)
end


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

-- Halves
hs.hotkey.bind(hyper, "A", move(0, 0, 0.5, 1))      -- Left Half
hs.hotkey.bind(hyper, "D", move(0.5, 0, 0.5, 1))    -- Right Half
hs.hotkey.bind(hyper, "S", move(0.25, 0, 0.5, 1))   -- Center Half

hs.hotkey.bind(hyper, "G", move(0, 0, 1, 0.5))      -- Top Half
hs.hotkey.bind(hyper, "B", move(0, 0.5, 1, 0.5))    -- Bottom Half

-- Corners (Quarters)
hs.hotkey.bind(hyper, "U", move(0, 0, 0.5, 0.5))    -- Top Left
hs.hotkey.bind(hyper, "I", move(0.5, 0, 0.5, 0.5))  -- Top Right
hs.hotkey.bind(hyper, "J", move(0, 0.5, 0.5, 0.5))  -- Bottom Left
hs.hotkey.bind(hyper, "K", move(0.5, 0.5, 0.5, 0.5))-- Bottom Right

-- Thirds
hs.hotkey.bind(hyper, "1", move(0, 0, 1/3, 1))      -- First Third
hs.hotkey.bind(hyper, "2", move(1/3, 0, 1/3, 1))    -- Center Third
hs.hotkey.bind(hyper, "3", move(2/3, 0, 1/3, 1))    -- Last Third

-- Two Thirds
hs.hotkey.bind(hyper, "W", move(0, 0, 2/3, 1))      -- First Two Thirds
hs.hotkey.bind(hyper, "E", move(1/3, 0, 2/3, 1))    -- Last Two Thirds

-- Sizing & Restoration
hs.hotkey.bind(hyper, "F", maximize)                -- Maximize
hs.hotkey.bind(hyper, "C", center)                  -- Center
hs.hotkey.bind(hyper, "R", unMinimizeAll)           -- Unminimize All
hs.hotkey.bind(hyper, "M", isolateActiveWindow)     -- Minimize All Except Active
hs.hotkey.bind(hyper, "Q", minimizeFocused)         -- Minimize
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

-- Scroll
hs.hotkey.bind({"ctrl", "shift"}, "J", function() startScroll(-BASE_SPEED) end, stopScroll)
hs.hotkey.bind({"ctrl", "shift"}, "K", function() startScroll(BASE_SPEED) end, stopScroll)

-- Terminal and Browser
hs.hotkey.bind(hyper, "T", launchWezterm)
hs.hotkey.bind(hyper, "N", launchChrome)

-- Debug
hs.hotkey.bind(hyper, "P", debugSpaces)

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
-- MONITOR MODE SWITCHER
-- =====================================================================
-- Two modes: "plugged" (external monitor connected) and "unplugged" (laptop only).
-- On a screen change event, saves all windows for the current mode, minimizes
-- everything, then restores all windows saved for the incoming mode.
-- State persists across reloads in ~/.hammerspoon/monitor_mode_state.json

local monitorModeState   = { plugged = {}, unplugged = {} }
local currentMonitorMode = nil
local modeDebounceTimer  = nil
local MODE_STATE_FILE    = os.getenv("HOME") .. "/.hammerspoon/monitor_mode_state.json"
local mmLog              = hs.logger.new("monitorMode", "info")

local NEVER_HIDE = { Finder = true, SystemUIServer = true, Dock = true, Spotlight = true, loginwindow = true }

local function loadModeState()
  local f = io.open(MODE_STATE_FILE, "r")
  if not f then return end
  local raw = f:read("*a"); f:close()
  local ok, data = pcall(hs.json.decode, raw)
  if ok and data then monitorModeState = data end
end

local function saveModeState()
  local ok, encoded = pcall(hs.json.encode, monitorModeState)
  if not ok then return end
  local f = io.open(MODE_STATE_FILE, "w")
  if not f then return end
  f:write(encoded); f:close()
end

local function detectMode()
  return #hs.screen.allScreens() > 1 and "plugged" or "unplugged"
end

-- Collect every standard window across every space on every screen.
-- Two-pass approach because app:allWindows() misses inactive-space windows
-- on newer macOS: the hs.spaces pass catches what the app pass misses.
local function collectAllWindows()
  local result = {}
  local seen   = {}

  local function add(win)
    if win and not seen[win:id()] and win:isStandard() then
      local app = win:application()
      if app and not NEVER_HIDE[app:name()] then
        seen[win:id()] = true
        result[#result + 1] = win
      end
    end
  end

  -- Pass 1: per-app enumeration
  for _, app in ipairs(hs.application.runningApplications()) do
    if not NEVER_HIDE[app:name()] then
      for _, win in ipairs(app:allWindows()) do add(win) end
    end
  end

  -- Pass 2: per-space enumeration via hs.spaces (catches inactive-space windows)
  for _, screen in ipairs(hs.screen.allScreens()) do
    for _, sid in ipairs(hs.spaces.spacesForScreen(screen) or {}) do
      local ok, ids = pcall(hs.spaces.allWindowsForSpace, sid)
      if ok and ids then
        for _, wid in ipairs(ids) do
          add(hs.window(wid))
        end
      end
    end
  end

  mmLog.i("collectAllWindows found " .. #result .. " windows")
  return result
end

local function captureAllWindows()
  local snapshot = {}
  for _, win in ipairs(collectAllWindows()) do
    local app = win:application()
    local f   = win:frame()
    local s   = win:screen()
    local entry = {
      appName    = app:name(),
      bundleID   = app:bundleID() or "",
      title      = win:title(),
      frame      = { x = f.x, y = f.y, w = f.w, h = f.h },
      screenName = s and s:name() or "",
      screenId   = s and s:id() or 0,
      wasHidden  = win:isMinimized(),  -- app:isHidden() would silently drop whole apps
    }
    mmLog.i("  capture: [" .. (entry.wasHidden and "minimized" or "visible") .. "] " .. entry.appName .. " — " .. entry.title)
    snapshot[#snapshot + 1] = entry
  end
  return snapshot
end

local function minimizeAllWindows()
  local wins = collectAllWindows()
  mmLog.i("minimizeAllWindows: targeting " .. #wins .. " windows")
  for _, win in ipairs(wins) do
    if not win:isMinimized() then
      if win:isFullscreen() then
        win:setFullscreen(false)
        local w = win
        hs.timer.doAfter(0.6, function() if w:isStandard() then w:minimize() end end)
      else
        win:minimize()
      end
    end
  end
end

local function restoreWindowsForMode(mode)
  local saved = monitorModeState[mode]
  if not saved or #saved == 0 then
    hs.alert.show("Monitor: no saved layout for '" .. mode .. "'", 2)
    return
  end

  -- Index screens by both ID and name so either can match
  local screenById   = {}
  local screenByName = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    screenById[s:id()]     = s
    screenByName[s:name()] = s
  end
  local primary = hs.screen.primaryScreen()

  local byExact = {}
  local byApp   = {}
  local claimed = {}

  for _, win in ipairs(collectAllWindows()) do
    local app = win:application()
    local bid = app:bundleID() or app:name()
    local exact = bid .. "|" .. win:title()
    byExact[exact] = byExact[exact] or {}
    byExact[exact][#byExact[exact] + 1] = win
    byApp[bid] = byApp[bid] or {}
    byApp[bid][#byApp[bid] + 1] = win
  end

  local function claimWin(entry)
    local bid   = entry.bundleID ~= "" and entry.bundleID or entry.appName
    local exact = bid .. "|" .. entry.title
    for _, pool in ipairs({ byExact[exact], byApp[bid] }) do
      if pool then
        for _, w in ipairs(pool) do
          if not claimed[w:id()] then
            claimed[w:id()] = true
            return w
          end
        end
      end
    end
  end

  -- Build the full restore list before touching any windows
  local restoreList = {}
  mmLog.i("restoreWindowsForMode: " .. mode .. " has " .. #saved .. " saved entries")
  for _, entry in ipairs(saved) do
    if not entry.wasHidden then
      local win = claimWin(entry)
      if win then
        -- Resolve target screen: prefer ID match, fall back to name, then clamp to primary
        local targetScreen = screenById[entry.screenId or 0] or screenByName[entry.screenName]
        local f = entry.frame
        if not targetScreen then
          local pf = primary:frame()
          f = {
            x = math.max(pf.x, math.min(f.x, pf.x + pf.w - f.w)),
            y = math.max(pf.y, math.min(f.y, pf.y + pf.h - f.h)),
            w = f.w, h = f.h,
          }
        end
        mmLog.i("  restore: " .. entry.appName .. " — " .. entry.title)
        restoreList[#restoreList + 1] = { win = win, frame = f }
      else
        mmLog.i("  restore: NO MATCH for " .. entry.appName .. " — " .. entry.title)
      end
    end
  end

  -- Phase 1: unminimize all at once
  for _, item in ipairs(restoreList) do
    item.win:unminimize()
  end

  -- Phase 2: set all frames after animations finish.
  -- duration=0 makes setFrame instant so it can't be overridden by the unminimize animation.
  local function applyFrames()
    for _, item in ipairs(restoreList) do
      if item.win:isStandard() then
        item.win:setFrame(hs.geometry(item.frame.x, item.frame.y, item.frame.w, item.frame.h), 0)
      end
    end
  end

  hs.timer.doAfter(0.6, applyFrames)
  hs.timer.doAfter(1.5, applyFrames)  -- second pass catches stragglers
end

local function doMonitorModeSwitch()
  local newMode = detectMode()
  if newMode == currentMonitorMode then return end

  mmLog.i("switching " .. currentMonitorMode .. " → " .. newMode)
  monitorModeState[currentMonitorMode] = captureAllWindows()
  saveModeState()
  minimizeAllWindows()

  local previousMode = currentMonitorMode
  currentMonitorMode = newMode
  hs.alert.show("Monitor: " .. previousMode .. "  →  " .. newMode, 2)
  -- 2.5s gives fullscreen windows time to exit (0.6s) + minimize animation + buffer
  hs.timer.doAfter(2.5, function() restoreWindowsForMode(currentMonitorMode) end)
end

local function onScreenChange()
  if modeDebounceTimer then modeDebounceTimer:stop() end
  modeDebounceTimer = hs.timer.doAfter(2.0, doMonitorModeSwitch)
end

hs.hotkey.bind(hyper, "V", function()
  monitorModeState[currentMonitorMode] = captureAllWindows()
  saveModeState()
  hs.alert.show("Monitor: saved layout for '" .. currentMonitorMode .. "'", 2)
end)

-- Bootstrap (disabled — re-enable by uncommenting below)
-- loadModeState()
-- currentMonitorMode = detectMode()

-- monitorWatcher = hs.screen.watcher.new(onScreenChange)
-- monitorWatcher:start()

local function currentScreenIds()
  local ids = {}
  for _, s in ipairs(hs.screen.allScreens()) do ids[s:id()] = true end
  return ids
end

-- local lastScreenIds = currentScreenIds()
-- screenPollTimer = hs.timer.doEvery(2, function()
--   local nowIds  = currentScreenIds()
--   local changed = false
--   for id in pairs(lastScreenIds) do
--     if not nowIds[id] then changed = true; break end
--   end
--   if not changed then
--     for id in pairs(nowIds) do
--       if not lastScreenIds[id] then changed = true; break end
--     end
--   end
--   if changed then
--     lastScreenIds = nowIds
--     onScreenChange()
--   end
-- end)

-- =====================================================================
-- CONFIG LOADED MESSAGE
-- =====================================================================
hs.hotkey.bind(hyper, "Z", function()               -- Reload Config
  hs.reload()
end)

hs.alert.show("Hammerspoon Config Loaded")
