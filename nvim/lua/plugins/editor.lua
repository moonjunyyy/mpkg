return {
    {
        'nvim-tree/nvim-tree.lua',
        cmd = { 'NvimTreeToggle', 'NvimTreeFindFile' },
        keys = {
            { '<C-n>', '<cmd>NvimTreeToggle<CR>', desc = 'File tree' },
            { '<leader>fe', '<cmd>NvimTreeFindFile<CR>', desc = 'Reveal file in tree' },
        },
        opts = {
            view = { width = 35, side = 'left', signcolumn = 'yes' },
            renderer = { highlight_git = true, indent_markers = { enable = true } },
            filters = { dotfiles = false },
            actions = { open_file = { quit_on_open = false } },
        },
    },

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

    -- Symbol outline from LSP or tree-sitter; takes over from tagbar, which
    -- needed ctags.
    {
        'stevearc/aerial.nvim',
        cmd = { 'AerialToggle', 'AerialNavToggle' },
        keys = {
            { '<leader>tb', '<cmd>AerialToggle!<CR>', desc = 'Symbol outline' },
        },
        opts = {
            backends = { 'lsp', 'treesitter', 'markdown', 'man' },
            layout = { default_direction = 'prefer_right', min_width = 30 },
        },
    },

    {
        'nvim-mini/mini.pairs',
        event = 'InsertEnter',
        opts = {},
    },
}
