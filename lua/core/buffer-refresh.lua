local M = {}

local LUMEN = '/home/linuxbrew/.linuxbrew/bin/lumen'

M._temp_files = {}

function M.get_dirty_bufs()
  local dirty = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buflisted
      and vim.bo[buf].buftype == ''
      and vim.bo[buf].modified
      and vim.api.nvim_buf_get_name(buf) ~= ''
    then
      table.insert(dirty, buf)
    end
  end
  return dirty
end

function M.reload_all()
  vim.cmd('checktime')
  local changed = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buflisted
      and vim.bo[buf].buftype == ''
      and not vim.bo[buf].modified
      and vim.api.nvim_buf_get_name(buf) ~= ''
    then
      local tick_before = vim.api.nvim_buf_get_changedtick(buf)
      pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd('edit')
      end)
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick_before then
        changed = changed + 1
      end
    end
  end
  vim.schedule(function()
    if changed == 0 then
      vim.cmd('echomsg "Buffer refresh: no changes on disk"')
    else
      vim.cmd(string.format('echomsg "Buffer refresh: %d file%s updated from disk"', changed, changed == 1 and '' or 's'))
    end
  end)
end

function M.force_reload_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buflisted
      and vim.bo[buf].buftype == ''
      and vim.api.nvim_buf_get_name(buf) ~= ''
    then
      pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd('edit!')
      end)
    end
  end
  vim.notify('All buffers force-reloaded (unsaved changes discarded)', vim.log.levels.WARN)
end

function M.show_lumen_diff(buf)
  local disk_path = vim.api.nvim_buf_get_name(buf)
  if disk_path == '' then
    vim.notify('Buffer has no file path', vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(disk_path) == 0 then
    vim.notify('File not found on disk: ' .. disk_path, vim.log.levels.WARN)
    return
  end

  local tmp = vim.fn.tempname()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.fn.writefile(lines, tmp)
  M._temp_files[tmp] = true

  local diff_base = string.format('diff -u %s %s', vim.fn.shellescape(disk_path), vim.fn.shellescape(tmp))
  local cmd
  if vim.fn.executable(LUMEN) == 1 then
    cmd = diff_base .. ' | ' .. vim.fn.shellescape(LUMEN) .. ' show'
  else
    cmd = diff_base
  end
  -- diff exits 1 when files differ (expected); append pause so output stays readable
  local full_cmd = cmd .. '; echo; echo "--- press q or <C-w>c to close ---"; read -r _'

  vim.cmd('botright split')
  vim.cmd('resize 20')

  local term_buf = vim.api.nvim_get_current_buf()

  vim.fn.termopen(full_cmd, {
    on_exit = function()
      if M._temp_files[tmp] then
        vim.fn.delete(tmp)
        M._temp_files[tmp] = nil
      end
    end,
  })

  vim.cmd('startinsert')

  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = term_buf,
    once = true,
    callback = function()
      if M._temp_files[tmp] then
        vim.fn.delete(tmp)
        M._temp_files[tmp] = nil
      end
    end,
  })
end

function M.open_warning_float(dirty_bufs)
  local header = '  Unsaved buffers — j/k: navigate  Enter: diff  R: force reload  q: close'
  local lines = { header, '' }
  local file_entries = {}

  for _, buf in ipairs(dirty_bufs) do
    local full_path = vim.api.nvim_buf_get_name(buf)
    local rel = vim.fn.fnamemodify(full_path, ':~:.')
    table.insert(lines, '  * ' .. rel)
    table.insert(file_entries, buf)
  end
  table.insert(lines, '')

  local width = math.min(math.max(#header + 4, 60), math.floor(vim.o.columns * 0.85))
  local height = #lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.bo[float_buf].modifiable = false
  vim.bo[float_buf].bufhidden = 'wipe'

  local float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = '  Buffer Refresh  ',
    title_pos = 'center',
    noautocmd = true,
  })

  local header_lines = 2
  vim.api.nvim_win_set_cursor(float_win, { header_lines + 1, 2 })

  local function close_float()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
  end

  local function get_cursor_buf()
    local row_ = vim.api.nvim_win_get_cursor(float_win)[1]
    local idx = row_ - header_lines
    if idx >= 1 and idx <= #file_entries then
      return file_entries[idx]
    end
  end

  local opts = { noremap = true, silent = true, buffer = float_buf, nowait = true }

  vim.keymap.set('n', 'j', function()
    local cur = vim.api.nvim_win_get_cursor(float_win)[1]
    local max = header_lines + #file_entries
    if cur < max then
      vim.api.nvim_win_set_cursor(float_win, { cur + 1, 2 })
    end
  end, opts)

  vim.keymap.set('n', 'k', function()
    local cur = vim.api.nvim_win_get_cursor(float_win)[1]
    if cur > header_lines + 1 then
      vim.api.nvim_win_set_cursor(float_win, { cur - 1, 2 })
    end
  end, opts)

  vim.keymap.set('n', '<CR>', function()
    local buf = get_cursor_buf()
    if buf then
      close_float()
      M.show_lumen_diff(buf)
    end
  end, opts)

  vim.keymap.set('n', 'R', function()
    close_float()
    M.force_reload_all()
  end, opts)

  vim.keymap.set('n', 'q', close_float, opts)
  vim.keymap.set('n', '<Esc>', close_float, opts)

  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = float_buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(float_win) then
          vim.api.nvim_win_close(float_win, true)
        end
      end)
    end,
  })
end

function M.refresh()
  local dirty = M.get_dirty_bufs()
  if #dirty == 0 then
    M.reload_all()
  else
    M.open_warning_float(dirty)
  end
end

return M
