return {
  'nvim-neorg/neorg',
  lazy = false, -- Disable lazy loading as some `lazy.nvim` distributions set `lazy = true` by default
  opts = {
    load = {
      ['core.defaults'] = {},
      ['core.keybinds'] = {},
      ['core.concealer'] = {},
      ['core.dirman'] = {
        config = {
          workspaces = {
            dev = '~/dev',
          },
        },
      },
    },
  },
  version = '*', -- Pin Neorg to the latest stable release
  config = true,
}
