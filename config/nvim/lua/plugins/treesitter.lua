-- nvim-treesitter's main branch: it only installs parsers and queries; the
-- highlighting itself is Neovim's, started per buffer below. Building parsers
-- needs the tree-sitter CLI and a C compiler.
return {
    {
        'nvim-treesitter/nvim-treesitter',
        branch = 'main',
        lazy = false,
        build = ':TSUpdate',
        -- languages.lua's parsers, plus the extend.parsers of modules.
        opts = { parsers = vim.list_extend({}, require('config.languages').parsers) },
        opts_extend = { 'parsers' },
        config = function(_, opts)
            local parsers = opts.parsers
            local ts = require('nvim-treesitter')
            ts.setup()

            -- Install whatever is missing, in the background. Not in a headless
            -- nvim: that is a script (mpkg's nvim-config package, :Lazy! sync)
            -- which either installs the parsers itself or quits before a
            -- background install could finish.
            -- Nor without the tree-sitter CLI and a C compiler: the install
            -- would fail again on every start, with a burst of errors.
            local can_build = vim.fn.executable('tree-sitter') == 1
                and (vim.fn.executable('cc') == 1 or vim.fn.executable('gcc') == 1 or vim.fn.executable('clang') == 1)
            if #vim.api.nvim_list_uis() > 0 and can_build then
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
                    -- The buffer's own window: FileType also fires for buffers
                    -- shown elsewhere (a Telescope preview while the prompt
                    -- window is current), and vim.wo would fold that window.
                    local win = vim.fn.bufwinid(args.buf)
                    if win ~= -1 then
                        local wo = vim.wo[win][0]
                        wo.foldmethod = 'expr'
                        wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
                        wo.foldlevel = 99
                    end
                end,
            })
        end,
    },
}
