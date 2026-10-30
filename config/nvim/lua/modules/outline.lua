-- Symbol outline from LSP or tree-sitter; takes over from tagbar, which
-- needed ctags.
return {
    desc = 'Symbol outline (aerial)',
    plugins = {
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
    },
}
