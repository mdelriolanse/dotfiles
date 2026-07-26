-- Open lumen's interactive diff viewer for "everything my branch changed since main".
--
-- Resolves the base branch the current branch forked from, takes the merge-base so
-- commits that landed on main after the fork don't show up as our changes, and runs
-- `lumen diff <merge-base>..HEAD` in a floating terminal.
--
-- Git commands run with cwd set to the current buffer's directory, so this does the
-- right thing inside a linked worktree (each worktree has its own HEAD).

local M = {}

local LUMEN = 'lumen'

-- Branches to try, in order, when origin/HEAD isn't set.
local FALLBACK_BASES = { 'main', 'master', 'trunk', 'develop' }

local function cwd()
  local buf_dir = vim.fn.expand '%:p:h'
  if buf_dir ~= '' and vim.fn.isdirectory(buf_dir) == 1 then
    return buf_dir
  end
  return vim.fn.getcwd()
end

-- Run git, return trimmed stdout on success or nil on any failure.
local function git(args, dir)
  local res = vim.system(vim.list_extend({ 'git' }, args), { cwd = dir, text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  local out = vim.trim(res.stdout or '')
  return out ~= '' and out or nil
end

local function has_local_branch(name, dir)
  return git({ 'rev-parse', '--verify', '--quiet', 'refs/heads/' .. name }, dir) ~= nil
end

local function has_remote_branch(name, dir)
  return git({ 'rev-parse', '--verify', '--quiet', 'refs/remotes/origin/' .. name }, dir) ~= nil
end

-- Prefer the local branch (that's what you're actually rebasing onto); fall back to
-- origin/<name> when the branch only exists on the remote.
local function resolve(name, dir)
  if has_local_branch(name, dir) then
    return name
  end
  if has_remote_branch(name, dir) then
    return 'origin/' .. name
  end
  return nil
end

-- A candidate is only a plausible base if it actually shares history with HEAD.
-- This matters: a repo can carry a stale `main` with an unrelated history alongside
-- the real trunk, and picking it by name alone would give a meaningless diff.
local function shares_history(ref, dir)
  return git({ 'merge-base', ref, 'HEAD' }, dir) ~= nil
end

--- Best guess at the branch the current branch was cut from.
--- Set `vim.g.lumen_diff_base` to pin it explicitly when the guess is wrong.
--- @return string|nil ref, string|nil short_name
function M.base_branch(dir)
  dir = dir or cwd()

  local pinned = vim.g.lumen_diff_base
  if pinned and pinned ~= '' then
    return pinned, (pinned:gsub('^origin/', ''))
  end

  -- `git remote set-head origin --auto` populates this; it's the authoritative answer.
  local head = git({ 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' }, dir)
  if head then
    local short = head:gsub('^origin/', '')
    local ref = resolve(short, dir)
    if ref and shares_history(ref, dir) then
      return ref, short
    end
  end

  for _, name in ipairs(FALLBACK_BASES) do
    local ref = resolve(name, dir)
    if ref and shares_history(ref, dir) then
      return ref, name
    end
  end

  return nil, nil
end

-- Fork point of the current branch, or nil plus a reason it isn't available.
-- Shared by the 'branch' and 'stacked' scopes.
local function fork_point(dir)
  local base, short = M.base_branch(dir)
  if not base then
    return nil, 'no base branch found (looked for origin/HEAD, ' .. table.concat(FALLBACK_BASES, ', ') .. ')'
  end

  local current = git({ 'rev-parse', '--abbrev-ref', 'HEAD' }, dir)
  if current == short or current == base then
    return nil, 'already on ' .. base
  end

  local merge_base = git({ 'merge-base', base, 'HEAD' }, dir)
  if not merge_base then
    return nil, 'no common ancestor with ' .. base
  end
  if merge_base == git({ 'rev-parse', 'HEAD' }, dir) then
    return nil, 'no commits ahead of ' .. base
  end

  return merge_base, (current or 'HEAD') .. ' vs ' .. base
end

--- Build the `lumen diff` argument list for a scope.
--- Base resolution is deliberately independent of the scope: which branch you're on
--- decides what you're compared *against*, never which question you're asking.
--- @param scope 'branch'|'worktree'|'last'|'stacked'|'watch'|'pr'
--- @return table|nil args, string label
function M.diff_args(scope, dir)
  scope = scope or 'branch'
  dir = dir or cwd()

  if git({ 'rev-parse', '--is-inside-work-tree' }, dir) ~= 'true' then
    return nil, 'not a git repository'
  end

  if scope == 'worktree' then
    return { 'diff' }, 'uncommitted'
  end

  if scope == 'watch' then
    return { 'diff', '--watch' }, 'uncommitted (watching)'
  end

  if scope == 'pr' then
    return { 'diff', '--detect-pr' }, 'pull request'
  end

  if scope == 'last' then
    if not git({ 'rev-parse', '--verify', '--quiet', 'HEAD' }, dir) then
      return nil, 'no commits yet'
    end
    return { 'diff', 'HEAD' }, 'last commit (' .. (git({ 'log', '-1', '--format=%h %s' }, dir) or 'HEAD') .. ')'
  end

  local merge_base, info = fork_point(dir)

  if scope == 'stacked' then
    -- There is nothing to step through without commits of our own.
    if not merge_base then
      return nil, info
    end
    return { 'diff', merge_base .. '..HEAD', '--stacked' }, info .. ' (stacked)'
  end

  -- scope == 'branch'. On the base branch, or nothing committed yet, the range would
  -- be empty, so show uncommitted work instead of an empty viewer.
  if not merge_base then
    return { 'diff' }, 'uncommitted (' .. info .. ')'
  end
  return { 'diff', merge_base .. '..HEAD' }, info
end

local function open_float(cmd, dir, label)
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' lumen diff — ' .. label .. ' ',
    title_pos = 'center',
  })

  local job = vim.fn.jobstart(cmd, {
    cwd = dir,
    term = true,
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })

  -- lumen quits on q/esc by itself. <C-q> closes windows everywhere else in this
  -- config (see core/keymaps.lua), but that mapping is normal-mode only: in terminal
  -- mode the key gets forwarded to lumen, which doesn't bind it, so nothing happens.
  -- Bind it buffer-locally in both terminal and terminal-normal mode, and stop the
  -- job too — the global mapping would close the window and leave lumen running.
  local function close()
    vim.fn.jobstop(job)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set({ 't', 'n' }, '<C-q>', close, {
    buffer = buf,
    nowait = true,
    silent = true,
    desc = 'Close lumen diff',
  })

  -- lumen is a full-screen TUI, so hand it every other keystroke. Deferred because
  -- the terminal isn't attached yet on the same tick as jobstart.
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.cmd 'startinsert'
    end
  end)
end

--- Open the lumen diff viewer for the given scope (default 'branch').
--- @param scope 'branch'|'worktree'|'last'|'stacked'|'watch'|'pr'|nil
function M.open(scope)
  local dir = cwd()

  local args, label = M.diff_args(scope, dir)
  if not args then
    vim.notify('lumen diff: ' .. label, vim.log.levels.WARN)
    return
  end

  if vim.fn.executable(LUMEN) == 0 then
    vim.notify('lumen not found on PATH (wanted: ' .. label .. ')', vim.log.levels.ERROR)
    return
  end

  open_float(vim.list_extend({ LUMEN }, args), dir, label)
end

return M
