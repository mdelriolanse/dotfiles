return {
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    -- Pinned to the last commit verified working on Neovim 0.11.x. The main branch
    -- is drifting toward Neovim 0.12-only APIs; pinning prevents a future :Lazy
    -- update from pulling a commit that uses an API 0.11 lacks (which would silently
    -- stop ALL parser installs). Unpin once Neovim is upgraded to 0.12+.
    commit = '4916d6592ede8c07973490d9322f187e07dfefac',
    build = ':TSUpdate',
    config = function()
      -- Polyfill for Neovim 0.12's vim.list.unique, the single 0.12-only API this
      -- pinned commit uses (config.lua, during parser-name normalization). Without
      -- it, parser installs error with "attempt to index field 'list' (a nil value)"
      -- on 0.11. Remove once on Neovim 0.12+. Preserves first-occurrence order.
      if not vim.list then vim.list = {} end
      if not vim.list.unique then
        vim.list.unique = function(t)
          local seen, out = {}, {}
          for _, v in ipairs(t) do
            if not seen[v] then
              seen[v] = true
              out[#out + 1] = v
            end
          end
          return out
        end
      end

      local ts = require('nvim-treesitter')
      ts.setup()

      -- Ensure parsers are installed
      local ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'python', 'luadoc', 'markdown', 'markdown_inline', 'query', 'rust', 'toml', 'vim', 'vimdoc' }
      local installed_set = {}
      for _, p in ipairs(ts.get_installed()) do
        installed_set[p] = true
      end
      local to_install = {}
      for _, lang in ipairs(ensure_installed) do
        if not installed_set[lang] then
          table.insert(to_install, lang)
        end
      end
      if #to_install > 0 then
        ts.install(to_install)
      end

      -- Enable treesitter highlighting. The main branch doesn't auto-start it, so
      -- drive vim.treesitter.start() per buffer. pcall keeps filetypes without a
      -- parser on Vim's regex syntax instead of erroring. Covers both future
      -- buffers (FileType) and any already open when this config runs at startup.
      local function start_ts(buf)
        pcall(vim.treesitter.start, buf)
      end
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('treesitter-highlight', { clear = true }),
        desc = 'Start treesitter highlighting when a parser exists',
        callback = function(ev)
          start_ts(ev.buf)
        end,
      })
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          start_ts(buf)
        end
      end
    end,
  },
}
