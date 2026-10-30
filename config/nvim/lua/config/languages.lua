-- The languages this configuration sets up, in one place. mpkg reads this file
-- too: the nvim-config package installs the parsers and the mason package
-- installs the servers, so a fresh machine has both before nvim first starts.
return {
    -- nvim-treesitter parser names
    parsers = {
        'bash', 'c', 'cmake', 'cpp', 'cuda', 'diff', 'git_config', 'gitcommit',
        'java', 'json', 'lua', 'luadoc', 'make', 'markdown', 'markdown_inline',
        'powershell', 'python', 'query', 'regex', 'toml', 'vim', 'vimdoc', 'yaml',
    },

    -- nvim-lspconfig server names; Mason maps them to its own package names.
    servers = {
        'bashls', 'clangd', 'jsonls', 'lua_ls', 'markdown_oxide', 'powershell_es',
        'pyright', 'vimls',
    },
}
