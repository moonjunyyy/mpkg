return {
    {
        'catppuccin/nvim',
        name = 'catppuccin',
        lazy = false,
        priority = 1000,
        opts = {
            flavour = 'mocha',
            integrations = {
                aerial = true,
                blink_cmp = true,
                gitsigns = true,
                mason = true,
                native_lsp = { enabled = true },
                nvimtree = true,
                telescope = { enabled = true },
                treesitter = true,
                which_key = true,
            },
        },
        config = function(_, opts)
            require('catppuccin').setup(opts)
            vim.cmd.colorscheme('catppuccin-mocha')
        end,
    },
}
