return {
  'rebelot/kanagawa.nvim',
  config = function()
    require('kanagawa').setup {
      compile = false, -- enable compiling the colorscheme
      undercurl = true, -- enable undercurls
      commentStyle = { italic = true },
      functionStyle = {},
      keywordStyle = { italic = true },
      statementStyle = { bold = true },
      typeStyle = {},
      transparent = true, -- do not set background color
      dimInactive = false, -- dim inactive window `:h hl-NormalNC`
      terminalColors = true, -- define vim.g.terminal_color_{0,17}
      colors = { -- add/modify theme and palette colors
        palette = {},
        theme = { wave = {}, lotus = {}, dragon = {}, all = {} },
      },
      overrides = function(colors)
        local theme = colors.theme
        local palette = colors.palette

        return {
          -- Dark completion menu background
          Pmenu = { fg = theme.ui.shade0, bg = theme.ui.bg_p1, blend = vim.o.pumblend },
          PmenuSel = { fg = "NONE", bg = theme.ui.bg_p2 },
          PmenuSbar = { bg = theme.ui.bg_m1 },
          PmenuThumb = { bg = theme.ui.bg_p2 },

          -- LSP hover and floating windows (match Pmenu style)
          NormalFloat = { fg = theme.ui.shade0, bg = theme.ui.bg_p1 },
          FloatBorder = { fg = palette.fujiWhite, bg = theme.ui.bg_p1 },
          FloatTitle = { fg = theme.ui.fg, bg = theme.ui.bg_p1, bold = true },

          -- nvim-cmp highlights
          CmpItemAbbr = { fg = theme.ui.fg },
          CmpItemAbbrDeprecated = { fg = theme.syn.comment, strikethrough = true },
          CmpItemAbbrMatch = { fg = palette.dragonBlue, bold = true },
          CmpItemAbbrMatchFuzzy = { fg = palette.dragonBlue, bold = true },
          CmpItemMenu = { fg = theme.syn.comment, italic = true },

          -- Completion item kinds
          CmpItemKindDefault = { fg = theme.ui.fg_dim },
          CmpItemKindText = { fg = theme.ui.fg },
          CmpItemKindMethod = { fg = palette.dragonBlue },
          CmpItemKindFunction = { fg = palette.dragonBlue },
          CmpItemKindConstructor = { fg = palette.dragonYellow },
          CmpItemKindField = { fg = palette.dragonGreen2 },
          CmpItemKindVariable = { fg = palette.dragonWhite },
          CmpItemKindClass = { fg = palette.dragonYellow },
          CmpItemKindInterface = { fg = palette.dragonYellow },
          CmpItemKindModule = { fg = palette.dragonBlue },
          CmpItemKindProperty = { fg = palette.dragonGreen2 },
          CmpItemKindUnit = { fg = palette.dragonOrange },
          CmpItemKindValue = { fg = palette.dragonOrange },
          CmpItemKindEnum = { fg = palette.dragonYellow },
          CmpItemKindKeyword = { fg = palette.dragonPink },
          CmpItemKindSnippet = { fg = palette.dragonTeal },
          CmpItemKindColor = { fg = palette.dragonRed },
          CmpItemKindFile = { fg = theme.ui.fg },
          CmpItemKindReference = { fg = palette.dragonRed },
          CmpItemKindFolder = { fg = palette.dragonBlue },
          CmpItemKindEnumMember = { fg = palette.dragonGreen2 },
          CmpItemKindConstant = { fg = palette.dragonOrange },
          CmpItemKindStruct = { fg = palette.dragonYellow },
          CmpItemKindEvent = { fg = palette.dragonYellow },
          CmpItemKindOperator = { fg = palette.dragonRed },
          CmpItemKindTypeParameter = { fg = palette.dragonGreen2 },
        }
      end,
      theme = 'dragon', -- Load "wave" theme
      background = { -- map the value of 'background' option to a theme
        dark = 'dragon',
        light = 'lotus',
      },
    }

    -- Apply the colorscheme
    vim.cmd.colorscheme 'kanagawa'
  end,
}
