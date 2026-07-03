vim.g.have_nerd_font = true

vim.o.clipboard = 'unnamedplus'

vim.o.number = true
vim.o.relativenumber = true
vim.o.mouse = 'a'
vim.o.showmode = false
vim.o.breakindent = true
vim.o.undofile = true

vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 2

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.o.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250

-- Decrease mapped sequence wait time
vim.o.timeoutlen = 300

-- Configure how new splits should be opened
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.list = false

-- Preview substitutions live, as you type!
vim.o.inccommand = 'split'
vim.o.cursorline = true

vim.o.scrolloff = 10
vim.o.confirm = true

vim.o.cmdheight = 0

vim.opt.cursorline = false

vim.keymap.set('n', '<Tab>', ':bnext<CR>', opts)
vim.keymap.set('n', '<S-Tab>', ':bprevious<CR>', opts)
vim.keymap.set('n', '\\', '<Cmd>Neotree toggle<CR>')

-- Colorscheme is applied by core.theme-toggle (required last in init.lua) so the
-- persisted catppuccin/gruvbox mode is restored without a flash.

-- <Esc> in terminal mode intentionally left unbound — single Esc passes through
-- to the program inside the terminal. Use <Esc><Esc> to exit terminal mode
-- (set in core/keymaps.lua), then <C-w>h to move to the editor window.

local opts = { noremap = true, silent = true }

local function quickfix()
	vim.lsp.buf.code_action {
		filter = function(a)
			return a.isPreferred
		end,
		apply = true,
	}
end

vim.keymap.set('n', 'yf', quickfix, opts)

vim.o.conceallevel = 3

vim.api.nvim_set_hl(0, 'NorgMarkupBold', { bold = true })
vim.api.nvim_set_hl(0, 'NorgMarkupItalic', { italic = true })

-- Ensure Neovim uses the correct Node.js from nvm
if vim.fn.executable('nvm') == 1 then
  vim.env.PATH = vim.fn.expand('~/.nvm/versions/node/v18.20.8/bin') .. ':' .. vim.env.PATH
else
  -- Fallback: add common Node.js paths
  vim.env.PATH = vim.fn.expand('~/.local/bin') .. ':' .. vim.env.PATH
end