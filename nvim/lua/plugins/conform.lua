return {
	{ -- Autoformat
		'stevearc/conform.nvim',
		event = { 'BufWritePre' },
		cmd = { 'ConformInfo' },
		keys = {
			{
				'<leader>f',
				function()
					require('conform').format { async = true, lsp_format = 'fallback' }
				end,
				mode = '',
				desc = '[F]ormat buffer',
			},
		},
		opts = {
			notify_on_error = false,
			format_on_save = function(bufnr)
				-- Don't format on save for c/cpp by default (it can fight with WIP code).
				-- Use <leader>f for explicit format, or set vim.b.format_on_save=true per buffer.
				local disable_filetypes = { c = true, cpp = true }
				if disable_filetypes[vim.bo[bufnr].filetype] and not vim.b[bufnr].format_on_save then
					return nil
				end
				return {
					timeout_ms = 500,
					lsp_format = 'fallback',
				}
			end,
			formatters_by_ft = {
				lua = { 'stylua' },
				c = { 'clang-format' },
				cpp = { 'clang-format' },
				rust = { 'rustfmt' },
				-- Hardware development formatters
				verilog = { 'vsg' },
				systemverilog = { 'vsg' },
				vhdl = { 'vsg' },
				-- Conform can also run multiple formatters sequentially
				-- python = { "isort", "black" },
				--
				-- You can use 'stop_after_first' to run the first available formatter from the list
				-- javascript = { "prettierd", "prettier", stop_after_first = true },
			},
		},
	},
}
