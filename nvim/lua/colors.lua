function LineNumberColors()
	vim.api.nvim_set_hl(0, 'LineNrAbove', { fg = 'white', bold = true })
	vim.api.nvim_set_hl(0, 'LineNr', { fg = 'white', bold = true })
	vim.api.nvim_set_hl(0, 'LineNrBelow', { fg = 'white', bold = true })
end

LineNumberColors()
