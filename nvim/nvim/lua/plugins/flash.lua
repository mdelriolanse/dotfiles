-- lua/plugins/flash.lua
-- Enhances f/t/F/T and search with labeled jump targets
--
-- USAGE:
-- Flash works automatically with:
--   f/F/t/T  - Character motions show jump labels
--   /        - Search shows jump labels on all matches
--   s        - Flash jump mode (treesitter-aware)
--
-- KEYMAPS:
--   s         - Flash jump (in normal mode)
--   S         - Flash treesitter selection
--   r         - Remote flash (operator pending)
--   <c-s>     - Toggle flash search (in search mode)
--
-- The "Feel": Navigate files by "teleporting" with precision
-- rather than hunting for characters.

return {
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {
    modes = {
      char = {
        jump_labels = true,
      },
    },
  },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
    { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
    { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
    { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
  },
}
