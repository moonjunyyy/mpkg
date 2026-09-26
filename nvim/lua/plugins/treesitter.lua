-- nvim-treesitter's main branch: it only installs parsers and queries; the
-- highlighting itself is Neovim's, started per buffer below. Building parsers
-- needs the tree-sitter CLI and a C compiler.
return {
    {
        'nvim-treesitter/nvim-treesitter',
        branch = 'main',
        lazy = false,
        build = ':TSUpdate',
        config = function()
            local parsers = require('config.languages').parsers
            local ts = require('nvim-treesitter')
            ts.setup()

            -- Install whatever is missing, in the background. Not in a headless
            -- nvim: that is a script (mpkg's nvim-config package, :Lazy! sync)
            -- which either installs the parsers itself or quits before a
            -- background install could finish.
            if #vim.api.nvim_list_uis() > 0 then
                local installed = ts.get_installed('parsers')
                local missing = vim.tbl_filter(function(p) return not vim.list_contains(installed, p) end, parsers)
                if #missing > 0 then
                    ts.install(missing)
                end
            end

            vim.api.nvim_create_autocmd('FileType', {
                group = vim.api.nvim_create_augroup('user_treesitter', { clear = true }),
                callback = function(args)
                    if not pcall(vim.treesitter.start, args.buf) then
                        return
                    end
                    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                    vim.wo.foldmethod = 'expr'
                    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
                    vim.wo.foldlevel = 99
                end,
            })
        end,
    },
}
