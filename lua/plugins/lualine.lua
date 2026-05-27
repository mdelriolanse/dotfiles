return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  event = 'VeryLazy',
  opts = {
    options = {
      theme = 'catppuccin',
      icons_enabled = true,
      globalstatus = true,
      component_separators = { left = '', right = '' },
      section_separators = { left = '', right = '' },
      disabled_filetypes = {
        statusline = { 'neo-tree', 'dap-repl', 'dapui_scopes', 'dapui_breakpoints',
                       'dapui_stacks', 'dapui_watches', 'dapui_console' },
      },
    },
    sections = {
      lualine_a = { 'mode' },
      lualine_b = {
        'branch',
        { 'diff', symbols = { added = ' ', modified = ' ', removed = ' ' } },
        { 'diagnostics', sources = { 'nvim_diagnostic' },
          symbols = { error = ' ', warn = ' ', info = ' ', hint = '󰌶 ' } },
      },
      lualine_c = {
        { 'filename', path = 1, symbols = { modified = ' ●', readonly = ' ', unnamed = '[No Name]' } },
      },
      lualine_x = {
        -- LSP servers attached to current buffer
        {
          function()
            local clients = vim.lsp.get_clients({ bufnr = 0 })
            if #clients == 0 then return '' end
            local names = {}
            for _, c in ipairs(clients) do table.insert(names, c.name) end
            return ' ' .. table.concat(names, ',')
          end,
          cond = function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end,
        },
        'encoding',
        'fileformat',
        'filetype',
      },
      lualine_y = { 'progress' },
      lualine_z = { 'location' },
    },
    extensions = { 'neo-tree', 'lazy', 'mason', 'fugitive', 'quickfix', 'nvim-dap-ui' },
  },
}
