local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local act = wezterm.action
local c = require 'colors'
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
  { key = '-', mods = 'CTRL|SHIFT', action = act.DecreaseFontSize },
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
  { key = 'H', mods = 'SUPER', action = act.ActivateTabRelative(-1) },
  { key = 'L', mods = 'SUPER', action = act.ActivateTabRelative(1) },
  { key = 'w', mods = 'SUPER', action = act.CloseCurrentPane { confirm = false } },
  { key = 't', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' }, 
  
  -- Pop out and pop in tabs
  -- "Pop out" current tab to a new window
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(win, pane)
    pane:move_to_new_window()
  end) },
  -- "Pop in" a tab from another window into the current one
  { key = 'i', mods = 'CTRL|SHIFT', action = act.PaneSelect { mode = 'MoveToNewTab' } },
  
  -- Vim Keybinds for Navigation (replaced by tmux)
  -- { key = 'h', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  -- { key = 'l', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  -- { key = 'k', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  -- { key = 'j', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },

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
