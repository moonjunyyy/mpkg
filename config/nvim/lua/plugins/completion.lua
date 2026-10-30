-- Completion: blink.cmp. Modules add sources through extend.sources
-- (config/loader.lua), e.g. Copilot.
--
-- Insert mode: Tab / S-Tab and the arrows move through the menu, Enter takes
-- the selected item; with nothing selected Enter is a plain Enter, and with no
-- menu Tab jumps through a snippet or inserts a tab. C-e puts back what was
-- typed. (A literal tab while the menu is open: C-e, then Tab.)
-- Command line: Tab opens the menu and moves on, Up / Down move through it
-- while it is open and through history otherwise, Left / Right always move the
-- cursor, Enter takes the selected item and runs the command.
return {
    {
        'saghen/blink.cmp',
        version = '1.*', -- release tags ship a prebuilt fuzzy matcher
        event = { 'InsertEnter', 'CmdlineEnter' },
        dependencies = { 'rafamadriz/friendly-snippets' },
        opts = {
            keymap = {
                preset = 'none',
                ['<Tab>'] = { 'select_next', 'snippet_forward', 'fallback' },
                ['<S-Tab>'] = { 'select_prev', 'snippet_backward', 'fallback' },
                ['<Down>'] = { 'select_next', 'fallback' },
                ['<Up>'] = { 'select_prev', 'fallback' },
                ['<C-n>'] = { 'select_next', 'fallback_to_mappings' },
                ['<C-p>'] = { 'select_prev', 'fallback_to_mappings' },
                ['<CR>'] = { 'accept', 'fallback' },
                ['<C-y>'] = { 'select_and_accept', 'fallback' },
                ['<C-e>'] = { 'cancel', 'fallback' },
                ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
                ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
                ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
                ['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' },
            },
            cmdline = {
                keymap = {
                    preset = 'none',
                    ['<Tab>'] = { 'show_and_insert_or_accept_single', 'select_next' },
                    ['<S-Tab>'] = { 'show_and_insert_or_accept_single', 'select_prev' },
                    ['<Down>'] = { 'select_next', 'fallback' },
                    ['<Up>'] = { 'select_prev', 'fallback' },
                    ['<C-n>'] = { 'select_next', 'fallback' },
                    ['<C-p>'] = { 'select_prev', 'fallback' },
                    ['<CR>'] = { 'accept_and_enter', 'fallback' },
                    ['<C-y>'] = { 'select_and_accept', 'fallback' },
                    ['<C-e>'] = { 'cancel', 'fallback' },
                    ['<C-space>'] = { 'show', 'fallback' },
                },
            },
            appearance = { nerd_font_variant = 'mono' },
            completion = {
                -- Nothing selected until Tab / an arrow selects it, and the
                -- selection is previewed in the text; so Enter never takes an
                -- item you did not pick.
                list = { selection = { preselect = false, auto_insert = true } },
                documentation = { auto_show = true, auto_show_delay_ms = 300 },
                ghost_text = { enabled = false },
            },
            signature = { enabled = true },
            sources = {
                default = { 'lsp', 'path', 'snippets', 'buffer' },
                -- lazydev only where it applies; as a default source every
                -- buffer of every filetype loaded it.
                per_filetype = { lua = { 'lazydev', inherit_defaults = true } },
                providers = {
                    lazydev = { name = 'LazyDev', module = 'lazydev.integrations.blink', score_offset = 100 },
                },
            },
            fuzzy = { implementation = 'prefer_rust_with_warning' },
        },
        opts_extend = { 'sources.default' },
    },
}
