-- lua/plugins/smear-cursor.lua
-- Adds a physics-based "smear" trail effect to cursor movements
--
-- USAGE:
-- The effect is automatic - no keymaps needed. Large cursor jumps
-- (like gg, G, search results) will show a fluid slide animation.
--
-- COMMANDS:
--   :SmearCursorToggle  - Toggle the smear effect on/off
--
-- CUSTOMIZATION:
-- Adjust physics parameters in opts to change the feel:
--   stiffness          - Higher = stiffer, less elastic trail (default: 0.6)
--   trailing_stiffness - Responsiveness of the trail (default: 0.3)
--   damping            - Lower = more bouncy/elastic (default: 0.9)
--   cursor_color       - Manual color if terminal overrides Neovim's cursor
--
-- Example custom config:
--   opts = {
--     stiffness = 0.8,
--     trailing_stiffness = 0.6,
--     damping = 0.95,
--     cursor_color = "#d3cdc3",
--   }
--
-- NOTE: Some terminals override cursor color. If the smear color looks wrong,
-- set cursor_color manually to match your preferred cursor color.

return {
  "sphamba/smear-cursor.nvim",
  opts = {},
}
