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
    config = function()
      require('diffview').setup()

      -- With cmdheight=0 (see core/options.lua) there's no room to show even a
      -- one-line message, so diffview's scroll/status output forces the
      -- "Press ENTER or type command to continue" prompt. Restore a 1-line
      -- cmdline only while a diffview tab is active, then put it back.
      local saved
      local grp = vim.api.nvim_create_augroup('DiffviewCmdheight', { clear = true })
      vim.api.nvim_create_autocmd('User', {
        group = grp,
        pattern = 'DiffviewViewEnter',
        callback = function()
          saved = vim.o.cmdheight
          if vim.o.cmdheight == 0 then vim.o.cmdheight = 1 end
        end,
      })
      vim.api.nvim_create_autocmd('User', {
        group = grp,
        pattern = 'DiffviewViewLeave',
        callback = function()
          if saved ~= nil then vim.o.cmdheight = saved end
        end,
      })
    end,
  },
}
