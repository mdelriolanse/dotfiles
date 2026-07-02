-- Note: mapleader is set in init.lua before lazy.nvim setup

vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>e', function()
  vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.ERROR })
  vim.cmd('lopen')
end, { desc = '[E]rrors (current buffer) in location list' })

-- Tab navigation (gt-style)
vim.keymap.set('n', 'gt', '<cmd>tabnext<CR>', { desc = 'Next tab' })
vim.keymap.set('n', 'gT', '<cmd>tabprevious<CR>', { desc = 'Previous tab' })
vim.keymap.set('n', 'gn', '<cmd>tabnew<CR>', { desc = 'New tab' })
vim.keymap.set('n', 'gc', '<cmd>tabclose<CR>', { desc = 'Close tab' })

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
-- Seamless nav across nvim splits AND tmux panes (vim-tmux-navigator).
vim.keymap.set('n', '<C-h>', '<cmd>TmuxNavigateLeft<CR>', { desc = 'Move focus left (nvim split / tmux pane)' })
vim.keymap.set('n', '<C-l>', '<cmd>TmuxNavigateRight<CR>', { desc = 'Move focus right (nvim split / tmux pane)' })
vim.keymap.set('n', '<C-j>', '<cmd>TmuxNavigateDown<CR>', { desc = 'Move focus down (nvim split / tmux pane)' })
vim.keymap.set('n', '<C-k>', '<cmd>TmuxNavigateUp<CR>', { desc = 'Move focus up (nvim split / tmux pane)' })

-- Track the diagnostic float (synchronous open returns its winid).
local diag_win = nil
local function close_if_open(win_ref)
  if win_ref and vim.api.nvim_win_is_valid(win_ref) then
    pcall(vim.api.nvim_win_close, win_ref, true)
    return true
  end
  return false
end

-- Find an LSP-hover-style floating window. LSP hover floats have filetype
-- 'markdown' (or 'lsp-hover') in a floating window. Scanning each call sidesteps
-- the async race where vim.lsp.buf.hover() creates the float after we return.
local function find_hover_float()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) then
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= '' then
        local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
        if ft == 'markdown' or ft == 'lsp-hover' or ft == 'lsp-floating-preview' then
          return w
        end
      end
    end
  end
end

-- Pull the RETURN VALUE and ERRORS sections from a man page so a hover tells
-- us not just the return *type* but which value signals an error and which
-- errno values to expect. Tries syscall (2) then libc (3) then any section.
-- Returns markdown lines, or nil if the word has no man page.
local MAN_SECTIONS = { ['RETURN VALUE'] = true, ['ERRORS'] = true }
local function man_return_sections(word)
  if not word:match('^[%w_]+$') then return nil end
  local cmd = string.format(
    'for s in 2 3 ""; do o=$(MANWIDTH=80 man $s %s 2>/dev/null | col -bx); '
      .. '[ -n "$o" ] && { printf %%s "$o"; break; }; done',
    word
  )
  local raw = vim.fn.systemlist({ 'sh', '-c', cmd })
  if vim.v.shell_error ~= 0 or vim.tbl_isempty(raw) then return nil end
  local out, capturing = {}, false
  for _, l in ipairs(raw) do
    if l:match('^[A-Z][A-Z ]+$') then
      capturing = MAN_SECTIONS[l] == true
      if capturing then
        if #out > 0 then table.insert(out, '') end
        table.insert(out, '**' .. l .. '**')
      end
    elseif capturing then
      table.insert(out, (l:gsub('^%s+', '')))
    end
  end
  return #out > 0 and out or nil
end

-- Smart hover: prefer LSP (project symbols, clangd for C/C++) and, for words
-- with a man page, append the RETURN VALUE + ERRORS sections beneath the
-- signature. Falls back to a man-only float, then :help / :Man.
-- Pressing the keybind again (from main buffer OR from inside the float) closes it.
local function smart_hover()
  local existing = find_hover_float()
  if existing then
    pcall(vim.api.nvim_win_close, existing, true)
    return
  end

  local word = vim.fn.expand('<cword>')
  local man = word ~= '' and man_return_sections(word) or nil

  local function append_man(lines)
    if not man then return lines end
    if #lines > 0 then
      table.insert(lines, '')
      table.insert(lines, '---')
      table.insert(lines, '')
    end
    return vim.list_extend(lines, man)
  end

  local hover_client
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if c:supports_method('textDocument/hover') then
      hover_client = c
      break
    end
  end

  if hover_client then
    local params = vim.lsp.util.make_position_params(0, hover_client.offset_encoding)
    vim.lsp.buf_request_all(0, 'textDocument/hover', params, function(results)
      local lines = {}
      for _, r in pairs(results or {}) do
        local result = r.result or r
        if result and result.contents then
          vim.list_extend(lines, vim.lsp.util.convert_input_to_markdown_lines(result.contents))
        end
      end
      lines = append_man(lines)
      if vim.tbl_isempty(lines) then
        vim.notify('No hover docs for ' .. word, vim.log.levels.INFO)
        return
      end
      vim.lsp.util.open_floating_preview(lines, 'markdown', {
        border = 'rounded',
        focusable = true,
        wrap = true,
        max_width = 80,
      })
    end)
    return
  end

  if man then
    vim.lsp.util.open_floating_preview(man, 'markdown', {
      border = 'rounded',
      focusable = true,
      wrap = true,
      max_width = 80,
    })
    return
  end

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
vim.keymap.set('n', '<A-k>', smart_hover, { desc = 'Hover docs (LSP → man/help), toggle' })

local function toggle_line_diagnostics()
  if close_if_open(diag_win) then diag_win = nil; return end
  local _, win = vim.diagnostic.open_float(nil, { focus = false, border = 'rounded', scope = 'line' })
  diag_win = win
end
vim.keymap.set('n', '<leader>l', toggle_line_diagnostics, { desc = 'Toggle diagnostics for current [L]ine (float)' })
vim.keymap.set('n', '<C-q>', '<cmd>close<CR>', { desc = 'Close window' })

-- Insert mode: escape and switch (nvim split / tmux pane)
vim.keymap.set('i', '<C-h>', '<Esc><cmd>TmuxNavigateLeft<CR>', { desc = 'Escape and move focus left' })
vim.keymap.set('i', '<C-j>', '<Esc><cmd>TmuxNavigateDown<CR>', { desc = 'Escape and move focus down' })
vim.keymap.set('i', '<C-k>', '<Esc><cmd>TmuxNavigateUp<CR>', { desc = 'Escape and move focus up' })
vim.keymap.set('i', '<C-l>', '<Esc><cmd>TmuxNavigateRight<CR>', { desc = 'Escape and move focus right' })

-- Terminal mode: escape and switch (nvim split / tmux pane)
vim.keymap.set('t', '<C-h>', '<C-\\><C-n><cmd>TmuxNavigateLeft<CR>', { desc = 'Escape terminal and move focus left' })
vim.keymap.set('t', '<C-j>', '<C-\\><C-n><cmd>TmuxNavigateDown<CR>', { desc = 'Escape terminal and move focus down' })
vim.keymap.set('t', '<C-k>', '<C-\\><C-n><cmd>TmuxNavigateUp<CR>', { desc = 'Escape terminal and move focus up' })
vim.keymap.set('t', '<C-l>', '<C-\\><C-n><cmd>TmuxNavigateRight<CR>', { desc = 'Escape terminal and move focus right' })

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

-- Adjust current window width. Step defaults to 5; an optional count overrides
-- it, e.g. 10<C-w>> grows by 10. Repeatable: hold <C-w>, tap < or >.
local function resize_width(sign)
  return function()
    local step = vim.v.count > 0 and vim.v.count or 5
    vim.cmd('vertical resize ' .. sign .. step)
  end
end
vim.keymap.set('n', '<C-w><', resize_width('-'), { desc = 'Shrink window width (count = step)' })
vim.keymap.set('n', '<C-w>>', resize_width('+'), { desc = 'Grow window width (count = step)' })

-- Equalize window widths only (even vertical splits), leaving heights alone.
vim.keymap.set('n', '<C-w>=', function()
  local ead = vim.o.eadirection
  vim.o.eadirection = 'hor'
  vim.cmd('wincmd =')
  vim.o.eadirection = ead
end, { desc = 'Equalize window widths (even vertical splits)' })

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

-- Drop animation keymaps
vim.keymap.set('n', '<leader>dt', function()
  if _G.DropPickTheme then
    _G.DropPickTheme()
  end
end, { desc = '[D]rop [T]heme picker' })

vim.keymap.set('n', '<leader>dT', function()
  if _G.DropToggle then
    _G.DropToggle()
  end
end, { desc = '[D]rop [T]oggle (manual)' })

-- Python virtual environment switcher
vim.keymap.set('n', '<leader>pv', '<cmd>SwenvPick<CR>', { desc = '[P]ick Python [V]env' })
vim.keymap.set('n', '<leader>pV', '<cmd>SwenvCurrent<CR>', { desc = 'Show current Python [V]env' })

-- Buffer refresh: reload all from disk, or show unsaved-changes warning with lumen diff
vim.keymap.set('n', '<leader>br', function()
  require('core.buffer-refresh').refresh()
end, { desc = '[B]uffer [R]efresh (warn if unsaved)' })

-- Line notes: Google-Docs-style local comments attached to lines (core/notes.lua).
local notes = require('core.notes')
notes.setup()
vim.keymap.set('n', '<A-c>', notes.add, { desc = '[N]ote: add/edit on current line' })
vim.keymap.set('x', '<A-c>', notes.add_visual, { desc = '[N]ote: add for selected range' })
vim.keymap.set('n', '<leader>nv', notes.view, { desc = '[N]ote: [V]iew on current line (float)' })
vim.keymap.set('n', '<leader>nd', notes.delete, { desc = '[N]ote: [D]elete on current line' })
vim.keymap.set('n', '<leader>nl', notes.list, { desc = '[N]ote: [L]ist all (Telescope)' })

