return {
    "AckslD/nvim-neoclip.lua",
    dependencies = {
        { 'nvim-telescope/telescope.nvim' },
    },

    keys = {
        {
            '<leader>p',
            '<cmd>Telescope neoclip<cr>',
            desc = 'Neoclip',
        },
    },
    config = function()
        require('neoclip').setup()
    end,
}
