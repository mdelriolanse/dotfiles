-- lua/plugins/fidget.lua
-- Shows LSP progress notifications with animated indicators
--
-- USAGE:
-- The effect is automatic - when your LSP is working (indexing,
-- analyzing, etc.), you'll see a small animated spinner and
-- progress text in the bottom corner.
--
-- WHY:
-- Makes the "mechanical" parts of the editor visible and active,
-- so you know when your LSP is actually working vs frozen.
--
-- CUSTOMIZATION:
-- You can adjust the appearance in opts:
--   progress.display.done_icon - Icon shown when complete
--   notification.window.winblend - Transparency (0-100)

return {
  "j-hui/fidget.nvim",
  event = "LspAttach",
  opts = {
    progress = {
      display = {
        done_icon = "✓",
      },
    },
    notification = {
      window = {
        winblend = 0,
      },
    },
  },
}
