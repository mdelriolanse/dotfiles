return {
  "L3MON4D3/LuaSnip",
  config = function()
    require("luasnip.loaders.from_vscode").lazy_load() -- optional: load snippets from vscode repo
  end,
}

