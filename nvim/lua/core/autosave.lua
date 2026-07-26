-- Debounced autosave.
--
-- Why: the linters that matter most here run off the file on *disk*, not the
-- buffer — rust-analyzer's clippy flycheck (see plugins/rust.lua) only reruns on
-- textDocument/didSave, which nvim sends on BufWritePost. So without a write,
-- diagnostics go stale until you hit :w. This writes the buffer once you stop
-- typing for DEBOUNCE_MS, which makes those messages refresh on their own.
--
-- Formatting is deliberately skipped on these writes: conform's format_on_save
-- checks vim.b.autosaving (plugins/conform.lua) and bails, so rustfmt/stylua
-- never reindent under the cursor mid-edit. An explicit :w still formats.

local M = {}

-- Idle time before a write. Long enough that a `cargo clippy` isn't kicked off
-- between keystrokes, short enough to feel live.
local DEBOUNCE_MS = 800

-- Buffers where writing on every pause is wrong or surprising.
local excluded_filetypes = {
  gitcommit = true,
  gitrebase = true,
  ['neo-tree'] = true,
  oil = true,
}

-- changedtick per buffer at the moment a write was scheduled; a newer tick means
-- the user kept typing and this scheduled write is stale.
local pending = {}

local function should_save(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return false end
  if vim.g.autosave_disabled or vim.b[buf].autosave_disabled then return false end
  if not vim.bo[buf].modified or not vim.bo[buf].modifiable or vim.bo[buf].readonly then return false end
  if vim.bo[buf].buftype ~= '' then return false end
  if excluded_filetypes[vim.bo[buf].filetype] then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return false end
  -- Only real files: skip oil://, fugitive://, diffview:// and friends, which
  -- error on :write (and which nothing lints anyway).
  if vim.uri_from_bufnr(buf):sub(1, 7) ~= 'file://' then return false end
  return true
end

function M.save(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not should_save(buf) then return end
  -- Never write mid-completion: accepting an item right after would leave the
  -- half-typed word on disk and, worse, the write can dismiss the popup.
  if vim.fn.pumvisible() == 1 then return end

  vim.b[buf].autosaving = true
  local ok, err = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd 'silent lockmarks write'
    end)
  end)
  vim.b[buf].autosaving = nil

  if not ok then
    -- Typically E13 (file changed on disk). Retrying every 800ms would spam the
    -- same error forever, so back off for this buffer and let the user resolve it.
    vim.b[buf].autosave_disabled = true
    vim.notify(
      ('autosave: disabled for this buffer — %s\nResolve, then :AutoSave on'):format(err),
      vim.log.levels.WARN
    )
  end
end

local function schedule(buf)
  if not should_save(buf) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  pending[buf] = tick
  vim.defer_fn(function()
    if pending[buf] ~= tick then return end -- superseded by a later edit
    pending[buf] = nil
    M.save(buf)
  end, DEBOUNCE_MS)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('autosave', { clear = true })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    desc = 'Autosave after a pause in typing',
    callback = function(ev) schedule(ev.buf) end,
  })

  -- Leaving insert/the buffer/the window is a natural commit point: write now
  -- rather than waiting out the debounce.
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'BufLeave', 'FocusLost' }, {
    group = group,
    desc = 'Autosave immediately on leaving the buffer',
    callback = function(ev)
      pending[ev.buf] = nil
      M.save(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(ev) pending[ev.buf] = nil end,
  })

  vim.api.nvim_create_user_command('AutoSave', function(opts)
    local arg = opts.args ~= '' and opts.args or 'toggle'
    if arg == 'on' then
      vim.g.autosave_disabled = false
      vim.b.autosave_disabled = nil
    elseif arg == 'off' then
      vim.g.autosave_disabled = true
    else
      vim.g.autosave_disabled = not vim.g.autosave_disabled
      if not vim.g.autosave_disabled then vim.b.autosave_disabled = nil end
    end
    vim.notify('autosave ' .. (vim.g.autosave_disabled and 'off' or 'on'))
  end, {
    nargs = '?',
    complete = function() return { 'on', 'off', 'toggle' } end,
    desc = 'Toggle debounced autosave (on|off|toggle)',
  })
end

return M
