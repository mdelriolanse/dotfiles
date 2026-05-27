-- Note: mapleader is set in init.lua before lazy.nvim setup

vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('n', '<leader>e', function()
  vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.ERROR })
  vim.cmd('lopen')
end, { desc = '[E]rrors (current buffer) in location list' })

-- Double-Esc is the universal "close this view" binding.
-- Single Esc keeps its normal vim role everywhere (mode exit, nohlsearch),
-- so apps running inside :terminal (htop, less, REPLs, nested vim) get raw Esc.
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
vim.keymap.set('t', '<C-Space>', '<C-\\><C-n>', { desc = 'Master escape from terminal mode' })
vim.keymap.set('i', '<C-Space>', '<Esc>', { desc = 'Master escape from insert mode' })

-- Normal-mode double-Esc: close the current "view" if it's a special window
-- (terminal, help, quickfix/loclist, floating window, or a scratch/nofile buffer
-- like the [C/C++ Build] output). On a regular file buffer it's a no-op.
local function close_view()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local cfg = vim.api.nvim_win_get_config(win)
  local bt = vim.bo[buf].buftype

  if cfg.relative ~= '' then
    vim.api.nvim_win_close(win, true) -- floating window
    return
  end
  if bt == 'terminal' or bt == 'help' or bt == 'quickfix' or bt == 'nofile' then
    -- If it's the only window in the tab, just hide the buffer instead of erroring.
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then
      vim.api.nvim_win_hide(win)
    else
      vim.cmd('enew')
    end
  end
end
vim.keymap.set('n', '<Esc><Esc>', close_view, { desc = 'Close current view (terminal/help/qf/float/scratch)' })

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<cmd>wincmd h<CR>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<cmd>wincmd l<CR>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<cmd>wincmd j<CR>', { desc = 'Move focus to the lower window' })
-- <C-k> reassigned to smart_hover below; use native <C-w>k for window-up.

-- Track floats we opened so the same keybind can toggle them closed.
local hover_win, diag_win = nil, nil
local function close_if_open(win_ref)
  if win_ref and vim.api.nvim_win_is_valid(win_ref) then
    pcall(vim.api.nvim_win_close, win_ref, true)
    return true
  end
  return false
end

-- Smart hover: prefer LSP (project symbols, clangd for C/C++), fall back to
-- man pages for C/shell, :help for vim/lua, man pages otherwise.
-- Pressing the keybind again closes the float.
local function smart_hover()
  if close_if_open(hover_win) then hover_win = nil; return end
  local prev = vim.api.nvim_list_wins()
  local prev_set = {}
  for _, w in ipairs(prev) do prev_set[w] = true end
  local function capture_new_float()
    vim.schedule(function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if not prev_set[w] and vim.api.nvim_win_get_config(w).relative ~= '' then
          hover_win = w
          return
        end
      end
    end)
  end
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if c:supports_method('textDocument/hover') then
      vim.lsp.buf.hover({ border = 'rounded' })
      capture_new_float()
      return
    end
  end
  local word = vim.fn.expand('<cword>')
  if word == '' then
    vim.notify('No word under cursor', vim.log.levels.INFO)
    return
  end
  local ft = vim.bo.filetype
  local cmd = (ft == 'vim' or ft == 'lua' or ft == 'help') and 'help ' or 'Man '
  local ok, err = pcall(vim.cmd, cmd .. word)
  if not ok then
    vim.notify(err or ('No docs for ' .. word), vim.log.levels.INFO)
  end
end
vim.keymap.set('n', '<C-k>', smart_hover, { desc = 'Hover docs (LSP → man/help), toggle' })

local function toggle_line_diagnostics()
  if close_if_open(diag_win) then diag_win = nil; return end
  local _, win = vim.diagnostic.open_float(nil, { focus = false, border = 'rounded', scope = 'line' })
  diag_win = win
end
vim.keymap.set('n', '<leader>l', toggle_line_diagnostics, { desc = 'Toggle diagnostics for current [L]ine (float)' })
vim.keymap.set('n', '<C-q>', '<cmd>close<CR>', { desc = 'Close window' })

-- Insert mode: escape and switch windows
vim.keymap.set('i', '<C-h>', '<Esc><C-w>h', { desc = 'Escape and move focus left' })
vim.keymap.set('i', '<C-j>', '<Esc><C-w>j', { desc = 'Escape and move focus down' })
-- <C-k> in insert mode dropped — would conflict with smart_hover idiom; use <Esc><C-w>k.
vim.keymap.set('i', '<C-l>', '<Esc><C-w>l', { desc = 'Escape and move focus right' })

-- Terminal mode: escape and switch windows
vim.keymap.set('t', '<C-h>', '<C-\\><C-n><C-w>h', { desc = 'Escape terminal and move focus left' })
vim.keymap.set('t', '<C-j>', '<C-\\><C-n><C-w>j', { desc = 'Escape terminal and move focus down' })
-- <C-k> in terminal mode dropped — reserved for symmetry with smart_hover; use <C-\><C-n><C-w>k.
vim.keymap.set('t', '<C-l>', '<C-\\><C-n><C-w>l', { desc = 'Escape terminal and move focus right' })

-- NOTE: Some terminals have colliding keymaps or are not able to send distinct keycodes
-- vim.keymap.set("n", "<C-S-h>", "<C-w>H", { desc = "Move window to the left" })
-- vim.keymap.set("n", "<C-S-l>", "<C-w>L", { desc = "Move window to the right" })
-- vim.keymap.set("n", "<C-S-j>", "<C-w>J", { desc = "Move window to the lower" })
-- vim.keymap.set("n", "<C-S-k>", "<C-w>K", { desc = "Move window to the upper" })

-- Window zoom toggle (fullscreen current window)
local zoom_tab = nil
local function toggle_zoom()
  if zoom_tab and vim.api.nvim_tabpage_is_valid(zoom_tab) then
    -- We're zoomed - close the zoom tab to restore
    vim.cmd('tabclose')
    zoom_tab = nil
  else
    -- Zoom in - create new tab with current buffer
    vim.cmd('tab split')
    zoom_tab = vim.api.nvim_get_current_tabpage()
  end
end

vim.keymap.set('n', '<C-w>m', toggle_zoom, { desc = 'Toggle window zoom (maximize)' })

require 'core.snippets'
vim.keymap.set('n', '<A-t>', function()
	TermToggle(60)
end, { noremap = true, silent = true })
vim.keymap.set('t', '<A-t>', '<C-\\><C-n><cmd>lua TermToggle(60)<CR>', { noremap = true, silent = true })

vim.keymap.set('n', '<leader>td', function()
	vim.diagnostic.enable(not vim.diagnostic.is_enabled())
end, { silent = true, noremap = true })

-- Copy selected text to Windows clipboard with Ctrl+C
vim.keymap.set({ 'v', 'x' }, '<C-c>', '"+y', { desc = 'Copy selection to Windows clipboard' })

-- Arrow symbol auto-replacement in insert mode
vim.keymap.set('i', '-->', '→', { desc = 'Replace --> with →' })
vim.keymap.set('i', '==>', '⇒', { desc = 'Replace ==> with ⇒' })

-- Python virtual environment switcher
vim.keymap.set('n', '<leader>pv', '<cmd>SwenvPick<CR>', { desc = '[P]ick Python [V]env' })
vim.keymap.set('n', '<leader>pV', '<cmd>SwenvCurrent<CR>', { desc = 'Show current Python [V]env' })

-- Buffer refresh: reload all from disk, or show unsaved-changes warning with lumen diff
vim.keymap.set('n', '<leader>br', function()
  require('core.buffer-refresh').refresh()
end, { desc = '[B]uffer [R]efresh (warn if unsaved)' })

