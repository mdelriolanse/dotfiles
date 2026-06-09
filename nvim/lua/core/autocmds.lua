-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Terminal buffer settings
local terminal_group = vim.api.nvim_create_augroup('terminal-settings', { clear = true })

-- Set up terminal-specific keymaps when opening a terminal
vim.api.nvim_create_autocmd('TermOpen', {
  group = terminal_group,
  desc = 'Set up terminal buffer keymaps',
  callback = function()
    -- Press Enter in normal mode to enter insert/terminal mode
    vim.keymap.set('n', '<CR>', 'i', { buffer = true, desc = 'Enter terminal insert mode' })
  end,
})

-- In neo-tree sidebar, make :q behave like :qa (quit all)
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'neo-tree',
  desc = ':q in neo-tree quits everything',
  callback = function(ev)
    vim.keymap.set('n', ':q<CR>',  ':qa<CR>',  { buffer = ev.buf, silent = true })
    vim.keymap.set('n', ':q!<CR>', ':qa!<CR>', { buffer = ev.buf, silent = true })
    vim.keymap.set('n', ':wq<CR>', ':wqa<CR>', { buffer = ev.buf, silent = true })
    -- Also handle when the user types :q at the cmdline (abbreviation)
    vim.cmd([[cnoreabbrev <expr> <buffer> q (getcmdtype()==':' && getcmdline()==#'q') ? 'qa' : 'q']])
    vim.cmd([[cnoreabbrev <expr> <buffer> q! (getcmdtype()==':' && getcmdline()==#'q!') ? 'qa!' : 'q!']])
    vim.cmd([[cnoreabbrev <expr> <buffer> wq (getcmdtype()==':' && getcmdline()==#'wq') ? 'wqa' : 'wq']])
  end,
})

-- Auto-enter insert mode when entering a terminal buffer (covers mouse clicks)
vim.api.nvim_create_autocmd('BufEnter', {
  group = terminal_group,
  desc = 'Auto-enter insert mode in terminal buffers',
  callback = function()
    if vim.bo.buftype == 'terminal' then
      vim.cmd('startinsert')
    end
  end,
})
