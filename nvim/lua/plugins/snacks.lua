return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  keys = {
    { '<leader>gh', function() Snacks.terminal('ghui') end, desc = 'GitHub PRs (ghui)' },
  },
  opts = {
    dashboard = {
      preset = {
        header = [[
███╗   ██╗██╗   ██╗██╗███╗   ███╗
████╗  ██║██║   ██║██║████╗ ████║
██╔██╗ ██║██║   ██║██║██╔████╔██║
██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝]],
      },
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
