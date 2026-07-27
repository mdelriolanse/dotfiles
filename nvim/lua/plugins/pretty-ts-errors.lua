return {
  'youyoumu/pretty-ts-errors.nvim',
  ft = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  -- Requires: npm install -g pretty-ts-errors-markdown
  opts = {
    auto_open = false,
    float_opts = {
      border = 'rounded',
    },
  },
}
