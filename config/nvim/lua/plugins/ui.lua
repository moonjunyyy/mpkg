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
        opts_extend = { 'spec' }, -- modules add entries (extend.groups)
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
}
