-- Seamless Ctrl+hjkl navigation between Neovim splits and tmux panes.
-- Pairs with the matching bindings in ~/.tmux.conf.
-- Mappings are defined in lua/core/keymaps.lua; this spec just loads the
-- plugin on first use and suppresses its built-in default mappings.
return {
  'christoomey/vim-tmux-navigator',
  cmd = {
    'TmuxNavigateLeft',
    'TmuxNavigateDown',
    'TmuxNavigateUp',
    'TmuxNavigateRight',
    'TmuxNavigatePrevious',
  },
  init = function()
    vim.g.tmux_navigator_no_mappings = 1
  end,
}
