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
			numhl = false, -- disabled diff color on line numbers
			linehl = false, -- disabled full-line diff highlighting
			on_attach = function(bufnr)
				local gitsigns = require('gitsigns')

				local function map(mode, l, r, opts)
					opts = opts or {}
					opts.buffer = bufnr
					vim.keymap.set(mode, l, r, opts)
				end

				-- Navigation
				map('n', ']c', function()
					if vim.wo.diff then
						vim.cmd.normal({ ']c', bang = true })
					else
						gitsigns.nav_hunk('next')
					end
				end, { desc = 'Next git change' })

				map('n', '[c', function()
					if vim.wo.diff then
						vim.cmd.normal({ '[c', bang = true })
					else
						gitsigns.nav_hunk('prev')
					end
				end, { desc = 'Previous git change' })

				-- Actions
				map('v', '<leader>hs', function()
					gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
				end, { desc = 'Stage git hunk' })
				map('v', '<leader>hr', function()
					gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
				end, { desc = 'Reset git hunk' })
				map('n', '<leader>hs', gitsigns.stage_hunk, { desc = 'Git: stage hunk' })
				map('n', '<leader>hr', gitsigns.reset_hunk, { desc = 'Git: reset hunk' })
				map('n', '<leader>hS', gitsigns.stage_buffer, { desc = 'Git: stage buffer' })
				map('n', '<leader>hu', gitsigns.undo_stage_hunk, { desc = 'Git: undo stage hunk' })
				map('n', '<leader>hR', gitsigns.reset_buffer, { desc = 'Git: reset buffer' })
				map('n', '<leader>hp', gitsigns.preview_hunk, { desc = 'Git: preview hunk' })
				map('n', '<leader>hb', function()
					gitsigns.blame_line({ full = true })
				end, { desc = 'Git: blame line' })
				map('n', '<leader>hd', gitsigns.diffthis, { desc = 'Git: diff against index' })
				map('n', '<leader>hD', function()
					gitsigns.diffthis('~')
				end, { desc = 'Git: diff against last commit' })

				-- Toggles
				map('n', '<leader>ts', gitsigns.toggle_signs, { desc = '[T]oggle git [S]igns' })
				map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git [B]lame' })
				map('n', '<leader>tl', gitsigns.toggle_linehl, { desc = '[T]oggle git [L]ine highlight' })
				map('n', '<leader>tn', gitsigns.toggle_numhl, { desc = '[T]oggle git [N]umber highlight' })
				map('n', '<leader>tD', gitsigns.toggle_deleted, { desc = '[T]oggle git show [D]eleted' })
			end,
		},
	},
}
