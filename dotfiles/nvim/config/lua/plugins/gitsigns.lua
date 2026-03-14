return { -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    keys = {},
    opts = {
        signs = {
            add = { text = '+' },
            change = { text = '~' },
            delete = { text = '_' },
            topdelete = { text = '‾' },
            changedelete = { text = '~' },
        },
        on_attach = function(bufnr)
            local gitsigns = require 'gitsigns'

            local function map(mode, l, r, opts)
                opts = opts or {}
                opts.buffer = bufnr
                vim.keymap.set(mode, l, r, opts)
            end

            -- Navigation
            map('n', '<leader>go', function()
                gitsigns.nav_hunk 'next'
            end, { desc = 'Jump to next git [c]hange' })

            map('n', '<leader>gi', function()
                gitsigns.nav_hunk 'prev'
            end, { desc = 'Jump to previous git [c]hange' })

            -- normal mode
            map('n', '<leader>gp', gitsigns.preview_hunk, { desc = 'git [p]review hunk' })
            map('n', '<leader>gb', gitsigns.blame_line, { desc = 'git [b]lame line' })
            -- Toggles
            map('n', '<leader>gb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
        end
    },
}
