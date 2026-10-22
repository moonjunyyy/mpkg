return {
    { 'nvim-tree/nvim-web-devicons', lazy = true },

    {
        'nvim-lualine/lualine.nvim',
        event = 'VeryLazy',
        opts = {
            options = { theme = 'auto', globalstatus = true },
            sections = {
                lualine_c = { { 'filename', path = 1 } },
                lualine_x = { 'lsp_status', 'encoding', 'fileformat', 'filetype' },
            },
        },
    },

    {
        'folke/which-key.nvim',
        event = 'VeryLazy',
        opts = {
            preset = 'modern',
            spec = {
                { '<leader>e', group = 'diagnostics' },
                { '<leader>f', group = 'find' },
                { '<leader>g', group = 'goto (LSP)' },
                { '<leader>h', group = 'help / actions' },
                { '<leader>t', group = 'types / outline' },
                { '<leader>u', group = 'toggle' },
                { '<leader>G', group = 'git / workspace' },
            },
        },
        keys = {
            { '<leader>?', function() require('which-key').show({ global = false }) end, desc = 'Buffer keymaps' },
        },
    },

    {
        'OXY2DEV/markview.nvim',
        -- Not lazy-loaded: markview defers its own work, and loading it on
        -- FileType sometimes missed the first markdown buffer (upstream advice).
        lazy = false,
        config = function()
            local presets = require('markview.presets')
            require('markview').setup({
                markdown = { headings = presets.headings.slanted },
                preview = { icon_provider = 'devicons' },
            })
        end,
    },
}
