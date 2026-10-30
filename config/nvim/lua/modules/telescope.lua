return {
    desc = 'Fuzzy finder (telescope)',
    plugins = {
        {
            'nvim-telescope/telescope.nvim',
            cmd = 'Telescope',
            dependencies = {
                'nvim-lua/plenary.nvim',
                {
                    'nvim-telescope/telescope-fzf-native.nvim',
                    build = 'make',
                    cond = function() return vim.fn.executable('make') == 1 end,
                },
            },
            keys = {
                { '<leader>ff', '<cmd>Telescope find_files<CR>', desc = 'Files' },
                { '<leader>fg', '<cmd>Telescope live_grep<CR>', desc = 'Grep' },
                { '<leader>fb', '<cmd>Telescope buffers<CR>', desc = 'Buffers' },
                { '<leader>fh', '<cmd>Telescope help_tags<CR>', desc = 'Help' },
                { '<leader>fr', '<cmd>Telescope oldfiles<CR>', desc = 'Recent files' },
                { '<leader>fw', '<cmd>Telescope grep_string<CR>', desc = 'Word under cursor' },
                { '<leader>fd', '<cmd>Telescope diagnostics<CR>', desc = 'Diagnostics' },
                { '<leader>fk', '<cmd>Telescope keymaps<CR>', desc = 'Keymaps' },
                { '<leader>f.', '<cmd>Telescope resume<CR>', desc = 'Resume last picker' },
            },
            config = function()
                local telescope = require('telescope')
                telescope.setup({
                    defaults = {
                        sorting_strategy = 'ascending',
                        layout_config = { prompt_position = 'top' },
                    },
                })
                pcall(telescope.load_extension, 'fzf')
            end,
        },
    },
}
