source ~/.vimrc

set completeopt+=menuone,noselect,popup
let g:clipboard = 'osc52'
" Set Python 3 interpreter with system path; Not a virtual environment
" let g:python3_host_prog  = '/usr/bin/python'
"
" If you are on macos or other POSIX system, or want to change the directory
" of python executable, need to change the path: 
" let g:python3_host_prog  = '/opt/homebrew/bin/python3.14'

" let g:clang_library_path = '/usr/lib/llvm-20/lib/libclang.so'
" let g:node_host_prog = '~/.nvm/versions/node/*/bin/neovim-node-host'

lua << EOF
do
     -- Specifies where to install/use rocks.nvim
    local install_location = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "rocks")
    -- Set up configuration options related to rocks.nvim (recommended to leave as default)
    local rocks_config = {
        rocks_path = vim.fs.normalize(install_location),
    }
    vim.g.rocks_nvim = rocks_config
    local luarocks_path = {
        vim.fs.joinpath(rocks_config.rocks_path, "share", "lua", "5.1", "?.lua"),
	    vim.fs.joinpath(rocks_config.rocks_path, "share", "lua", "5.1", "?", "init.lua"),
    }
    package.path = package.path .. ";" .. table.concat(luarocks_path, ";")
    local luarocks_cpath = {
        vim.fs.joinpath(rocks_config.rocks_path, "lib", "lua", "5.1", "?.so"),
	    vim.fs.joinpath(rocks_config.rocks_path, "lib64", "lua", "5.1", "?.so"),
	    -- Remove the dylib and dll paths if you do not need macos or windows support
	    vim.fs.joinpath(rocks_config.rocks_path, "lib", "lua", "5.1", "?.dylib"),
	    vim.fs.joinpath(rocks_config.rocks_path, "lib64", "lua", "5.1", "?.dylib"),
	    vim.fs.joinpath(rocks_config.rocks_path, "lib", "lua", "5.1", "?.dll"),
	    vim.fs.joinpath(rocks_config.rocks_path, "lib64", "lua", "5.1", "?.dll"),
    }
    package.cpath = package.cpath .. ";" .. table.concat(luarocks_cpath, ";")
    -- Add rocks.nvim to the runtimepath
    vim.opt.runtimepath:append(vim.fs.joinpath(rocks_config.rocks_path, "lib", "luarocks", "rocks-5.1", "rocks.nvim", "*"))
end
if not pcall(require, "rocks") then
    local rocks_location = vim.fs.joinpath(vim.fn.stdpath("cache") --[[@as string]], "rocks.nvim")
    if not vim.uv.fs_stat(rocks_location) then
        -- Pull down rocks.nvim
        local url = "https://github.com/lumen-oss/rocks.nvim"
        vim.fn.system({ "git", "clone", "--filter=blob:none", url, rocks_location })
        -- Make sure the clone was successfull
        assert(vim.v.shell_error == 0, "rocks.nvim installation failed. Try exiting and re-entering Neovim!")
    end
    -- If the clone was successful then source the bootstrapping script
    vim.cmd.source(vim.fs.joinpath(rocks_location, "bootstrap.lua"))
    vim.fn.delete(rocks_location, "rf")
end
EOF

source ~/.config/nvim/autoload/plug.vim
filetype off                  " required
call plug#begin()
Plug 'L3MON4D3/LuaSnip'
Plug 'nvim-lua/plenary.nvim'
Plug 'OXY2DEV/markview.nvim'
Plug 'nvim-tree/nvim-tree.lua'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'catppuccin/nvim'
Plug 'williamboman/mason.nvim'
Plug 'williamboman/mason-lspconfig.nvim'
Plug 'neovim/nvim-lspconfig'
" Plug 'hrsh7th/nvim-cmp'
" Plug 'hrsh7th/cmp-nvim-lsp'
" Plug 'saadparwaiz1/cmp_luasnip'
Plug 'nvim-lualine/lualine.nvim'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-telescope/telescope.nvim', { 'branch': '0.1.x' }
Plug 'preservim/tagbar'
Plug 'tpope/vim-fugitive'
Plug 'lewis6991/gitsigns.nvim'
" Plug 'vim-airline/vim-airline'
" Plug 'rip-rip/clang_complete'
Plug 'github/copilot.vim'
call plug#end()             " required
filetype plugin indent on   " required
syntax on
set termguicolors
colorscheme catppuccin-mocha

" lua scripts
lua << EOF
require('gitsigns').setup()
require('luasnip').setup{}
require('lualine').setup{ options = { theme = 'auto' } }

--- Nvim Tree
require('nvim-tree').setup {
  view = {
    width = 35,
    side = 'left',
    signcolumn = 'yes',
  },
  renderer = {
    highlight_git = true,
    indent_markers = { enable = true },
  },
  filters = {
    dotfiles = false,
  },
  actions = {
    open_file = { quit_on_open = false },
  }
}
vim.keymap.set('n', '<C-n>', ':NvimTreeToggle<CR>', { silent = true })

local presets = require('markview.presets');
require('markview').setup({
    markdown = {
        headings = presets.headings.slanted
    },
    preview = {
        icon_provider = 'devicons'
    }
})
EOF

lua << EOF
-- Setup lspconfig.
require('nvim-treesitter.configs').setup{
  ensure_installed = { 'c','cpp','python','cmake','make','bash','lua','json','powershell','vim','markdown' },
  highlight = { enable = true, additional_vim_regex_highlighting = false },
  indent = { enable = true },
}
EOF

lua << EOF
--- Setup LSP keymaps and settings based on server capabilities
vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('userLspConfigs', {}),
    callback = function(args)
        local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
        vim.print('LSP started for buffer ' .. args.buf .. ' with client ID ' .. args.data.client_id)
        vim.print('Client name: ' .. client.name)
        vim.print('Client capabilities: ' .. vim.inspect(client.server_capabilities))

        vim.keymap.set('n', '<leader>gd',       vim.lsp.buf.declaration,     {silent=true})
        vim.keymap.set('n', '<leader>gD',       vim.lsp.buf.definition,      {silent=true})
        vim.keymap.set('n', '<leader>gi',       vim.lsp.buf.implementation,  {silent=true})
        vim.keymap.set('n', '<leader>gr',       vim.lsp.buf.references,      {silent=true})
        vim.keymap.set('n', '<leader>g0',       vim.lsp.buf.document_symbol, {silent=true})
        vim.keymap.set('n', '<leader><leader>', vim.lsp.buf.hover,           {silent=true})
        vim.keymap.set('n', '<leader>tD',       vim.lsp.buf.type_definition, {silent=true})

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'typeHierARCHyProvider') then
            vim.keymap.set('n', '<leader>tP', function() vim.lsp.buf.typehierachy({kind='subtypes'})   end, {silent=true})
            vim.keymap.set('n', '<leader>tC', function() vim.lsp.buf.typehierachy({kind='supertypes'}) end, {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'codeLensProvider') then
            vim.keymap.set('n', '<leader>lc', function() vim.lsp.codelens.clear  ({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>ls', function() vim.lsp.codelens.display({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.nvim_create_autocmd({'BufEnter','CursorHold','InsertLeave'}, {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function() vim.lsp.codelens.refresh({ bufnr = 0 }) end
            })
            vim.keymap.set('n', '<leader>lr', function() vim.lsp.codelens.refresh({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>lS', function() vim.lsp.codelens.save   ({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>lg', function() vim.lsp.codelens.get({bufnr=0}) end, {silent=true})
            vim.keymap.set('n', '<leader>lR', vim.lsp.codelens.run, {silent=true})
        end

        vim.diagnostic.config({
            virtual_text = {
                prefix = '●',
                spacing = 4,
            },
            float = {
                border = 'rounded',
                source = 'always',
                header = '',
                prefix = '',
            },
            signs = true,
            underline = true,
            update_in_insert = false,
            severity_sort = true,
        })
        vim.keymap.set('n', '<leader>ee',  vim.diagnostic.open_float,               {silent=true})
        vim.keymap.set('n', '<leader>e]', function() vim.diagnostic.jump({count =  1, float=true}) end, {silent=true})
        vim.keymap.set('n', '<leader>e[', function() vim.diagnostic.jump({count = -1, float=true}) end, {silent=true})
        vim.keymap.set('n', '<leader>el', function() vim.diagnostic.setqflist(); vim.cmd('copen') end,  {silent=true})

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'signatureHelpProvider') then
            vim.keymap.set('n', '<leader>hS',    vim.lsp.buf.signature_help, {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'codeActionProvider') then
            vim.keymap.set('n', '<leader>hA',    vim.lsp.buf.code_action,    {silent=true})
        end
         
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'renameProvider') then
            vim.keymap.set('n', '<F2>',          vim.lsp.buf.rename,         {silent=true})
        end
 
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'WorkspaceSymbolOptions') then
            vim.keymap.set('n', '<leader>G0',    vim.lsp.buf.workspace_symbol,{silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'inlayHintProvider') then
            vim.lsp.inlay_hint.enable(true)
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'completionProvider') then
            --- for _char=32,126 do
            ---     vim.list_extend( client.server_capabilities.completionProvider.triggerCharacters, { string.char(_char), } )
            --- end
            buffer = vim.api.nvim_get_current_buf(),
            vim.lsp.completion.enable(true, client.id, 0, {
                autotrigger = true,
                convert = function(item)
                    return { abbr = item.label:gsub('%b()', '') }
                end,
            })
        end
        
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentFormattingProvider') then
            vim.keymap.set('n', '<leader>hA', function()
                    vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
                end
                ,{silent=true})
            vim.api.nvim_create_autocmd('BufWritePre', {
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                buffer = args.buf,
                callback = function()
                    vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
                end,
            })
        end
        
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentHighlightProvider') then
            vim.api.nvim_create_autocmd('CursorHold', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function()
                    vim.lsp.buf.document_highlight()
                end
            })
            vim.api.nvim_create_autocmd('CursorHoldI', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function()
                    vim.lsp.buf.document_highlight()
                end
            })
            vim.api.nvim_create_autocmd('CursorMoved', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function()
                    vim.lsp.buf.clear_references() 
                end
            })
        end
       
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'diagnosticProvider') then
        --- end
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'declarationProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'definitionProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'implementationProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'referencesProvider') then
        --- end
        --- 
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentSymbolProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'hoverProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'typeDefinitionProvider') then
        --- end

        --- These capabilities not used for now, but can be added later
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'inlineValueProvider') then
        --- end
        
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'selectionRangeProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentRangeFormattingProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentOnTypeFormattingProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.willCreate') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.didCreate') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.willRename') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.didRename') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.willDelete') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.didDelete') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'foldingRangeProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'colorProvider') then
        --- end
        
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentLinkProvider') then
        --- end
    end,
})

--- Mason
require('mason').setup()
require('mason-lspconfig').setup({
    ensure_installed = { 'clangd', 'pyright', 'bashls', 'lua_ls', 'jsonls', 'powershell_es', 'vimls', 'markdown_oxide'},
    automatic_enable = true
})
EOF

" == Telescope ==
nnoremap <silent> <leader>ff :Telescope find_files<CR>
nnoremap <silent> <leader>fg :Telescope live_grep<CR>
nnoremap <silent> <leader>fb :Telescope buffers<CR>
nnoremap <silent> <leader>fh :Telescope help_tags<CR>
nnoremap <silent> <leader>Ch :highlight clear<CR>

" === Tagbar ===
nnoremap <leader>tb :TagbarToggle<CR>
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'default'

" CUDA filetype settings
augroup cuda_ft
  autocmd!
  autocmd BufRead,BufNewFile *.cu,*.cuh set filetype=cuda
augroup END

" Markdown filetype settings
augroup markdown
  autocmd!
  autocmd BufRead,BufNewFile *.md setlocal filetype=markdown
augroup END
