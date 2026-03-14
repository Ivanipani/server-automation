return {
    'nvimdev/dashboard-nvim',
    event = 'VimEnter',
    config = function()
        require('dashboard').setup {
            -- config
        }
    end,
    dependencies = { { 'nvim-tree/nvim-web-devicons' } },
    keys = {
        {
            '<leader>d',
            '<cmd>Dashboard<cr>',
            desc = '[D]ashboard'
        }
    }
}
