-- lazy.nvim bootstrap: clone it on first start, then load the core plugins
-- (lua/plugins/*.lua) and the feature modules that are not dropped
-- (lua/modules/*.lua, see config/loader.lua).
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
    local out = vim.fn.system({
        'git', 'clone', '--filter=blob:none', '--branch=stable',
        'https://github.com/folke/lazy.nvim.git', lazypath,
    })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({ { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' }, { out } }, true, {})
        return
    end
end
vim.opt.rtp:prepend(lazypath)

local modules = require('config.loader')

require('lazy').setup({
    spec = vim.list_extend({ { import = 'plugins' } }, modules.spec()),
    install = { colorscheme = { 'catppuccin-mocha', 'habamax' } },
    checker = { enabled = false },
    change_detection = { notify = false },
    rocks = { enabled = false },
    performance = {
        rtp = {
            disabled_plugins = { 'gzip', 'netrwPlugin', 'tarPlugin', 'tohtml', 'tutor', 'zipPlugin' },
        },
    },
})

modules.command()
