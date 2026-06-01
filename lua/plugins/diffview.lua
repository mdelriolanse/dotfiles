return {
  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory', 'DiffviewToggleFiles' },
    keys = {
      { '<leader>jd', '<cmd>DiffviewOpen<cr>',          desc = '[D]iffview open' },
      { '<leader>jD', '<cmd>DiffviewClose<cr>',         desc = '[D]iffview close' },
      { '<leader>jf', '<cmd>DiffviewFileHistory %<cr>', desc = '[F]ile history (current)' },
      { '<leader>jF', '<cmd>DiffviewFileHistory<cr>',   desc = '[F]ile history (repo)' },
    },
  },
}
