return {
	'stevearc/oil.nvim',
	dependencies = { 'nvim-tree/nvim-web-devicons' },
	lazy = true,
	cmd = 'Oil',
	keys = {
		{
			'<leader>ro',
			function()
				-- Toggle oil in a left split, matching neo-tree's position
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					local buf = vim.api.nvim_win_get_buf(win)
					if vim.bo[buf].filetype == 'oil' then
						vim.api.nvim_win_close(win, true)
						return
					end
				end
				vim.cmd 'topleft vsplit | vertical resize 40 | Oil'
			end,
			desc = 'Toggle Oil sidebar',
		},
		{
			'<leader>rt',
			function()
				-- Open a terminal in the pwd (works on SSH remote too)
				local cwd = vim.fn.getcwd()
				vim.cmd('botright split | resize 15 | terminal')
				vim.api.nvim_chan_send(vim.b.terminal_job_id, 'cd ' .. vim.fn.shellescape(cwd) .. '\n')
			end,
			desc = 'Open terminal in pwd',
		},
	},
	config = function(_, opts)
		require('oil').setup(opts)

		-- Make oil buffers non-insertable (disable insert mode)
		vim.api.nvim_create_autocmd('FileType', {
			pattern = 'oil',
			callback = function(args)
				local buf = args.buf
				-- Block insert mode in oil buffers
				local block_insert = function()
					vim.cmd 'stopinsert'
				end
				vim.keymap.set('n', 'i', '<Nop>', { buffer = buf, nowait = true })
				vim.keymap.set('n', 'I', '<Nop>', { buffer = buf, nowait = true })
				vim.keymap.set('n', 'a', function()
					-- Add file: prompt for name, then create it
					local oil = require 'oil'
					local dir = oil.get_current_dir()
					if not dir then return end
					vim.ui.input({ prompt = 'New file name: ' }, function(name)
						if not name or name == '' then return end
						local path = dir .. name
						-- If name ends with / create a directory, otherwise a file
						if name:sub(-1) == '/' then
							vim.fn.mkdir(path, 'p')
						else
							-- Create parent dirs if needed then touch the file
							local parent = vim.fn.fnamemodify(path, ':h')
							vim.fn.mkdir(parent, 'p')
							vim.fn.writefile({}, path)
						end
						-- Refresh oil to show the new entry
						vim.cmd('edit ' .. vim.fn.fnameescape(dir))
					end)
				end, { buffer = buf, nowait = true, desc = 'Add file/directory' })
				vim.keymap.set('n', 'A', '<Nop>', { buffer = buf, nowait = true })
				vim.keymap.set('n', 'o', '<Nop>', { buffer = buf, nowait = true })
				vim.keymap.set('n', 'O', '<Nop>', { buffer = buf, nowait = true })
				vim.api.nvim_create_autocmd('InsertEnter', {
					buffer = buf,
					callback = block_insert,
				})
			end,
		})

		vim.api.nvim_create_autocmd('VimLeavePre', {
			desc = 'Kill oil.nvim SSH connections on exit',
			callback = function()
				for _, buf in ipairs(vim.api.nvim_list_bufs()) do
					local name = vim.api.nvim_buf_get_name(buf)
					if name:match '^oil%-ssh://' then
						vim.api.nvim_buf_delete(buf, { force = true })
					end
				end
			end,
		})
	end,
	opts = {
		default_file_explorer = false,
		columns = {
			'icon',
			'size',
		},
		keymaps = {
			['g?'] = 'actions.show_help',
			['<CR>'] = {
				callback = function()
					local oil = require 'oil'
					local entry = oil.get_cursor_entry()
					if not entry then return end

					if entry.type == 'directory' then
						oil.select()
						return
					end

					-- Build the file path/URL from the buffer name (works for local + SSH)
					local bufname = vim.api.nvim_buf_get_name(0)
					if not bufname:match('/$') then bufname = bufname .. '/' end
					local file_url = bufname .. entry.name

					-- For local paths, use the filesystem path instead of oil:// URL
					local dir = oil.get_current_dir()
					if dir then
						file_url = dir .. entry.name
					end

					-- Find a normal (non-floating, non-oil) window to open in
					local oil_win = vim.api.nvim_get_current_win()
					local target_win = nil
					for _, win in ipairs(vim.api.nvim_list_wins()) do
						if win ~= oil_win then
							local win_config = vim.api.nvim_win_get_config(win)
							if win_config.relative == '' then
								local buf = vim.api.nvim_win_get_buf(win)
								if vim.bo[buf].filetype ~= 'oil' then
									target_win = win
									break
								end
							end
						end
					end

					if target_win then
						vim.api.nvim_set_current_win(target_win)
						vim.cmd('edit ' .. vim.fn.fnameescape(file_url))
					else
						vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(file_url))
					end
				end,
				desc = 'Open file in right split',
				mode = 'n',
			},
			['-'] = 'actions.parent',
			['_'] = 'actions.open_cwd',
			['g.'] = 'actions.toggle_hidden',
			['q'] = 'actions.close',
			['r'] = {
				callback = function()
					local oil = require 'oil'
					local entry = oil.get_cursor_entry()
					if not entry then return end
					local dir = oil.get_current_dir()
					if not dir then return end
					local old_path = dir .. entry.name
					vim.ui.input({ prompt = 'Rename: ', default = entry.name }, function(new_name)
						if not new_name or new_name == '' or new_name == entry.name then return end
						local new_path = dir .. new_name
						vim.fn.rename(old_path, new_path)
						-- Refresh
						vim.cmd('edit ' .. vim.fn.fnameescape(dir))
					end)
				end,
				desc = 'Rename file/directory',
			},
			['d'] = {
				callback = function()
					local oil = require 'oil'
					local entry = oil.get_cursor_entry()
					if not entry then return end
					local dir = oil.get_current_dir()
					if not dir then return end
					local path = dir .. entry.name
					vim.ui.select({ 'Yes', 'No' }, {
						prompt = 'Delete "' .. entry.name .. '"?',
					}, function(choice)
						if choice ~= 'Yes' then return end
						if entry.type == 'directory' then
							vim.fn.delete(path, 'rf')
						else
							vim.fn.delete(path)
						end
						-- Refresh
						vim.cmd('edit ' .. vim.fn.fnameescape(dir))
					end)
				end,
				desc = 'Delete file/directory',
			},
		},
		use_default_keymaps = false,
	},
}
