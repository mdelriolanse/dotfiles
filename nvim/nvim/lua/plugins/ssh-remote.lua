return {
	'jsongerber/telescope-ssh-config',
	dependencies = {
		'nvim-telescope/telescope.nvim',
		'stevearc/oil.nvim',
	},
	keys = {
		{
			'<leader>rs',
			function()
				require('telescope').load_extension 'ssh-config'
				require('telescope').extensions['ssh-config']['ssh-config'] {
					client = 'oil',
				}
			end,
			desc = '[R]emote [S]SH',
		},
	},
}
