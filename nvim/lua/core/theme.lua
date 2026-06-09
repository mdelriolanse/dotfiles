-- Centralized backdrop palette. Change values here to retint the whole UI.
-- Consumed by lua/plugins/catppuccin.lua (and any future component that wants
-- to match the editor's backdrop).
return {
  bg     = '#2a1f3d', -- main backdrop: editor, floats, lualine middle
  bg_dim = '#241a35', -- sidebars (neo-tree) — slightly darker for separation
  accent = '#cba6f7', -- catppuccin mauve — borders, separators, accents
}
