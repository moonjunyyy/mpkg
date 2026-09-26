return {
    -- Server definitions (lsp/<name>.lua) for vim.lsp.config; no setup call.
    { 'neovim/nvim-lspconfig', lazy = false },

    {
        'mason-org/mason.nvim',
        cmd = { 'Mason', 'MasonInstall', 'MasonUpdate' },
        opts = { ui = { border = 'rounded' } },
    },

    {
        'mason-org/mason-lspconfig.nvim',
        event = { 'BufReadPre', 'BufNewFile' },
        dependencies = { 'mason-org/mason.nvim', 'neovim/nvim-lspconfig' },
        opts = {
            ensure_installed = require('config.languages').servers,
            -- vim.lsp.enable() every server Mason has installed.
            automatic_enable = true,
        },
    },

    -- Completion and type information for Neovim's own Lua API in lua_ls.
    {
        'folke/lazydev.nvim',
        ft = 'lua',
        opts = {
            library = { { path = '${3rd}/luv/library', words = { 'vim%.uv' } } },
        },
    },
}
