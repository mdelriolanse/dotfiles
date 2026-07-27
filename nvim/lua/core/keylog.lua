-- Diagnostic keylogger for the "keys go dead after refocusing the window" bug.
--
-- Enable by starting nvim with NVIM_KEYLOG=1, then reproduce the bug and read
-- the log with ~/bin/kbd-nvimlog. Records the raw byte stream nvim receives so
-- we can tell whether dead keys are (a) never arriving, (b) arriving but being
-- swallowed as part of an unterminated mouse escape sequence, or (c) arriving
-- in an unexpected mode.
--
-- Remove the require in init.lua once the bug is found.

local M = {}

local logfile = vim.fn.expand('~/.cache/nvim-keylog.txt')

local function esc(s)
  return (s:gsub('[^\32-\126]', function(c)
    return string.format('<%02x>', c:byte())
  end))
end

function M.setup()
  local fh = io.open(logfile, 'a')
  if not fh then
    return
  end

  local function write(kind, detail)
    -- Mode and pending-input state are the two things that distinguish a
    -- swallowed key from a key that was never delivered.
    local ok, mode = pcall(vim.api.nvim_get_mode)
    local mode_s = ok and (mode.mode .. (mode.blocking and ' BLOCKING' or '')) or '?'
    fh:write(string.format('%s  %-12s mode=%-12s %s\n',
      os.date('%H:%M:%S'), kind, mode_s, detail))
    fh:flush()
  end

  write('START', string.format('pid=%d tty=%s term=%s',
    vim.fn.getpid(), vim.fn.expand('$TTY'), vim.env.TERM or '?'))

  vim.on_key(function(key, typed)
    local d = 'key=' .. esc(key)
    -- `typed` is the pre-mapping byte stream; a divergence means a mapping or
    -- a partial escape sequence is consuming input.
    if typed and typed ~= '' and typed ~= key then
      d = d .. '  typed=' .. esc(typed)
    end
    write('KEY', d)
  end)

  local group = vim.api.nvim_create_augroup('keylog-diag', { clear = true })

  for _, ev in ipairs({ 'FocusGained', 'FocusLost', 'VimResume', 'VimSuspend' }) do
    vim.api.nvim_create_autocmd(ev, {
      group = group,
      callback = function()
        write(ev, '')
      end,
    })
  end

  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    callback = function()
      write('ModeChanged', vim.v.event.old_mode .. ' -> ' .. vim.v.event.new_mode)
    end,
  })

  -- A hung clipboard provider or LSP request looks identical to dead keys from
  -- the user's side, so note when nvim is waiting on a shell command.
  vim.api.nvim_create_autocmd('CmdlineEnter', {
    group = group,
    callback = function()
      write('CmdlineEnter', '')
    end,
  })
end

return M
