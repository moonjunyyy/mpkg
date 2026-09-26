return {
    {
        'saghen/blink.cmp',
        version = '1.*', -- release tags ship a prebuilt fuzzy matcher
        event = { 'InsertEnter', 'CmdlineEnter' },
        dependencies = { 'rafamadriz/friendly-snippets' },
        opts = {
            keymap = { preset = 'default' }, -- <C-y> accept, <C-space> open, <C-n>/<C-p> move
            appearance = { nerd_font_variant = 'mono' },
            completion = {
                documentation = { auto_show = true, auto_show_delay_ms = 300 },
                ghost_text = { enabled = false }, -- copilot draws its own
            },
            signature = { enabled = true },
            sources = {
                default = { 'lazydev', 'lsp', 'path', 'snippets', 'buffer' },
                providers = {
                    lazydev = { name = 'LazyDev', module = 'lazydev.integrations.blink', score_offset = 100 },
                },
            },
            fuzzy = { implementation = 'prefer_rust_with_warning' },
        },
        opts_extend = { 'sources.default' },
    },

    {
        'github/copilot.vim',
        event = 'InsertEnter',
        cmd = 'Copilot',
    },
}
