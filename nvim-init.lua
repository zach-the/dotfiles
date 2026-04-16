-- ------------------------------------------------------ --
-- ╔════════════════════════════════════════════════════╗ --
-- ║ ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ║ --
-- ║ ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ║ --
-- ║ ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ║ --
-- ║ ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ║ --
-- ║ ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ║ --
-- ║ ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ║ --
-- ╚════════════════════════════════════════════════════╝ --
-- ------------------------------------------------------ --

-- Bootstrap lazy.nvim -------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    lazyrepo, lazypath
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Leader keys ---------------------------------------------------------------
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- linux/mac specific settings
if vim.loop.os_uname().sysname == "Darwin" then
  vim.o.clipboard = "unnamedplus"
elseif vim.loop.os_uname().sysname == "Linux" then
  -- xsel for clipboard ---------------------------------------------------------
  -- vim.g.clipboard = {
  --   name = 'xsel',
  --   copy = {
  --     ['+'] = 'xsel --clipboard --input',
  --     ['*'] = 'xsel --primary --input',
  --   },
  --   paste = {
  --     ['+'] = 'xsel --clipboard --output',
  --     ['*'] = 'xsel --primary --output',
  --   },
  --   cache_enabled = 0,
  -- }
end


-- Statusline ----------------------------------------------------------------
vim.o.statusline = table.concat({
  " %<%F",
  " %=",
  "%{&expandtab ? 'spaces:' . &shiftwidth : 'tabs:' . &tabstop}",
  " %5l / %2L ",
})

-- Basic settings ------------------------------------------------------------
vim.o.number = true
vim.o.relativenumber = true
vim.o.showmatch = true
vim.o.breakindent = true
vim.o.wrap = false
vim.o.smartcase = true
vim.o.ignorecase = true
vim.o.hlsearch = true
vim.o.clipboard = "unnamedplus"
vim.o.scrolloff = 5
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4
vim.o.softtabstop = 4
-- vim.o.termguicolors = true
vim.opt.termguicolors = false
vim.o.cursorline = true
vim.o.cursorcolumn = true
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Create an autocommand for HTML files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "html",
  callback = function()
    vim.opt_local.wrap = true      -- Enable wrapping
    vim.opt_local.linebreak = true -- Wrap at words rather than mid-character
  end,
})

-- Better up/down ------------------------------------------------------------
vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

-- Insert Mode: Better Arrow Keys (New)
-- <C-o> lets us execute one Normal mode command and then returns to Insert mode
vim.keymap.set('i', '<Down>', '<C-o>gj', { desc = "Down (display line)" })
vim.keymap.set('i', '<Up>', '<C-o>gk', { desc = "Up (display line)" })

-- Insert Mode: Alt+j/k for home-row navigation (New & Recommended)
-- This allows you to stay on the home row while moving through wrapped lines
vim.keymap.set('i', '<A-j>', '<C-o>gj', { desc = "Down (display line)" })
vim.keymap.set('i', '<A-k>', '<C-o>gk', { desc = "Up (display line)" })

-- Scroll 1/3 of the page instead of 1/2 fo the page -------------------------
vim.keymap.set('n', '<C-d>', function()
  local step = math.floor(vim.api.nvim_win_get_height(0) / 3)
  return step .. '<C-d>'
end, { expr = true, replace_keycodes = true })
vim.keymap.set('n', '<C-u>', function()
  local step = math.floor(vim.api.nvim_win_get_height(0) / 3)
  return step .. '<C-u>'
end, { expr = true, replace_keycodes = true })

-- Make macro recording purple -----------------------------------------------
-- Create the group for our autocommands
local macro_group = vim.api.nvim_create_augroup("macro", { clear = true })

-- Helper to get colors safely
local function get_hl_color(name, key)
  local hl = vim.api.nvim_get_hl(0, { name = name })
  if not hl or vim.tbl_isempty(hl) then return nil end
  
  local color = hl[key]
  if color then
    return string.format("#%06x", color)
  elseif hl.link then
    return get_hl_color(hl.link, key)
  end
  return nil 
end

vim.api.nvim_create_autocmd("RecordingEnter", {
  group = macro_group,
  callback = function()
    local text_color = get_hl_color("Normal", "fg") or "#1d2021"
    vim.api.nvim_set_hl(0, "MacroLine", { bg = "#c678dd", fg = text_color, bold = true })
    vim.opt_local.winhighlight = "CursorLine:MacroLine"
  end,
})

vim.api.nvim_create_autocmd("RecordingLeave", {
  group = macro_group,
  callback = function()
    -- Simply remove the window override. 
    -- Neovim falls back to the standard (transparent) CursorLine.
    vim.opt_local.winhighlight = ""
  end,
})

-- Normal/Visual Mode: Move line/block up/down ------------------------------
vim.keymap.set('n', '<S-j>', ':m .+1<CR>==', { silent = true })
vim.keymap.set('n', '<S-k>', ':m .-2<CR>==', { silent = true })
vim.keymap.set('v', '<S-j>', ":m '>+1<CR>gv=gv", { silent = true })
vim.keymap.set('v', '<S-k>', ":m '<-2<CR>gv=gv", { silent = true })

-- Make matches blue --------------------------------------------------------
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    vim.api.nvim_set_hl(0, "CurSearch", { bg = "#61afef", fg = "#dcdfe4" })
  end,
})

-- ----------------------------------------------------------- --
-- ╔═════════════════════════════════════════════════════════╗ --
-- ║ ██████╗ ██╗     ██╗   ██╗ ██████╗ ██╗███╗   ██╗███████╗ ║ --
-- ║ ██╔══██╗██║     ██║   ██║██╔════╝ ██║████╗  ██║██╔════╝ ║ --
-- ║ ██████╔╝██║     ██║   ██║██║  ███╗██║██╔██╗ ██║███████╗ ║ --
-- ║ ██╔═══╝ ██║     ██║   ██║██║   ██║██║██║╚██╗██║╚════██║ ║ --
-- ║ ██║     ███████╗╚██████╔╝╚██████╔╝██║██║ ╚████║███████║ ║ --
-- ║ ╚═╝     ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝ ║ --
-- ╚═════════════════════════════════════════════════════════╝ --
-- ----------------------------------------------------------- --

require("lazy").setup({
  spec = {
    "tpope/vim-sleuth",

-- -------------------------------------- --
--   _   _                                --
--  | |_| |__   ___ _ __ ___   ___  ___   --
--  | __| '_ \ / _ \ '_ ` _ \ / _ \/ __|  --
--  | |_| | | |  __/ | | | | |  __/\__ \  --
--   \__|_| |_|\___|_| |_| |_|\___||___/  --
--                                        --
-- -------------------------------------- --

    -- {
    --   "folke/tokyonight.nvim",
    --   lazy = false,
    --   priority = 1000,
    --   opts = {
    --     style = "night", -- Valid: storm, night, moon, day
    --     transparent = true, -- Enable transparent background
    --     styles = {
    --       sidebars = "transparent",
    --       floats = "transparent",
    --     },
    --   },
    --   config = function()
    --     vim.cmd[[colorscheme tokyonight]]
    --   end,
    -- },

    {
        'navarasu/onedark.nvim',
        priority = 1000, -- Load this before all other plugins
        config = function()
            require('onedark').setup({
                style = 'cool', -- Options: dark, darker, cool, deep, warm, warmer, light
                transparent = false, -- Show/hide background
                term_colors = true, -- Terminal colors
                ending_tildes = false, -- Show ~ at the end of buffer
                cmp_itemkind_reverse = false,
                
                -- Toggle italic text for keywords, functions, etc.
                code_style = {
                    comments = 'none',
                    keywords = 'none',
                    functions = 'none',
                    strings = 'none',
                    variables = 'none',
                },
            })
            require('onedark').load()
        end,
    },
    -- {
      -- "sonph/onehalf",
      -- priority = 1000,
      -- config = function()
        -- vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/onehalf/vim")
        -- vim.cmd.colorscheme("onehalfdark")
      -- end,
    -- },

-- --------------------------------------- --
--                             _   _       --
--   ___ _ __ ___   ___   ___ | |_| |__    --
--  / __| '_ ` _ \ / _ \ / _ \| __| '_ \   --
--  \__ \ | | | | | (_) | (_) | |_| | | |  --
--  |___/_| |_| |_|\___/ \___/ \__|_| |_|  --
--                                         --
-- --------------------------------------- --
    {
      "karb94/neoscroll.nvim",
      config = function()
        local neoscroll = require("neoscroll")
        neoscroll.setup({})

        -- Helper to translate keycodes
        local t = function(str)
          return vim.api.nvim_replace_termcodes(str, true, true, true)
        end

        -- =========================================================================
        -- Highlight Toggling Logic (Performance)
        -- =========================================================================
        -- Keeps track of stacked animations to prevent flickering
        local hl_disabled_counter = 0
        local hl_was_active = false

        local disable_hl = function()
          if hl_disabled_counter == 0 then
            -- Check if search is active (vim.v.hlsearch) and highlighting is on
            if vim.v.hlsearch == 1 and vim.opt.hlsearch:get() then
              hl_was_active = true
              vim.opt.hlsearch = false
            end
          end
          hl_disabled_counter = hl_disabled_counter + 1
        end

        local enable_hl = function()
          hl_disabled_counter = hl_disabled_counter - 1
          if hl_disabled_counter <= 0 then
            hl_disabled_counter = 0
            if hl_was_active then
              vim.opt.hlsearch = true
            end
            hl_was_active = false -- Reset state
          end
        end

        -- Configuration
        local small_step_duration = 225
        local mid_step_duration = 275
        local full_step_duration = 375
        local easing_profile = 'circular'
        local large_jump_duration = 500

        -- Define hooks for standard scrolling
        local scroll_opts = function(duration)
          return { 
            move_cursor = true, 
            duration = duration, 
            easing = easing_profile,
            pre_hook = disable_hl, 
            post_hook = enable_hl 
          } 
        end

        -- Standard Helpers
        local get_step = function() return math.floor(vim.api.nvim_win_get_height(0) * 4 / 9) end
        local get_small_step = function() return math.floor(vim.api.nvim_win_get_height(0) * 1 / 8) end
        local get_full_page = function() return vim.api.nvim_win_get_height(0) end

        -- Standard Keybindings (Updated with hooks)
        vim.keymap.set("n", "<C-y>", function() neoscroll.scroll(-get_small_step(), scroll_opts(small_step_duration)) end)
        vim.keymap.set("n", "<C-e>", function() neoscroll.scroll(get_small_step(), scroll_opts(small_step_duration)) end)
        vim.keymap.set("n", "<C-d>", function() neoscroll.scroll(get_step(), scroll_opts(mid_step_duration)) end)
        vim.keymap.set("n", "<C-u>", function() neoscroll.scroll(-get_step(), scroll_opts(mid_step_duration)) end)
        vim.keymap.set("n", "<C-f>", function() neoscroll.scroll(get_full_page(), scroll_opts(full_step_duration)) end)
        vim.keymap.set("n", "<C-b>", function() neoscroll.scroll(-get_full_page(), scroll_opts(full_step_duration)) end)

        -- =========================================================================
        -- Custom Logic: Smart Jump & Animated Cursor
        -- =========================================================================

        local get_duration = function(distance, screen_height)
          local ratio = distance / screen_height
          if ratio <= 0.125 then return 200
          elseif ratio <= 1.0 then return math.floor(200 + (ratio - 0.125) * (400 - 200) / (1.0 - 0.125))
          else return 450 end
        end

        -- [UPDATED] Cursor Animation with Quintic Ease-Out
        local animate_cursor = function(target_line)
          local current_line = vim.fn.line('.')
          local diff = target_line - current_line
          if diff == 0 then return end

          local screen_height = vim.api.nvim_win_get_height(0)
          local duration = get_duration(math.abs(diff), screen_height)

          disable_hl() -- Disable HL at start of animation

          local start_time = vim.uv.hrtime() / 1e6
          local timer = vim.uv.new_timer()

          timer:start(0, 16, vim.schedule_wrap(function()
            local now = vim.uv.hrtime() / 1e6
            local elapsed = now - start_time
            local t = math.min(elapsed / duration, 1)

            -- Quintic Ease-Out
            local ease = 1 - math.pow(1 - t, 5)

            local next_line = math.floor(current_line + (diff * ease) + 0.5)
            local max_lines = vim.fn.line('$')
            next_line = math.max(1, math.min(next_line, max_lines))

            pcall(vim.api.nvim_win_set_cursor, 0, { next_line, 0 })

            if t >= 1 then
              timer:stop(); timer:close()
              pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
              enable_hl() -- Re-enable HL when finished
            end
          end))
        end

        local smart_jump = function(target_line)
          local total_lines = vim.fn.line('$')
          target_line = math.max(1, math.min(target_line, total_lines))

          local current_line = vim.fn.line('.')
          local diff = target_line - current_line
          local abs_diff = math.abs(diff)
          local screen_height = vim.api.nvim_win_get_height(0)
          local scrolloff = vim.wo.scrolloff

          if abs_diff == 0 then return end

          if abs_diff > screen_height * 3 then
              local scroll_dist = screen_height  * 3
              local teleport_line

              if diff > 0 then -- DOWN
                  teleport_line = target_line - scroll_dist
                  teleport_line = math.max(1, math.min(teleport_line, total_lines))

                  vim.api.nvim_win_set_cursor(0, { teleport_line, 0 })
                  vim.cmd("norm! zb")
                  if scrolloff > 0 then vim.cmd("norm! " .. scrolloff .. t("<C-e>")) end

                  neoscroll.scroll(scroll_dist, { move_cursor = false, duration = 500, easing = 'linear', pre_hook = disable_hl, post_hook = enable_hl })
              else -- UP
                  teleport_line = target_line + scroll_dist
                  teleport_line = math.max(1, math.min(teleport_line, total_lines))

                  vim.api.nvim_win_set_cursor(0, { teleport_line, 0 })
                  vim.cmd("norm! zt")
                  if scrolloff > 0 then vim.cmd("norm! " .. scrolloff .. t("<C-y>")) end

                  neoscroll.scroll(-scroll_dist, { move_cursor = false, duration = 500, easing = 'linear', pre_hook = disable_hl, post_hook = enable_hl })
              end

              vim.defer_fn(function() animate_cursor(target_line) end, large_jump_duration)
          else
              neoscroll.scroll(diff, { move_cursor = true, duration = large_jump_duration, easing = easing_profile, pre_hook = disable_hl, post_hook = enable_hl })
          end
        end

        local move_smart = function(direction)
          local count = vim.v.count

          if count == 0 then 
            local wrap_dir = (direction == "j") and "gj" or "gk"
            vim.cmd("normal! " .. wrap_dir)
            return 
          end

          local current_line = vim.fn.line('.')
          local target_line = (direction == "j") and (current_line + count) or (current_line - count)
          local total_lines = vim.fn.line('$')
          target_line = math.max(1, math.min(target_line, total_lines))
          local screen_height = vim.api.nvim_win_get_height(0)

          if math.abs(target_line - current_line) > screen_height * 2 then
            smart_jump(target_line)
            return
          end

          local scrolloff = vim.wo.scrolloff
          local top_safe = vim.fn.line('w0') + scrolloff
          local bot_safe = vim.fn.line('w$') - scrolloff
          local scroll_needed = 0

          if target_line > bot_safe then scroll_needed = target_line - bot_safe
          elseif target_line < top_safe then scroll_needed = target_line - top_safe end

          if scroll_needed ~= 0 then
            local scroll_duration = get_duration(math.abs(scroll_needed), screen_height)
            neoscroll.scroll(scroll_needed, { move_cursor = false, duration = scroll_duration, easing = easing_profile, pre_hook = disable_hl, post_hook = enable_hl })
            vim.defer_fn(function() animate_cursor(target_line) end, scroll_duration + 10)
          else
            animate_cursor(target_line)
          end
        end

        vim.keymap.set("n", "j", function() move_smart("j") end, { silent = true })
        vim.keymap.set("n", "k", function() move_smart("k") end, { silent = true })
        vim.keymap.set("n", "gg", function() smart_jump(1) end)
        vim.keymap.set("n", "G", function() smart_jump(vim.fn.line('$')) end)
      end,
    },

-- --------------------------------------- --
--   _   _                            _    --
--  | |_| |__   ___     _ __ ___  ___| |_  --
--  | __| '_ \ / _ \   | '__/ _ \/ __| __| --
--  | |_| | | |  __/   | | |  __/\__ \ |_  --
--   \__|_| |_|\___|   |_|  \___||___/\__| --
--                                         --                                       
-- --------------------------------------- --

    {
      'tribela/transparent.nvim',
      event = 'VimEnter',
      config = function()
        require('transparent').setup({
          exclude_groups = { "CursorLine" },
        })
      end,
    },

    {
      "numToStr/Comment.nvim",
      dependencies = { "nvim-treesitter/nvim-treesitter" },
      config = function()
        local comment = require("Comment")
        local api = require("Comment.api")

        comment.setup()

        -- Keymap <C-\> for intelligent commenting
        vim.keymap.set("n", "<C-\\>", function()
          local count = vim.v.count1
          for _ = 1, count do
            api.toggle.linewise.current()
            vim.cmd("normal! j")
          end
        end, { noremap = true, silent = true, desc = "Toggle comment line(s)" })

        vim.keymap.set("x", "<C-\\>", function()
          local esc = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)
          vim.api.nvim_feedkeys(esc, "nx", false)
          api.toggle.linewise(vim.fn.visualmode())
          vim.cmd("normal! j")
        end, { noremap = true, silent = true, desc = "Toggle comment selection" })

        vim.keymap.set("i", "<C-\\>", function()
          vim.cmd("stopinsert")
          api.toggle.linewise.current()
          vim.cmd("normal! jA")
        end, { noremap = true, silent = true, desc = "Toggle comment from insert" })
      end,
    },


    {
      "andrewferrier/wrapping.nvim",
      config = function()
        require("wrapping").setup({
          softener = { markdown = true, html = true, text = true },
          create_keymaps = true,
          keymaps = {
            motion = true,
            text_obj = true,
          },
        })
      end,
    },

    {
      "nvim-telescope/telescope.nvim",
      tag = "0.1.8",
      dependencies = { "nvim-lua/plenary.nvim" },
      config = function()
        local telescope = require("telescope")
        local builtin = require("telescope.builtin")

        telescope.setup({
          defaults = {
            prompt_prefix = "🔍 ",
            selection_caret = " ",
            sorting_strategy = "ascending",
            layout_config = {
              prompt_position = "top",
            },
            mappings = {
              i = {
                ["<C-j>"] = "move_selection_next",
                ["<C-k>"] = "move_selection_previous",
              },
            },
          },
        })

        -- Keymaps for quick access
        local map = vim.keymap.set
        map("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
        map("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
        map("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
        map("n", "<leader>fh", builtin.help_tags, { desc = "Find help" })
      end,
    },

    {
      "folke/snacks.nvim",
      opts = {
        -- indent = { enabled = true }, -- this is the one that creates the long vertical pipes
        input = { enabled = true },
        notifier = { enabled = false },
        scope = { enabled = true },
        statuscolumn = { enabled = false },
        words = { enabled = true },
      },
    },
      
    {
      "nvim-lualine/lualine.nvim",
      config = function()
        vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/onehalf/vim")
        local config = {
          options = {
            component_separators = "",
            section_separators = "",
          },
          sections = {
            lualine_a = {
              {
                "mode",
                fmt = function(s)
                  local map = {
                    NORMAL = "N", INSERT = "I", VISUAL = "V", ["V-LINE"] = "VL",
                    REPLACE = "R", COMMAND = "!", TERMINAL = "T",
                  }
                  return map[s] or s
                end,
              },
            },
            lualine_b = {
              { "branch", icon = "" },
            },
            lualine_c = {
              {
                "filename",
                path = 2, -- Absolute path (as discussed)
                
                -- Dynamic color logic
                color = function()
                  -- Check if the buffer is modified
                  local is_modified = vim.bo.modified
                  
                  -- Return specific hex color if modified, otherwise use default (nil)
                  -- '#ff9e64' is a bright orange. You can change this to any hex code.
                  return { fg = is_modified and "#e06c75" or nil, gui = is_modified and "bold" or nil }
                end,
              },
            },
            lualine_x = {
              { "diagnostics", sources = { "nvim_diagnostic" } },
              {
                function()
                  return "lines:" .. vim.api.nvim_buf_line_count(0)
                end,
              },
              { "progress" },   -- percentage through the file
              { "location" },   -- current line:column
              { "fileformat", fmt = string.upper },
            },
            lualine_y = {},
            lualine_z = {},
          },
          inactive_sections = {
            lualine_a = {}, lualine_b = {}, lualine_y = {},
            lualine_z = {}, lualine_c = {}, lualine_x = {},
          },
        }

        require("lualine").setup(config)
      end,
    },
    -- end of plugins
  },

  -- General lazy.nvim settings
  checker = { enabled = true, notify = false },
  change_detection = { enabled = true, notify = false },
  ui = { wrap = true },
})
