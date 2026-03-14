local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim"
	local out = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"--branch=stable",
		lazyrepo,
		lazypath,
	})
	if vim.v.shell_error ~= 0 then
		error("Error cloning lazy.nvim:\n" .. out)
	end
end
vim.opt.rtp:prepend(lazypath)

if vim.g.vscode then 
    require("lazy").setup({
        require("plugins.gitsigns"),
        require("plugins.local-highlight"),
        require("plugins.todo"),
        require("plugins.flash"),
        require("plugins.indent"),
    })
else
    require("lazy").setup({
        require("plugins.blink"),
        require("plugins.colorscheme"),
        require("plugins.conform"),
        require("plugins.gitsigns"),
        require("plugins.hunk"),
        require("plugins.lazy-dev"),
        require("plugins.lsp"),
        require("plugins.lualine"),
        require("plugins.go"),
        require("plugins.local-highlight"),
        require("plugins.dashboard"),
        require("plugins.neo-tree"),
        require("plugins.neoclip"),
        require("plugins.telescope"),
        require("plugins.todo"),
        require("plugins.treesitter"),
        require("plugins.snacks"),
        require("plugins.which-key"),
        require("plugins.venv"),
        require("plugins.flash"),
        require("plugins.indent"),
        require("plugins.zellij-nav"),
    })
end
