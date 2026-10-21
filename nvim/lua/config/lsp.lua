-- Language servers use Neovim's built-in client (vim.lsp.config / vim.lsp.enable).
-- nvim-lspconfig supplies the default server configs, Mason installs the
-- servers, and mason-lspconfig enables every server Mason has installed.
--
-- Neovim's defaults already map, in any buffer with a server attached:
--   K hover   grn rename   gra code action   grr references   gri implementation
--   grt type definition   gO document symbols   <C-s> (insert) signature help

vim.diagnostic.config({
    severity_sort = true,
    underline = true,
    update_in_insert = false,
    virtual_text = { prefix = '●', spacing = 4, source = 'if_many' },
    float = { border = 'rounded', source = true, header = '' },
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = '',
            [vim.diagnostic.severity.WARN] = '',
            [vim.diagnostic.severity.INFO] = '',
            [vim.diagnostic.severity.HINT] = '',
        },
    },
})

-- Settings for all servers, then per-server overrides. These merge over the
-- defaults nvim-lspconfig ships in its lsp/<name>.lua files.
vim.lsp.config('*', {
    root_markers = { '.git' },
})

vim.lsp.config('clangd', {
    cmd = { 'clangd', '--background-index', '--clang-tidy', '--header-insertion=iwyu' },
})

vim.lsp.config('lua_ls', {
    settings = {
        Lua = {
            completion = { callSnippet = 'Replace' },
            hint = { enable = true },
            workspace = { checkThirdParty = false },
        },
    },
})

vim.lsp.config('pyright', {
    settings = {
        python = { analysis = { typeCheckingMode = 'basic', autoSearchPaths = true } },
    },
})

-- markdown-oxide treats its root as a notes vault, indexes all of it, and
-- holds a lock on it: with the default root ('.git') every repository became a
-- vault, and a second nvim in the same repository failed with
-- "Failed to get VAULT lock". Only start it inside real vaults.
vim.lsp.config('markdown_oxide', {
    root_dir = function(buf, on_dir)
        local root = vim.fs.root(buf, { '.obsidian', '.moxide.toml' })
        if root then on_dir(root) end
    end,
})

local group = vim.api.nvim_create_augroup('user_lsp', { clear = true })

-- One augroup per buffer and feature, recreated (clear = true) on every
-- attach: a second server, or :LspRestart, then cannot stack duplicates.
local function buf_group(feature, buf)
    return vim.api.nvim_create_augroup(('user_lsp_%s_%d'):format(feature, buf), { clear = true })
end

vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
        local buf = args.buf
        local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
        local function map(lhs, rhs, desc, mode)
            vim.keymap.set(mode or 'n', lhs, rhs, { buffer = buf, silent = true, desc = desc })
        end

        -- The mappings this configuration has always had, next to the defaults above.
        map('<leader>gd', vim.lsp.buf.declaration, 'Declaration')
        map('<leader>gD', vim.lsp.buf.definition, 'Definition')
        map('<leader>gi', vim.lsp.buf.implementation, 'Implementation')
        map('<leader>gr', vim.lsp.buf.references, 'References')
        map('<leader>g0', vim.lsp.buf.document_symbol, 'Document symbols')
        map('<leader>G0', vim.lsp.buf.workspace_symbol, 'Workspace symbols')
        map('<leader><leader>', vim.lsp.buf.hover, 'Hover')
        map('<leader>tD', vim.lsp.buf.type_definition, 'Type definition')
        map('<leader>hS', vim.lsp.buf.signature_help, 'Signature help')
        map('<leader>hA', vim.lsp.buf.code_action, 'Code action', { 'n', 'x' })
        map('<F2>', vim.lsp.buf.rename, 'Rename')
        map('gd', vim.lsp.buf.definition, 'Definition')

        if client:supports_method('typeHierarchy/prepareTypeHierarchy', buf) then
            map('<leader>tP', function() vim.lsp.buf.typehierarchy('subtypes') end, 'Subtypes')
            map('<leader>tC', function() vim.lsp.buf.typehierarchy('supertypes') end, 'Supertypes')
        end

        if client:supports_method('textDocument/inlayHint', buf) then
            vim.lsp.inlay_hint.enable(true, { bufnr = buf })
            map('<leader>uh', function()
                vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
            end, 'Toggle inlay hints')
        end

        if client:supports_method('textDocument/codeLens', buf) then
            if vim.lsp.codelens.enable then -- Neovim 0.12+
                vim.lsp.codelens.enable(true, { bufnr = buf })
            else
                vim.api.nvim_create_autocmd({ 'BufEnter', 'CursorHold', 'InsertLeave' }, {
                    group = buf_group('codelens', buf),
                    buffer = buf,
                    callback = function() vim.lsp.codelens.refresh({ bufnr = buf }) end,
                })
                vim.lsp.codelens.refresh({ bufnr = buf })
            end
            map('<leader>lR', vim.lsp.codelens.run, 'Run code lens')
        end

        -- Highlight other uses of the symbol under the cursor.
        if client:supports_method('textDocument/documentHighlight', buf) then
            local g = buf_group('highlight', buf)
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                group = g,
                buffer = buf,
                callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                group = g,
                buffer = buf,
                callback = vim.lsp.buf.clear_references,
            })
        end
    end,
})

-- When a server goes away, drop a feature's autocmds only if no other server
-- on the buffer still provides it. (Clearing them all made highlights and code
-- lenses stop for every server whenever any one of them exited.)
vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(args)
        local buf, gone = args.buf, args.data.client_id
        local function still(method)
            for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
                if c.id ~= gone and c:supports_method(method, buf) then return true end
            end
            return false
        end
        if not still('textDocument/documentHighlight') then
            pcall(vim.api.nvim_del_augroup_by_name, ('user_lsp_highlight_%d'):format(buf))
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_call(buf, vim.lsp.buf.clear_references)
            end
        end
        if not still('textDocument/codeLens') then
            pcall(vim.api.nvim_del_augroup_by_name, ('user_lsp_codelens_%d'):format(buf))
        end
    end,
})
