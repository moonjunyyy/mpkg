-- Formatting goes through conform.nvim: a formatter listed here when it is
-- installed, the language server's formatter otherwise. Format-on-save can be
-- turned off with <leader>uf (globally) or :FormatDisable! (this buffer only).
return {
    {
        'stevearc/conform.nvim',
        event = 'BufWritePre',
        cmd = 'ConformInfo',
        keys = {
            {
                '<leader>hF',
                function() require('conform').format({ async = true }) end,
                mode = { 'n', 'x' },
                desc = 'Format',
            },
            {
                '<leader>uf',
                function()
                    vim.g.disable_autoformat = not vim.g.disable_autoformat
                    vim.notify('Format on save ' .. (vim.g.disable_autoformat and 'off' or 'on'))
                end,
                desc = 'Toggle format on save',
            },
        },
        opts = {
            formatters_by_ft = {
                lua = { 'stylua' },
                python = { 'ruff_format' },
                sh = { 'shfmt' },
            },
            default_format_opts = { lsp_format = 'fallback' },
            format_on_save = function(buf)
                if vim.g.disable_autoformat or vim.b[buf].disable_autoformat then
                    return
                end
                return { timeout_ms = 1000 }
            end,
        },
        init = function()
            vim.api.nvim_create_user_command('FormatDisable', function(args)
                if args.bang then
                    vim.b.disable_autoformat = true
                else
                    vim.g.disable_autoformat = true
                end
            end, { desc = 'Disable format on save (! for this buffer only)', bang = true })
            vim.api.nvim_create_user_command('FormatEnable', function()
                vim.b.disable_autoformat = false
                vim.g.disable_autoformat = false
            end, { desc = 'Enable format on save' })
        end,
    },
}
