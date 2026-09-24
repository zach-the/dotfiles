local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local act = wezterm.action
local c = require 'colors'
config.disable_default_key_bindings = true

-- Helper variables to identify the OS based on the target_triple
local is_mac = wezterm.target_triple:find("darwin") ~= nil
local is_linux = wezterm.target_triple:find("linux") ~= nil

-- Is tmux the foreground process in this pane? Used to decide whether
-- Alt-based split/navigation keys should act on WezTerm's own panes or
-- pass through raw for tmux to handle -- unlike tab-cycling (where an
-- empty target genuinely means "nothing to cycle to"), splitting/moving
-- should always do *something*, so gating on pane count alone left these
-- keys silently doing nothing in a single WezTerm pane with no tmux
-- running.
local function pane_is_tmux(pane)
  local ok, name = pcall(function()
    return pane:get_foreground_process_name()
  end)
  return ok and name ~= nil and name:find 'tmux' ~= nil
end

-- Whether an Alt+h/j/k/l (or arrow) press should pass through raw to the
-- pane instead of moving WezTerm's own pane focus: either tmux owns this
-- pane (see pane_is_tmux above), or there's only one WezTerm pane in the
-- tab, so there's no WezTerm-level pane to move focus to anyway --
-- passing through lets the app inside (a shell, vim, etc.) receive the
-- keystroke rather than having it silently swallowed by a no-op.
local function should_passthrough(pane)
  return pane_is_tmux(pane) or #pane:tab():panes() <= 1
end

-- Equalize WezTerm's own panes in the current tab, mirroring tmux's
-- select-layout -E (Alt+=, tmux.conf section 4): panes sharing a row (same
-- top) get their widths evened out, then panes sharing a column (same
-- left) get their heights evened out.
--
-- WezTerm's AdjustPaneSize only moves one border by a relative amount --
-- there's no tmux resize-pane -x/-y equivalent to set an absolute size --
-- so each group is resized by walking left-to-right (or top-to-bottom)
-- and pushing only the border between each adjacent pair to its target
-- position, the same technique tmux-resize-pane.sh uses. Only positive
-- amounts are used (growing whichever side of the border needs the
-- space) since AdjustPaneSize's negative-amount behavior isn't reliable.
--
-- Grouping is by exact top/left match, not overlap like the tmux scripts
-- (which also handle a sub-split column/row counting as one slot in its
-- parent row/column) -- that means a simple row of panes or column of
-- panes equalizes correctly, but a pane that's itself split again within
-- one slot of a larger row/column won't be folded into that outer
-- group's count. Good enough for typical layouts; not a full port of
-- tmux's recursive tree-based algorithm.
local function equalize_panes(window, pane)
  local function equalize_groups(infos, pos_key, size_key, grow_dir, shrink_neighbor_dir, total)
    local groups = {}
    local order = {}
    for _, info in ipairs(infos) do
      local key = info[pos_key]
      if not groups[key] then
        groups[key] = {}
        table.insert(order, key)
      end
      table.insert(groups[key], info)
    end
    table.sort(order)
    for _, key in ipairs(order) do
      local group = groups[key]
      if #group > 1 then
        local cross_key = pos_key == 'top' and 'left' or 'top'
        table.sort(group, function(a, b) return a[cross_key] < b[cross_key] end)
        local target = math.floor(total / #group)
        for i = 1, #group - 1 do
          local delta = target - group[i][size_key]
          if delta > 0 then
            -- AdjustPaneSize acts on whichever pane is currently active,
            -- not on whatever pane object is passed to perform_action --
            -- so the target must be made active first, or this silently
            -- resizes the pane the user actually pressed Alt+= from.
            group[i].pane:activate()
            window:perform_action(act.AdjustPaneSize { grow_dir, delta }, group[i].pane)
            group[i][size_key] = target
            group[i + 1][size_key] = group[i + 1][size_key] - delta
          elseif delta < 0 then
            group[i + 1].pane:activate()
            window:perform_action(act.AdjustPaneSize { shrink_neighbor_dir, -delta }, group[i + 1].pane)
            group[i][size_key] = target
            group[i + 1][size_key] = group[i + 1][size_key] - delta
          end
        end
      end
    end
  end

  local infos = pane:tab():panes_with_info()
  if #infos < 2 then
    return
  end

  local tab_width, tab_height = 0, 0
  for _, info in ipairs(infos) do
    tab_width = math.max(tab_width, info.left + info.width)
    tab_height = math.max(tab_height, info.top + info.height)
  end

  -- Pass 1: equalize widths within each row (grouped by top).
  equalize_groups(infos, 'top', 'width', 'Right', 'Left', tab_width)

  -- Pass 2: equalize heights within each column (grouped by left),
  -- re-fetched since pass 1 may have moved panes' left edges.
  equalize_groups(pane:tab():panes_with_info(), 'left', 'height', 'Down', 'Up', tab_height)

  -- Each AdjustPaneSize call above had to activate its target pane; restore
  -- focus to whichever pane the user actually pressed Alt+= from.
  pane:activate()
end

config.window_background_opacity = is_mac and 0.88 or 1.0
config.text_background_opacity = is_mac and 0.88 or 1.0

-- Font Configuration
config.font = wezterm.font 'JetBrainsMono Nerd Font Mono'
config.font_size = is_linux and 11 or 14

-- Default Window Size
-- Note: WezTerm uses columns/rows, not pixels. Adjust these to match your old 1100x600 size.
config.initial_cols = 120
config.initial_rows = 35

config.colors = {
  foreground    = c.fg,
  background    = c.bg_normal,
  cursor_bg     = c.pink,
  cursor_fg     = c.bg,
  cursor_border = c.pink,
  selection_fg  = c.bg,
  selection_bg  = c.blue,
  split         = c.pink,
  ansi = {
    c.bg, c.pink, c.green, c.yellow,
    c.blue, c.purple, c.orange, c.white,
  },
  brights = {
    c.black_bright, c.pink_bright, c.green_bright, c.yellow_bright,
    c.blue_bright, c.purple_bright, c.orange_bright, c.white_bright,
  },
  tab_bar = {
    background   = c.bg_normal,
    active_tab   = { bg_color = c.pink,      fg_color = c.bg },
    inactive_tab = { bg_color = c.bg_normal,  fg_color = c.bg_normal },
    new_tab      = { bg_color = c.bg_normal,  fg_color = c.grey },
  },
}

-- Inactive border color dimming
config.inactive_pane_hsb = {
  brightness = 0.5,
}

-- Other Behavior
config.window_close_confirmation = 'NeverPrompt'
config.selection_word_boundary = " \t\n{}[]()\"'`|│"
config.default_cursor_style = 'BlinkingBlock'
config.pane_focus_follows_mouse = true

-- Tab Bar Customization
config.use_fancy_tab_bar = false -- Gives a retro, un-styled look similar to basic Kitty
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
-- config.tab_bar_at_bottom = true

-- OS Specific Settings
config.window_decorations = is_linux and "NONE" or "RESIZE" -- if linux, use NONE, else use RESIZE (needed for MACOS)
config.send_composed_key_when_left_alt_is_pressed = false -- macos_option_as_alt equivalent
config.send_composed_key_when_right_alt_is_pressed = false

-- Keybinds
config.keys = {
  -- Copy/Paste
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },

  -- Font size
  { key = '+', mods = 'CTRL|SHIFT', action = act.IncreaseFontSize },
  { key = '_', mods = 'CTRL|SHIFT', action = act.DecreaseFontSize },
  { key = '0', mods = 'CTRL|SHIFT', action = act.ResetFontSize },


  -- ctrl+hjkl to send arrow keys (linux only; on mac, handled by Karabiner)

  -- alt+shift+h/l move left/right by a word
  -- { key = 'H', mods = 'ALT|SHIFT', action = act.SendKey { key = 'LeftArrow', mods = 'CTRL' } },
  -- { key = 'L', mods = 'ALT|SHIFT', action = act.SendKey { key = 'RightArrow', mods = 'CTRL' } },

  -- WezTerm splits (was ALT, now SUPER+SHIFT)
  { key = '-',  mods = 'SUPER|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '\\', mods = 'SUPER|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
 
  -- Pane Swapping / Rotation
  -- { key = 'p', mods = 'ALT', action = act.PaneSelect { mode = 'SwapWithActive' } },
  -- { key = 'n', mods = 'ALT', action = act.PaneSelect { mode = 'SwapWithActive' } },
  -- { key = 'b', mods = 'ALT', action = act.PaneSelect { mode = 'SwapWithActive' } },
  -- { key = 'm', mods = 'ALT', action = act.RotatePanes 'Clockwise' },

  -- Swallow hyper+Z (Hammerspoon config reload) so it doesn't reach the terminal
  { key = 'z', mods = 'CTRL|ALT|SUPER|SHIFT', action = act.DisableDefaultAssignment },

  -- Switch to tab by number (win+1-9)
  { key = '1', mods = 'SUPER', action = act.ActivateTab(0) },
  { key = '2', mods = 'SUPER', action = act.ActivateTab(1) },
  { key = '3', mods = 'SUPER', action = act.ActivateTab(2) },
  { key = '4', mods = 'SUPER', action = act.ActivateTab(3) },
  { key = '5', mods = 'SUPER', action = act.ActivateTab(4) },
  { key = '6', mods = 'SUPER', action = act.ActivateTab(5) },
  { key = '7', mods = 'SUPER', action = act.ActivateTab(6) },
  { key = '8', mods = 'SUPER', action = act.ActivateTab(7) },
  { key = '9', mods = 'SUPER', action = act.ActivateTab(8) },

  -- Kitty Tab Actions
  { key = 'w', mods = 'SUPER', action = act.CloseCurrentPane { confirm = false } },
  { key = 't', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' }, 
  
  -- Pop in a tab from another window into the current one
  -- (Ctrl+Shift+D freed up for tmux copy-mode scroll-down)
  { key = 'i', mods = 'CTRL|SHIFT', action = act.PaneSelect { mode = 'MoveToNewTab' } },

  -- Ctrl+Tab / Ctrl+Shift+Tab : cycle WezTerm tabs forward/backward when
  -- there's more than one; with just a single tab, there's nothing to
  -- cycle, so pass the raw keypress through to the pane instead, letting
  -- tmux's own C-Tab/C-S-Tab window-cycling bindings (tmux.conf section 4)
  -- see it.
  {
    key = 'Tab',
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      if #window:mux_window():tabs() > 1 then
        window:perform_action(act.ActivateTabRelative(1), pane)
      else
        window:perform_action(act.SendKey { key = 'Tab', mods = 'CTRL' }, pane)
      end
    end),
  },
  {
    key = 'Tab',
    mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(window, pane)
      if #window:mux_window():tabs() > 1 then
        window:perform_action(act.ActivateTabRelative(-1), pane)
      else
        window:perform_action(act.SendKey { key = 'Tab', mods = 'CTRL|SHIFT' }, pane)
      end
    end),
  },

  -- Ctrl+Shift+H / Ctrl+Shift+L : same "cycle WezTerm tabs if there's more
  -- than one, otherwise pass through" pattern as Ctrl+(Shift+)Tab above, so
  -- these fall through to tmux's own C-S-H/C-S-L window-cycling bindings
  -- (tmux.conf section 4) when there's only a single WezTerm tab.
  {
    key = 'h',
    mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(window, pane)
      if #window:mux_window():tabs() > 1 then
        window:perform_action(act.ActivateTabRelative(-1), pane)
      else
        window:perform_action(act.SendKey { key = 'H', mods = 'CTRL|SHIFT' }, pane)
      end
    end),
  },
  {
    key = 'l',
    mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(window, pane)
      if #window:mux_window():tabs() > 1 then
        window:perform_action(act.ActivateTabRelative(1), pane)
      else
        window:perform_action(act.SendKey { key = 'L', mods = 'CTRL|SHIFT' }, pane)
      end
    end),
  },

  -- Win(Super)+/ : split the current WezTerm pane horizontally (new pane to the right)
  { key = '/', mods = 'SUPER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  -- Win(Super)+- : split the current WezTerm pane vertically (new pane below)
  { key = '-', mods = 'SUPER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  -- Alt+/, Alt+\, Alt+- are deliberately left unbound here (no WezTerm
  -- interception) so they pass through untouched to tmux's own M-/, M-\,
  -- M-- split bindings (tmux.conf section 4), with no collision risk
  -- against Super+//- above.

  -- Alt+= : equalize WezTerm's own panes (see equalize_panes above), unless
  -- tmux is the foreground process or there's only one WezTerm pane in the
  -- tab (see should_passthrough above) -- in which case pass the raw key
  -- through, to tmux's own M-= (select-layout -E, tmux.conf section 4) or
  -- to whatever app is running, rather than have it silently swallowed by
  -- equalize_panes' own no-op when there's nothing to equalize.
  {
    key = '=',
    mods = 'ALT',
    action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = '=', mods = 'ALT' }, pane)
      else
        equalize_panes(window, pane)
      end
    end),
  },

  -- Alt+h/j/k/l (and Alt+arrows) : move focus between WezTerm panes,
  -- unless tmux is the foreground process in the current pane or there's
  -- only one WezTerm pane in the tab (see should_passthrough above), in
  -- which case pass the raw key through -- to tmux's own M-h/j/k/l (or
  -- M-Left/Down/Up/Right) bindings, or to whatever app is running, rather
  -- than have it silently swallowed by ActivatePaneDirection's own no-op.
  { key = 'h', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'h', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Left', pane)
      end
    end) },
  { key = 'j', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'j', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Down', pane)
      end
    end) },
  { key = 'k', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'k', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Up', pane)
      end
    end) },
  { key = 'l', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'l', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Right', pane)
      end
    end) },
  { key = 'LeftArrow', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'LeftArrow', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Left', pane)
      end
    end) },
  { key = 'DownArrow', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'DownArrow', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Down', pane)
      end
    end) },
  { key = 'UpArrow', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'UpArrow', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Up', pane)
      end
    end) },
  { key = 'RightArrow', mods = 'ALT', action = wezterm.action_callback(function(window, pane)
      if should_passthrough(pane) then
        window:perform_action(act.SendKey { key = 'RightArrow', mods = 'ALT' }, pane)
      else
        window:perform_action(act.ActivatePaneDirection 'Right', pane)
      end
    end) },
  
  -- tmux support
  -- { key = '_',  mods = 'CTRL|SHIFT', action = act.SendString '\x02_' },
  -- { key = '|',  mods = 'CTRL|SHIFT', action = act.SendString '\x02|' },
  -- { key = 't', mods = 'CTRL|SHIFT', action = act.SendString '\x02T' },
  -- { key = 'w', mods = 'CTRL|SHIFT', action = act.SendString '\x02W' },
  -- { key = 'h', mods = 'CTRL|SHIFT', action = act.SendString '\x02H' },
  -- { key = 'l', mods = 'CTRL|SHIFT', action = act.SendString '\x02L' },
}

if is_linux then
  local hjkl = {
    { key = 'k', mods = 'CTRL', action = act.SendString '\x1b[A' },
    { key = 'j', mods = 'CTRL', action = act.SendString '\x1b[B' },
    { key = 'h', mods = 'CTRL', action = act.SendString '\x1b[D' },
    { key = 'l', mods = 'CTRL', action = act.SendString '\x1b[C' },
  }
  for _, bind in ipairs(hjkl) do
    table.insert(config.keys, bind)
  end
end

-- Mouse Bindings
config.mouse_bindings = {
  -- Right-click block selection
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = act.SelectTextAtMouseCursor 'Block',
  },
}


-- ==========================================
-- Custom Gradient Tab Bar (Numbers Only)
-- ==========================================
wezterm.on(
  'format-tab-title',
  function(tab, tabs, panes, config, hover, max_width)
    local background = c.bg_inactive
    local foreground = c.grey
    local edge_background = c.bg

    if tab.is_active then
      background = c.blue
      foreground = c.bg
    elseif hover then
      background = c.pink
      foreground = c.bg
    end

    local fade_in = '░▒▓'
    local fade_out = '▓▒░'

    -- Construct the title with just the tab number and some padding
    local title = ' ' .. (tab.tab_index + 1) .. ' '

    return {
      -- Left Fade
      { Background = { Color = edge_background } },
      { Foreground = { Color = background } },
      { Text = fade_in },

      -- Solid Tab Body
      { Background = { Color = background } },
      { Foreground = { Color = foreground } },
      { Text = title },

      -- Right Fade
      { Background = { Color = edge_background } },
      { Foreground = { Color = background } },
      { Text = fade_out },
    }
  end
)

config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}

return config
