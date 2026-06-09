-- core/notes.lua — Google-Docs-style local line comments ("notes").
--
-- Press <A-c> to attach a free-form, multi-line note to the current line (or a
-- visual range). A gutter icon marks the line. Notes are tracked with extmarks
-- so they follow the code as you edit, and persisted to a single centralized
-- JSON file (never written into any project), keyed by absolute file path.
--
-- Public API used by keymaps (see core/keymaps.lua):
--   add(), add_visual(), view(), delete(), list(), setup()

local M = {}

local ICON = '\u{f075}' -- nerd-font "comment" glyph (nf-fa-comment)
local ICON_FALLBACK = '💬'
local DIR = vim.fn.stdpath('data') .. '/notes'
local FILE = DIR .. '/notes.json'

M.ns = vim.api.nvim_create_namespace('user_notes')
M.store = {} -- path -> list of { id, line, end_line, text, created, updated }
M.marks = {} -- bufnr -> { [extmark_id] = note }

-- The sign cell can be at most 2 columns wide; pick a glyph that fits the font.
local function sign_text()
  return (vim.g.have_nerd_font ~= false) and ICON or ICON_FALLBACK
end

-------------------------------------------------------------------------------
-- Persistence
-------------------------------------------------------------------------------

-- Read the full on-disk database. Disk is the source of truth: many nvim
-- sessions share this one file, so we re-read it on every operation rather than
-- trusting a long-lived in-memory copy.
local function read_disk()
  local f = io.open(FILE, 'r')
  if not f then
    return {}
  end
  local raw = f:read('*a')
  f:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  return (ok and type(decoded) == 'table') and decoded or {}
end

local function write_disk(tbl)
  vim.fn.mkdir(DIR, 'p')
  local ok, encoded = pcall(vim.json.encode, tbl)
  if not ok then
    vim.notify('notes: failed to encode store', vim.log.levels.ERROR)
    return
  end
  local f = io.open(FILE, 'w')
  if not f then
    vim.notify('notes: cannot write ' .. FILE, vim.log.levels.ERROR)
    return
  end
  f:write(encoded)
  f:close()
end

-- Reload the entire in-memory store from disk (for all-files views / startup).
function M.reload_store()
  M.store = read_disk()
end

-- Persist only the notes for a single file path. Read-modify-write against the
-- freshest disk copy so a session never clobbers other files' notes written by
-- other concurrent sessions.
local function persist_path(path)
  local disk = read_disk()
  if M.store[path] and #M.store[path] > 0 then
    disk[path] = M.store[path]
  else
    disk[path] = nil
  end
  write_disk(disk)
end

local function path_of(bufnr)
  bufnr = bufnr or 0
  if vim.bo[bufnr].buftype ~= '' then
    return nil -- terminal/help/quickfix/nofile/etc.
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end
  return vim.fn.fnamemodify(name, ':p')
end

local function next_id(path)
  local max = 0
  for _, note in ipairs(M.store[path] or {}) do
    if note.id > max then
      max = note.id
    end
  end
  return max + 1
end

-------------------------------------------------------------------------------
-- Placement & sync (extmarks both track position AND draw the gutter sign)
-------------------------------------------------------------------------------

-- (Re)create extmarks for every note belonging to this buffer's file.
function M.place(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local path = path_of(bufnr)
  if not path then
    return
  end

  -- Pull this file's notes from disk so notes written by other sessions appear
  -- (this fires on BufReadPost/BufWinEnter and via <leader>br's :edit reload).
  M.store[path] = read_disk()[path]

  -- Idempotent: clear any marks we previously set in this buffer.
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  M.marks[bufnr] = {}

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, note in ipairs(M.store[path] or {}) do
    local row = math.min(math.max(note.line - 1, 0), line_count - 1)
    local end_row = math.min(math.max(note.end_line - 1, row), line_count - 1)
    local id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, row, 0, {
      end_row = end_row,
      sign_text = sign_text(),
      sign_hl_group = 'NoteSign',
      right_gravity = false,
    })
    M.marks[bufnr][id] = note
  end
end

-- Read live extmark positions back into the store and persist.
function M.sync(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local path = path_of(bufnr)
  if not path or not M.marks[bufnr] then
    return
  end
  for id, note in pairs(M.marks[bufnr]) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.ns, id, { details = true })
    if pos and pos[1] then
      local start_row = pos[1]
      local end_row = (pos[3] and pos[3].end_row) or start_row
      note.line = start_row + 1
      note.end_line = math.max(end_row, start_row) + 1
    end
  end
  persist_path(path)
end

-------------------------------------------------------------------------------
-- Lookups
-------------------------------------------------------------------------------

-- The note whose extmark covers the cursor line (start..end inclusive), if any.
local function note_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local marks = M.marks[bufnr]
  if not marks then
    return nil
  end
  local cur = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
  for id, note in pairs(marks) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.ns, id, { details = true })
    if pos and pos[1] then
      local s = pos[1] + 1
      local e = ((pos[3] and pos[3].end_row) or pos[1]) + 1
      if cur >= s and cur <= e then
        return note, id
      end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Floating multi-line input
-------------------------------------------------------------------------------

-- Open a centered floating scratch buffer. <CR> (normal) submits the text,
-- <Esc><Esc> cancels (matches the global "close view" convention).
local function input_float(default_text, on_submit)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'

  local lines = vim.split(default_text or '', '\n', { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = math.min(80, math.max(40, math.floor(vim.o.columns * 0.5)))
  local height = math.min(12, math.max(6, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' note (CR=save, Esc Esc=cancel) ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = true

  local submitted = false
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set('n', '<CR>', function()
    submitted = true
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    close()
    on_submit(vim.trim(text))
  end, { buffer = buf, nowait = true, desc = 'Save note' })

  vim.keymap.set('n', '<Esc><Esc>', close, { buffer = buf, nowait = true, desc = 'Cancel note' })

  -- Guard against leaving the window some other way.
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      if not submitted then
        -- no-op: cancelled
      end
    end,
  })

  vim.cmd('startinsert')
  if default_text and default_text ~= '' then
    vim.cmd('stopinsert')
  end
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------

-- Upsert a note at [start_line, end_line] (1-based) for the given buffer.
local function upsert(bufnr, start_line, end_line, existing)
  local path = path_of(bufnr)
  if not path then
    vim.notify('notes: buffer has no file on disk', vim.log.levels.WARN)
    return
  end

  input_float(existing and existing.text or '', function(text)
    M.store[path] = M.store[path] or {}

    if text == '' then
      -- Empty submission deletes an existing note, or is a no-op for a new one.
      if existing then
        M.delete()
      end
      return
    end

    local now = os.time()
    if existing then
      existing.text = text
      existing.updated = now
    else
      table.insert(M.store[path], {
        id = next_id(path),
        line = start_line,
        end_line = end_line,
        text = text,
        created = now,
        updated = now,
      })
    end
    persist_path(path)
    M.place(bufnr)
  end)
end

function M.add()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local existing = note_at_cursor(bufnr)
  upsert(bufnr, line, line, existing)
end

function M.add_visual()
  -- Leave visual mode so the '< '> marks are set, then read the range.
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'x', false)
  local bufnr = vim.api.nvim_get_current_buf()
  local s = vim.api.nvim_buf_get_mark(bufnr, '<')[1]
  local e = vim.api.nvim_buf_get_mark(bufnr, '>')[1]
  if s > e then
    s, e = e, s
  end
  upsert(bufnr, s, e, nil)
end

function M.view()
  -- Toggle: if a notes float is open, close it.
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) then
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= '' and vim.w[w].is_note_float then
        pcall(vim.api.nvim_win_close, w, true)
        return
      end
    end
  end

  local note = note_at_cursor()
  if not note then
    vim.notify('No note on this line', vim.log.levels.INFO)
    return
  end
  local lines = vim.split(note.text, '\n', { plain = true })
  local _, win = vim.lsp.util.open_floating_preview(lines, 'markdown', {
    border = 'rounded',
    focusable = true,
    wrap = true,
    max_width = 80,
  })
  if win then
    vim.w[win].is_note_float = true
  end
end

function M.delete()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = path_of(bufnr)
  if not path then
    return
  end
  local note, id = note_at_cursor(bufnr)
  if not note then
    vim.notify('No note on this line', vim.log.levels.INFO)
    return
  end

  if id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, id)
    if M.marks[bufnr] then
      M.marks[bufnr][id] = nil
    end
  end
  for i, n in ipairs(M.store[path] or {}) do
    if n.id == note.id then
      table.remove(M.store[path], i)
      break
    end
  end
  if M.store[path] and #M.store[path] == 0 then
    M.store[path] = nil
  end
  persist_path(path)
  vim.notify('Note deleted', vim.log.levels.INFO)
end

function M.list()
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.notify('notes: telescope not available', vim.log.levels.ERROR)
    return
  end
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  -- Reflect notes written by other sessions in the all-files picker.
  M.reload_store()

  local entries = {}
  for path, notes in pairs(M.store) do
    for _, note in ipairs(notes) do
      local first = vim.split(note.text, '\n', { plain = true })[1] or ''
      table.insert(entries, {
        path = path,
        line = note.line,
        display = string.format('%s:%d  ▏ %s', vim.fn.fnamemodify(path, ':~'), note.line, first),
      })
    end
  end

  if #entries == 0 then
    vim.notify('No notes yet', vim.log.levels.INFO)
    return
  end

  pickers
    .new({}, {
      prompt_title = 'Notes',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return { value = e, display = e.display, ordinal = e.display }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local sel = action_state.get_selected_entry()
          if not sel then
            return
          end
          vim.cmd('edit ' .. vim.fn.fnameescape(sel.value.path))
          pcall(vim.api.nvim_win_set_cursor, 0, { sel.value.line, 0 })
        end)
        return true
      end,
    })
    :find()
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

function M.setup()
  M.reload_store()
  vim.api.nvim_set_hl(0, 'NoteSign', { link = 'DiagnosticInfo', default = true })

  local group = vim.api.nvim_create_augroup('UserNotes', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWinEnter' }, {
    group = group,
    callback = function(args)
      M.place(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(args)
      M.sync(args.buf)
    end,
  })
  return M
end

return M
