local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local act = wezterm.action
config.disable_default_key_bindings = true

-- Helper variables to identify the OS based on the target_triple
local is_mac = wezterm.target_triple:find("darwin") ~= nil
local is_linux = wezterm.target_triple:find("linux") ~= nil

-- Font Configuration
config.font = wezterm.font 'JetBrainsMono Nerd Font Mono'
config.font_size = is_linux and 11 or 13

-- Default Window Size
-- Note: WezTerm uses columns/rows, not pixels. Adjust these to match your old 1100x600 size.
config.initial_cols = 120
config.initial_rows = 35

config.color_scheme = 'CyberpunkNeon'

-- Inactive border color dimming
config.inactive_pane_hsb = {
  brightness = 0.5,
}

-- Other Behavior
config.selection_word_boundary = " \t\n{}[]()\"'`"
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

  -- ctrl+hjkl to send arrow keys
  { key = 'k', mods = 'CTRL', action = act.SendString '\x1b[A' },
  { key = 'j', mods = 'CTRL', action = act.SendString '\x1b[B' },
  { key = 'h', mods = 'CTRL', action = act.SendString '\x1b[D' },
  { key = 'l', mods = 'CTRL', action = act.SendString '\x1b[C' },

  -- alt+shift+h/l move left/right by a word
  -- { key = 'H', mods = 'ALT|SHIFT', action = act.SendKey { key = 'LeftArrow', mods = 'CTRL' } },
  -- { key = 'L', mods = 'ALT|SHIFT', action = act.SendKey { key = 'RightArrow', mods = 'CTRL' } },

  -- Split Panes
  { key = '-', mods = 'ALT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } }, -- top/bottom split
  { key = '\\', mods = 'ALT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } }, -- left/right split
  
  -- Pane Swapping / Rotation
  { key = 'p', mods = 'ALT', action = act.PaneSelect { mode = 'SwapWithActive' } },
  { key = 'n', mods = 'ALT', action = act.PaneSelect { mode = 'SwapWithActive' } },
  { key = 'b', mods = 'ALT', action = act.PaneSelect { mode = 'SwapWithActive' } },
  { key = 'm', mods = 'ALT', action = act.RotatePanes 'Clockwise' },

  -- Kitty Tab Actions
  { key = 'H', mods = 'CMD', action = act.ActivateTabRelative(-1) },
  { key = 'L', mods = 'CMD', action = act.ActivateTabRelative(1) },
  { key = 'w', mods = 'CMD', action = act.CloseCurrentPane { confirm = false } },
  { key = 't', mods = 'CMD', action = act.SpawnTab 'CurrentPaneDomain' }, 
  
  -- Pop out and pop in tabs
  -- "Pop out" current tab to a new window
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(win, pane)
    pane:move_to_new_window()
  end) },
  -- "Pop in" a tab from another window into the current one
  { key = 'i', mods = 'CTRL|SHIFT', action = act.PaneSelect { mode = 'MoveToNewTab' } },
  
  -- Vim Keybinds for Navigation
  { key = 'h', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },
}

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
    -- Define colors matching your Cyberpunk theme
    local background = '#161626' -- inactive bg
    local foreground = '#787c99' -- inactive fg
    local edge_background = '#0d0d17' -- the base tab bar background

    if tab.is_active then
      background = '#ff007f' -- active bg (pink)
      foreground = '#0d0d17' -- active fg (obsidian)
    elseif hover then
      background = '#33ccff' -- hover bg (blue)
      foreground = '#0d0d17' -- hover fg
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


return config
