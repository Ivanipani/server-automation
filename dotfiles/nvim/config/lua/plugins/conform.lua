local function format_diffs()
	local ignore_filetypes = { "lua" }
	if vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
		vim.notify("range formatting for " .. vim.bo.filetype .. " not working properly.")
		return
	end

	local hunks = require("gitsigns").get_hunks()
	if hunks == nil then
		return
	end

	local format = require("conform").format

	local function format_range()
		if next(hunks) == nil then
			vim.notify("done formatting git hunks", "info", { title = "formatting" })
			return
		end
		local hunk = nil
		while next(hunks) ~= nil and (hunk == nil or hunk.type == "delete") do
			hunk = table.remove(hunks)
		end

		if hunk ~= nil and hunk.type ~= "delete" then
			local start = hunk.added.start
			local last = start + hunk.added.count
			-- nvim_buf_get_lines uses zero-based indexing -> subtract from last
			local last_hunk_line = vim.api.nvim_buf_get_lines(0, last - 2, last - 1, true)[1]
			local range = {
				start = { start, 0 },
				["end"] = { last - 1, last_hunk_line:len() },
			}
			format({ range = range, async = true, lsp_fallback = true }, function()
				vim.defer_fn(function()
					format_range()
				end, 1)
			end)
		end
	end

	format_range()
end
return { -- Autoformat
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>fm",
			function()
				format_diffs()
			end,
			mode = "",
			desc = "Modifications Only",
		},
		{
			"<leader>ff",
			function()
				require("conform").format({
					async = true,
					lsp_format = "fallback",
				})
			end,
			mode = "",
			desc = "Entire File",
		},
		{
			"<leader>fx",
			function()
				require("conform").format({
					async = true,
					lsp_format = "fallback",
					formatters = { "ruff_fix", "ruff_format" },
				})
			end,
			mode = "",
			desc = "Fix & Format (includes import cleanup)",
		},
	},
	opts = {
		notify_on_error = false,
		format_on_save = function(bufnr)
			-- Disable "format_on_save lsp_fallback" for languages that don't
			-- have a well standardized coding style. You can add additional
			-- languages here or re-enable it for the disabled ones.
			local disable_filetypes = { c = true, cpp = true }
			if disable_filetypes[vim.bo[bufnr].filetype] then
				return nil
			else
				-- Use format_diffs as the default format on save method
				vim.defer_fn(function()
					format_diffs()
				end, 10)
				return false -- Disable the default format_on_save behavior
			end
		end,
		formatters = {
			ruff_fix = {
				cwd = function(self, ctx)
					return require("conform.util").root_file({
						"ruff.toml",
						"pyproject.toml",
					})(self, ctx)
				end,
			},
			ruff_format = {
				cwd = function(self, ctx)
					return require("conform.util").root_file({
						"ruff.toml",
						"pyproject.toml",
					})(self, ctx)
				end,
			},
		},
		formatters_by_ft = {
			lua = { "stylua" },
			python = { "ruff_format" },
			rust = { "rustfmt" },
			javascript = { "prettier" },
			typescript = { "prettier" },
			javascriptreact = { "prettier" },
			typescriptreact = { "prettier" },
			jsx = { "prettier" },
			tsx = { "prettier" },
			["_"] = { "trim_whitespace" },
			-- sql = { 'sqruff' }
		},
	},
}
