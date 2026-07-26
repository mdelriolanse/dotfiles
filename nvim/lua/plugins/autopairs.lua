-- lua/plugins/autopairs.lua
-- Auto-inserts the matching closing bracket/quote as you type the opening one.
--
-- USAGE:
--   Typing `{`  ->  `{|}`            (cursor between the pair)
--   Then <CR>   ->  opens the block and drops `}` on its own line, re-indented
--                   by the buffer's indent engine, so a nested block closes at
--                   ITS depth rather than colliding with an outer `}`:
--
--                       fn main() {
--                           if x {
--                               |
--                           }        <- lands here, not at column 0
--                       }
--
--   Typing `}` where one already sits just moves over it (no doubled brace).
--   <M-e>       -> fast_wrap: wrap the word after the cursor in the pair you
--                  just opened, instead of retyping the closing half.
--
-- WHY THIS SETUP:
--   check_ts uses treesitter to suppress QUOTE pairing inside the node types
--   listed in ts_config, so an apostrophe typed inside a string stays a lone
--   apostrophe. It does not gate brackets -- a `{` typed inside a string or
--   comment still gets its `}`. The <CR> handling is what
--   actually fixes the indentation complaint -- it re-indents the closing line
--   via indentexpr/cindent (Neovim's built-in ftplugins set these), so depth is
--   computed from the syntax, not copied from the opening line.
--
--   The nvim-cmp `confirm_done` hookup lives in plugins/cmp-config.lua, and
--   nvim-cmp lists this plugin as a dependency so autopairs owns <CR> BEFORE
--   cmp wraps it -- otherwise cmp's fallback would bypass the block-opening.

return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  config = function()
    require('nvim-autopairs').setup {
      check_ts = true, -- don't pair inside strings/comments
      ts_config = {
        lua = { 'string' },
        javascript = { 'template_string' },
      },
      fast_wrap = {
        map = '<M-e>',
        chars = { '{', '[', '(', '"', "'" },
        end_key = '$',
        keys = 'qwertyuiopzxcvbnmasdfghjkl',
      },
    }
  end,
}
