return {
	{
		'NeogitOrg/neogit',
		dependencies = {
			'nvim-lua/plenary.nvim',
			'sindrets/diffview.nvim',
		},
		cmd = 'Neogit',
		keys = {
			{ '<leader>gg', '<cmd>Neogit<CR>',                            desc = '[G]it status (Neogit)' },
			{ '<leader>gc', '<cmd>Neogit commit<CR>',                     desc = '[G]it [C]ommit' },
			{ '<leader>gp', '<cmd>Neogit push<CR>',                       desc = '[G]it [P]ush' },
			{ '<leader>gP', '<cmd>Neogit pull<CR>',                       desc = '[G]it [P]ull' },
			{ '<leader>gb', '<cmd>Neogit branch<CR>',                     desc = '[G]it [B]ranch' },
			{ '<leader>gl', '<cmd>Neogit log<CR>',                        desc = '[G]it [L]og' },
			{ '<leader>gd', '<cmd>DiffviewOpen<CR>',                      desc = '[G]it [D]iff (diffview)' },
			{ '<leader>gD', '<cmd>DiffviewOpen HEAD<CR>',                 desc = '[G]it [D]iff HEAD' },
			{ '<leader>gf', '<cmd>DiffviewFileHistory %<CR>',             desc = '[G]it [F]ile history' },
			{ '<leader>gx', '<cmd>DiffviewClose<CR>',                     desc = '[G]it close diffview' },
		},
		opts = {
			integrations = {
				diffview = true,
			},
			-- Disable mappings that collide with our window navigation (<C-h/j/k/l>)
			mappings = {
				popup = {
					['<C-h>'] = false,
					['<C-j>'] = false,
					['<C-k>'] = false,
					['<C-l>'] = false,
				},
			},
		},
	},
}
