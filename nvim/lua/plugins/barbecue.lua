return {
  'utilyre/barbecue.nvim',
  name = 'barbecue',
  version = '*',
  dependencies = {
    'SmiteshP/nvim-navic',
    'nvim-tree/nvim-web-devicons',
  },
  opts = {
    symbols = {
      separator = ' > ',
    },
    -- Disable kind icons (nerd font glyphs) — plain text breadcrumb chain.
    kinds = false,
  },
}

