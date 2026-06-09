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
      -- Restart LSP after setting a new environment
      post_set_venv = function()
        vim.cmd('LspRestart')
        vim.notify('Python virtual environment changed. LSP restarted.', vim.log.levels.INFO)
      end,
    })

    -- Create user commands with error handling for compatibility issues
    vim.api.nvim_create_user_command('SwenvPick', function()
      local ok, err = pcall(function()
        require('swenv.api').pick_venv()
      end)
      if not ok then
        -- Fallback: try to find venvs manually and set them
        local venvs = {}
        local cwd = vim.fn.getcwd()

        -- Common venv locations in project
        local common_names = { '.venv', 'venv', '.env', 'env' }
        for _, name in ipairs(common_names) do
          local venv_path = cwd .. '/' .. name
          if vim.fn.isdirectory(venv_path) == 1 then
            table.insert(venvs, { name = name, path = venv_path })
          end
        end

        -- Check conda envs
        local conda_prefix = vim.env.CONDA_PREFIX
        if conda_prefix then
          local conda_envs = vim.fn.expand('~/.conda/envs')
          if vim.fn.isdirectory(conda_envs) == 1 then
            local handle = vim.loop.fs_scandir(conda_envs)
            if handle then
              while true do
                local name, type = vim.loop.fs_scandir_next(handle)
                if not name then break end
                if type == 'directory' then
                  table.insert(venvs, { name = 'conda:' .. name, path = conda_envs .. '/' .. name })
                end
              end
            end
          end
        end

        -- Check pyenv virtualenvs
        local pyenv_root = vim.env.PYENV_ROOT or vim.fn.expand('~/.pyenv')
        local pyenv_versions = pyenv_root .. '/versions'
        if vim.fn.isdirectory(pyenv_versions) == 1 then
          local handle = vim.loop.fs_scandir(pyenv_versions)
          if handle then
            while true do
              local name, type = vim.loop.fs_scandir_next(handle)
              if not name then break end
              if type == 'directory' then
                table.insert(venvs, { name = 'pyenv:' .. name, path = pyenv_versions .. '/' .. name })
              end
            end
          end
        end

        if #venvs == 0 then
          vim.notify('No Python virtual environments found', vim.log.levels.WARN)
          return
        end

        vim.ui.select(venvs, {
          prompt = 'Select Python venv:',
          format_item = function(item)
            return item.name .. ' (' .. item.path .. ')'
          end,
        }, function(choice)
          if choice then
            vim.env.VIRTUAL_ENV = choice.path
            vim.env.PATH = choice.path .. '/bin:' .. vim.env.PATH
            vim.cmd('LspRestart')
            vim.notify('Activated: ' .. choice.name, vim.log.levels.INFO)
          end
        end)
      end
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
