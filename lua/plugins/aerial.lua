return {
  'stevearc/aerial.nvim',
  -- master requires Neovim 0.12+; pin the legacy branch for 0.11.x.
  branch = 'nvim-0.11',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'nvim-tree/nvim-web-devicons',
  },
  keys = {
    { '<leader>o', '<cmd>AerialToggle float<CR>', desc = '[O]utline (toggle popup)' },
  },
  config = function()
    require('aerial').setup {
      -- Prefer LSP (clangd) symbols, fall back to treesitter / markdown / man.
      backends = { 'lsp', 'treesitter', 'markdown', 'man' },
      layout = {
        default_direction = 'float', -- popup, not a docked sidebar
      },
      -- Symbols stay in file order (top-to-bottom); this is aerial's default.
      -- filter_kind = false shows everything: functions, structs, fields,
      -- variables, etc. (not just the default subset).
      filter_kind = false,
      float = {
        border = 'rounded',
        relative = 'editor',
      },
      -- Buffer-local maps inside the outline are aerial defaults:
      --   j/k move, <CR> or mouse click jumps, q/<Esc> closes.
      on_attach = function(bufnr)
        vim.keymap.set('n', '<leader>o', '<cmd>AerialToggle float<CR>', { buffer = bufnr, desc = '[O]utline (toggle popup)' })
      end,
    }

    -- Quick-select shortcuts: press a label to jump straight to that item.
    -- Numbers 1-9 then 0 (items 1-10), then letters as runoff. Letters skip
    -- keys aerial already uses in its buffer (h j k l o O p q) so its built-in
    -- navigation/fold maps keep working.
    local labels = {}
    for i = 1, 9 do
      labels[i] = tostring(i)
    end
    labels[10] = '0'
    for c in ('abcdefgimnrstuvwxyz'):gmatch '.' do
      labels[#labels + 1] = c
    end

    vim.api.nvim_set_hl(0, 'AerialQuickSelect', { link = 'Number', default = true })
    local ns = vim.api.nvim_create_namespace 'aerial_quickselect'

    local function render_labels(buf)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      local n = math.min(vim.api.nvim_buf_line_count(buf), #labels)
      for line = 1, n do
        vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
          virt_text = { { labels[line] .. ' ', 'AerialQuickSelect' } },
          virt_text_pos = 'inline',
        })
      end
    end

    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'aerial',
      group = vim.api.nvim_create_augroup('aerial-quickselect', { clear = true }),
      callback = function(ev)
        local buf = ev.buf
        for idx, lbl in ipairs(labels) do
          vim.keymap.set('n', lbl, function()
            require('aerial').select { index = idx }
          end, { buffer = buf, nowait = true, desc = 'Aerial select #' .. idx })
        end
        render_labels(buf)
        -- aerial re-renders the buffer on updates, which wipes extmarks;
        -- re-draw the labels whenever its lines change.
        vim.api.nvim_buf_attach(buf, false, {
          on_lines = function()
            vim.schedule(function()
              render_labels(buf)
            end)
          end,
          on_detach = function()
            return true
          end,
        })
      end,
    })
  end,
}
