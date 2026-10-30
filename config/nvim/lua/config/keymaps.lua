local map = vim.keymap.set

-- Clear search highlighting (and any highlight left by :match & co).
map('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })
map('n', '<leader>Ch', '<cmd>highlight clear<CR>', { desc = 'Clear highlights' })

-- Windows
map('n', '<C-h>', '<C-w>h', { desc = 'Window left' })
map('n', '<C-j>', '<C-w>j', { desc = 'Window down' })
map('n', '<C-k>', '<C-w>k', { desc = 'Window up' })
map('n', '<C-l>', '<C-w>l', { desc = 'Window right' })

-- Keep the selection when shifting indentation.
map('v', '<', '<gv')
map('v', '>', '>gv')

-- Diagnostics (buffer-independent, so they are global rather than per-LSP).
map('n', '<leader>ee', vim.diagnostic.open_float, { desc = 'Diagnostic under cursor' })
map('n', '<leader>e]', function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = 'Next diagnostic' })
map('n', '<leader>e[', function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = 'Previous diagnostic' })
map('n', '<leader>el', function() vim.diagnostic.setqflist() end, { desc = 'Diagnostics to quickfix' })
