return {
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
      local ts = require('nvim-treesitter')
      ts.setup()

      -- Ensure parsers are installed
      local ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'python', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' }
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
    end,
  },
}
