return {
    desc = 'Git signs, hunks and :Git (gitsigns, fugitive)',
    plugins = {
        {
            'lewis6991/gitsigns.nvim',
            event = { 'BufReadPre', 'BufNewFile' },
            opts = {
                on_attach = function(buf)
                    local gs = require('gitsigns')
                    local function map(mode, lhs, rhs, desc)
                        vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
                    end
                    map('n', ']h', function() gs.nav_hunk('next') end, 'Next hunk')
                    map('n', '[h', function() gs.nav_hunk('prev') end, 'Previous hunk')
                    map('n', '<leader>Gs', gs.stage_hunk, 'Stage hunk')
                    map('n', '<leader>Gr', gs.reset_hunk, 'Reset hunk')
                    map('n', '<leader>Gp', gs.preview_hunk, 'Preview hunk')
                    map('n', '<leader>Gb', function() gs.blame_line({ full = true }) end, 'Blame line')
                end,
            },
        },

        { 'tpope/vim-fugitive', cmd = { 'Git', 'G', 'Gdiffsplit', 'Gread', 'Gwrite', 'Gvdiffsplit' } },
    },
}
