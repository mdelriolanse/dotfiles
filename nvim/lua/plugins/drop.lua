return {
  'folke/drop.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  event = 'VimEnter',
  config = function(_, opts)
    local data_dir = vim.fn.stdpath('data')
    local theme_file = data_dir .. '/drop_theme.txt'
    local enabled_file = data_dir .. '/drop_enabled.txt'

    -- ── persistence helpers ──────────────────────────────────
    local function load_theme()
      local f = io.open(theme_file, 'r')
      if f then
        local theme = f:read('*l')
        f:close()
        if theme and theme:match('^[%w_]+$') then
          return theme
        end
      end
      return nil
    end

    local function save_theme(theme)
      local f = io.open(theme_file, 'w')
      if f then
        f:write(theme)
        f:close()
      end
    end

    local function load_enabled()
      local f = io.open(enabled_file, 'r')
      if f then
        local val = f:read('*l')
        f:close()
        return val ~= 'false'
      end
      return true -- default: enabled
    end

    local function save_enabled(enabled)
      local f = io.open(enabled_file, 'w')
      if f then
        f:write(enabled and 'true' or 'false')
        f:close()
      end
    end

    local saved_theme = load_theme() or 'matrix'
    local is_enabled = load_enabled()

    local my_opts = {
      theme = saved_theme,
      max = 75,
      interval = 100,
      screensaver = false,
      winblend = 100,
      -- when disabled, suppress dashboard auto-show by giving empty filetypes
      filetypes = is_enabled and { 'snacks_dashboard', 'dashboard', 'alpha', 'ministarter' } or {},
    }
    for k, v in pairs(opts or {}) do
      my_opts[k] = v
    end

    require('drop').setup(my_opts)

    -- ── telescope picker with live preview ─────────────────
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local telescope_themes = require('telescope.themes')
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local conf = require('telescope.config').values

    local function pick_theme()
      local theme_names = {}
      local themes_module = require('drop.themes')
      for name, _ in pairs(themes_module) do
        table.insert(theme_names, name)
      end
      table.sort(theme_names)

      local original_theme = require('drop.config').options.theme
      local was_running = require('drop.drop').timer ~= nil
      local is_confirmed = false

      -- selecting a theme implicitly re-enables drops
      local function set_theme(name)
        if not name then
          return
        end
        require('drop').hide()
        vim.schedule(function()
          require('drop.config').options.theme = name
          require('drop').show()
        end)
      end

      pickers.new(telescope_themes.get_ivy({
        sorting_strategy = 'ascending',
        layout_config = { height = 10 },
        border = false,
      }), {
        prompt_title = 'Drop Theme (j/k or arrows to preview, Enter to save, Esc/q to cancel)',
        finder = finders.new_table({ results = theme_names }),
        sorter = conf.generic_sorter(),
        attach_mappings = function(prompt_bufnr, map)
          local function preview_current()
            local entry = action_state.get_selected_entry()
            if entry and entry[1] then
              set_theme(entry[1])
            end
          end

          local function move_next()
            actions.move_selection_next(prompt_bufnr)
            preview_current()
          end
          local function move_prev()
            actions.move_selection_previous(prompt_bufnr)
            preview_current()
          end

          map('i', '<Down>', move_next)
          map('i', '<Up>', move_prev)
          map('i', '<C-n>', move_next)
          map('i', '<C-p>', move_prev)
          map('n', 'j', move_next)
          map('n', 'k', move_prev)
          map('n', '<Down>', move_next)
          map('n', '<Up>', move_prev)

          local function confirm_picker()
            is_confirmed = true
            local entry = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if entry and entry[1] then
              save_theme(entry[1])
              save_enabled(true) -- picking a theme re-enables drops
              is_enabled = true
              vim.notify('Drop enabled & saved: ' .. entry[1], vim.log.levels.INFO)
            end
          end
          map('i', '<CR>', confirm_picker)
          map('n', '<CR>', confirm_picker)

          local function cancel_picker()
            actions.close(prompt_bufnr)
            if not is_confirmed then
              require('drop').hide()
              require('drop.config').options.theme = original_theme
              if was_running then
                require('drop').show()
              end
              -- if user was previously disabled, restore disabled state
              if not is_enabled then
                require('drop').hide()
              end
              vim.notify('Theme preview cancelled', vim.log.levels.INFO)
            end
          end
          map('i', '<Esc>', cancel_picker)
          map('n', '<Esc>', cancel_picker)
          map('n', 'q', cancel_picker)
          map('i', '<C-c>', cancel_picker)

          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(prompt_bufnr) then
              preview_current()
            end
          end)

          return true
        end,
      }):find()
    end

    -- ── manual toggle (persists across sessions) ───────────────
    local drop_active = false
    local function drop_toggle()
      if is_enabled then
        -- disable permanently
        require('drop').hide()
        save_enabled(false)
        is_enabled = false
        drop_active = false
        vim.notify('Drop disabled (saved)', vim.log.levels.INFO)
      else
        -- re-enable
        save_enabled(true)
        is_enabled = true
        drop_active = true
        require('drop').show()
        vim.notify('Drop enabled: ' .. saved_theme, vim.log.levels.INFO)
      end
    end

    _G.DropPickTheme = pick_theme
    _G.DropToggle = drop_toggle
  end,
}
