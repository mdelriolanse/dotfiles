return {
  'catppuccin/nvim',
  name = 'catppuccin',
  priority = 1000,
  config = function()
    require('catppuccin').setup {
      flavour = 'mocha', -- latte, frappe, macchiato, mocha
      transparent_background = true,
      term_colors = true,
      styles = {
        comments = { 'italic' },
        keywords = { 'italic' },
        functions = {},
        statements = { 'bold' },
      },
      integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        neotree = true,
        treesitter = true,
        telescope = { enabled = true },
        which_key = true,
        mason = true,
        dap = true,
        dap_ui = true,
        fidget = true,
        flash = true,
        indent_blankline = { enabled = true },
        native_lsp = {
          enabled = true,
          virtual_text = {
            errors = { 'italic' },
            hints = { 'italic' },
            warnings = { 'italic' },
            information = { 'italic' },
          },
          underlines = {
            errors = { 'undercurl' },
            hints = { 'undercurl' },
            warnings = { 'undercurl' },
            information = { 'undercurl' },
          },
        },
      },
    }
    vim.cmd.colorscheme 'catppuccin'

    -- Tint editor, floats, neo-tree, and lualine middle sections with a
    -- catppuccin mauve-flavoured background. Re-applied on every colorscheme
    -- change so it survives :colorscheme reloads.
    local function tint_theme()
      local palette = require('catppuccin.palettes').get_palette('mocha')
      local backdrop = require('core.theme')
      local mauve = backdrop.accent
      local bg = backdrop.bg
      local bg_dim = backdrop.bg_dim

      -- Editor
      vim.api.nvim_set_hl(0, 'Normal',       { bg = bg, fg = palette.text })
      vim.api.nvim_set_hl(0, 'NormalNC',     { bg = bg, fg = palette.text })
      vim.api.nvim_set_hl(0, 'EndOfBuffer',  { bg = bg, fg = bg })
      vim.api.nvim_set_hl(0, 'SignColumn',   { bg = bg })
      vim.api.nvim_set_hl(0, 'LineNr',       { bg = bg, fg = palette.overlay0 })
      vim.api.nvim_set_hl(0, 'CursorLineNr', { bg = bg, fg = mauve, bold = true })
      vim.api.nvim_set_hl(0, 'WinSeparator', { bg = bg, fg = mauve })

      -- Floats (hover, diagnostics, etc.)
      vim.api.nvim_set_hl(0, 'NormalFloat',  { bg = bg, fg = palette.text })
      vim.api.nvim_set_hl(0, 'FloatBorder',  { bg = bg, fg = mauve })
      vim.api.nvim_set_hl(0, 'FloatTitle',   { bg = bg, fg = mauve, bold = true })

      -- Neo-tree
      vim.api.nvim_set_hl(0, 'NeoTreeNormal',       { bg = bg_dim, fg = palette.text })
      vim.api.nvim_set_hl(0, 'NeoTreeNormalNC',     { bg = bg_dim, fg = palette.text })
      vim.api.nvim_set_hl(0, 'NeoTreeEndOfBuffer',  { bg = bg_dim, fg = bg_dim })
      vim.api.nvim_set_hl(0, 'NeoTreeWinSeparator', { bg = bg_dim, fg = mauve })
      vim.api.nvim_set_hl(0, 'NeoTreeTitleBar',     { bg = mauve,  fg = palette.base, bold = true })

      -- Lualine middle sections (c/x). Section a/b/y/z keep their mode colors.
      for _, mode in ipairs({ 'normal', 'insert', 'visual', 'replace', 'command', 'terminal', 'inactive' }) do
        vim.api.nvim_set_hl(0, 'lualine_c_' .. mode, { bg = bg, fg = palette.text })
        vim.api.nvim_set_hl(0, 'lualine_x_' .. mode, { bg = bg, fg = palette.text })
      end
    end
    tint_theme()
    vim.api.nvim_create_autocmd('ColorScheme', { callback = tint_theme })

    -- Lualine builds its highlights after `require('lualine').setup`, so re-apply
    -- once VimEnter fires (after all plugins finish loading).
    vim.api.nvim_create_autocmd('VimEnter', { callback = tint_theme })
  end,
}
