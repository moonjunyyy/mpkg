-- Lean 4 through lean.nvim (needs Neovim 0.12+).
--
-- No extend.servers or extend.parsers: lean.nvim enables the Lean server
-- (leanls) itself, and that server is `lake serve` from the project's own
-- toolchain (elan, which must be on PATH). Highlighting comes from lean.nvim's
-- syntax files and the server's semantic tokens, not a tree-sitter parser.
return {
    desc = 'Lean 4 (lean.nvim: infoview, abbreviations, leanls)',
    plugins = {
        {
            'Julian/lean.nvim',
            -- lean.nvim brings its own filetype detection, so it loads on the
            -- file pattern; `ft = 'lean'` would wait for a filetype nothing sets yet.
            event = { 'BufReadPre *.lean', 'BufNewFile *.lean' },
            ---@type lean.Config
            opts = {
                -- <LocalLeader> is '\' here, the same key as <Leader>: \i infoview,
                -- \r restart file, \x / \c pins, \\ abbreviation lookup, ... None
                -- of them is taken globally, and lsp.lua leaves alone the
                -- buffer-local keys a filetype plugin set (\\ stays lean's; hover
                -- in Lean files is K, lean.nvim's interactive one).
                mappings = true,
            },
        },
    },
}
