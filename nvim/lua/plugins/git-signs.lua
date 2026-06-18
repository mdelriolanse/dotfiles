return {
	{ -- Adds git related
		'lewis6991/gitsigns.nvim',
		opts = {
			signs = {
				add = { text = '+' },
				change = { text = '~' },
				delete = { text = '_' },
				topdelete = { text = '‾' },
				changedelete = { text = '~' },
			},
			numhl = true,  -- highlight line numbers with diff color
			linehl = true, -- highlight changed lines themselves
		},
	},
}
