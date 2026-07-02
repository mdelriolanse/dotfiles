return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    dashboard = {
      sections = {
        { section = 'header' },
        { icon = ' ', title = 'Keymaps', section = 'keys', indent = 2 },
        { icon = ' ', title = 'Recent Files', section = 'recent_files', indent = 2 },
        { icon = ' ', title = 'Session', section = 'session', indent = 2 },
        { section = 'startup' },
      },
    },
  },
}
