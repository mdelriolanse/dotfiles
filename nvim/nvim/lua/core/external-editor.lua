-- External editor functionality for Claude Code
-- Allows opening files from external processes (like Claude CLI's Ctrl+G) in the current Neovim session
--
-- Usage: When Claude Code opens a file via Ctrl+G, it will appear in a new tab.
-- To finish editing: save the file (:w) then press <leader>e or run :ExternalEditFinish
-- This signals to Claude Code that editing is complete.

local M = {}

--- Close the current buffer and signal editing is complete
--- Removes the .editing lock file to signal the wrapper script
function M.finish_external_edit()
  local filepath = vim.api.nvim_buf_get_name(0)
  
  -- Save first if modified
  if vim.bo.modified then
    vim.cmd('write')
  end
  
  -- Remove the lock file to signal completion
  local lock_file = filepath .. '.editing'
  os.remove(lock_file)
  
  -- Close the tab/buffer fully
  if vim.fn.tabpagenr('$') > 1 then
    vim.cmd('tabclose')
  else
    vim.cmd('bdelete')
  end
  
  -- Also run :q to ensure window is fully closed
  pcall(vim.cmd, 'q')
  
  vim.notify('External editing complete', vim.log.levels.INFO)
end

-- Create user command
vim.api.nvim_create_user_command('ExternalEditFinish', function()
  M.finish_external_edit()
end, { desc = 'Save and close buffer (finish external editing)' })

-- Keybinding for finishing external edit
vim.keymap.set('n', '<leader>e', function()
  M.finish_external_edit()
end, { desc = 'Finish external editing (save & close)' })

return M
