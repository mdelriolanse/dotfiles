return {
	{
		'nvim-neo-tree/neo-tree.nvim',
		branch = 'v3.x',
		dependencies = {
			'nvim-lua/plenary.nvim',
			'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
			'MunifTanjim/nui.nvim',
			-- Optional image support for file preview: See `# Preview Mode` for more information.
			-- {"3rd/image.nvim", opts = {}},
			-- OR use snacks.nvim's image module:
			-- "folke/snacks.nvim",
		},
		lazy = false, -- neo-tree will lazily load itself
		---@module "neo-tree"
		---@type neotree.Config?
		opts = function()
			local nf = vim.g.have_nerd_font
			return {
				filesystem = {
					filtered_items = {
						visible = true,
						hide_dotfiles = false,
					},
				},
				default_component_configs = {
					indent = nf and {} or {
						indent_marker = '  ',
						last_indent_marker = '  ',
						expander_collapsed = '+',
						expander_expanded = '-',
					},
					icon = nf and {} or {
						folder_closed = '[D]',
						folder_open = '[D]',
						folder_empty = '[D]',
						folder_empty_open = '[D]',
					},
					git_status = nf and {} or {
						symbols = {
							added     = 'A',
							deleted   = 'D',
							modified  = 'M',
							renamed   = 'R',
							untracked = '?',
							ignored   = '!',
							unstaged  = 'U',
							staged    = 'S',
							conflict  = 'C',
						},
					},
				},
			}
		end,
	},
}
