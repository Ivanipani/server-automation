return {
    "linux-cultist/venv-selector.nvim",
    dependencies = {
        "neovim/nvim-lspconfig", "mfussenegger/nvim-dap",
        "mfussenegger/nvim-dap-python", -- optional
        {
            "nvim-telescope/telescope.nvim",
            branch = "0.1.x",
            dependencies = {"nvim-lua/plenary.nvim"}
        }
    },
    lazy = false,
    keys = {
        {
            "<leader>v",
            "<cmd>VenvSelect<cr>",
            desc = "Select virtual environment"
        }
    },
    opts = {
        -- Your settings go here
    }
}

