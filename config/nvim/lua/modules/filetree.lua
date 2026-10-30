return {
    desc = 'File tree (nvim-tree)',
    plugins = {
        {
            'nvim-tree/nvim-tree.lua',
            cmd = { 'NvimTreeToggle', 'NvimTreeFindFile' },
            keys = {
                { '<C-n>', '<cmd>NvimTreeToggle<CR>', desc = 'File tree' },
                { '<leader>fe', '<cmd>NvimTreeFindFile<CR>', desc = 'Reveal file in tree' },
            },
            opts = {
                view = { width = 35, side = 'left', signcolumn = 'yes' },
                renderer = { highlight_git = true, indent_markers = { enable = true } },
                filters = { dotfiles = false },
                actions = { open_file = { quit_on_open = false } },
            },
        },
    },
}
