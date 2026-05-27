-- C/C++ workflow: build, run, output, header/source switch, valgrind, gdb.
-- Self-contained, no extra plugin deps. Wires keymaps lazily for c/cpp buffers.

local M = {}

------------------------------------------------------------------------------
-- Output window: scratch buffer in a bottom split that we reuse across runs.
------------------------------------------------------------------------------

local out_buf = nil
local out_win = nil

local function ensure_out_window()
  if out_win and vim.api.nvim_win_is_valid(out_win) then
    return
  end
  if not (out_buf and vim.api.nvim_buf_is_valid(out_buf)) then
    out_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[out_buf].bufhidden = 'hide'
    vim.bo[out_buf].filetype = 'cbuild'
    vim.api.nvim_buf_set_name(out_buf, '[C/C++ Build]')
  end
  local prev = vim.api.nvim_get_current_win()
  vim.cmd('botright 15split')
  out_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(out_win, out_buf)
  vim.wo[out_win].number = false
  vim.wo[out_win].relativenumber = false
  vim.wo[out_win].signcolumn = 'no'
  vim.wo[out_win].wrap = false
  -- q closes the window
  vim.keymap.set('n', 'q', function()
    if out_win and vim.api.nvim_win_is_valid(out_win) then
      vim.api.nvim_win_hide(out_win)
      out_win = nil
    end
  end, { buffer = out_buf, silent = true })
  vim.api.nvim_set_current_win(prev)
end

local function out_clear()
  if out_buf and vim.api.nvim_buf_is_valid(out_buf) then
    vim.bo[out_buf].modifiable = true
    vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, {})
    vim.bo[out_buf].modifiable = false
  end
end

local function out_append(lines)
  if not (out_buf and vim.api.nvim_buf_is_valid(out_buf)) then return end
  vim.bo[out_buf].modifiable = true
  -- jobstart sometimes hands us a trailing empty string; trim it.
  if #lines > 0 and lines[#lines] == '' then table.remove(lines) end
  if #lines == 0 then
    vim.bo[out_buf].modifiable = false
    return
  end
  vim.api.nvim_buf_set_lines(out_buf, -1, -1, false, lines)
  vim.bo[out_buf].modifiable = false
  if out_win and vim.api.nvim_win_is_valid(out_win) then
    local last = vim.api.nvim_buf_line_count(out_buf)
    vim.api.nvim_win_set_cursor(out_win, { last, 0 })
  end
end

local function toggle_output()
  if out_win and vim.api.nvim_win_is_valid(out_win) then
    vim.api.nvim_win_hide(out_win)
    out_win = nil
  else
    ensure_out_window()
  end
end

------------------------------------------------------------------------------
-- Job runner with streamed output.
------------------------------------------------------------------------------

local current_job = nil
local last_binary = nil  -- absolute path to last successfully built binary
local last_args = ''     -- last argv string used with run

local function run_job(cmd, cwd, on_exit_ok)
  if current_job then
    pcall(vim.fn.jobstop, current_job)
    current_job = nil
  end
  ensure_out_window()
  out_clear()
  out_append({ '$ ' .. (type(cmd) == 'table' and table.concat(cmd, ' ') or cmd),
               '  (cwd: ' .. cwd .. ')',
               '' })
  current_job = vim.fn.jobstart(cmd, {
    cwd = cwd,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data) if data then out_append(data) end end,
    on_stderr = function(_, data) if data then out_append(data) end end,
    on_exit = function(_, code)
      current_job = nil
      out_append({ '', code == 0 and ('✓ exit 0') or ('✗ exit ' .. code) })
      if code == 0 and on_exit_ok then on_exit_ok() end
    end,
  })
end

------------------------------------------------------------------------------
-- Build/run logic.
------------------------------------------------------------------------------

local function project_root_for(file)
  local dir = vim.fs.dirname(file)
  -- Look upward for Makefile, CMakeLists.txt, compile_commands.json, .git
  local found = vim.fs.find(
    { 'Makefile', 'makefile', 'CMakeLists.txt', 'compile_commands.json', '.git' },
    { upward = true, path = dir }
  )
  if found and #found > 0 then return vim.fs.dirname(found[1]) end
  return dir
end

local function compiler_for(file)
  if file:match('%.cpp$') or file:match('%.cc$') or file:match('%.cxx$') or file:match('%.cpp$') then
    return 'g++'
  end
  return 'gcc'
end

local function out_path_for(file)
  local dir = vim.fs.dirname(file)
  local stem = vim.fn.fnamemodify(file, ':t:r')
  return dir .. '/' .. stem
end

local function has_file(dir, name)
  return vim.fn.filereadable(dir .. '/' .. name) == 1
end

-- Build current file directly (no Makefile/CMake), or use Makefile if present.
local function build(opts)
  opts = opts or {}
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then
    vim.notify('No file in buffer', vim.log.levels.WARN)
    return
  end
  local root = project_root_for(file)

  -- 1) Makefile -> run make
  if has_file(root, 'Makefile') or has_file(root, 'makefile') then
    run_job({ 'make' }, root, function()
      if opts.then_run then
        -- After make, we don't know what binary was produced; ask user.
        vim.ui.input({ prompt = 'Binary to run (relative to ' .. root .. '): ' }, function(input)
          if not input or input == '' then return end
          last_binary = root .. '/' .. input
          M.run()
        end)
      end
    end)
    return
  end

  -- 2) CMakeLists.txt -> configure + build in ./build
  if has_file(root, 'CMakeLists.txt') then
    local bdir = root .. '/build'
    vim.fn.mkdir(bdir, 'p')
    run_job({ 'sh', '-c', 'cmake -S . -B build && cmake --build build' }, root, function()
      if opts.then_run then
        vim.ui.input({ prompt = 'Binary in build/: ' }, function(input)
          if not input or input == '' then return end
          last_binary = bdir .. '/' .. input
          M.run()
        end)
      end
    end)
    return
  end

  -- 3) Single-file compile
  local cc = compiler_for(file)
  local out = out_path_for(file)
  local cmd = { cc, '-Wall', '-Wextra', '-g', '-O0', file, '-o', out }
  -- Auto-link math for C if it looks needed; cheap heuristic.
  if cc == 'gcc' then table.insert(cmd, '-lm') end
  run_job(cmd, vim.fs.dirname(file), function()
    last_binary = out
    if opts.then_run then M.run() end
  end)
end

function M.build() build() end
function M.build_and_run() build({ then_run = true }) end

function M.run()
  if not last_binary or vim.fn.executable(last_binary) ~= 1 then
    vim.notify('No binary built yet (use <leader>cb)', vim.log.levels.WARN)
    return
  end
  -- Always run in an interactive terminal so the user can type input.
  -- Open in a bottom split.
  vim.cmd('botright 15split | terminal ' ..
    vim.fn.shellescape(last_binary) .. ' ' .. last_args)
  vim.cmd('startinsert')
end

function M.run_with_args()
  vim.ui.input({ prompt = 'argv: ', default = last_args }, function(input)
    if input == nil then return end
    last_args = input
    M.run()
  end)
end

function M.make_clean()
  local file = vim.api.nvim_buf_get_name(0)
  local root = project_root_for(file ~= '' and file or vim.fn.getcwd())
  if has_file(root, 'Makefile') or has_file(root, 'makefile') then
    run_job({ 'make', 'clean' }, root)
  else
    vim.notify('No Makefile at ' .. root, vim.log.levels.WARN)
  end
end

function M.cmake_configure()
  local file = vim.api.nvim_buf_get_name(0)
  local root = project_root_for(file ~= '' and file or vim.fn.getcwd())
  if not has_file(root, 'CMakeLists.txt') then
    vim.notify('No CMakeLists.txt at ' .. root, vim.log.levels.WARN)
    return
  end
  run_job({ 'cmake', '-S', '.', '-B', 'build' }, root)
end

function M.valgrind()
  if not last_binary or vim.fn.executable(last_binary) ~= 1 then
    vim.notify('Build first (<leader>cb)', vim.log.levels.WARN)
    return
  end
  if vim.fn.executable('valgrind') ~= 1 then
    vim.notify('valgrind not installed', vim.log.levels.ERROR)
    return
  end
  local root = vim.fs.dirname(last_binary)
  run_job({ 'valgrind', '--leak-check=full', '--show-leak-kinds=all',
            '--track-origins=yes', last_binary }, root)
end

function M.gdb_terminal()
  if not last_binary or vim.fn.executable(last_binary) ~= 1 then
    vim.notify('Build first (<leader>cb)', vim.log.levels.WARN)
    return
  end
  vim.cmd('botright 15split | terminal gdb ' .. vim.fn.shellescape(last_binary))
  vim.cmd('startinsert')
end

function M.switch_source_header()
  -- clangd extension: textDocument/switchSourceHeader
  local clients = vim.lsp.get_clients({ bufnr = 0, name = 'clangd' })
  if #clients == 0 then
    vim.notify('clangd not attached', vim.log.levels.WARN)
    return
  end
  local params = { uri = vim.uri_from_bufnr(0) }
  clients[1].request('textDocument/switchSourceHeader', params, function(err, result)
    if err or not result then
      vim.notify('No matching header/source', vim.log.levels.INFO)
      return
    end
    vim.cmd('edit ' .. vim.uri_to_fname(result))
  end, 0)
end

function M.toggle_output() toggle_output() end

------------------------------------------------------------------------------
-- Keymaps. Active for c/cpp buffers; output toggle is global.
------------------------------------------------------------------------------

-- Global: output window toggle (useful even outside c/cpp)
vim.keymap.set('n', '<leader>co', M.toggle_output, { desc = '[C]ode: toggle [o]utput window' })

local group = vim.api.nvim_create_augroup('c-cpp-keymaps', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
  callback = function(ev)
    local map = function(lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = ev.buf, desc = desc, silent = true })
    end
    map('<leader>cb', M.build,             '[C]ode: [B]uild')
    map('<leader>cr', M.build_and_run,     '[C]ode: build & [R]un')
    map('<leader>cR', M.run,               '[C]ode: [R]un last binary')
    map('<leader>ca', M.run_with_args,     '[C]ode: run with [A]rgs')
    map('<leader>cC', M.make_clean,        '[C]ode: make [C]lean')
    map('<leader>ck', M.cmake_configure,   '[C]ode: cma[k]e configure')
    map('<leader>cv', M.valgrind,          '[C]ode: [V]algrind')
    map('<leader>cg', M.gdb_terminal,      '[C]ode: [G]db (terminal)')
    map('<leader>ch', M.switch_source_header, '[C]ode: switch [H]eader/source')
    map('<leader>co', M.toggle_output,     '[C]ode: toggle [o]utput')
    -- Fast keys without leader for compile cycles:
    vim.keymap.set('n', '<F5>',  M.build_and_run, { buffer = ev.buf, desc = 'Build & run' })
    vim.keymap.set('n', '<F6>',  M.run,           { buffer = ev.buf, desc = 'Run last binary' })
    vim.keymap.set('n', '<F7>',  M.build,         { buffer = ev.buf, desc = 'Build' })
    vim.keymap.set('n', '<F8>',  M.valgrind,      { buffer = ev.buf, desc = 'Valgrind' })
  end,
})

return M
