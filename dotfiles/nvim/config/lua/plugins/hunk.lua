return {
    "julienvincent/hunk.nvim",
    cmd = { "DiffEditor" },
    config = function()
        require("hunk").setup({

        })
        -- vim.keymap.set('n', '<leader>jp', function() require('hunk').prev_hunk() end, { desc = 'Hunk: Previous hunk' })
        -- vim.keymap.set('n', '<leader>js', function() require('hunk').stage_hunk() end, { desc = 'Hunk: Stage hunk' })
        -- vim.keymap.set('n', '<leader>jr', function() require('hunk').reset_hunk() end, { desc = 'Hunk: Reset hunk' })
        -- vim.keymap.set('n', '<leader>ju', function() require('hunk').undo_stage_hunk() end, { desc = 'Hunk: Undo stage hunk' })
        -- vim.keymap.set('n', '<leader>jP', function() require('hunk').preview_hunk() end, { desc = 'Hunk: Preview hunk' })
        -- vim.keymap.set('n', '<leader>jb', function() require('hunk').blame_line() end, { desc = 'Hunk: Blame line' })
        -- vim.keymap.set('n', '<leader>jd', function() require('hunk').diff() end, { desc = 'Hunk: Diff' })
    end
}

--     tree = {
--       expand_node = { "l", "<Right>" },
--       collapse_node = { "h", "<Left>" },

--       open_file = { "<Cr>" },

--       toggle_file = { "a" },
--     },

--     diff = {
--       toggle_hunk = { "A" },
--       toggle_line = { "a" },
--       -- This is like toggle_line but it will also toggle the line on the other
--       -- 'side' of the diff.
--       toggle_line_pair = { "s" },

--       prev_hunk = { "[h" },
--       next_hunk = { "]h" },

--       -- Jump between the left and right diff view
--       toggle_focus = { "<Tab>" },
--     },
--   },

--   ui = {
--     tree = {
--       -- Mode can either be `nested` or `flat`
--       mode = "nested",
--       width = 35,
--     },
--     --- Can be either `vertical` or `horizontal`
--     layout = "vertical",
--   },

--   icons = {
--     selected = "󰡖",
--     deselected = "",
--     partially_selected = "󰛲",

--     folder_open = "",
--     folder_closed = "",
--   },

--   -- Called right after each window and buffer are created.
--   hooks = {
--     ---@param _context { buf: number, tree: NuiTree, opts: table }
--     on_tree_mount = function(_context) end,
--     ---@param _context { buf: number, win: number }
--     on_diff_mount = function(_context) end,
--   },
-- })
