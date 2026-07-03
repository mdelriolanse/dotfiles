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
    -- Colorscheme selection, the mauve backdrop tint, and its ColorScheme/VimEnter
    -- autocmds now live in core.theme-toggle (which owns the catppuccin<->gruvbox
    -- toggle). This file only configures the catppuccin plugin itself.
  end,
}
