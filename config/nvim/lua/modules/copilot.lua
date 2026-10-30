-- GitHub Copilot as a completion source: its suggestions are items in the
-- blink menu, chosen with Tab / Enter like any other, instead of inline ghost
-- text competing with the menu for <Tab>. copilot.vim only runs the language
-- server here (sign-in, :Copilot status); blink-copilot asks that server.
return {
    desc = 'GitHub Copilot suggestions in the completion menu',
    plugins = {
        {
            'github/copilot.vim',
            cmd = 'Copilot',
            -- With the first window, not on InsertEnter: the server is up before
            -- the first keystroke instead of being started by it.
            event = 'BufWinEnter',
            init = function()
                vim.g.copilot_no_maps = true
                -- The language server bundled with the plugin (pinned by
                -- lazy-lock.json), not `npx @github/copilot-language-server`
                -- fetched on every start.
                vim.g.copilot_version = false
            end,
            config = function()
                -- copilot.vim's own autocmds draw ghost text while typing;
                -- keep only the two that attach buffers to the server.
                local group = vim.api.nvim_create_augroup('github_copilot', { clear = true })
                vim.api.nvim_create_autocmd({ 'FileType', 'BufUnload' }, {
                    group = group,
                    callback = function(args) vim.fn['copilot#On' .. args.event]() end,
                })
                vim.fn['copilot#OnFileType']()
            end,
        },
        { 'fang2hou/blink-copilot', lazy = true },
    },
    extend = {
        sources = {
            copilot = { name = 'Copilot', module = 'blink-copilot', async = true, score_offset = 100 },
        },
    },
}
