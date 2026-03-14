return {
    'github/copilot.vim',
    event = 'InsertEnter',
    cmd = 'Copilot',
    config = function()
        -- Disable default tab mapping to avoid conflicts
        vim.g.copilot_no_tab_map = true

        -- Configure copilot filetypes (enable for most, disable for specific ones if needed)
        vim.g.copilot_enterprise_uri = "https://bbgithub.dev.bloomberg.com"
        vim.g.copilot_filetypes = {
            ['*'] = true,
            gitcommit = false,
            gitrebase = false,
            help = false,
            markdown = true,
        }

        -- vim.g.copilot_proxy = 'http://proxy.bloomberg.com:80'
        vim.g.copilot_proxy = 'http://proxy.bloomberg.com:81'
        -- Set up keymaps for Copilot
        local opts = { silent = true, expr = true, replace_keycodes = false }
        local normal_opts = { silent = true }

        -- Insert mode mappings
        vim.keymap.set('i', '<C-j>', 'copilot#Accept("\\<CR>")', opts)
        vim.keymap.set('i', '<M-]>', '<Plug>(copilot-next)', { silent = true })
        vim.keymap.set('i', '<M-[>', '<Plug>(copilot-previous)', { silent = true })
        vim.keymap.set('i', '<C-]>', '<Plug>(copilot-dismiss)', { silent = true })
        vim.keymap.set('i', '<M-\\>', '<Plug>(copilot-suggest)', { silent = true })
        vim.keymap.set('i', '<M-Right>', '<Plug>(copilot-accept-word)', { silent = true })
        vim.keymap.set('i', '<M-C-Right>', '<Plug>(copilot-accept-line)', { silent = true })

        -- Leader-based mappings for normal mode
        vim.keymap.set('n', '<leader>ca', function()
            vim.cmd('Copilot enable')
            vim.notify('Copilot enabled', vim.log.levels.INFO)
        end, { desc = '[A]ctivate Copilot' })

        vim.keymap.set('n', '<leader>cd', function()
            vim.cmd('Copilot disable')
            vim.notify('Copilot disabled', vim.log.levels.WARN)
        end, { desc = '[D]isable Copilot' })

        vim.keymap.set('n', '<leader>cs', '<cmd>Copilot status<CR>', { desc = '[S]tatus' })
        vim.keymap.set('n', '<leader>cp', '<cmd>Copilot panel<CR>', { desc = '[P]anel' })
        vim.keymap.set('n', '<leader>cv', '<cmd>Copilot version<CR>', { desc = '[V]ersion' })
        vim.keymap.set('n', '<leader>cf', '<cmd>Copilot feedback<CR>', { desc = '[F]eedback' })

        vim.keymap.set('n', '<leader>cS', function()
            vim.cmd('Copilot setup')
        end, { desc = '[S]etup/Authenticate' })

        vim.keymap.set('n', '<leader>co', function()
            vim.cmd('Copilot signout')
        end, { desc = '[S]ign [O]ut' })

        -- Toggle buffer-specific copilot
        vim.keymap.set('n', '<leader>ct', function()
            local current_state = vim.b.copilot_enabled
            if current_state == false then
                vim.b.copilot_enabled = true
                vim.notify('Copilot enabled for current buffer', vim.log.levels.INFO)
            else
                vim.b.copilot_enabled = false
                vim.notify('Copilot disabled for current buffer', vim.log.levels.WARN)
            end
        end, { desc = '[T]oggle Buffer' })

        -- Telescope integration for Copilot commands
        vim.keymap.set('n', '<leader>cc', function()
            local telescope_ok, telescope = pcall(require, 'telescope.builtin')
            if not telescope_ok then
                vim.notify('Telescope not available', vim.log.levels.ERROR)
                return
            end

            local copilot_commands = {
                { name = 'Copilot Setup',    cmd = 'Copilot setup' },
                { name = 'Copilot Status',   cmd = 'Copilot status' },
                { name = 'Copilot Enable',   cmd = 'Copilot enable' },
                { name = 'Copilot Disable',  cmd = 'Copilot disable' },
                { name = 'Copilot Panel',    cmd = 'Copilot panel' },
                { name = 'Copilot Version',  cmd = 'Copilot version' },
                { name = 'Copilot Feedback', cmd = 'Copilot feedback' },
                { name = 'Copilot Signout',  cmd = 'Copilot signout' },
            }

            local pickers = require('telescope.pickers')
            local finders = require('telescope.finders')
            local conf = require('telescope.config').values
            local actions = require('telescope.actions')
            local action_state = require('telescope.actions.state')

            pickers.new({}, {
                prompt_title = 'Copilot Commands',
                finder = finders.new_table({
                    results = copilot_commands,
                    entry_maker = function(entry)
                        return {
                            value = entry,
                            display = entry.name,
                            ordinal = entry.name,
                        }
                    end,
                }),
                sorter = conf.generic_sorter({}),
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)
                        local selection = action_state.get_selected_entry()
                        if selection then
                            vim.cmd(selection.value.cmd)
                        end
                    end)
                    return true
                end,
            }):find()
        end, { desc = '[C]ommands (Telescope)' })

        -- Set up highlighting for Copilot suggestions
        vim.api.nvim_create_autocmd('ColorScheme', {
            pattern = '*',
            callback = function()
                vim.api.nvim_set_hl(0, 'CopilotSuggestion', {
                    fg = '#555555',
                    ctermfg = 8,
                    italic = true,
                })
            end,
            desc = 'Set Copilot suggestion highlighting',
        })
    end,
}
