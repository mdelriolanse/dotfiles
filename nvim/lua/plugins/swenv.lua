-- lua/plugins/swenv.lua
-- Python virtual environment switcher for Neovim
--
-- USAGE:
--   :SwenvPick - Pick a virtual environment from available options
--   :SwenvCurrent - Show the current virtual environment
--
-- WHY:
-- Allows switching Python virtual environments without restarting Neovim.
-- Automatically restarts LSP servers after switching to ensure proper
-- import resolution and type checking.

return {
  'AckslD/swenv.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('swenv').setup({
      -- Function to retrieve available virtual environments
      get_venvs = function(venvs_path)
        return require('swenv.api').get_venvs(venvs_path)
      end,
      -- Path to search for virtual environments
      -- Set to current directory to find project-local venvs (.venv, venv, etc.)
      venvs_path = vim.fn.getcwd(),
      -- Restart LSP after setting a new environment
      post_set_venv = function()
        vim.cmd('LspRestart')
        vim.notify('Python virtual environment changed. LSP restarted.', vim.log.levels.INFO)
      end,
    })

    -- Create user commands
    vim.api.nvim_create_user_command('SwenvPick', function()
      require('swenv.api').pick_venv()
    end, { desc = 'Pick a Python virtual environment' })

    vim.api.nvim_create_user_command('SwenvCurrent', function()
      local venv = require('swenv.api').get_current_venv()
      if venv then
        vim.notify('Current Python venv: ' .. venv, vim.log.levels.INFO)
      else
        vim.notify('No Python virtual environment set', vim.log.levels.WARN)
      end
    end, { desc = 'Show current Python virtual environment' })
  end,
}
