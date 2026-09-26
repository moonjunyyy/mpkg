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

-- Clipboard: the system one, reached over OSC 52 so it also works through SSH
-- and tmux.
opt.clipboard = 'unnamedplus'
vim.g.clipboard = 'osc52'

-- Language providers. mpkg's nvim-config package creates the Python venv;
-- providers that are not used are switched off to keep startup quiet.
local venv_python = vim.fn.stdpath('data') .. '/venv/bin/python'
if vim.uv.fs_stat(venv_python) then
    vim.g.python3_host_prog = venv_python
end
vim.g.loaded_perl_provider = 0
