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
            -- vim.lsp.enable() the servers languages.lua lists -- not every one
            -- Mason happens to have installed: leftovers (pylsp, basics_ls, ...)
            -- otherwise attach next to the intended server, and a Python buffer
            -- ends up with pyright and pylsp both reporting diagnostics.
            automatic_enable = require('config.languages').servers,
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
