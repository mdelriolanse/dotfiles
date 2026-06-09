-- lua/plugins/tiny-glimmer.lua
-- Adds smooth, satisfying animations when yanking text
--
-- USAGE:
-- The effect is automatic - when you yank text (y, yy, etc.),
-- you'll see a subtle animated glow/pulse effect.
--
-- CUSTOMIZATION:
-- You can customize the animation style in opts:
--   default_animation - "fade", "bounce", "left_to_right", "pulse", "rainbow"
--   timeout           - How long the animation lasts (ms)
--
-- Example custom config:
--   opts = {
--     default_animation = "rainbow",
--     timeout = 300,
--   }

return {
  "rachartier/tiny-glimmer.nvim",
  event = "TextYankPost",
  opts = {
    default_animation = "fade",
    timeout = 300,
  },
}
