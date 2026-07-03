return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons', 'catppuccin/nvim' },
  event = 'VeryLazy',
  opts = function()
    local ok, theme = pcall(require, 'lualine.themes.catppuccin-mocha')
    if not ok then
      ok, theme = pcall(require, 'lualine.themes.catppuccin')
    end
    -- Remember the catppuccin theme name so core.theme-toggle can restore it when
    -- switching back from gruvbox.
    _G.LualineCatppuccinTheme = ok and theme or 'auto'
    -- Honour the persisted theme mode: if gruvbox is active, load lualine themed to
    -- match so a restored session's statusline isn't briefly catppuccin-colored.
    local tt_ok, tt = pcall(require, 'core.theme-toggle')
    local active_theme = (tt_ok and tt.mode == 'gruvbox') and 'gruvbox' or (ok and theme or 'auto')
    local config = {
    options = {
      theme = active_theme,
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
    }
    -- Stash the fully-built config so core.theme-toggle can re-run setup() with a
    -- swapped options.theme (gruvbox <-> catppuccin) without losing these sections.
    _G.LualineOpts = config
    return config
  end,
}
