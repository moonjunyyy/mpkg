local opt = vim.opt

-- Files and encodings
opt.fileencodings = { 'utf-8', 'euc-kr', 'cp949' }
opt.backup = false
opt.swapfile = false
opt.undofile = true
opt.history = 1000

-- UI
opt.number = true
opt.cursorline = true
opt.signcolumn = 'yes'
opt.termguicolors = true
opt.title = true
opt.showmatch = true
opt.wrap = false
opt.scrolloff = 5
opt.sidescrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.showmode = false -- lualine shows it
opt.winborder = 'rounded'
opt.list = true
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
opt.updatetime = 250 -- CursorHold, used for LSP document highlight
opt.timeoutlen = 400

-- Editing
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.smartindent = true
opt.backspace = { 'indent', 'eol', 'start' }
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.inccommand = 'split'
opt.wildmode = { 'longest:full', 'full' }
opt.completeopt = { 'menuone', 'noselect', 'popup' }

-- Clipboard: the system one. Locally that is whatever Neovim detects (pbcopy,
-- wl-copy, xclip, ...). Over SSH, or with no such tool, it is OSC 52 -- for
-- copying only. An OSC 52 *paste* asks the terminal for its clipboard and
-- blocks until it answers; tmux (by default), Terminal.app and iTerm2 (unless
-- allowed) never do, so every `p` stalled for seconds. Pasting from the
-- system goes through the terminal's own paste (Cmd-V, bracketed paste) instead,
-- and `p` puts back what was last yanked here.
opt.clipboard = 'unnamedplus'
local has_local_clipboard = vim.iter({ 'pbcopy', 'wl-copy', 'xclip', 'xsel', 'win32yank.exe' })
    :any(function(tool) return vim.fn.executable(tool) == 1 end)
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION or not has_local_clipboard then
    local osc52 = require('vim.ui.clipboard.osc52')
    local last = { {}, 'v' }
    local function copy(reg)
        local send = osc52.copy(reg)
        return function(lines, regtype)
            last = { lines, regtype }
            send(lines, regtype)
        end
    end
    local function paste() return last end
    vim.g.clipboard = {
        name = 'OSC 52 (copy only)',
        copy = { ['+'] = copy('+'), ['*'] = copy('*') },
        paste = { ['+'] = paste, ['*'] = paste },
    }
end

-- Node for the language servers that run `#!/usr/bin/env node` (pyright,
-- bashls, jsonls, vimls) and for copilot. node comes from nvm, which only an
-- interactive shell loads: nvim started any other way -- a GUI, git's editor,
-- tmux/cron, `sh -c` -- started those servers without it, and they died with
-- exit code 127. Fall back to the newest node nvm has installed.
if vim.fn.executable('node') == 0 then
    local root = (vim.env.NVM_DIR or vim.fs.joinpath(vim.env.HOME, '.nvm')) .. '/versions/node'
    local best, best_v
    for name, kind in vim.fs.dir(root) do
        local v = kind == 'directory' and vim.version.parse(name)
        if v and (not best_v or vim.version.gt(v, best_v)) then
            best, best_v = name, v
        end
    end
    if best then
        vim.env.PATH = root .. '/' .. best .. '/bin:' .. vim.env.PATH
    end
end

-- Language providers. mpkg's nvim-config package creates the Python venv;
-- providers that are not used are switched off to keep startup quiet.
local venv_python = vim.fn.stdpath('data') .. '/venv/bin/python'
if vim.uv.fs_stat(venv_python) then
    vim.g.python3_host_prog = venv_python
end
vim.g.loaded_perl_provider = 0
