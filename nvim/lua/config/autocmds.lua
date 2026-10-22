local group = vim.api.nvim_create_augroup('user_config', { clear = true })

vim.filetype.add({
    extension = {
        cu = 'cuda',
        cuh = 'cuda',
    },
})

-- Briefly highlight yanked text.
vim.api.nvim_create_autocmd('TextYankPost', {
    group = group,
    callback = function() vim.hl.on_yank() end,
})

-- Return to the last cursor position when reopening a file.
vim.api.nvim_create_autocmd('BufReadPost', {
    group = group,
    callback = function(args)
        local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
        local lines = vim.api.nvim_buf_line_count(args.buf)
        if mark[1] > 0 and mark[1] <= lines and vim.bo[args.buf].filetype ~= 'gitcommit' then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
        end
    end,
})

-- Prose is wrapped.
vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'markdown', 'text', 'gitcommit' },
    callback = function()
        vim.opt_local.wrap = true
        vim.opt_local.linebreak = true
    end,
})
