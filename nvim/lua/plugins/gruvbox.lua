return {
  'ellisonleao/gruvbox.nvim',
  priority = 1000,
  config = function()
    require('gruvbox').setup {
      contrast = 'hard',        -- keep non-transparent fills dark, close to the terminal's #0d0e0f
      transparent_mode = true,  -- Normal/SignColumn/etc -> NONE natively (lets the terminal glass show through)
      italic = { comments = true, keywords = true },
      bold = true,
    }
    -- Do NOT auto-apply here; core.theme-toggle owns which colorscheme is active.
  end,
}
