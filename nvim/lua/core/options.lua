vim.g.have_nerd_font = true

-- WSL clipboard integration
vim.g.clipboard = {
  name = 'WslClipboard',
  copy = {
    ['+'] = 'clip.exe',
    ['*'] = 'clip.exe',
  },
  paste = {
    ['+'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
    ['*'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
  },
  cache_enabled = 0,
}

vim.o.clipboard = 'unnamedplus'

vim.o.number = true
vim.o.relativenumber = true
vim.o.mouse = 'a'
vim.o.showmode = false
vim.o.breakindent = true
vim.o.undofile = true

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

vim.opt.cursorline = false

vim.keymap.set('n', '<Tab>', ':bnext<CR>', opts)
vim.keymap.set('n', '<S-Tab>', ':bprevious<CR>', opts)
vim.keymap.set('n', '\\', '<Cmd>Neotree toggle<CR>')

vim.cmd 'colorscheme kanagawa-dragon'

vim.keymap.set('t', '<Esc>', '<C-\\><C-n><C-w>h', { silent = true })

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
