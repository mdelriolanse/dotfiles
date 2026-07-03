-- Theme toggle: catppuccin (opaque purple backdrop) <-> gruvbox (black-glass transparent).
--
-- Single source of truth for which colorscheme is active, the mode-aware highlight
-- overrides that used to live inline in plugins/catppuccin.lua, the lualine re-theme,
-- and persistence of the chosen mode across restarts. Triggered by :ThemeToggle.

local M = {}

local MODES = { catppuccin = true, gruvbox = true }
local state_file = vim.fn.stdpath 'state' .. '/theme-mode'

-- Persistence ---------------------------------------------------------------

local function read_mode()
  local f = io.open(state_file, 'r')
  if not f then
    return 'catppuccin'
  end
  local mode = vim.trim(f:read '*a' or '')
  f:close()
  return MODES[mode] and mode or 'catppuccin'
end

local function write_mode(mode)
  local f = io.open(state_file, 'w')
  if not f then
    return
  end
  f:write(mode)
  f:close()
end

M.mode = read_mode()

-- Highlight appliers --------------------------------------------------------

-- Catppuccin: tint editor, floats, neo-tree, and lualine middle sections with the
-- opaque mauve-flavoured backdrop from core.theme.
local function apply_catppuccin_tint()
  local palette = require('catppuccin.palettes').get_palette 'mocha'
  local backdrop = require 'core.theme'
  local mauve = backdrop.accent
  local bg = backdrop.bg
  local bg_dim = backdrop.bg_dim

  -- Editor
  vim.api.nvim_set_hl(0, 'Normal', { bg = bg, fg = palette.text })
  vim.api.nvim_set_hl(0, 'NormalNC', { bg = bg, fg = palette.text })
  vim.api.nvim_set_hl(0, 'EndOfBuffer', { bg = bg, fg = bg })
  vim.api.nvim_set_hl(0, 'SignColumn', { bg = bg })
  vim.api.nvim_set_hl(0, 'LineNr', { bg = bg, fg = palette.overlay0 })
  vim.api.nvim_set_hl(0, 'CursorLineNr', { bg = bg, fg = mauve, bold = true })
  vim.api.nvim_set_hl(0, 'WinSeparator', { bg = bg, fg = mauve })

  -- Floats (hover, diagnostics, etc.)
  vim.api.nvim_set_hl(0, 'NormalFloat', { bg = bg, fg = palette.text })
  vim.api.nvim_set_hl(0, 'FloatBorder', { bg = bg, fg = mauve })
  vim.api.nvim_set_hl(0, 'FloatTitle', { bg = bg, fg = mauve, bold = true })

  -- Neo-tree
  vim.api.nvim_set_hl(0, 'NeoTreeNormal', { bg = bg_dim, fg = palette.text })
  vim.api.nvim_set_hl(0, 'NeoTreeNormalNC', { bg = bg_dim, fg = palette.text })
  vim.api.nvim_set_hl(0, 'NeoTreeEndOfBuffer', { bg = bg_dim, fg = bg_dim })
  vim.api.nvim_set_hl(0, 'NeoTreeWinSeparator', { bg = bg_dim, fg = mauve })
  vim.api.nvim_set_hl(0, 'NeoTreeTitleBar', { bg = mauve, fg = palette.base, bold = true })

  -- Lualine middle sections (c/x). Section a/b/y/z keep their mode colors.
  for _, mode in ipairs { 'normal', 'insert', 'visual', 'replace', 'command', 'terminal', 'inactive' } do
    vim.api.nvim_set_hl(0, 'lualine_c_' .. mode, { bg = bg, fg = palette.text })
    vim.api.nvim_set_hl(0, 'lualine_x_' .. mode, { bg = bg, fg = palette.text })
  end
end

-- Clear a highlight group's background to NONE while preserving its other
-- attributes (fg, bold, etc.) so gruvbox's foregrounds survive.
local function clear_bg(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if not ok then
    return
  end
  hl.bg = nil
  hl.ctermbg = nil
  vim.api.nvim_set_hl(0, group, hl)
end

-- Gruvbox: gruvbox's transparent_mode already NONEs Normal/NormalNC/SignColumn/
-- EndOfBuffer. Additionally clear the groups the catppuccin tint would otherwise
-- fill, so the terminal's black glass shows through the whole UI.
local function apply_gruvbox_transparent()
  local groups = {
    'NormalFloat',
    'FloatBorder',
    'FloatTitle',
    'NeoTreeNormal',
    'NeoTreeNormalNC',
    'NeoTreeEndOfBuffer',
    'NeoTreeWinSeparator',
    'NeoTreeTitleBar',
  }
  for _, mode in ipairs { 'normal', 'insert', 'visual', 'replace', 'command', 'terminal', 'inactive' } do
    groups[#groups + 1] = 'lualine_c_' .. mode
    groups[#groups + 1] = 'lualine_x_' .. mode
  end
  for _, group in ipairs(groups) do
    clear_bg(group)
  end
end

local function apply_highlights()
  if M.mode == 'gruvbox' then
    apply_gruvbox_transparent()
  else
    apply_catppuccin_tint()
  end
end

-- Lualine re-theme ----------------------------------------------------------

-- Re-run lualine.setup with the full stashed config (see plugins/lualine.lua) but a
-- swapped theme, preserving the custom sections. pcall-guarded because lualine may
-- not have loaded yet (VeryLazy) during an early startup apply.
local function re_theme_lualine()
  if not _G.LualineOpts then
    return
  end
  local opts = vim.deepcopy(_G.LualineOpts)
  opts.options.theme = M.mode == 'gruvbox' and 'gruvbox' or (_G.LualineCatppuccinTheme or 'auto')
  pcall(function()
    require('lualine').setup(opts)
  end)
end

-- Public API ----------------------------------------------------------------

function M.set(mode)
  M.mode = MODES[mode] and mode or 'catppuccin'
  -- Setting the colorscheme fires the ColorScheme autocmd -> apply_highlights.
  vim.cmd.colorscheme(M.mode == 'gruvbox' and 'gruvbox' or 'catppuccin')
  -- Belt-and-suspenders: apply explicitly too (order-independent of the autocmd).
  apply_highlights()
  re_theme_lualine()
  write_mode(M.mode)
end

function M.toggle()
  M.set(M.mode == 'gruvbox' and 'catppuccin' or 'gruvbox')
  vim.notify('Theme: ' .. M.mode, vim.log.levels.INFO)
end

function M.setup()
  -- Re-apply the mode-appropriate tint/transparency on every colorscheme change
  -- (survives :colorscheme reloads and plugins that reset highlights).
  vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_highlights })

  -- Lualine builds its highlights after require('lualine').setup, so re-apply once
  -- all plugins finish loading; also re-theme lualine for a restored gruvbox mode.
  vim.api.nvim_create_autocmd('VimEnter', {
    callback = function()
      apply_highlights()
      re_theme_lualine()
    end,
  })

  vim.api.nvim_create_user_command('ThemeToggle', M.toggle, { desc = 'Toggle catppuccin <-> gruvbox/transparent' })

  -- Apply the restored initial mode.
  M.set(M.mode)
end

return M
