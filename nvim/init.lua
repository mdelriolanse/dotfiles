-- Set leader keys BEFORE lazy.nvim setup so plugin keymaps work correctly
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

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
  require 'plugins.conform',
  require 'plugins.git-signs',
  require 'plugins.lua-rocks',
  require 'plugins.guess-indent',
  require 'plugins.kanagawa-theme',
  require 'plugins.neo-tree',
  -- require 'plugins.null-ls',
  require 'plugins.nvim-lspconfig',
  require 'plugins.telescope',
  require 'plugins.todo-comments',
  require 'plugins.treesitter',
  require 'plugins.which-key',
  require 'plugins.lazy-dev',
  require 'plugins.claudecode',
  require 'plugins.lsp',
  require 'plugins.cmp-config',
  require 'plugins.barbecue',
  require 'plugins.dap',
  require 'plugins.render-markdown',
  require 'plugins.indent-blankline',
  require 'plugins.rainbow-delimiters',
  require 'plugins.smear-cursor',
  require 'plugins.tiny-glimmer',
  require 'plugins.flash',
  require 'plugins.fidget',
  require 'plugins.swenv',
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

require 'core.options'
require 'core.snippets'
require 'core.keymaps'
require 'core.autocmds'
require 'colors'
