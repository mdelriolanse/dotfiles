-- Set leader keys BEFORE lazy.nvim setup so plugin keymaps work correctly
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

-- Auto-detect nerd font support. Must run BEFORE lazy.setup.
-- Override: export NVIM_NERD_FONT=0 to force-disable.
vim.g.have_nerd_font = (function()
  if vim.fn.has('gui_running') == 1 then return true end
  if vim.fn.has('multi_byte') == 0 then return false end
  local env = vim.fn.getenv('NVIM_NERD_FONT')
  if env == '0' or env == 'false' then return false end
  return true
end)()

if not vim.g.have_nerd_font then
  -- Mock nvim-web-devicons so every plugin (lualine, neo-tree, oil, etc.)
  -- gets empty strings instead of broken nerd font glyphs.
  package.preload['nvim-web-devicons'] = function()
    local e = function() return '', '' end
    return {
      get_icon = e, get_icon_by_filetype = e, get_icon_colors = e,
      get_icon_colors_by_filetype = e, get_icon_color = function() return '' end,
      get_icon_color_by_filetype = function() return '' end,
      get_icon_cterm_color = function() return '' end,
      get_icon_cterm_color_by_filetype = function() return '' end,
      get_icon_name_by_filetype = function() return '' end,
      get_default_icon = function() return { icon = '', color = '', name = '' } end,
      get_icons = function() return {} end,
      get_icons_by_filename = function() return {} end,
      get_icons_by_extension = function() return {} end,
      get_icons_by_operating_system = function() return {} end,
      get_icons_by_desktop_environment = function() return {} end,
      get_icons_by_window_manager = function() return {} end,
      set_up_highlights = function() end, setup = function() end,
      set_icon = function() end, set_icon_by_filetype = function() end,
      set_default_icon = function() end, refresh = function() end,
      has_loaded = function() return true end,
    }
  end
end

local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end

---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

require('lazy').setup({
  require 'plugins.luasnip',
  require 'plugins.blink',
  require 'plugins.csvview',
  require 'plugins.conform',
  require 'plugins.git-signs',
  require 'plugins.lua-rocks',
  require 'plugins.guess-indent',
  require 'plugins.autopairs',
  require 'plugins.catppuccin',
  require 'plugins.gruvbox',
  require 'plugins.drop',
  require 'plugins.snacks',
  require 'plugins.neo-tree',
  -- require 'plugins.null-ls',
  require 'plugins.nvim-lspconfig',
  require 'plugins.rust',
  require 'plugins.telescope',
  require 'plugins.todo-comments',
  require 'plugins.treesitter',
  require 'plugins.which-key',
  require 'plugins.lazy-dev',
  require 'plugins.claudecode',
  require 'plugins.lsp',
  require 'plugins.cmp-config',
  require 'plugins.barbecue',
  require 'plugins.aerial',
  require 'plugins.dap',
  require 'plugins.render-markdown',
  require 'plugins.indent-blankline',
  require 'plugins.rainbow-delimiters',
  require 'plugins.smear-cursor',
  require 'plugins.tiny-glimmer',
  require 'plugins.flash',
  require 'plugins.fidget',
  require 'plugins.lualine',
  require 'plugins.swenv',
  require 'plugins.oil',
  require 'plugins.ssh-remote',
  require 'plugins.tmux-navigator',
}, {
  ui = {
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- Temporary: diagnostic keylogger for the dead-keys-after-refocus bug.
-- Only active when started with NVIM_KEYLOG=1. Remove once the bug is found.
if vim.env.NVIM_KEYLOG == '1' then
  require('core.keylog').setup()
end

require 'core.options'
require 'core.snippets'
require 'core.keymaps'
require 'core.autocmds'
require('core.autosave').setup()
require 'core.c-cpp'
require 'colors'

-- Owns colorscheme selection + the catppuccin<->gruvbox/transparent :ThemeToggle.
-- Runs last so it has the final word on the active colorscheme at startup.
require('core.theme-toggle').setup()
